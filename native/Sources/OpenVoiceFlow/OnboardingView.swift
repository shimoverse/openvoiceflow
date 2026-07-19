import SwiftUI

/// First-run onboarding — simplified from the phase-04 design after user
/// feedback ("too technical, too much").
///
/// Four steps, one idea each: welcome → three permission rows → getting
/// ready (one progress bar, zero jargon) → say hello. No model names, no
/// hostnames, no checksums, no file paths — the user should feel taken care
/// of, not informed. Technical detail lives behind a "Details" disclosure
/// on the failure state only.
struct OnboardingView: View {
    @ObservedObject var controller: AppController
    @State private var step = 0
    @State private var granted: [Permission: Bool] = [:]
    @State private var downloadDone = false
    @State private var helloDone = false

    private let accent = DT.emberDark

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 44)
            footer
        }
        .frame(width: 640, height: 440)
        .background(Color(hex: 0x211F1B))
        .preferredColorScheme(.dark)
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didBecomeKeyNotification)) { _ in refreshGrants() }
    }

    // MARK: chrome

    private var header: some View {
        HStack {
            Spacer()
            HStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { i in
                    Circle()
                        .fill(i <= step ? accent : .white.opacity(0.18))
                        .frame(width: 6, height: 6)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("‹ Back") { step -= 1 }
                    .buttonStyle(.plain).foregroundStyle(Color(hex: 0x96907F))
            }
            Spacer()
            primaryButton
        }
        .padding(20)
    }

    @ViewBuilder private var primaryButton: some View {
        switch step {
        case 0:
            pill("Get started") { step = 1 }
        case 1:
            pill("Continue") { step = 2 }
        case 2:
            if downloadDone {
                pill("Continue") { step = 3 }
            } else {
                Text("Getting ready…")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x6B6558))
                    .padding(.horizontal, 18).padding(.vertical, 9)
            }
        default:
            pill("Finish", disabled: !helloDone) {
                controller.settings.didOnboard = true
                controller.settings.save()
                _ = controller.startListening()
                NSApplication.shared.keyWindow?.close()
            }
        }
    }

    private func pill(_ title: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(disabled ? Color(hex: 0x6B6558) : Color(hex: 0x1A1508))
                .padding(.horizontal, 18).padding(.vertical, 9)
                .background(Capsule().fill(disabled ? Color.white.opacity(0.08) : accent))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: steps

    @ViewBuilder private var content: some View {
        switch step {
        case 0: welcome
        case 1: permissions
        case 2: GettingReadyStep(controller: controller, done: $downloadDone)
        default: helloStep
        }
    }

    private var welcome: some View {
        VStack(spacing: 14) {
            Spacer()
            RingGlyph(size: 72)
            Text("Speak. It types.")
                .font(.system(size: 30, weight: .bold)).kerning(-0.7)
                .foregroundStyle(Color(hex: 0xEAE6DD))
            Text("Hold a key, talk, let go — polished text appears at your cursor in any app.")
                .font(.system(size: 13.5)).foregroundStyle(Color(hex: 0x96907F))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    /// One screen, three rows, six words of "why" each. The real macOS
    /// prompt fires when the row's Allow is tapped; the dot turns green the
    /// moment the grant lands (re-checked whenever the window comes forward).
    private var permissions: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Three quick permissions")
                .font(.system(size: 24, weight: .bold)).kerning(-0.5)
                .foregroundStyle(Color(hex: 0xEAE6DD))
            Text("Everything happens on this Mac. Nothing is uploaded, ever.")
                .font(.system(size: 13)).foregroundStyle(Color(hex: 0x96907F))

            VStack(spacing: 0) {
                permissionRow(.microphone, name: "Microphone", why: "to hear you")
                divider
                permissionRow(.accessibility, name: "Accessibility", why: "to type for you")
                divider
                permissionRow(.inputMonitoring, name: "Input Monitoring", why: "to feel the hotkey — one key, nothing else")
            }
            .background(RoundedRectangle(cornerRadius: 12).fill(.white.opacity(0.04)))
        }
        .padding(.top, 24)
    }

    private var divider: some View {
        Rectangle().fill(.white.opacity(0.07)).frame(height: 1).padding(.horizontal, 16)
    }

    private func permissionRow(_ permission: Permission, name: String, why: String) -> some View {
        let isGranted = granted[permission] ?? false
        return HStack(spacing: 12) {
            Circle()
                .fill(isGranted ? DT.moss : .white.opacity(0.15))
                .frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(Color(hex: 0xEAE6DD))
            Text(why)
                .font(.system(size: 12.5)).foregroundStyle(Color(hex: 0x96907F))
            Spacer()
            if isGranted {
                Text("✓").font(.system(size: 13, weight: .bold)).foregroundStyle(DT.moss)
            } else {
                Button("Allow") {
                    permission.request()
                    refreshGrants()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: 0x1A1508))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Capsule().fill(accent))
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
    }

    private func refreshGrants() {
        for permission in Permission.allCases {
            granted[permission] = permission.status == .granted
        }
    }

    // MARK: say hello

    private var helloStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Say hello")
                .font(.system(size: 24, weight: .bold)).kerning(-0.5)
                .foregroundStyle(Color(hex: 0xEAE6DD))
            (Text("Hold ")
                + Text("Right \(controller.settings.hotkey.glyph)").bold()
                + Text(" and say: \"Hello from my own two vocal cords.\""))
                .font(.system(size: 13)).foregroundStyle(Color(hex: 0x96907F))

            HStack(spacing: 0) {
                Text(helloDone ? "Hello from my own two vocal cords." : "")
                    .font(.system(size: 13.5)).foregroundStyle(Color(hex: 0xEAE6DD))
                Rectangle().fill(accent).frame(width: 2, height: 15)
            }
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.04)))

            if helloDone {
                Text("That's it. You're set — we live in the menu bar now. ↗")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(DT.moss)
            } else {
                Button("I said it — mark me ready") { helloDone = true }
                    .buttonStyle(.bordered)
            }
            Spacer()
        }
        .padding(.top, 24)
        .onAppear { _ = controller.startListening() }
    }
}

