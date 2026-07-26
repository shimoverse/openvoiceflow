import SwiftUI

/// The palette onboarding draws from — the phase-06 light/dark pairs (T2).
///
/// Onboarding used to force `.preferredColorScheme(.dark)` and hardcode hex
/// literals inline, so a Mac in light mode got a dark window that matched
/// nothing else on screen. Every role below resolves from the system scheme,
/// exactly like `DashboardView` already does, and every value is an existing
/// `DT` token or a spec'd tertiary/label pair.
struct OBPalette {
    let ground: Color
    let card: Color
    let hairline: Color
    let ink: Color
    let ink2: Color
    let ink3: Color
    let accent: Color
    /// Label on top of an accent fill — near-black on dark, white on light.
    let onAccent: Color

    static func resolve(_ scheme: ColorScheme) -> OBPalette {
        scheme == .dark
            ? OBPalette(
                ground: DT.winDark,
                card: .white.opacity(0.04),
                hairline: .white.opacity(0.07),
                ink: DT.inkDark,
                ink2: DT.ink2Dark,
                ink3: Color(hex: 0x6B6558),
                accent: DT.emberDark,
                onAccent: Color(hex: 0x1A1508))
            : OBPalette(
                ground: DT.winLight,
                card: .black.opacity(0.035),
                hairline: .black.opacity(0.07),
                ink: DT.inkLight,
                ink2: DT.ink2Light,
                ink3: Color(hex: 0x9A9384),
                accent: DT.emberLight,
                onAccent: .white)
    }
}

/// First-run onboarding — phase-06 redesign.
///
/// Five steps, one idea each: welcome ("I live up there") → three permissions
/// granted in sequence → Know-Me while the speech engine downloads → say
/// anything → the payoff. No model names, hostnames, checksums or file paths
/// outside the failure disclosure; the user should feel taken care of, not
/// informed.
struct OnboardingView: View {
    @ObservedObject var controller: AppController
    @State private var step = 0
    @State private var granted: [Permission: Bool] = [:]
    @State private var downloadDone = false
    @State private var helloDone = false
    /// Polls TCC while the permissions step is on screen (see T4).
    @State private var permissionWatch: Task<Void, Never>?
    /// The menu-bar glyph waves once per run (T7).
    @State private var helloWaved = false
    /// How many words of the ink fill have been inked in (T9).
    @State private var revealedWords = 0
    @State private var fillTask: Task<Void, Never>?
    /// Download progress, mirrored up from the step so the footer can show it.
    @State private var downloadPercent = "0%"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme

    private var p: OBPalette { OBPalette.resolve(scheme) }

