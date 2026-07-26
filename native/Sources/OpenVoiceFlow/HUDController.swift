import AppKit
import SwiftUI

/// The floating dictation HUD — phase-06 redesign.
///
/// A non-activating `NSPanel` capsule, bottom-centre of the focused screen,
/// 24 px above the bottom edge. It never steals focus; error actions use
/// click-through hit-testing over their own bounds only.
///
/// Two things changed in phase 06. It shrank from 290×44 to 172×38 at rest —
/// at the old size it was a banner, and it is on screen during every single
/// dictation. And the line now **morphs** between states rather than cutting
/// between five unrelated drawings, so it reads as one object doing different
/// jobs.
///
/// It stays bottom-centre. Following the caret would mean reading text position
/// out of every app through the Accessibility API, and "I don't read what's on
/// your screen" is a promise the permissions copy makes explicitly. Bottom
/// centre costs no extra permission, never occludes the insertion point, and is
/// in the same place every time — which is what "glanceable" actually means.
@MainActor
final class HUDController {
    enum State: Equatable {
        case hidden
        case recording(hotkey: Hotkey)
        case transcribing
        case cleaning
        /// The tail of what was inserted — or a word count when the user has
        /// turned `echoInsertedText` off. A count is a receipt; the tail is
        /// proof, and it lets someone catch a bad transcription without looking
        /// away from their cursor.
        case result(tail: String)
        /// Released too soon / nothing heard — a gentle nudge, not an error.
        case tooShort
        case error(HUDError)
    }

    enum HUDError: Equatable {
        case microphone
        case timeout
        case pasteBlocked

        var message: String {
            switch self {
            case .microphone: return "No microphone."
            case .timeout: return "Took too long — audio kept."
            case .pasteBlocked: return "Copied instead — press ⌘V"
            }
        }