/// Step 3 — "Getting ready". One friendly sentence, one progress bar, zero
/// jargon. On a real Mac this drives WhisperKit's download+prepare; wire the
/// actual progress fraction into `progress` and any thrown error's
/// description into `failureDetail`.
private struct GettingReadyStep: View {
    @ObservedObject var controller: AppController
    @Binding var done: Bool
    @State private var progress: Double = 0
    @State private var failed = false
    @State private var failureDetail: String?
    @State private var showDetail = false

    private let accent = DT.emberDark

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Getting ready")
                .font(.system(size: 24, weight: .bold)).kerning(-0.5)
                .foregroundStyle(Color(hex: 0xEAE6DD))
            Text("Downloading the speech engine — one time, then everything works offline.")
                .font(.system(size: 13)).foregroundStyle(Color(hex: 0x96907F))

            VStack(alignment: .leading, spacing: 12) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.09))
                        Capsule().fill(failed ? DT.errorAccent : accent)
                            .frame(width: geo.size.width * progress / 100)
                            .animation(.linear(duration: 0.2), value: progress)
                    }
                }
                .frame(height: 6)

                if failed {
                    Text("That didn't finish — check your connection and try again.")
                        .font(.system(size: 12.5)).foregroundStyle(Color(hex: 0xC9C3B4))
                    HStack(spacing: 14) {
                        Button("Try again") { retry() }
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x1A1508))
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(accent))
                        if failureDetail != nil {
                            Button(showDetail ? "Hide details" : "Details") { showDetail.toggle() }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5)).foregroundStyle(Color(hex: 0x6B6558))
                        }
                    }
                    if showDetail, let failureDetail {
                        Text(failureDetail)
                            .font(.system(size: 10.5, design: .monospaced))
                            .foregroundStyle(Color(hex: 0x6B6558))
                            .textSelection(.enabled)
                            .lineLimit(4)
                    }
                } else if done {
                    Text("Ready.").font(.system(size: 12.5, weight: .semibold)).foregroundStyle(DT.moss)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.04)))

            Text("Your voice never leaves this Mac.")
                .font(.system(size: 11)).foregroundStyle(Color(hex: 0x6B6558))
            Spacer()
        }
        .padding(.top, 24)
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
                try await controller.prepareModelForOnboarding { fraction in
                    Task { @MainActor in
                        progress = min(max(fraction * 100, 0), 100)
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