    var body: some View {
        VStack(spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 44)
                .padding(.top, 24)
            footer
        }
        .frame(width: 720, height: 470)
        .background(p.ground)
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didBecomeKeyNotification)) { _ in refreshGrants() }
    }

    // MARK: chrome

    // The 4-dot pagination header is deliberately gone: it is a web carousel
    // pattern. Mac onboarding names its steps or shows nothing.

    private var footer: some View {
        HStack {
            if step > 0 && step < 4 {
                Button("‹ Back") { step -= 1 }
                    .buttonStyle(.plain).foregroundStyle(p.ink2)
            } else {
                Text("Takes about a minute.")
                    .font(.system(size: 12.5)).foregroundStyle(p.ink3)
            }
            Spacer()
            primaryButton
        }
        .padding(20)
    }

    @ViewBuilder private var primaryButton: some View {
        switch step {
        case 0:
            pill("Let's go") { step = 1 }
        case 1:
            // No Continue until all three are granted — before that, quiet
            // progress rather than a button that would skip setup.
            if allGranted {
                pill("Continue") { step = 2 }
            } else {
                quiet("\(grantedCount) of 3")
            }
        case 2:
            if downloadDone {
                pill("Try it") { step = 3 }
            } else {
                quiet(downloadPercent)
            }
        case 3:
            // No pill here at all: the only way forward is to speak (or Skip).
            EmptyView()
        default:
            pill("Start using it", disabled: !helloDone) {
                controller.settings.didOnboard = true
                controller.settings.save()
                _ = controller.startListening()
                NSApplication.shared.keyWindow?.close()
            }
        }
    }

    /// Primary pill: 13.5 pt semibold, padding 22 × 10, capsule.
    private func pill(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(disabled ? p.ink3 : p.onAccent)
                .padding(.horizontal, 22).padding(.vertical, 10)
                .background(Capsule().fill(disabled ? p.card : p.accent))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    /// Quiet progress text where a pill would be premature.
    private func quiet(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(p.ink3)
            .padding(.horizontal, 22).padding(.vertical, 10)
    }

    // MARK: steps

    @ViewBuilder private var content: some View {
        switch step {
        case 0: welcome
        case 1: permissions
        case 2: KnowMeDownloadStep(controller: controller, done: $downloadDone,
                                   percent: $downloadPercent, palette: p)
        case 3: tryItStep
        default: payoffStep
        }
    }

    /// Step 0 — answers "where did it go?" before the user can ask it. The
    /// menu-bar glyph plays its `hello` swell while this is on screen (T7), so
    /// the sentence has something to point at.
    private var welcome: some View {
        VStack(spacing: 0) {
            Spacer()
            RingGlyph(size: 96)
            Text("I live up there.")
                .font(.system(size: 34, weight: .bold)).kerning(-1.02)  // −0.03em
                .foregroundStyle(p.ink)
                .padding(.top, 22)
            Text("No window to keep open. Just a small waveform in the menu bar, "
                 + "and a key you hold when you want to talk.")
                .font(.system(size: 14.5))
                .lineSpacing(6.5)  // line-height 1.65
                .foregroundStyle(p.ink2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .padding(.top, 12)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        // Once per run, not once per visit — going Back shouldn't replay it.
        .onAppear {
            guard !helloWaved else { return }
            helloWaved = true
            NotificationCenter.default.post(name: .ovfPlayHello, object: nil)
        }
    }

    /// Step 1 — three permissions, asked one at a time.
    ///
    /// Presenting all three Allow buttons at once gave no order and no sense of
    /// progress. Now the next row's button appears only once the previous grant
    /// lands, each row states what the permission *cannot* do, and the recovery
    /// hint is visible from the start rather than after a failure.
    private var permissions: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Three switches, then we're done.")
                .font(.system(size: 25, weight: .bold)).kerning(-0.625)  // −0.025em
                .foregroundStyle(p.ink)
            Text("macOS holds the keys, not me.")
                .font(.system(size: 13)).foregroundStyle(p.ink2)
                .padding(.top, 6)

            VStack(spacing: 0) {
                ForEach(Array(Permission.onboardingOrder.enumerated()), id: \.element) { i, permission in
                    if i > 0 { divider }
                    permissionRow(permission, reachable: isReachable(i))
                }
            }
            .background(RoundedRectangle(cornerRadius: DT.rCard).fill(p.card))
            .overlay(RoundedRectangle(cornerRadius: DT.rCard).strokeBorder(p.hairline))
            .padding(.top, 18)

            escapeHatch.padding(.top, 15)
            Spacer()
        }
        .onAppear(perform: startWatchingPermissions)
        .onDisappear { permissionWatch?.cancel(); permissionWatch = nil }
    }

    /// Row 0 is always askable; row N unlocks when row N−1 is granted.
    private func isReachable(_ index: Int) -> Bool {
        guard index > 0 else { return true }
        return granted[Permission.onboardingOrder[index - 1]] ?? false
    }

    private var grantedCount: Int {
        Permission.onboardingOrder.filter { granted[$0] ?? false }.count
    }

    private var allGranted: Bool { grantedCount == Permission.onboardingOrder.count }

    private var divider: some View {
        Rectangle().fill(p.hairline).frame(height: 1).padding(.horizontal, 17)
    }

    private func permissionRow(_ permission: Permission, reachable: Bool) -> some View {
        let isGranted = granted[permission] ?? false
        // Not yet reachable: name and reason at full opacity so the user can see
        // what's coming, but no button and no limit line — they aren't being
        // asked yet.
        let showsDetail = isGranted || reachable
        return HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(isGranted ? DT.moss : p.ink.opacity(0.16))
                .frame(width: 8, height: 8)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(permission.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(p.ink)
                    Text(permission.why)
                        .font(.system(size: 12.5)).foregroundStyle(p.ink2)
                }
                if showsDetail {
                    Text(permission.limit)
                        .font(.system(size: 12)).foregroundStyle(p.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            if isGranted {
                Text("Allowed")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(DT.moss)
            } else if reachable {
                Button("Allow") {
                    permission.request()
                    refreshGrants()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(p.onAccent)
                .padding(.horizontal, 17).padding(.vertical, 7)
                .background(Capsule().fill(p.accent))
            }
        }
        .padding(.horizontal, 17).padding(.vertical, 15)
        .animation(DT.arrive, value: showsDetail)
    }

    /// Always visible — the user shouldn't have to fail before being told how to
    /// recover. Targets whichever row is currently being asked for.
    private var escapeHatch: some View {
        let target = Permission.onboardingOrder.first { !(granted[$0] ?? false) }
            ?? Permission.onboardingOrder[0]
        return HStack(spacing: 5) {
            Text("Clicked Allow and nothing happened?")
                .foregroundStyle(p.ink3)
            Button("Open System Settings") { NSWorkspace.shared.open(target.settingsURL) }
                .buttonStyle(.plain)
                .fontWeight(.semibold)
                .foregroundStyle(p.accent)
            // One step dimmer than tertiary, per the spec's #514C42 on dark;
            // derived rather than hardcoded so light mode stays legible.
            Text("— click + and pick OpenVoiceFlow from Applications.")
                .foregroundStyle(p.ink3.opacity(0.75))
        }
        .font(.system(size: 11.5))
    }

    private func startWatchingPermissions() {
        refreshGrants()
        guard permissionWatch == nil, !allGranted else { return }
        permissionWatch = Permission.watch { statuses in
            for (permission, status) in statuses {
                granted[permission] = status == .granted
            }
            if allGranted {
                permissionWatch?.cancel()
                permissionWatch = nil
            }
        }
    }

    private func refreshGrants() {
        for permission in Permission.allCases {
            granted[permission] = permission.status == .granted
        }
    }

    // MARK: say anything → the payoff

    /// Step 3 — the moment the app stops being a promise.
    ///
    /// A suggested sentence sits in the field in grey; the user's own words ink
    /// in over it as they speak, and the caret walks the boundary between spoken
    /// and unspoken. The grey line is a suggestion, not a script: say something
    /// else and it is discarded the instant the first real word lands.
    private var tryItStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Say anything.")
                .font(.system(size: 25, weight: .bold)).kerning(-0.625)
                .foregroundStyle(p.ink)
            (Text("Hold ")
                + Text(controller.settings.hotkey.displayName).bold()
                + Text(" and talk. Not sure what to say? Read the grey line."))
                .font(.system(size: 13)).foregroundStyle(p.ink2)
                .padding(.top, 6)

            // macOS gives fn/🌐 its own job (emoji picker / input switch) unless
            // it's set to do nothing, which would otherwise fire on every take.
            if controller.settings.hotkey == .fn {
                HStack(spacing: 8) {
                    Text("Tip: set System Settings ▸ Keyboard ▸ \"Press 🌐 to\" → \"Do Nothing\" so the key is all yours.")
                        .font(.system(size: 11.5)).foregroundStyle(p.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open") {
                        NSWorkspace.shared.open(
                            URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension")!)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold)).foregroundStyle(p.accent)
                }
                .padding(.top, 10)
            }

            InkFillView(
                suggestion: Self.suggestion,
                spoken: spokenText,
                revealedWords: revealedWords,
                idleHint: controller.isRecording ? nil : "Waiting for you…",
                palette: p)
                .padding(.top, 18)

            if !helloDone {
                Button("Skip") { helloDone = true; step = 4 }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5)).foregroundStyle(p.ink3)
                    .padding(.top, 14)
            }
            Spacer()
        }
        .onAppear {
            controller.streamPartials = true
            _ = controller.startListening()
        }
        .onDisappear { controller.streamPartials = false }
        // Live partials reveal as they arrive; the final transcript completes
        // the fill and moves on to the payoff.
        .onChange(of: controller.partialTranscript) { _ in revealFromPartial() }
        .onChange(of: controller.lastTranscript) { text in
            guard text?.isEmpty == false else { return }
            helloDone = true
            completeFill()
        }
    }

    /// The grey line. Deliberately a plain sentence someone would actually say —
    /// it has to be readable aloud at a glance.
    static let suggestion = "This is much faster than typing."

    /// What the user has actually said so far: the live partial while holding,
    /// the final transcript once it lands.
    private var spokenText: String {
        controller.lastTranscript ?? controller.partialTranscript ?? ""
    }

    /// Reveal on a 300 ms beat while the key is held — one word per partial that
    /// brings a new word, so the fill tracks speech rather than jumping.
    private func revealFromPartial() {
        let count = spokenText.split(whereSeparator: \.isWhitespace).count
        guard count > revealedWords else { return }
        withAnimation(reduceMotion ? nil : DT.arrive) { revealedWords = count }
    }

    /// On release the remainder completes at 70 ms per word — fast, but still a
    /// fill rather than a cut, so the eye can follow it. Reduce Motion inks the
    /// whole line at once instead.
    private func completeFill() {
        let total = spokenText.split(whereSeparator: \.isWhitespace).count
        guard total > 0 else { return }
        if reduceMotion {
            revealedWords = total
            advanceToPayoff()
            return
        }
        fillTask?.cancel()
        fillTask = Task {
            while revealedWords < total, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(70))
                if Task.isCancelled { return }
                revealedWords += 1
            }
            try? await Task.sleep(for: .milliseconds(420))
            if !Task.isCancelled { advanceToPayoff() }
        }
    }

    private func advanceToPayoff() {
        guard step == 3 else { return }
        withAnimation(reduceMotion ? .linear(duration: 0.2) : DT.settle) { step = 4 }
    }

    /// Step 4 — the payoff. Everything else falls away; what's left is the
    /// user's own sentence and the one number that matters.
    private var payoffStep: some View {
        VStack(spacing: 0) {
            Spacer()
            RingGlyph(size: 76)
                .padding(.bottom, 22)
            Text("YOUR FIRST WORDS")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .kerning(0.77)
                .foregroundStyle(DT.moss)
                .accessibilityAddTraits(.isHeader)
            Text("“\(controller.lastTranscript ?? Self.suggestion)”")
                .font(.system(size: 21, weight: .medium))
                .lineSpacing(10.5)
                .foregroundStyle(p.ink)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
                .padding(.top, 14)
            if let comparison = spokenComparison {
                Text(comparison)
                    .font(.system(size: 13)).foregroundStyle(p.ink2)
                    .padding(.top, 16)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            // The most important instant in the app shouldn't be silent.
            NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                                 userInfo: [.announcement: payoffAnnouncement,
                                            .priority: NSAccessibilityPriorityLevel.high.rawValue])
        }
    }

    /// "You spoke for 4 seconds. Typing that would have taken 18." — the same
    /// 40 wpm divisor the dashboard uses, so the two never disagree.
    private var spokenComparison: String? {
        guard let text = controller.lastTranscript, !text.isEmpty else { return nil }
        let words = text.split(whereSeparator: \.isWhitespace).count
        let spoke = max(1, Int(speechSeconds.rounded()))
        let typed = max(1, Int((Double(words) / 40.0 * 60).rounded()))
        guard typed > spoke else { return nil }
        return "You spoke for \(spoke) seconds. Typing that would have taken \(typed)."
    }

    private var speechSeconds: Double { controller.lastSpeechSeconds }

    private var payoffAnnouncement: String {
        "Your first words: \(controller.lastTranscript ?? "")"
    }
}

