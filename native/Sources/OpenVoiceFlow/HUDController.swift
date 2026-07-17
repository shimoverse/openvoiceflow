import AppKit
import SwiftUI

/// The floating status pill. A non-activating `NSPanel` (never steals focus)
/// hosting a SwiftUI view, positioned on the display the user is actually
/// working on and honoring Reduce Motion.
@MainActor
final class HUDController {
    enum State: Equatable {
        case hidden
        case recording
        case transcribing
        case cleaning
        case result(String)
        case error(String)
    }

    private var panel: NSPanel?
    private let model = HUDModel()
    private var hideTask: Task<Void, Never>?

    func show(_ state: State, autoHideAfter seconds: Double? = nil) {
        ensurePanel()
        model.state = state
        positionOnActiveScreen()
        panel?.alphaValue = 0
        panel?.orderFrontRegardless()
        animateAlpha(to: 1)
        hideTask?.cancel()
        if let seconds {
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(seconds))
                if !Task.isCancelled { self?.hide() }
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        animateAlpha(to: 0) { [weak self] in self?.panel?.orderOut(nil) }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        self.panel = panel
    }

    /// Place the pill bottom-center of the screen holding the mouse/active app,
    /// within its `visibleFrame` (so it clears the Dock and notch).
    private func positionOnActiveScreen() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + 96
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func animateAlpha(to target: CGFloat, completion: (() -> Void)? = nil) {
        guard let panel else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = target
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = target > 0 ? 0.18 : 0.28
            panel.animator().alphaValue = target
        } completionHandler: completion
    }
}

/// Observable model driving the SwiftUI HUD.
@MainActor
final class HUDModel: ObservableObject {
    @Published var state: HUDController.State = .hidden
}

/// The pill's SwiftUI content: SF Symbol + label + real progress spinner.
private struct HUDView: View {
    @ObservedObject var model: HUDModel

    var body: some View {
        HStack(spacing: 8) {
            icon
            Text(label).font(.system(size: 13, weight: .medium)).lineLimit(1)
        }
        .padding(.horizontal, 16)
        .frame(minWidth: 160, minHeight: 40)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.08)))
        .fixedSize()
    }

    @ViewBuilder private var icon: some View {
        switch model.state {
        case .recording:
            Image(systemName: "mic.fill").foregroundStyle(.red).symbolEffect(.pulse)
        case .transcribing, .cleaning:
            ProgressView().controlSize(.small)
        case .result:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
        case .hidden:
            EmptyView()
        }
    }

    private var label: String {
        switch model.state {
        case .hidden: return ""
        case .recording: return "Listening…"
        case .transcribing: return "Transcribing…"
        case .cleaning: return "Cleaning up…"
        case .result(let t): return t
        case .error(let e): return e
        }
    }
}