        var actionTitle: String {
            switch self {
            case .microphone: return "Sound settings"
            case .timeout: return "Try again"
            case .pasteBlocked: return "Fix"
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

    /// The per-take ceiling (seconds), so the HUD countdown matches Settings.
    func setMaxSeconds(_ seconds: Double) { model.maxSeconds = seconds }

    /// Whether to draw the hotkey chip — true only for the first 7 days after
    /// the hotkey was learned (see `Settings.hotkeyLearnedAt`).
    func setShowChip(_ show: Bool) { model.showChip = show }

    func show(_ state: State, autoHideAfter seconds: Double? = nil) {
        ensurePanel()
        model.transition(to: state)
        if case .recording = state { positionOnActiveScreen() }  // re-home between takes, never mid-take
        panel?.orderFrontRegardless()
        summonIfNeeded(state)
        hideTask?.cancel()
        // Errors auto-dismiss after 6 s per spec; success holds for dwellSuccess;
        // the "keep going" nudge is brief.
        let auto: Double? = {
            switch state {
            case .error: return 6
            case .tooShort: return seconds ?? 2.4
            case .result: return seconds ?? DT.dwellSuccess
            default: return seconds
            }
        }()
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
        // Sized for the widest state; the capsule sizes itself inside and the
        // panel background is clear, so narrower states simply centre.
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: DT.hudMax, height: DT.hudHeight),
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

// MARK: - The one line

/// The five shapes the HUD's single stroke takes.
///
/// Every generator below already existed inside `draw()`; what's new is that
/// they all resolve to the *same* fixed-length point array, which is what makes
/// tweening between them possible.
enum HUDShape {
    case wave, coil, flat, tick, broken
}

/// A sampled stroke: a fixed-length point array plus the indices where the pen
/// lifts (only the broken error line uses those).
struct HUDLine {
    var points: [CGPoint]
    var breaks: Set<Int> = []
}

enum HUDGeometry {
    /// 128 is plenty at these sizes and cheap to lerp per frame.
    static let samples = 128

    static func line(
        _ shape: HUDShape, size: CGSize, t: Double,
        history: [Double], amp: Double
    ) -> HUDLine {
        let w = size.width, h = size.height, mid = h / 2
        switch shape {
        case .wave:
            // 150-bucket amplitude history; breath only applies when quiet.
            let n = history.count
            var pts: [CGPoint] = []
            pts.reserveCapacity(samples)
            for i in 0..<samples {
                let u = Double(i) / Double(samples - 1)
                let x = u * w
                let a = history[min(n - 1, Int(u * Double(n - 1)))]
                let breath = a < 0.03 ? sin(x * 0.045 - t * 1.7) * 1.15 * max(0, 1 - a * 3) : 0
                let y = mid + breath + Voiceline.wobble(x: x, t: t, amp: a, height: h) * Voiceline.window(u)
                pts.append(CGPoint(x: x, y: y))
            }
            return HUDLine(points: pts)

        case .coil:
            // rot 6.9 rad/s ≈ 1.1 rev/s, sweeping to 4π.
            let cx = w / 2, cy = mid
            let rg = min(1, h * 0.028), rot = t * 6.9
            var pts: [CGPoint] = []
            pts.reserveCapacity(samples)
            for i in 0..<samples {
                let a = Double(i) / Double(samples - 1) * 4 * .pi
                let r = (2.5 + a * 0.95) * rg
                pts.append(CGPoint(x: cx + cos(a + rot) * r, y: cy + sin(a + rot) * r * 0.92))
            }
            return HUDLine(points: pts)

        case .flat:
            return HUDLine(points: resample([CGPoint(x: 0, y: mid), CGPoint(x: w, y: mid)], to: samples))

        case .tick:
            // 16 pt check, centred.
            let cx = w / 2
            let raw = [
                CGPoint(x: cx - 8, y: mid),
                CGPoint(x: cx - 2, y: mid + 5),
                CGPoint(x: cx + 8, y: mid - 5),
            ]
            return HUDLine(points: resample(raw, to: samples))

        case .broken:
            // Two runs with an 8 pt gap; the right half sits 1 pt lower.
            let gap: CGFloat = 8, cx = w / 2
            let half = samples / 2
            let left = resample([CGPoint(x: 0, y: mid), CGPoint(x: cx - gap / 2, y: mid)], to: half)
            let right = resample([CGPoint(x: cx + gap / 2, y: mid + 1), CGPoint(x: w, y: mid + 1)],
                                 to: samples - half)
            return HUDLine(points: left + right, breaks: [half])
        }
    }

    /// Walk a polyline by arc length and emit `n` evenly spaced points, so a
    /// 2- or 3-point shape can be tweened against a 128-point one.
    static func resample(_ pts: [CGPoint], to n: Int) -> [CGPoint] {
        guard pts.count > 1 else { return Array(repeating: pts.first ?? .zero, count: n) }
        var lengths: [CGFloat] = [0]
        var total: CGFloat = 0
        for i in 1..<pts.count {
            total += hypot(pts[i].x - pts[i - 1].x, pts[i].y - pts[i - 1].y)
            lengths.append(total)
        }
        guard total > 0 else { return Array(repeating: pts[0], count: n) }
        var out: [CGPoint] = []
        out.reserveCapacity(n)
        var seg = 1
        for i in 0..<n {
            let target = CGFloat(i) / CGFloat(n - 1) * total
            while seg < pts.count - 1 && lengths[seg] < target { seg += 1 }
            let span = lengths[seg] - lengths[seg - 1]
            let k = span > 0 ? (target - lengths[seg - 1]) / span : 0
            let a = pts[seg - 1], b = pts[seg]
            out.append(CGPoint(x: a.x + (b.x - a.x) * k, y: a.y + (b.y - a.y) * k))
        }
        return out
    }

    /// `spring(response:dampingFraction:)` in closed form, so the morph can be
    /// driven by the Canvas clock rather than a view animation. Slight overshoot
    /// is kept (that is the spring); it is bounded so a lerp can't extrapolate
    /// into nonsense.
    static func springProgress(_ elapsed: Double, response: Double = 0.22,
                               damping: Double = 0.85) -> Double {
        guard elapsed > 0 else { return 0 }
        guard elapsed < 0.6 else { return 1 }
        let omega = 2 * Double.pi / response
        let value: Double
        if damping < 1 {
            let wd = omega * (1 - damping * damping).squareRoot()
            let decay = exp(-damping * omega * elapsed)
            value = 1 - decay * (cos(wd * elapsed) + (damping * omega / wd) * sin(wd * elapsed))
        } else {
            value = 1 - exp(-omega * elapsed) * (1 + omega * elapsed)
        }
        return min(1.08, max(0, value))
    }
}

// MARK: - Model

@MainActor
final class HUDModel: ObservableObject {
    @Published var state: HUDController.State = .hidden
    @Published var elapsed: TimeInterval = 0
    /// Per-take ceiling (seconds); drives the amber "time left" countdown.
    var maxSeconds: Double = 300
    /// Chip visibility is decided by the controller from Settings.
    var showChip: Bool = true

    /// Scrolling 150-bucket amplitude history (design: 43 RMS buckets @60 Hz
    /// → 80 ms EMA; we keep the 150-sample scroll the canvas draws from).
    private(set) var history = [Double](repeating: 0, count: 150)
    private var smoothed: Double = 0
    private var started = Date()
    private var timer: Timer?

    // ── morph clock ─────────────────────────────────────────────────────────
    /// The shape being left and the shape being entered. Interpolating these
    /// point-for-point is what makes wave → coil read as one line changing job
    /// rather than two drawings swapping.
    private(set) var fromShape: HUDShape = .flat
    private(set) var toShape: HUDShape = .flat
    private var morphStart = Date.distantPast

    /// 0…1 (plus a little overshoot) across `DT.morph`'s 220 ms. Reduce Motion
    /// swaps at the frame boundary instead of tweening.
    var morphProgress: Double {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return 1 }
        return HUDGeometry.springProgress(Date().timeIntervalSince(morphStart))
    }

    func pushLevel(_ level: Double) {
        // EMA with τ≈70 ms at 60 Hz.
        smoothed += (level - smoothed) * (1 - exp(-16.7 / 70))
        history.removeFirst()
        history.append(smoothed)
        objectWillChange.send()
    }

    var currentAmp: Double { smoothed }

    func transition(to newState: HUDController.State) {
        let next = Self.shape(for: newState)
        if next != toShape {
            fromShape = toShape
            toShape = next
            morphStart = Date()
        }
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

    static func shape(for state: HUDController.State) -> HUDShape {
        switch state {
        case .recording: return .wave
        case .transcribing: return .coil
        case .cleaning: return .flat
        case .result: return .tick
        case .error: return .broken
        case .tooShort, .hidden: return .flat
        }
    }

    /// Three real checkpoints, not a fake continuous bar: a made-up percentage
    /// would be dishonest, and 0 / 0.45 / 0.84 / 1.0 are things that actually
    /// happened. `nil` means no operation is in flight, so no spine is drawn.
    var spineFraction: Double? {
        switch state {
        case .transcribing: return 0.45
        case .cleaning: return 0.84
        case .result: return 1.0
        default: return nil
        }
    }
}

// MARK: - View

/// Capsule: h 38, radius h/2, h-padding 12, gap 9, width per state.
private struct HUDView: View {
    @ObservedObject var model: HUDModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var dark: Bool { scheme == .dark }

    /// Per-state widths: the capsule is only as wide as its content needs.
    private var stateWidth: CGFloat {
        switch model.state {
        case .result: return 300
        case .tooShort: return 244
        case .error: return DT.hudMax
        default: return DT.hudMin
        }
    }

    var body: some View {
        HStack(spacing: DT.hudGap) {
            if case .recording(let hotkey) = model.state, model.showChip {
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
        .padding(.horizontal, DT.hudPad)
        .frame(width: stateWidth, height: DT.hudHeight)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(dark ? .white.opacity(0.10) : .black.opacity(0.10)))
        .overlay(alignment: .bottom) { spine }
        .animation(reduceMotion ? nil : DT.snap, value: stateWidth)  // `grow`
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
            RoundedRectangle(cornerRadius: DT.rControl)
                .fill(dark ? .white.opacity(0.08) : .black.opacity(0.06))
        )
    }

    /// The progress hairline: 1.5 pt, inset 12 each side, 5 pt above the bottom
    /// edge. Absent — not empty — when nothing is in flight.
    @ViewBuilder private var spine: some View {
        if let fraction = model.spineFraction {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(dark ? .white.opacity(0.07) : .black.opacity(0.07))
                    Capsule()
                        .fill(dark ? DT.emberDark : Color(red: 181 / 255, green: 118 / 255, blue: 60 / 255))
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: DT.spineWeight)
            .padding(.horizontal, 12)
            .padding(.bottom, 5)
            .transition(.opacity)
            .animation(reduceMotion ? .linear(duration: 0.2) : DT.spineCurve, value: fraction)
        }
    }

    /// Frame rate is a state, not a constant: display rate while recording (it
    /// is tracking a live signal), 20 fps while the coil and shimmer run (they
    /// read identically), and nothing at all when hidden.
    @ViewBuilder private var waveform: some View {
        if reduceMotion {
            reducedMotionIndicator
        } else {
            switch model.state {
            case .hidden:
                EmptyView()
            case .recording, .result:
                TimelineView(.animation) { context in canvas(context.date) }
                    .frame(minWidth: 36, maxWidth: .infinity).frame(height: 26)
            case .transcribing, .cleaning, .tooShort:
                TimelineView(.periodic(from: .now, by: 1.0 / 20)) { context in canvas(context.date) }
                    .frame(minWidth: 36, maxWidth: .infinity).frame(height: 26)
            case .error:
                canvas(Date())
                    .frame(width: 34, height: 26)
            }
        }
    }

    private func canvas(_ date: Date) -> some View {
        Canvas { ctx, size in
            draw(in: &ctx, size: size, t: date.timeIntervalSinceReferenceDate)
        }
    }

    /// Reduce Motion: 9-dot level meter while recording (10 Hz); 3 pulsing dots
    /// while working; static capsule otherwise; the tick drawn complete.
    @ViewBuilder private var reducedMotionIndicator: some View {
        switch model.state {
        case .recording:
            // 10 Hz is the spec: fast enough to track a voice, slow enough not
            // to be the motion Reduce Motion is asking us to drop.
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                HStack(spacing: 6) {
                    let lit = Int((model.currentAmp * 9).rounded())
                    ForEach(0..<9, id: \.self) { i in
                        Circle()
                            .fill(accent.opacity(i < lit ? 1 : 0.4))
                            .frame(width: 4.8, height: 4.8)
                    }
                }
            }
        case .transcribing, .cleaning:
            TimelineView(.periodic(from: .now, by: 0.9)) { context in
                let phase = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 5.8) {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().fill(accent.opacity(0.45 + 0.55 * (0.5 + 0.5 * sin(phase * 2 + Double(i) * 0.7))))
                            .frame(width: 5.2, height: 5.2)
                    }
                }
            }
        case .result:
            Canvas { ctx, size in
                var line = Path()
                let pts = HUDGeometry.line(.tick, size: size, t: 0, history: model.history, amp: 0).points
                line.addLines(pts)
                ctx.stroke(line, with: .color(accent),
                           style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
            }
            .frame(width: 34, height: 26)
        default:
            Capsule().fill(dimInk).frame(width: 36, height: 2)
        }
    }