/// Turns raw byte callbacks into the three numbers that make waiting bearable:
/// size, rate, and a time remaining that doesn't jitter.
///
/// Rate comes from a rolling 3-second window rather than the whole transfer, so
/// it reflects the connection now instead of an average that never recovers from
/// a slow start. The ETA string is held for at least a second — recomputing it
/// on every callback makes it flicker between values and reads as broken.
@MainActor
final class DownloadMeter: ObservableObject {
    @Published private(set) var received: Int64 = 0
    @Published private(set) var expected: Int64 = 0
    @Published private(set) var rateText = ""
    @Published private(set) var etaText = ""

    private var samples: [(t: Date, bytes: Int64)] = []
    private var lastETAUpdate = Date.distantPast

    var fraction: Double {
        guard expected > 0 else { return 0 }
        return min(1, max(0, Double(received) / Double(expected)))
    }

    /// "412 of 981 MB" — decimal MB, matching how the OS reports download sizes.
    var sizeText: String {
        guard expected > 0 else { return "" }
        let mb = 1_000_000.0
        return "\(Int(Double(received) / mb)) of \(Int(Double(expected) / mb)) MB"
    }

    var percentText: String { "\(Int((fraction * 100).rounded()))%" }

    /// Land the bar exactly on full when the load finishes, rather than leaving
    /// it wherever the last progress callback happened to fire.
    func complete() {
        if expected > 0 { received = expected } else { expected = 1; received = 1 }
        etaText = ""
        rateText = ""
    }

