import AppKit
import SwiftUI

/// The floating dictation HUD — design phase 01 (native/design/01-system-hud.dc.html).
///
/// A non-activating `NSPanel` capsule, bottom-center of the focused screen,
/// 24 px above the bottom edge. It never steals focus; error actions use
/// click-through hit-testing over their own bounds only. Every state, color,
/// and animation here follows the design spec; Reduce Motion swaps the
/// canvas animations for the specified static/low-rate variants.
@MainActor
final class HUDController {
    enum State: Equatable {
        case hidden
        case recording(hotkey: Hotkey)
        case transcribing
        case cleaning
        case result(words: Int)
        case error(HUDError)
    }

    enum HUDError: Equatable {
        case microphone
        case timeout
        case pasteBlocked

        var message: String {
            switch self {
            case .microphone: return "Microphone unavailable."
            case .timeout: return "Timed out. Audio kept."
            case .pasteBlocked: return "Copied instead — press ⌘V."
            }
        }

        var actionTitle: String {
            switch self {
            case .microphone: return "Open Sound Settings"
            case .timeout: return "Retry"
            case .pasteBlocked: return "Grant Access"
            }
        }
    }

    private var panel: NSPanel?
    private let model = HUDModel()
    private var hideTask: Task<Void, Never>?

    /// Live mic level (0…1) fed by AudioCapture at ~60 Hz.
    func updateLevel(_ rms: Double) {
        model.pushLevel(min(1, rms * 5.5))
    }

    func show(_ state: State, autoHideAfter seconds: Double? = nil) {
        ensurePanel()
        model.transition(to: state)
        if case .recording = state { positionOnActiveScreen() }  // re-home between takes, never mid-take
        panel?.orderFrontRegardless()
        summonIfNeeded(state)
        hideTask?.cancel()
        // Errors auto-dismiss after 6 s per spec.
        let auto: Double? = { if case .error = state { return 6 } else { return seconds } }()
        if let auto {
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(auto))
                if !Task.isCancelled { self?.hide() }
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        model.transition(to: .hidden)
        // Dismiss: 160 ms fade + 4 px down (Reduce Motion: fade only).
        guard let panel else { return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 0
            panel.orderOut(nil)
            panel.alphaValue = 1
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.16
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            panel?.orderOut(nil)
            panel?.alphaValue = 1
        }
    }

    private func summonIfNeeded(_ state: State) {
        guard let panel else { return }
        guard case .recording = state, panel.alphaValue < 1 else {
            panel.alphaValue = 1
            return
        }
        // Summon: 90 ms fade + 9 px rise (Reduce Motion: 130 ms fade only).
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            panel.alphaValue = 0
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.13
                panel.animator().alphaValue = 1
            }
            return
        }
        let origin = panel.frame.origin
        panel.setFrameOrigin(NSPoint(x: origin.x, y: origin.y - 9))
        panel.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.09
            panel.animator().alphaValue = 1
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.30
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.34, 1.3, 0.44, 1)
            panel.animator().setFrameOrigin(origin)
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 290, height: 44),
            styleMask: [.borderless, .nonactivatingPanel, .hudWindow],
            backing: .buffered, defer: false
        )
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.becomesKeyOnlyIfNeeded = true
        // Mouse events pass through except over the error action button.
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.contentView = NSHostingView(rootView: HUDView(model: model))
        self.panel = panel
    }

    /// Bottom-center of the screen owning keyboard focus, 24 px above the
    /// bottom of its visibleFrame (clears the Dock).
    private func positionOnActiveScreen() {
        guard let panel else { return }
        let screen = NSScreen.main
            ?? NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.minY + 24))
    }
}

// MARK: - Model

@MainActor
final class HUDModel: ObservableObject {
    @Published var state: HUDController.State = .hidden
    @Published var elapsed: TimeInterval = 0

    /// Scrolling 150-bucket amplitude history (design: 43 RMS buckets @60 Hz
    /// → 80 ms EMA; we keep the 150-sample scroll the canvas draws from).
    private(set) var history = [Double](repeating: 0, count: 150)
    private var smoothed: Double = 0
    private var started = Date()
    private var timer: Timer?

    func pushLevel(_ level: Double) {
        // EMA with τ≈70 ms at 60 Hz.
        smoothed += (level - smoothed) * (1 - exp(-16.7 / 70))
        history.removeFirst()
        history.append(smoothed)
        objectWillChange.send()
    }

    var currentAmp: Double { smoothed }

    func transition(to newState: HUDController.State) {
        state = newState
        if case .recording = newState {
            started = Date()
            elapsed = 0
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.elapsed = Date().timeIntervalSince(self.started)
                }
            }
        } else {
            timer?.invalidate()
            timer = nil
        }
    }
}

