import Carbon
import Foundation

enum HotKeyFailure: LocalizedError {
    case eventHandler(OSStatus)
    case registration(OSStatus)

    var errorDescription: String? {
        switch self {
        case .eventHandler(let status):
            return "Could not install the global shortcut handler (\(status))."
        case .registration(let status):
            return "Control+Option+Space is already used by another app (\(status))."
        }
    }
}

final class HotKeyMonitor {
    private static let signature: OSType = 0x4F_56_46_53 // OVFS
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let pressed: () -> Void
    private let released: () -> Void

    init(pressed: @escaping () -> Void, released: @escaping () -> Void) {
        self.pressed = pressed
        self.released = released
    }

    func register() throws {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let context = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
                switch GetEventKind(event) {
                case UInt32(kEventHotKeyPressed):
                    DispatchQueue.main.async(execute: monitor.pressed)
                case UInt32(kEventHotKeyReleased):
                    DispatchQueue.main.async(execute: monitor.released)
                default:
                    return OSStatus(eventNotHandledErr)
                }
                return noErr
            },
            eventTypes.count,
            &eventTypes,
            context,
            &eventHandlerRef
        )
        guard handlerStatus == noErr else {
            throw HotKeyFailure.eventHandler(handlerStatus)
        }

        var identifier = EventHotKeyID(signature: Self.signature, id: 1)
        let modifiers = UInt32(controlKey | optionKey)
        let registrationStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            modifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        guard registrationStatus == noErr else {
            throw HotKeyFailure.registration(registrationStatus)
        }
    }

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }
}