    func update(received: Int64, expected: Int64, now: Date = Date()) {
        self.received = received
        if expected > 0 { self.expected = expected }

        samples.append((now, received))
        samples.removeAll { now.timeIntervalSince($0.t) > 3 }
        guard let first = samples.first, samples.count > 1 else { return }
        let seconds = now.timeIntervalSince(first.t)
        guard seconds > 0.25 else { return }

        let perSecond = Double(received - first.bytes) / seconds
        rateText = perSecond > 0 ? String(format: "%.1f MB/s", perSecond / 1_000_000) : ""

        guard now.timeIntervalSince(lastETAUpdate) >= 1 else { return }
        lastETAUpdate = now
        guard perSecond > 0, self.expected > received else { etaText = ""; return }
        let remaining = Double(self.expected - received) / perSecond
        etaText = remaining >= 90
            ? "\(Int((remaining / 60).rounded())) min left"
            : "\(max(1, Int(remaining.rounded()))) sec left"
    }
}

/// Step 2 — the interview, with the download running underneath it.
///
/// The model download used to be a step of its own: a progress bar and nothing
/// to do. Now the longest wait in the product happens while the user does the
/// single most valuable thing for transcription quality — telling the app their
/// name and the words it will get wrong.
private struct KnowMeDownloadStep: View {
    @ObservedObject var controller: AppController
    @Binding var done: Bool
    @Binding var percent: String
    let palette: OBPalette
    @StateObject private var meter = DownloadMeter()
    @State private var failed = false
    @State private var failureDetail: String?
    @State private var showDetail = false
    /// True when the model was already on disk, so there is nothing to show.
    @State private var skipProgress = false
    @State private var name = ""
    @State private var words: [String] = []

