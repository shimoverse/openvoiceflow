import AppKit
import SwiftUI

/// Menu-bar status icon states (design phase 02).
enum StatusIconState: Equatable {
    case idle
    case listening
    case working
    case success
    case error
    case paused
}

/// Renders the 24×16 pt template glyph for each state, following the design
/// file's canvas math verbatim (native/design/02-menu-bar.dc.html). Template
/// images so macOS tints them correctly in light/dark/tinted menu bars.
enum StatusIconRenderer {
    static let size = NSSize(width: 24, height: 16)

    /// Edge-taper envelope from the design: win(u) = sin(πu)^0.85.
    private static func win(_ u: CGFloat) -> CGFloat {
        pow(max(0, sin(.pi * u)), 0.85)
    }

    /// Speech-like amplitude gate from the design: S(t).
    private static func amplitude(_ t: CGFloat) -> CGFloat {
        let gate: CGFloat = (sin(t * 0.9) + sin(t * 0.53 + 1.2)) > 0.9 ? 0.06 : 1
        var v = (sin(t * 2.3) + sin(t * 3.85 + 1.4) + sin(t * 5.9 + 0.4)) / 3
        v = max(0, v * 0.75 + 0.5)
        return min(1, v * gate)
    }

    static func image(for state: StatusIconState, t: CGFloat = 0) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let w = size.width, h = size.height
            let x0 = (w - 16) / 2, mid = h / 2, cx = w / 2
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setLineWidth(1.6)
            ctx.setLineCap(.round)

            switch state {
            case .idle:
                ctx.beginPath()
                for i in 0...16 {
                    let x = CGFloat(i)
                    let y = mid + sin(x * 0.7) * 1.6 * win(x / 16)
                    let p = CGPoint(x: x0 + x, y: y)
                    i == 0 ? ctx.move(to: p) : ctx.addLine(to: p)
                }
                ctx.strokePath()

            case .listening:
                let a = amplitude(t)
                ctx.beginPath()
                for i in 0...16 {
                    let x = CGFloat(i)
                    let y = mid + sin(x * 0.85 + t * 7) * 3.2 * a * win(x / 16)
                    let p = CGPoint(x: x0 + x, y: y)
                    i == 0 ? ctx.move(to: p) : ctx.addLine(to: p)
                }
                ctx.strokePath()

            case .working:
                // Spinning spiral ("coil"): rot = t*6.
                let rot = t * 6
                ctx.beginPath()
                var a: CGFloat = 0
                var first = true
                while a <= 3.6 * .pi {
                    let r = 1.2 + a * 0.42
                    let p = CGPoint(x: cx + cos(a + rot) * r, y: mid + sin(a + rot) * r * 0.9)
                    first ? ctx.move(to: p) : ctx.addLine(to: p)
                    first = false
                    a += 0.15
                }
                ctx.strokePath()

            case .success:
                // 45%-alpha baseline + full-alpha check (assets spec §2).
                ctx.saveGState()
                ctx.setAlpha(0.45)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x0, y: mid))
                ctx.addLine(to: CGPoint(x: x0 + 16, y: mid))
                ctx.strokePath()
                ctx.restoreGState()
                ctx.beginPath()
                ctx.move(to: CGPoint(x: cx - 3, y: mid))
                ctx.addLine(to: CGPoint(x: cx - 0.5, y: mid - 2.5))
                ctx.addLine(to: CGPoint(x: cx + 3.5, y: mid + 2.5))
                ctx.strokePath()

            case .error:
                // Broken line + two dots at the break.
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x0, y: mid))
                ctx.addLine(to: CGPoint(x: cx - 3, y: mid))
                ctx.move(to: CGPoint(x: cx + 3, y: mid + 1))
                ctx.addLine(to: CGPoint(x: x0 + 16, y: mid + 1))
                ctx.strokePath()
                for p in [CGPoint(x: cx - 3, y: mid), CGPoint(x: cx + 3, y: mid + 1)] {
                    ctx.fillEllipse(in: CGRect(x: p.x - 1.4, y: p.y - 1.4, width: 2.8, height: 2.8))
                }

            case .paused:
                // Flat line at 45% alpha + two full-opacity pause ticks.
                ctx.saveGState()
                ctx.setAlpha(0.45)
                ctx.beginPath()
                ctx.move(to: CGPoint(x: x0, y: mid))
                ctx.addLine(to: CGPoint(x: x0 + 16, y: mid))
                ctx.strokePath()
                ctx.restoreGState()
                ctx.fill(CGRect(x: cx - 3.5, y: mid - 3, width: 2, height: 6))
                ctx.fill(CGRect(x: cx + 1.5, y: mid - 3, width: 2, height: 6))
            }
            return true
        }
        image.isTemplate = true
        return image
    }
}

/// Publishes the current status-icon frame. Animates listening/working at
/// 20 fps; static frames otherwise, and always static under Reduce Motion.
@MainActor
final class StatusIconAnimator: ObservableObject {
    @Published private(set) var image: NSImage = StatusIconRenderer.image(for: .idle)

    private var timer: Timer?
    private var start = Date()
    private(set) var state: StatusIconState = .idle

    func set(_ state: StatusIconState) {
        guard state != self.state else { return }
        self.state = state
        timer?.invalidate()
        timer = nil
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let animated = (state == .listening || state == .working) && !reduceMotion
        if animated {
            start = Date()
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let t = CGFloat(Date().timeIntervalSince(self.start))
                    self.image = StatusIconRenderer.image(for: self.state, t: t)
                }
            }
        }
        image = StatusIconRenderer.image(for: state)
    }
}
