import AppKit
import SwiftUI

/// "I live up there" needs a *there*. While the welcome step is on screen,
/// this hangs a small non-interactive bubble directly beneath the app's own
/// menu-bar item, so the sentence and the icon connect without the user
/// having to scan the whole bar. If the item can't be found on screen — a
/// crowded menu bar or the notch has swallowed it — `show()` returns false
/// and the welcome step draws a mock menu bar inside the card instead.
@MainActor
enum HelloCallout {
    private static var panel: NSPanel?

    /// Screen frame of this app's status-bar item, if macOS is showing it.
    ///
    /// The status item is hosted in a window this process owns, so it appears
    /// in `NSApp.windows`. Its class (NSStatusBarWindow) is not API, which is
    /// why this matches the class *name* and then validates that the frame
    /// really occupies a menu-bar slot before trusting it.
    private static func anchorFrame() -> NSRect? {
        for window in NSApp.windows
        where String(describing: type(of: window)).contains("StatusBarWindow") {
            let frame = window.frame
            guard frame.width > 0, frame.height > 0,
                  let screen = NSScreen.screens.first(where: { $0.frame.intersects(frame) }),
                  // In the menu-bar band, i.e. above the visible (below-menu) area.
                  frame.minY >= screen.visibleFrame.maxY - 1
            else { continue }
            // On a notched Mac an item can exist yet sit under the notch,
            // invisible. The auxiliary areas are the two usable strips beside
            // the notch; an item not inside either is not actually on screen.
            if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
               !left.contains(frame), !right.contains(frame) {
                continue
            }
            return frame
        }
        return nil
    }

    /// Present the bubble under the live icon. False = caller should fall
    /// back to an in-window illustration.
    @discardableResult
    static func show() -> Bool {
        dismiss()
        guard let anchor = anchorFrame(),
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) })
        else { return false }

        // Size the bubble first, then clamp it on screen and aim the arrow
        // back at the icon so clamping never detaches the two visually.
        let probe = NSHostingController(rootView: CalloutBubble(arrowX: 0))
        let size = probe.view.fittingSize
        let x = min(max(anchor.midX - size.width / 2, screen.visibleFrame.minX + 8),
                    screen.visibleFrame.maxX - size.width - 8)
        let host = NSHostingController(rootView: CalloutBubble(arrowX: anchor.midX - x))

        let panel = NSPanel(
            contentRect: NSRect(x: x, y: anchor.minY - size.height - 2,
                                width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false  // the bubble draws its own soft shadow
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .transient]
        panel.contentViewController = host
        panel.orderFront(nil)
        Self.panel = panel
        return true
    }

    static func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }
}

/// The bubble itself: an up-arrow speech shape in system material, so it
/// reads over any wallpaper in either appearance.
private struct CalloutBubble: View {
    /// Arrow tip x, in bubble coordinates — aimed at the icon's midX.
    var arrowX: CGFloat

    var body: some View {
        Text("Here — this little waveform.")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .padding(.top, CalloutShape.arrowHeight)
            .background(
                CalloutShape(arrowX: arrowX)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
            )
            .overlay(CalloutShape(arrowX: arrowX).strokeBorder(.separator, lineWidth: 1))
            .fixedSize()
    }
}

/// Rounded rect with a small triangle on top; one shape so material and
/// hairline wrap the whole outline seamlessly.
private struct CalloutShape: InsettableShape {
    static let arrowHeight: CGFloat = 7
    static let arrowHalfWidth: CGFloat = 8

    var arrowX: CGFloat
    var inset: CGFloat = 0

    func inset(by amount: CGFloat) -> CalloutShape {
        var copy = self
        copy.inset += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 9 - inset
        let body = CGRect(x: rect.minX + inset,
                          y: rect.minY + Self.arrowHeight + inset,
                          width: rect.width - inset * 2,
                          height: rect.height - Self.arrowHeight - inset * 2)
        // Keep the tip clear of the corner arcs however far the bubble slid.
        let tip = min(max(arrowX, body.minX + r + Self.arrowHalfWidth),
                      body.maxX - r - Self.arrowHalfWidth)

        var path = Path()
        path.move(to: CGPoint(x: body.minX + r, y: body.minY))
        path.addLine(to: CGPoint(x: tip - Self.arrowHalfWidth, y: body.minY))
        path.addLine(to: CGPoint(x: tip, y: rect.minY + inset))
        path.addLine(to: CGPoint(x: tip + Self.arrowHalfWidth, y: body.minY))
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.minY),
                    tangent2End: CGPoint(x: body.maxX, y: body.maxY), radius: r)
        path.addArc(tangent1End: CGPoint(x: body.maxX, y: body.maxY),
                    tangent2End: CGPoint(x: body.minX, y: body.maxY), radius: r)
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.maxY),
                    tangent2End: CGPoint(x: body.minX, y: body.minY), radius: r)
        path.addArc(tangent1End: CGPoint(x: body.minX, y: body.minY),
                    tangent2End: CGPoint(x: body.maxX, y: body.minY), radius: r)
        path.closeSubpath()
        return path
    }
}