    private var p: OBPalette { palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(skipProgress ? "Who am I typing for?" : "While that downloads — who am I typing for?")
                .font(.system(size: 25, weight: .bold)).kerning(-0.625)
                .foregroundStyle(p.ink)
            Text("Two answers, and your name comes out spelled right the first time.")
                .font(.system(size: 13)).foregroundStyle(p.ink2)
                .padding(.top, 6)

            interviewCard.padding(.top, 18)
            if !skipProgress {
                progressCard.padding(.top, 14)
            }
            Spacer()
        }
        .onAppear(perform: start)
        .onDisappear(perform: persist)
    }

    private var interviewCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            KnowMeTextField(
                label: "What should I call you?",
                placeholder: "Alex Chen",
                text: $name,
                ink: p.ink, ink2: p.ink2,
                fill: p.ink.opacity(0.06),
                accent: p.accent)
            KnowMeTokenRow(
                label: "Any names or words I'd get wrong?",
                tokens: $words,
                ink2: p.ink2, ink3: p.ink3,
                chipInk: scheme_chipInk,
                chipFill: p.ink.opacity(0.07))
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: DT.rCard).fill(p.card))
        .overlay(RoundedRectangle(cornerRadius: DT.rCard).strokeBorder(p.hairline))
    }

    private var scheme_chipInk: Color {
        p.ink == DT.inkDark ? DT.chipInkDark : DT.chipInkLight
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Speech engine")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(scheme_chipInk)
                Spacer()
                if failed {
                    Text("stopped").font(.system(size: 11.5)).foregroundStyle(DT.errorAccent)
                } else {
                    metric(meter.sizeText, color: p.ink2)
                    if !meter.rateText.isEmpty {
                        dot; metric(meter.rateText, color: p.ink2)
                    }
                    if !meter.etaText.isEmpty {
                        dot
                        Text(meter.etaText)
                            .font(.system(size: 11.5, weight: .semibold)).monospacedDigit()
                            .foregroundStyle(p.accent)
                    }
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(p.ink.opacity(0.09))
                    Capsule().fill(failed ? DT.errorAccent : p.accent)
                        .frame(width: geo.size.width * meter.fraction)
                }
            }
            .frame(height: 5)
            .animation(DT.spineCurve, value: meter.fraction)
            .padding(.top, 11)

            if failed {
                Text("That stopped. Check your connection?")
                    .font(.system(size: 12.5)).foregroundStyle(Color(hex: 0xC9C3B4))
                    .padding(.top, 9)
                HStack(spacing: 14) {
                    Button("Try again") { start() }
                        .buttonStyle(.plain)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(p.onAccent)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(p.accent))
                    if failureDetail != nil {
                        Button(showDetail ? "Hide details" : "Details") { showDetail.toggle() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11.5)).foregroundStyle(p.ink3)
                    }
                }
                .padding(.top, 9)
                if showDetail, let failureDetail {
                    Text(failureDetail)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(p.ink3)
                        .textSelection(.enabled)
                        .lineLimit(4)
                        .padding(.top, 6)
                }
            } else {
                Text("Downloaded once. After this, everything runs offline on this Mac.")
                    .font(.system(size: 11)).foregroundStyle(p.ink3)
                    .padding(.top, 9)
            }
        }
        .padding(.horizontal, 17).padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: DT.rCard).fill(p.ink.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: DT.rCard).strokeBorder(p.hairline))
    }

    private func metric(_ text: String, color: Color) -> some View {
        Text(text).font(.system(size: 11.5)).monospacedDigit().foregroundStyle(color)
    }

    private var dot: some View {
        Text("·").font(.system(size: 11.5)).foregroundStyle(p.ink3)
    }

    private func start() {
        name = controller.profileStore.profile.name
        if words.isEmpty { words = controller.profileStore.profile.technicalTerms }
        guard !done else { return }
        failed = false
        failureDetail = nil
        showDetail = false

        Task {
            // A reinstall already has the model: no bar, no wait, straight to
            // "Try it" — showing 0→100% for something instant is theatre.
            if await controller.isModelReady() {
                skipProgress = true
                done = true
                return
            }
            do {
                try await controller.prepareModelForOnboarding { received, expected in
                    Task { @MainActor in
                        meter.update(received: received, expected: expected)
                        percent = meter.percentText
                    }
                }
                meter.complete()
                done = true
            } catch {
                failed = true
                failureDetail = error.localizedDescription
            }
        }
    }

    /// Answers are written when the step is left, so a user who types and moves
    /// on doesn't lose them to a missing Save button.
    private func persist() {
        var profile = controller.profileStore.profile
        profile.name = name.trimmingCharacters(in: .whitespaces)
        profile.technicalTerms = words
        controller.profileStore.profile = profile
        controller.dictionaryStore.seed(with: controller.profileStore.dictionaryWords)
    }
}