    private var sideText: some View {
        Group {
            switch model.state {
            case .recording:
                if model.elapsed < primerSeconds {
                    // Live cue: encourage the user to keep talking past the
                    // reliable-transcription threshold before releasing.
                    Text("Keep going")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                } else if remaining <= 30 {
                    Text("\(clock(remaining)) left")
                        .foregroundStyle(DT.warnAmber)
                        .font(.system(size: 12, weight: .bold).monospacedDigit())
                } else if model.elapsed >= 60 {
                    // Long dictation: timer promotes to 14 pt semibold primary.
                    Text(clock(model.elapsed))
                        .font(.system(size: 14, weight: .semibold).monospacedDigit())
                        .foregroundStyle(dark ? DT.hudMsgDark : DT.hudMsgLight)
                } else if model.elapsed >= 20 {
                    // 20 s, not 3 s: a timer that appears three seconds into
                    // every take is a stopwatch nobody asked for.
                    Text(clock(model.elapsed))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(sideInk)
                }
            case .transcribing:
                Text("Transcribing").font(.system(size: 12)).foregroundStyle(sideInk)
            case .cleaning:
                Text("Polishing").font(.system(size: 12)).foregroundStyle(sideInk)
            case .result(let tail):
                Text(tail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(dark ? DT.hudMsgDark : DT.hudMsgLight)
                    .lineLimit(1)
                    .truncationMode(.tail)
            case .tooShort:
                Text("Hold a moment longer")
                    .font(.system(size: 12))
                    .foregroundStyle(dark ? DT.hudMsgDark : DT.hudMsgLight)
            case .error(let err):
                Text(err.message).font(.system(size: 12)).foregroundStyle(dark ? DT.hudMsgDark : DT.hudMsgLight)
            case .hidden:
                EmptyView()
            }
        }
    }

    // MARK: canvas drawing

    /// Draws the single stroke, tweened between the shape being left and the one
    /// being entered. Per-state decoration (the hot ember overlay, the polish
    /// shimmer, the error dots, the too-short dots) fades in as the morph
    /// completes so nothing pops mid-tween.
    private func draw(in ctx: inout GraphicsContext, size: CGSize, t: Double) {
        let progress = model.morphProgress
        let from = HUDGeometry.line(model.fromShape, size: size, t: t,
                                    history: model.history, amp: model.currentAmp)
        let to = HUDGeometry.line(model.toShape, size: size, t: t,
                                  history: model.history, amp: model.currentAmp)

        var pts: [CGPoint]
        if progress >= 1 {
            pts = to.points
        } else {
            pts = zip(from.points, to.points).map { a, b in
                CGPoint(x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress)
            }
        }
        // Breaks only apply once the target has arrived; during a tween the line
        // stays continuous, which is the whole point of morphing it.
        let breaks = progress >= 1 ? to.breaks : []

        let settled = progress >= 1
        let isTick = model.toShape == .tick
        let lineStyle = StrokeStyle(lineWidth: isTick && settled ? 2.4 : 2,
                                    lineCap: .round, lineJoin: .round)
        let base: Color = {
            switch model.toShape {
            case .tick: return accent
            case .coil: return accent
            case .broken: return DT.errorAccent
            default: return dimInk
            }
        }()

        stroke(&ctx, points: pts, breaks: breaks, color: base, style: lineStyle)

        guard settled else { return }

        switch model.state {
        case .recording:
            // Hot ember overlay on the segments that are actually loud.
            let alpha = min(1, model.currentAmp * 5)
            guard alpha > 0 else { break }
            let n = model.history.count
            var hot = Path()
            var lifted = true
            for (i, p) in pts.enumerated() {
                let u = Double(i) / Double(pts.count - 1)
                let a = model.history[min(n - 1, Int(u * Double(n - 1)))]
                if a > 0.04 {
                    lifted ? hot.move(to: p) : hot.addLine(to: p)
                    lifted = false
                } else {
                    lifted = true
                }
            }
            ctx.stroke(hot, with: .color(accent.opacity(alpha)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

        case .cleaning:
            // Ember shimmer travelling at 150 px/s over a 96 px window.
            let w = size.width, mid = size.height / 2
            var line = Path()
            line.addLines(pts)
            let pos = (t * 150).truncatingRemainder(dividingBy: w + 160) - 80
            let gradient = Gradient(stops: [
                .init(color: accent.opacity(0), location: 0),
                .init(color: accent, location: 0.5),
                .init(color: accent.opacity(0), location: 1),
            ])
            ctx.stroke(line,
                       with: .linearGradient(gradient,
                                             startPoint: CGPoint(x: pos - 48, y: mid),
                                             endPoint: CGPoint(x: pos + 48, y: mid)),
                       style: StrokeStyle(lineWidth: 2, lineCap: .round))

        case .tooShort:
            // Three pulsing dots instead of a line.
            let cx = size.width / 2, mid = size.height / 2
            for i in 0..<3 {
                let scale = 0.6 + 0.4 * (0.5 + 0.5 * sin(3 * t + 0.6 * Double(i)))
                let r = 2.2 * scale
                let x = cx + Double(i - 1) * 9
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: mid - r, width: r * 2, height: r * 2)),
                         with: .color(DT.warnAmber.opacity(0.55 + 0.45 * scale)))
            }

        case .error:
            // 1.6 pt dots at each break.
            for index in to.breaks {
                for i in [index - 1, index] where pts.indices.contains(i) {
                    let p = pts[i]
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.6, y: p.y - 1.6, width: 3.2, height: 3.2)),
                             with: .color(DT.errorAccent))
                }
            }

