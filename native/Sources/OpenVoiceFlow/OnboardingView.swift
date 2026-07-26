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
            if step > 0 {
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
                quiet("Getting ready")
            }
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
        case 2: GettingReadyStep(controller: controller, done: $downloadDone, palette: p)
        default: helloStep
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

    // MARK: say anything

    private var helloStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Say anything.")
                .font(.system(size: 24, weight: .bold)).kerning(-0.5)
                .foregroundStyle(p.ink)
            (Text("Hold ")
                + Text(controller.settings.hotkey.displayName).bold()
                + Text(" and talk. Let go when you're done."))
                .font(.system(size: 13)).foregroundStyle(p.ink2)

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
            }

            // Shows what was actually heard. The paste itself goes to whatever
            // app has focus, so echoing the transcript here is the honest
            // confirmation that the whole loop works.
            HStack(spacing: 0) {
                Text(controller.lastTranscript ?? "")
                    .font(.system(size: 13.5)).foregroundStyle(p.ink)
                if controller.lastTranscript == nil {
                    Text(controller.isRecording ? "Listening…"
                         : controller.isWorking ? "Working…" : "Waiting for you…")
                        .font(.system(size: 13)).foregroundStyle(p.ink3)
                }
                Rectangle().fill(p.accent).frame(width: 2, height: 15)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(p.card))

            if helloDone {
                Text("That worked. You're set — hold the key in any app. ↗")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(DT.moss)
            } else {
                Button("Skip") { helloDone = true }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5)).foregroundStyle(p.ink3)
            }
            Spacer()
        }
        .onAppear { _ = controller.startListening() }
        // Auto-detect: the moment a dictation lands, mark the step complete.
        .onChange(of: controller.lastTranscript) { transcript in
            if transcript?.isEmpty == false { helloDone = true }
        }
    }
}

/// Step 2 — "Getting ready". One friendly sentence, one progress bar, zero
/// jargon. On a real Mac this drives WhisperKit's download+prepare; wire the
/// actual progress fraction into `progress` and any thrown error's
/// description into `failureDetail`.
private struct GettingReadyStep: View {
    @ObservedObject var controller: AppController
    @Binding var done: Bool
    let palette: OBPalette
    @State private var progress: Double = 0
    @State private var failed = false
    @State private var failureDetail: String?
    @State private var showDetail = false

    private var p: OBPalette { palette }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Getting ready")
                .font(.system(size: 24, weight: .bold)).kerning(-0.5)
                .foregroundStyle(p.ink)
            Text("Downloading the speech engine — one time, then everything works offline.")
                .font(.system(size: 13)).foregroundStyle(p.ink2)

            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(p.hairline)
                        Capsule().fill(failed ? DT.errorAccent : p.accent)
                            .frame(width: geo.size.width * progress / 100)
                            .animation(.linear(duration: 0.2), value: progress)
                    }
                }
                .frame(height: 6)

                if failed {
                    Text("That stopped. Check your connection?")
                        .font(.system(size: 12.5)).foregroundStyle(p.ink)
                    HStack(spacing: 14) {
                        Button("Try again") { retry() }
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
                    if showDetail, let failureDetail {
                        Text(failureDetail)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(p.ink3)
                            .textSelection(.enabled)
                            .lineLimit(4)
                    }
                } else if done {
                    Text("Ready.").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(DT.moss)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(p.card))

            Text("Downloaded once. After this, everything runs offline on this Mac.")
                .font(.system(size: 11)).foregroundStyle(p.ink3)
            Spacer()
        }
        .onAppear(perform: start)
    }

    /// Starts WhisperKit preparation. The progress bar is driven only by the
    /// framework's download callback; errors retain their original detail for
    /// the existing disclosure UI.
    private func start() {
        guard !done else { return }
        failed = false
        failureDetail = nil
        showDetail = false

        Task {
            do {
                try await controller.prepareModelForOnboarding { received, expected in
                    Task { @MainActor in
                        guard expected > 0 else { return }
                        progress = min(max(Double(received) / Double(expected) * 100, 0), 100)
                    }
                }
                done = true
            } catch {
                failed = true
                failureDetail = error.localizedDescription
            }
        }
    }

    private func retry() {
        failed = false
        failureDetail = nil
        showDetail = false
        progress = 0
        start()
    }
}
