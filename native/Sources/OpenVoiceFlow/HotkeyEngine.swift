import ApplicationServices
import CoreGraphics
import Foundation

/// The set of keys usable as a push-to-talk hotkey.
///
/// Unlike the Python app (pynput can't see the fn/Globe key at all), a
/// `CGEventTap` receives the raw `flagsChanged` event for fn, so `.fn` works
/// here. Modifiers are matched by the physical key's virtual keycode (which
/// distinguishes left/right) plus the corresponding event flag (which tells
/// press from release); F-keys are matched on keyDown/keyUp.
enum Hotkey: String, CaseIterable, Codable {
    case rightCommand, leftCommand
    case rightOption, leftOption
    case rightControl
    case fn
    case f5, f6, f7, f8, f9, f10, f11, f12

    var displayName: String {
        switch self {
        case .rightCommand: return "Right Command (⌘)"
        case .leftCommand: return "Left Command (⌘)"
        case .rightOption: return "Right Option (⌥)"
        case .leftOption: return "Left Option (⌥)"
        case .rightControl: return "Right Control (⌃)"
        case .fn: return "Fn / 🌐 Globe"
        default: return rawValue.uppercased()
        }
    }

    /// The hardware virtual keycode (`kVK_*`).
    var keyCode: CGKeyCode {
        switch self {
        case .rightCommand: return 0x36
        case .leftCommand: return 0x37
        case .rightOption: return 0x3D
        case .leftOption: return 0x3A
        case .rightControl: return 0x3E
        case .fn: return 0x3F
        case .f5: return 0x60
        case .f6: return 0x61
        case .f7: return 0x62
        case .f8: return 0x64
        case .f9: return 0x65
        case .f10: return 0x6D
        case .f11: return 0x67
        case .f12: return 0x6F
        }
    }

    /// True for keys delivered as modifier `flagsChanged` events (incl. fn).
    var isModifier: Bool { modifierFlag != nil }

    /// The event flag whose presence means "this modifier is currently down".
    var modifierFlag: CGEventFlags? {
        switch self {
        case .rightCommand, .leftCommand: return .maskCommand
        case .rightOption, .leftOption: return .maskAlternate
        case .rightControl: return .maskControl
        case .fn: return .maskSecondaryFn
        default: return nil
        }
    }
}

/// A global push-to-talk listener built on a listen-only `CGEventTap`.
///
/// Fires `onPress` when the configured hotkey goes down and `onRelease` when
/// it comes up. The tap is listen-only, so it never swallows the key from
/// other apps. Requires Accessibility (and, in practice, Input Monitoring).
final class HotkeyEngine {
    var hotkey: Hotkey
    var onPress: () -> Void = {}
    var onRelease: () -> Void = {}

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isDown = false

    init(hotkey: Hotkey) {
        self.hotkey = hotkey
    }

    /// Whether the process is trusted for Accessibility (required for the tap).
    static var accessibilityTrusted: Bool { AXIsProcessTrusted() }

    /// Prompt for Accessibility if not yet granted (opens the consent dialog).
    static func requestAccessibility() {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// Start listening. Returns false if the tap couldn't be created (usually
    /// missing Accessibility/Input Monitoring) — the caller should surface that.
    @discardableResult
    func start() -> Bool {
        stop()
        let mask =
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let engine = Unmanaged<HotkeyEngine>.fromOpaque(refcon).takeUnretainedValue()
            engine.handle(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
        isDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // macOS can disable a slow tap; re-enable and move on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))

        if hotkey.isModifier {
            // Only react to the physical key we care about; the keycode of a
            // flagsChanged event identifies the exact (left/right/fn) key.
            guard type == .flagsChanged, keyCode == hotkey.keyCode,
                  let flag = hotkey.modifierFlag else { return }
            let pressed = event.flags.contains(flag)
            setDown(pressed)
        } else {
            guard keyCode == hotkey.keyCode else { return }
            if type == .keyDown { setDown(true) }
            else if type == .keyUp { setDown(false) }
        }
    }

    private func setDown(_ down: Bool) {
        guard down != isDown else { return }  // debounce key-repeat
        isDown = down
        // Callbacks are dispatched to main so UI/state mutate on the main actor.
        DispatchQueue.main.async { [weak self] in
            down ? self?.onPress() : self?.onRelease()
        }
    }
}
