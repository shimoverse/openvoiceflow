import AppKit
import ApplicationServices
import CoreGraphics

/// Inserts text at the cursor by placing it on the pasteboard and synthesizing
/// ⌘V with `CGEventPost`.
///
/// This needs only **Accessibility** — unlike the Python app's
/// `osascript … System Events` path, which additionally triggers an Apple
/// Events (Automation) consent dialog and spawns a subprocess on every paste.
enum Paster {
    private static let vKeyCode: CGKeyCode = 0x09  // kVK_ANSI_V

    /// Paste `text` at the current cursor and report whether the synthetic paste
    /// could actually be delivered. Preserves the user's clipboard (including
    /// non-text contents like images/files) on success by snapshotting and
    /// restoring the pasteboard items.
    ///
    /// If the process isn't trusted for Accessibility, `CGEventPost` is silently
    /// dropped — so rather than paste into the void *and* wipe the clipboard, we
    /// leave the dictated text on the clipboard (no restore) and return `false`
    /// so the caller can tell the user to press ⌘V.
    @discardableResult
    static func paste(_ text: String) -> Bool {
        let pb = NSPasteboard.general

        guard AXIsProcessTrusted() else {
            // Can't synthesize ⌘V — keep the text on the clipboard for a manual paste.
            pb.clearContents()
            pb.setString(text, forType: .string)
            return false
        }

        let saved = snapshot(pb)
        pb.clearContents()
        pb.setString(text, forType: .string)

        sendCommandV()

        // Restore after the target app has had a moment to read the paste.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            restore(saved, to: pb)
        }
        return true
    }

    private static func sendCommandV() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }

    // MARK: clipboard snapshot/restore (type-preserving)

    private static func snapshot(_ pb: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pb.pasteboardItems ?? []).map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { dict[type] = data }
            }
            return dict
        }
    }

    private static func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], to pb: NSPasteboard) {
        guard !saved.isEmpty else { return }
        pb.clearContents()
        let items: [NSPasteboardItem] = saved.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict { item.setData(data, forType: type) }
            return item
        }
        pb.writeObjects(items)
    }
}
