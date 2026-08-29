import AppKit
import SwiftUI

/// Adds one macOS convention that SwiftUI's stock sheet does not provide:
/// a click back on the blocked parent window dismisses this lightweight form.
/// The local event monitor sees only OpenVoiceFlow events, so clicking another
/// app never needs Accessibility or Input Monitoring permission.
struct SheetOutsideClickDismissal: NSViewRepresentable {
    let onOutsideClick: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onOutsideClick: onOutsideClick)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.track(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onOutsideClick = onOutsideClick
        context.coordinator.track(nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onOutsideClick: () -> Void
        private weak var trackedView: NSView?
        private var monitor: Any?
        private var isDismissing = false

        init(onOutsideClick: @escaping () -> Void) {
            self.onOutsideClick = onOutsideClick
        }

        func track(_ view: NSView) {
            trackedView = view
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(
                matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
            ) { [weak self] event in
                guard let self,
                      let sheetWindow = self.trackedView?.window else { return event }
                let parentWindow = sheetWindow.sheetParent
                guard Coordinator.shouldDismiss(
                    eventWindow: event.window,
                    parentWindow: parentWindow
                ) else { return event }
                guard !self.isDismissing else { return nil }
                self.isDismissing = true
                DispatchQueue.main.async { self.onOutsideClick() }
                return nil
            }
        }

        static func shouldDismiss(eventWindow: NSWindow?, parentWindow: NSWindow?) -> Bool {
            guard let eventWindow, let parentWindow else { return false }
            return eventWindow === parentWindow
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            trackedView = nil
            isDismissing = false
        }

        deinit { stop() }
    }
}