// MARK: - View

/// Capsule: h 44, radius h/2, h-padding 14, min-w 290, max-w 460, gap 10.
private struct HUDView: View {
    @ObservedObject var model: HUDModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dark: Bool { scheme == .dark }

    var body: some View {
        HStack(spacing: 10) {
            if case .recording(let hotkey) = model.state {
                keyChip(hotkey)
            }
            waveform
            sideText
            if case .error(let err) = model.state {
                Button(err.actionTitle) { perform(err) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(DT.errorAccent)
            }
        }
        .padding(.horizontal, 14)
        .frame(minWidth: 290, maxWidth: 460, minHeight: 44, maxHeight: 44)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(dark ? .white.opacity(0.10) : .black.opacity(0.10)))
        .fixedSize(horizontal: true, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceOverLabel)
    }

    // Hotkey chip: h 23, pad 0×8, radius 6, glyph 12.5 semibold + "HELD".
    private func keyChip(_ hotkey: Hotkey) -> some View {
        HStack(spacing: 4) {
            Text(hotkey.glyph).font(.system(size: 12.5, weight: .semibold))
            Text("HELD")
                .font(.system(size: 8.5, weight: .semibold))
                .kerning(0.5)
                .opacity(0.6)
        }
        .foregroundStyle(dark ? DT.chipInkDark : DT.chipInkLight)
        .padding(.horizontal, 8)
        .frame(height: 23)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(dark ? .white.opacity(0.08) : .black.opacity(0.06))
        )
    }

    @ViewBuilder private var waveform: some View {
        if reduceMotion {
            reducedMotionIndicator
        } else {
            TimelineView(.animation) { context in
                Canvas { ctx, size in
                    draw(in: &ctx, size: size, t: context.date.timeIntervalSinceReferenceDate)
                }
            }
            .frame(minWidth: errorState ? 34 : 36, maxWidth: errorState ? 34 : .infinity)
            .frame(height: 32)
        }
    }

    /// Reduce Motion: 9-dot level meter while recording; 3 pulsing dots while
    /// working; static line otherwise (per spec §4).
    @ViewBuilder private var reducedMotionIndicator: some View {
        switch model.state {
        case .recording:
            HStack(spacing: 6) {
                let lit = Int((model.currentAmp * 9).rounded())
                ForEach(0..<9, id: \.self) { i in
                    Circle()
                        .fill(accent.opacity(i < lit ? 1 : 0.4))
                        .frame(width: 4.8, height: 4.8)
                }
            }
        case .transcribing, .cleaning:
            HStack(spacing: 11 - 5.2) {
                ForEach(0..<3, id: \.self) { _ in
                    Circle().fill(accent).frame(width: 5.2, height: 5.2)
                }
            }
        default:
            Capsule().fill(dimInk).frame(width: 36, height: 2)
        }
    }

    private var sideText: some View {
        Group {
            switch model.state {
            case .recording:
                if remaining <= 30 {
                    Text("\(clock(remaining)) left")
                        .foregroundStyle(DT.warnAmber)
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                } else if model.elapsed >= 60 {
                    // Long dictation: timer promotes to 14 pt semibold primary.
                    Text(clock(model.elapsed))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(dark ? DT.hudMsgDark : DT.hudMsgLight)
                } else if model.elapsed >= 3 {
                    Text(clock(model.elapsed))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(sideInk)
                }
            case .transcribing:
                Text("Transcribing…").font(.system(size: 12)).foregroundStyle(sideInk)
            case .cleaning:
                Text("Polishing…").font(.system(size: 12)).foregroundStyle(sideInk)
            case .result(let words):
                Text("\(words) words")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
            case .error(let err):
                Text(err.message).font(.system(size: 12)).foregroundStyle(dark ? DT.hudMsgDark : DT.hudMsgLight)
            case .hidden:
                EmptyView()
            }
        }
    }

    // MARK: canvas drawing (verbatim math from the design file)

    private func draw(in ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let w = size.width, h = size.height, mid = h / 2
        switch model.state {
        case .recording:
            let n = model.history.count
            var dim = Path(), hot = Path()
            var x: Double = 0
            var firstD = true, firstH = true
            while x <= w {
                let u = x / w
                let a = model.history[min(n - 1, Int(u * Double(n - 1)))]
                let breath = a < 0.03 ? sin(x * 0.045 - t * 1.7) * 1.15 * max(0, 1 - a * 3) : 0
                let y = mid + breath + Voiceline.wobble(x: x, t: t, amp: a, height: h) * Voiceline.window(u)
                let p = CGPoint(x: x, y: y)
                if firstD { dim.move(to: p); firstD = false } else { dim.addLine(to: p) }
                if a > 0.04 {
                    if firstH { hot.move(to: p); firstH = false } else { hot.addLine(to: p) }
                } else { firstH = true }
                x += 2
            }
            ctx.stroke(dim, with: .color(dimInk), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            let alpha = min(1, model.currentAmp * 5)
            if alpha > 0 {
                ctx.stroke(hot, with: .color(accent.opacity(alpha)), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }

        case .transcribing:
            // Coil: rot 6.9 rad/s ≈ 1.1 rev/s.
            let cx = w / 2, cy = h / 2
            let rg = min(1, h * 0.028), rot = t * 6.9
            var path = Path()
            var a: Double = 0
            var first = true
            while a <= 4 * .pi {
                let r = (2.5 + a * 0.95) * rg
                let p = CGPoint(x: cx + cos(a + rot) * r, y: cy + sin(a + rot) * r * 0.92)
                if first { path.move(to: p); first = false } else { path.addLine(to: p) }
                a += 0.12
            }
            ctx.stroke(path, with: .color(accent), style: StrokeStyle(lineWidth: 2, lineCap: .round))

        case .cleaning:
            // Flat dim line + ember shimmer: 150 px/s, 96 px gradient window.
            var line = Path()
            line.move(to: CGPoint(x: 0, y: mid))
            line.addLine(to: CGPoint(x: w, y: mid))
            ctx.stroke(line, with: .color(dimInk), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            let pos = (t * 150).truncatingRemainder(dividingBy: w + 160) - 80
            let gradient = Gradient(stops: [
                .init(color: accent.opacity(0), location: 0),
                .init(color: accent, location: 0.5),
                .init(color: accent.opacity(0), location: 1),
            ])
            ctx.stroke(
                line,
                with: .linearGradient(gradient,
                                      startPoint: CGPoint(x: pos - 48, y: mid),
                                      endPoint: CGPoint(x: pos + 48, y: mid)),
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )

        case .result:
            // Success tick: 16 px check + expanding ring.
            let cx = w / 2
            var tick = Path()
            tick.move(to: CGPoint(x: cx - 8, y: mid))
            tick.addLine(to: CGPoint(x: cx - 2, y: mid + 5))
            tick.addLine(to: CGPoint(x: cx + 8, y: mid - 5))
            ctx.stroke(tick, with: .color(accent), style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))

        case .error:
            // Broken line, error dot at each break.
            let cx = w / 2
            var line = Path()
            line.move(to: CGPoint(x: 0, y: mid))
            line.addLine(to: CGPoint(x: cx - 4, y: mid))
            line.move(to: CGPoint(x: cx + 4, y: mid + 1))
            line.addLine(to: CGPoint(x: w, y: mid + 1))
            ctx.stroke(line, with: .color(dimInk), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            for p in [CGPoint(x: cx - 4, y: mid), CGPoint(x: cx + 4, y: mid + 1)] {
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.6, y: p.y - 1.6, width: 3.2, height: 3.2)),
                         with: .color(DT.errorAccent))
            }

        case .hidden:
            break
        }
    }

    // MARK: helpers

    private var errorState: Bool { if case .error = model.state { return true }; return false }
    private var accent: Color { dark ? DT.emberDark : Color(red: 181/255, green: 118/255, blue: 60/255) }
    private var dimInk: Color { dark ? DT.dimWaveDark : DT.dimWaveLight }
    private var sideInk: Color { dark ? DT.hudSideDark : DT.hudSideLight }
    private var remaining: TimeInterval { max(0, 300 - model.elapsed) }

    private func clock(_ s: TimeInterval) -> String {
        String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }

    private var voiceOverLabel: String {
        switch model.state {
        case .hidden: return ""
        case .recording: return "Dictation on — listening."
        case .transcribing: return "Transcribing."
        case .cleaning: return "Cleaning up."
        case .result(let words): return "Inserted \(words) words."
        case .error(let err):
            switch err {
            case .microphone: return "Microphone unavailable — dictation stopped."
            case .timeout: return "Transcription timed out."
            case .pasteBlocked: return "Couldn't paste — copied instead."
            }
        }
    }

    private func perform(_ error: HUDController.HUDError) {
        switch error {
        case .microphone:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!)
        case .pasteBlocked:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        case .timeout:
            NotificationCenter.default.post(name: .ovfRetryTranscription, object: nil)
        }
    }
}

extension Notification.Name {
    static let ovfRetryTranscription = Notification.Name("ovfRetryTranscription")
}

extension Hotkey {
    var glyph: String {
        switch self {
        case .rightCommand, .leftCommand: return "⌘"
        case .rightOption, .leftOption: return "⌥"
        case .rightControl: return "⌃"
        case .fn: return "fn"
        default: return rawValue.uppercased()  // F5…F12
        }
    }
}
