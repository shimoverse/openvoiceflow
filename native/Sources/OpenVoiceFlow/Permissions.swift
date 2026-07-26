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

    /// Six words of "why", in the app's voice. The app says "I" when it is
    /// asking for something — that is what earns the first person here.
    var why: String {
        switch self {
        case .microphone: return "so I can hear you"
        case .accessibility: return "so I can type for you"
        case .inputMonitoring: return "so I can feel the key"
        }
    }

    /// The order onboarding asks in — hear, then type, then feel the key.
    static let onboardingOrder: [Permission] = [.microphone, .accessibility, .inputMonitoring]

    /// What this permission *cannot* do. Stating the limit next to the ask buys
    /// more trust than any badge, and it is the honest answer to the question
    /// the three system dialogs provoke.
    var limit: String {
        switch self {
        case .microphone:
            return "I only listen while the key is held. Nothing is recorded before or after."
        case .accessibility:
            return "I press ⌘V on your behalf. I don't read what's on your screen."
        case .inputMonitoring:
            return "One key — the one you choose. Every other keystroke passes straight through."
        }
    }

    /// Watch every grant on a timer, reporting only when something changes.
    ///
    /// A grant can land while our own window stays key: the user flips the
    /// switch in System Settings and `AXIsProcessTrusted()` starts returning
    /// true without the app ever losing or regaining focus, so refreshing on
    /// `NSWindow.didBecomeKeyNotification` misses it entirely. Cancel the
    /// returned task when every permission is granted or the step is left.
    static func watch(
        every interval: Duration = .milliseconds(600),
        onChange: @escaping @MainActor ([Permission: Status]) -> Void
    ) -> Task<Void, Never> {
        Task { @MainActor in
            var last: [Permission: Status] = [:]
            while !Task.isCancelled {
                let now = Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.status) })
                if now != last {
                    last = now
                    onChange(now)
                }
                try? await Task.sleep(for: interval)
            }
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
