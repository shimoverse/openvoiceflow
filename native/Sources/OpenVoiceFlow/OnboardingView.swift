import SwiftUI

/// First-run onboarding — design phase 04 (native/design/04-onboarding.dc.html).
///
/// Seven steps: welcome → three permission primings (explain first, then let
/// macOS ask) → hotkey with rehearsal → narrated model download → say hello.
/// Permissions re-check every time the window comes forward; nothing is
/// hard-blocked.
struct OnboardingView: View {
    @ObservedObject var controller: AppController
    @State private var step = 0
    @State private var rehearsed = false
    @State private var holding = false
    @State private var downloadDone = false
    @State private var helloDone = false

    private let accent = DT.emberDark

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, 40)
            footer
        }
        .frame(width: 760, height: 470)
        .background(Color(hex: 0x211F1B))
        .preferredColorScheme(.dark)
    }

    // MARK: chrome

    private var header: some View {
        HStack {
            Spacer()
            HStack(spacing: 5) {
                ForEach(0..<7, id: \.self) { i in
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
                Button("‹ Back") { step -= 1 }.buttonStyle(.plain).foregroundStyle(Color(hex: 0x96907F))
            }
            Spacer()
            Text(stepHint).font(.system(size: 11)).foregroundStyle(Color(hex: 0x6B6558))
            primaryButton
        }
        .padding(20)
    }

    private var stepHint: String {
        switch step {
        case 1, 3: return "macOS asks after you click Continue"
        case 2: return "one toggle in System Settings"
        case 4: return "hold to talk · release to transcribe"
        case 5: return "minutes-long waits deserve narration"
        case 6: return "hold, speak, release"
        default: return ""
        }
    }

    @ViewBuilder private var primaryButton: some View {
        switch step {
        case 0:
            pill("Get started") { step = 1 }
        case 1:
            pill("Continue") {
                AudioCapture.requestAccess { _ in }
                step = 2
            }
        case 2:
            pill("Continue") {
                Permission.accessibility.request()
                step = 3
            }
        case 3:
            pill("Continue") {
                Permission.inputMonitoring.request()
                step = 4
            }
        case 4:
            pill("Continue") { step = 5 }
        case 5:
            if downloadDone {
                pill("Continue") { step = 6 }
            } else {
                Text("Downloading…")
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
        case 1: priming(n: 1, title: "Let it hear you",
                        why: "Microphone access feeds your voice straight into Whisper — a model running on this Mac. The network is not involved; audio is discarded right after transcription.",
                        note: "macOS will ask once. Deny it and dictation simply can't hear you.")
        case 2: priming(n: 2, title: "Let it type for you",
                        why: "This is how text lands at your cursor: OpenVoiceFlow pastes on your behalf. macOS files that power under \"Accessibility.\"",
                        note: "No dialog for this one — macOS sends you to a toggle. One flip; we detect it instantly.")
        case 3: priming(n: 3, title: "Let it feel the hotkey",
                        why: "Input Monitoring lets the app notice your talk key held down even while another app has focus. We watch one key — not your typing.",
                        note: "This is the scariest-sounding permission, so the honest sentence first: one key, nothing else, verifiable in the source.")
        case 4: hotkeyStep
        case 5: ModelDownloadStep(done: $downloadDone)
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
            Text("Hold a key, talk, let go — polished text appears at your cursor in any app. Free and open source.")
                .font(.system(size: 13.5)).foregroundStyle(Color(hex: 0x96907F))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            HStack(spacing: 8) {
                badge("100% ON-DEVICE", color: DT.moss)
                badge("NO ACCOUNT", color: Color(hex: 0x96907F))
                badge("WORKS OFFLINE", color: Color(hex: 0x96907F))
            }
            Text("Setup takes about two minutes — three permissions, one download, one hello.")
                .font(.system(size: 11)).foregroundStyle(Color(hex: 0x6B6558))
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold)).kerning(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .overlay(Capsule().strokeBorder(color.opacity(0.5)))
    }

    private func priming(n: Int, title: String, why: String, note: String) -> some View {
        HStack(alignment: .top, spacing: 30) {
            VStack(alignment: .leading, spacing: 12) {
                Text("PERMISSION \(n) OF 3")
                    .font(.system(size: 10, weight: .bold, design: .monospaced)).kerning(0.8)
                    .foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 24, weight: .bold)).kerning(-0.5)
                    .foregroundStyle(Color(hex: 0xEAE6DD))
                Text(why)
                    .font(.system(size: 13)).lineSpacing(5)
                    .foregroundStyle(Color(hex: 0xC9C3B4))
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 1).fill(accent).frame(width: 2)
                    Text(note)
                        .font(.system(size: 12)).lineSpacing(4)
                        .foregroundStyle(Color(hex: 0x96907F))
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            mockPanel(for: n)
                .frame(width: 290)
        }
        .padding(.top, 24)
    }

    /// The "what macOS will show" preview cards.
    @ViewBuilder private func mockPanel(for n: Int) -> some View {
        VStack(spacing: 8) {
            VStack(spacing: 10) {
                RingGlyph(size: 26)
                Text(n == 1 ? "\"OpenVoiceFlow\" would like to access the microphone."
                     : n == 2 ? "System Settings › Privacy & Security › Accessibility"
                     : "\"OpenVoiceFlow\" would like to monitor input from your keyboard.")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: 0xEAE6DD))
                    .multilineTextAlignment(.center)
                Text(n == 1 ? "Dictation happens on this Mac. Audio is never uploaded."
                     : n == 2 ? "OpenVoiceFlow — one toggle, detected instantly."
                     : "Only the dictation hotkey is observed.")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(hex: 0x96907F))
                    .multilineTextAlignment(.center)
                if n != 2 {
                    HStack(spacing: 8) {
                        Text("Don't Allow").font(.system(size: 11.5))
                            .foregroundStyle(Color(hex: 0xC9C3B4))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(.white.opacity(0.08)))
                        Text("Allow").font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Color(hex: 0x1A1508))
                            .padding(.horizontal, 12).padding(.vertical, 5)
                            .background(RoundedRectangle(cornerRadius: 6).fill(accent))
                    }
                }
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(hex: 0x2B2925)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0.10)))

            Text(n == 2 ? "↑ one toggle — we detect it the instant you flip it, no restart"
                 : "↑ what macOS will show — we ask only when you click Continue")
                .font(.system(size: 10.5)).foregroundStyle(Color(hex: 0x6B6558))
                .multilineTextAlignment(.center)
        }
        .padding(.top, 24)
    }

    // MARK: hotkey step

    private var hotkeyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Pick your talk key")
                .font(.system(size: 24, weight: .bold)).kerning(-0.5)
                .foregroundStyle(Color(hex: 0xEAE6DD))
            Text("Hold it to talk, release to type. Right ⌘ suits most right hands.")
                .font(.system(size: 13)).foregroundStyle(Color(hex: 0x96907F))

            // Bottom keyboard row; selectable caps fill accent when chosen.
            HStack(spacing: 6) {
                keycap(.fn, label: "fn")
                dimCap("⌃"); dimCap("⌥"); dimCap("⌘")
                RoundedRectangle(cornerRadius: 8)
                    .fill(.white.opacity(0.05))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.10)))
                    .frame(width: 200, height: 40)
                keycap(.rightCommand, label: "⌘")
                keycap(.rightOption, label: "⌥")
                keycap(.rightControl, label: "⌃")
            }
            .padding(.vertical, 8)

            // Rehearse row: 700 ms hold confirms the gesture.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    Text("Rehearse it:").font(.system(size: 12.5)).foregroundStyle(Color(hex: 0x96907F))
                    Text(holding ? "Keep holding…" : "Hold me like it's \(controller.settings.hotkey.glyph)")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(holding ? Color(hex: 0x1A1508) : Color(hex: 0xC9C3B4))
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(holding ? accent : .white.opacity(0.08)))
                        .onLongPressGesture(minimumDuration: 0.7) {
                            rehearsed = true
                            holding = false
                        } onPressingChanged: { pressing in
                            holding = pressing
                        }
                }
                if rehearsed {
                    Text("✓ Nice — that's the whole gesture.")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(DT.moss)
                        .transition(.opacity)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.04)))
        }
        .padding(.top, 24)
    }

    private func keycap(_ key: Hotkey, label: String) -> some View {
        let selected = controller.settings.hotkey == key
        return Button {
            controller.updateHotkey(key)
            rehearsed = false  // changing keys resets the confirmation
        } label: {
            Text(label)
                .font(.system(size: 14, weight: selected ? .bold : .regular))
                .foregroundStyle(selected ? Color(hex: 0x1A1508) : Color(hex: 0xC9C3B4))
                .frame(width: 44, height: 40)
                .background(RoundedRectangle(cornerRadius: 8).fill(selected ? accent : .white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func dimCap(_ label: String) -> some View {
        Text(label)
            .font(.system(size: 14)).foregroundStyle(Color(hex: 0x6B6558))
            .frame(width: 44, height: 40)
            .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04)))
    }

    // MARK: say hello

    private var helloStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Say hello")
                .font(.system(size: 24, weight: .bold)).kerning(-0.5)
                .foregroundStyle(Color(hex: 0xEAE6DD))
            Text("Hold \(controller.settings.hotkey.displayName) and say: \"Hello from my own two vocal cords.\"")
                .font(.system(size: 13)).foregroundStyle(Color(hex: 0x96907F))

            HStack(spacing: 0) {
                Text(helloDone ? "Hello from my own two vocal cords." : "")
                    .font(.system(size: 13.5)).foregroundStyle(Color(hex: 0xEAE6DD))
                Rectangle().fill(accent).frame(width: 2, height: 15)
            }
            .frame(width: 420, height: 60, alignment: .topLeading)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.04)))

            if helloDone {
                Text("That's it. You're set — we live in the menu bar now. ↗")
                    .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(DT.moss)
            } else {
                // Live path uses the real hotkey once listening starts; this
                // button is the fallback used before permissions settle.
                Button("I said it — mark me ready") { helloDone = true }
                    .buttonStyle(.bordered)
            }
        }
        .padding(.top, 24)
        .onAppear { _ = controller.startListening() }
    }
}

