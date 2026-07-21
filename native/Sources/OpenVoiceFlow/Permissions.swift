import AVFoundation
import ApplicationServices
import Foundation
import IOKit.hid

/// The three TCC permissions dictation depends on, and helpers to check /
/// request / deep-link to each. Requesting them in-context (not all at once
/// at first launch, as the Python launcher does) is the HIG-correct flow.
enum Permission: CaseIterable {
    case microphone, accessibility, inputMonitoring

    enum Status { case granted, denied, undetermined }

    var status: Status {
        switch self {
        case .microphone:
            switch AVCaptureDevice.authorizationStatus(for: .audio) {
            case .authorized: return .granted
            case .notDetermined: return .undetermined
            default: return .denied
            }
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .inputMonitoring:
            switch IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) {
            case kIOHIDAccessTypeGranted: return .granted
            case kIOHIDAccessTypeDenied: return .denied
            default: return .undetermined
            }
        }
    }

    /// Trigger the OS prompt for this permission (attributed to the app).
    func request() {
        switch self {
        case .microphone:
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        case .accessibility:
            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(opts)
        case .inputMonitoring:
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
    }

    var title: String {
        switch self {
        case .microphone: return "Microphone"
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        }
    }

    var why: String {
        switch self {
        case .microphone: return "to hear your voice while you dictate."
        case .accessibility: return "to paste the transcribed text at your cursor."
        case .inputMonitoring: return "to detect your push-to-talk hotkey."
        }
    }

    /// System Settings deep link (current on macOS 13–15).
    var settingsURL: URL {
        let anchor: String
        switch self {
        case .microphone: anchor = "Privacy_Microphone"
        case .accessibility: anchor = "Privacy_Accessibility"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}