        default:
            break
        }
    }

    /// Strokes a sampled line, lifting the pen at `breaks`.
    private func stroke(_ ctx: inout GraphicsContext, points: [CGPoint], breaks: Set<Int>,
                        color: Color, style: StrokeStyle) {
        guard points.count > 1 else { return }
        var path = Path()
        var lifted = true
        for (i, p) in points.enumerated() {
            if breaks.contains(i) { lifted = true }
            lifted ? path.move(to: p) : path.addLine(to: p)
            lifted = false
        }
        ctx.stroke(path, with: .color(color), style: style)
    }

    // MARK: palette + helpers

    private var accent: Color {
        // Note: the HUD's light accent is deliberately *not* emberLight.
        dark ? DT.emberDark : Color(red: 181 / 255, green: 118 / 255, blue: 60 / 255)
    }
    private var dimInk: Color { dark ? DT.dimWaveDark : DT.dimWaveLight }
    private var sideInk: Color { dark ? DT.hudSideDark : DT.hudSideLight }

    /// Below this the take is too brief to transcribe reliably.
    private var primerSeconds: Double { 0.9 }
    private var remaining: Double { max(0, model.maxSeconds - model.elapsed) }

    private func clock(_ s: TimeInterval) -> String {
        String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
    }

    private var voiceOverLabel: String {
        switch model.state {
        case .recording: return "Dictation on — listening."
        case .transcribing: return "Transcribing."
        case .cleaning: return "Cleaning up."
        // Announce what landed, not how much of it: the tail is the useful part.
        case .result(let tail): return "Inserted: \(tail)"
        case .tooShort: return "Too short — hold a moment longer."
        case .error(let err):
            switch err {
            case .microphone: return "Microphone unavailable — dictation stopped."
            case .timeout: return "Transcription took too long."
            case .pasteBlocked: return "Couldn't paste — copied instead."
            }
        case .hidden: return ""
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
    /// The single character (or "fn") shown in the HUD chip and the menu-bar
    /// summary. Lives here because the chip is its only consumer.
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