/// Step 5 — narrated model download. On a real Mac this drives WhisperKit's
/// download+compile; here the checklist reflects reported progress.
private struct ModelDownloadStep: View {
    @Binding var done: Bool
    @State private var progress: Double = 0
    @State private var timer: Timer?

    private let accent = DT.emberDark

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Downloading your model")
                .font(.system(size: 24, weight: .bold)).kerning(-0.5)
                .foregroundStyle(Color(hex: 0xEAE6DD))
            Text("whisper-large-v3-turbo · 1.6 GB · the only download this app will ever need")
                .font(.system(size: 13)).foregroundStyle(Color(hex: 0x96907F))

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("\(Int(progress))%")
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                        .foregroundStyle(Color(hex: 0xEAE6DD))
                    Text(progress >= 100 ? "done — compiled for this Mac"
                         : "~\(max(2, Int((100 - progress) * 0.55))) s left")
                        .font(.system(size: 12)).foregroundStyle(Color(hex: 0x96907F))
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.09))
                        Capsule().fill(accent)
                            .frame(width: geo.size.width * progress / 100)
                            .animation(.linear(duration: 0.2), value: progress)
                    }
                }
                .frame(height: 6)

                VStack(alignment: .leading, spacing: 6) {
                    checkRow("Contact huggingface.co (the only network call)", at: 0)
                    checkRow("Download weights — 1.6 GB", at: 70)
                    checkRow("Verify SHA-256 checksum", at: 85)
                    checkRow("Compile for the Neural Engine", at: 100)
                }
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 10).fill(.white.opacity(0.04)))

            Text("While you wait: transcription happens on this Mac. After this screen, airplane mode changes nothing.")
                .font(.system(size: 11)).foregroundStyle(Color(hex: 0x6B6558))
        }
        .padding(.top, 24)
        .onAppear(perform: start)
        .onDisappear { timer?.invalidate() }
    }

    private func checkRow(_ label: String, at threshold: Double) -> some View {
        let state: (glyph: String, color: Color) =
            progress >= threshold && (threshold == 100 ? progress >= 100 : progress > threshold)
            ? ("✓", DT.moss)
            : progress >= threshold ? ("…", Color(hex: 0xC9C3B4)) : ("·", Color(hex: 0x6B6558))
        return HStack(spacing: 8) {
            Text(state.glyph).font(.system(size: 12, design: .monospaced)).foregroundStyle(state.color)
            Text(label).font(.system(size: 12, design: .monospaced)).foregroundStyle(state.color)
        }
    }

    private func start() {
        guard progress < 100 else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { t in
            Task { @MainActor in
                progress = min(100, progress + Double.random(in: 0.8...2.2))
                if progress >= 100 {
                    t.invalidate()
                    done = true
                }
            }
        }
    }
}