/// The ink fill — the moment the app stops being a promise.
///
/// A suggested sentence sits in the field in grey and the user's own words ink in
/// over it, word by word, with the caret walking the boundary between spoken and
/// unspoken.
///
/// The suggestion is a *suggestion*, not a script. If the user says something
/// else, the grey line is discarded the instant their words stop matching it and
/// their own words fill the field instead — so the moment still belongs to them.
/// When the two happen to agree it reads as a clean colour fill.
private struct InkFillView: View {
    let suggestion: String
    /// What the user has actually said (live partial, then the final transcript).
    let spoken: String
    /// How many of those words have been inked in so far.
    let revealedWords: Int
    /// Shown before anything has been heard.
    let idleHint: String?
    let palette: OBPalette

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Spoken / unspoken / caret, per appearance.
    private var inked: Color { scheme == .dark ? Color(hex: 0xEAE6DD) : Color(hex: 0x26221B) }
    private var unInked: Color { scheme == .dark ? Color(hex: 0x3E3A33) : Color(hex: 0xC6C0B2) }
    private var caret: Color { scheme == .dark ? Color(hex: 0xE8974E) : Color(hex: 0xB4661F) }

    private var spokenWords: [String] {
        spoken.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private var suggestionWords: [String] {
        suggestion.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The words to draw, and how many of them are inked.
    ///
    /// While the spoken words still match the suggestion word-for-word, the rest
    /// of the suggestion stays on as the grey tail. The moment they diverge the
    /// suggestion is dropped — showing a grey tail the user is not going to say
    /// would be a lie about what happens next.
    private var line: (words: [String], inkedCount: Int) {
        let said = spokenWords
        guard !said.isEmpty else { return (suggestionWords, 0) }
        let shown = min(revealedWords, said.count)
        let matches = zip(said, suggestionWords).allSatisfy { normalise($0) == normalise($1) }
        if matches && said.count <= suggestionWords.count {
            return (suggestionWords, shown)
        }
        return (said, shown)
    }

    /// Case- and punctuation-insensitive, so "typing." and "typing" agree.
    private func normalise(_ s: String) -> String {
        s.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }

    var body: some View {
        let content = line
        return VStack(alignment: .leading, spacing: 0) {
            // A wrapping run of words, each coloured by whether it's been said.
            // Under Reduce Motion the whole line inks at once, with no per-word
            // stagger and no caret walk.
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                wrapped(content.words, inkedCount: content.inkedCount)
                if !reduceMotion, content.inkedCount < content.words.count || content.inkedCount == 0 {
                    Rectangle().fill(caret)
                        .frame(width: 2, height: 22)
                        .padding(.leading, 3)
                }
            }
            if let idleHint, spokenWords.isEmpty {
                Text(idleHint)
                    .font(.system(size: 11.5)).foregroundStyle(palette.ink3)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .topLeading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: DT.rCard).fill(palette.card))
        .overlay(RoundedRectangle(cornerRadius: DT.rCard).strokeBorder(palette.hairline))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenWords.isEmpty ? (idleHint ?? suggestion) : spoken)
    }

    /// `Text` concatenation wraps as one paragraph, which a word-per-view HStack
    /// cannot do — and per-word colouring is exactly what `Text` + `+` is for.
    private func wrapped(_ words: [String], inkedCount: Int) -> some View {
        let run = words.enumerated().reduce(Text("")) { acc, pair in
            let (i, word) = pair
            return acc + Text(i == 0 ? word : " " + word)
                .font(.system(size: 21))
                .foregroundColor(i < inkedCount ? inked : unInked)
        }
        return run
            .kerning(-0.21)      // −0.01em at 21 pt
            .lineSpacing(6.3)    // line-height 1.5
    }
}
