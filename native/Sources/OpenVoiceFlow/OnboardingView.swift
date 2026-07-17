import SwiftUI

/// First-run SwiftUI flow: pick a cleanup backend + key, choose the hotkey,
/// then grant permissions in-context (one prompt at a time, explained first —
/// the HIG-correct approach the Python launcher's back-to-back prompts miss).
///
/// This is a first slice; polish (illustrations, the Know-Me profile, per-app
/// styles) is a later milestone (see BUILD_RUNBOOK.md).
struct OnboardingView: View {
    @ObservedObject var controller: AppController
    @State private var step = 0
    @State private var apiKey = ""

    var body: some View {
        VStack(spacing: 20) {
            switch step {
            case 0: welcome
            case 1: backendStep
            case 2: hotkeyStep
            default: permissionsStep
            }
        }
        .padding(32)
        .frame(width: 460)
    }

    private var welcome: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform").font(.system(size: 48)).foregroundStyle(.tint)
            Text("OpenVoiceFlow").font(.largeTitle.bold())
            Text("Hold a key, speak, release — perfect text at your cursor, anywhere.")
                .multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Get Started") { step = 1 }.buttonStyle(.borderedProminent).controlSize(.large)
        }
    }

    private var backendStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose AI cleanup").font(.title2.bold())
            Picker("Backend", selection: $controller.settings.backend) {
                ForEach(Backend.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
            }.pickerStyle(.radioGroup)
            if controller.settings.backend.needsAPIKey {
                SecureField("API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }
            nav(next: 2) {
                if controller.settings.backend.needsAPIKey, !apiKey.isEmpty {
                    Keychain.setKey(apiKey, for: controller.settings.backend)
                }
                controller.settings.save()
            }
        }
    }

    private var hotkeyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pick your push-to-talk key").font(.title2.bold())
            Picker("Hotkey", selection: $controller.settings.hotkey) {
                ForEach(Hotkey.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }.pickerStyle(.menu)
            nav(next: 3) { controller.updateHotkey(controller.settings.hotkey) }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Grant permissions").font(.title2.bold())
            ForEach(Permission.allCases, id: \.self) { perm in
                HStack {
                    VStack(alignment: .leading) {
                        Text(perm.title).font(.headline)
                        Text("OpenVoiceFlow needs this \(perm.why)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Allow") { perm.request() }
                }
            }
            Button("Finish") {
                controller.settings.didOnboard = true
                controller.settings.save()
                _ = controller.startListening()
                NSApplication.shared.keyWindow?.close()
            }.buttonStyle(.borderedProminent).controlSize(.large).frame(maxWidth: .infinity)
        }
    }

    private func nav(next: Int, onNext: @escaping () -> Void) -> some View {
        HStack {
            if step > 1 { Button("Back") { step -= 1 } }
            Spacer()
            Button("Continue") { onNext(); step = next }
                .buttonStyle(.borderedProminent)
        }
    }
}
