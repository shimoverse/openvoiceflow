import SwiftUI

/// Entry point. A menu-bar (`LSUIElement`) app: no Dock icon by default, a
/// `MenuBarExtra` for control, and a first-run onboarding window.
@main
struct OpenVoiceFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var controller = AppController()
    @State private var showOnboarding = false

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: controller, showOnboarding: $showOnboarding)
        } label: {
            Image(systemName: controller.isRecording ? "waveform.circle.fill"
                  : (controller.isListening ? "waveform" : "waveform.slash"))
        }

        Window("Welcome to OpenVoiceFlow", id: "onboarding") {
            OnboardingView(controller: controller)
        }
        .windowResizability(.contentSize)
    }
}

/// Kicks off listening (or onboarding) once the app finishes launching.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// The menu-bar dropdown.
private struct MenuContent: View {
    @ObservedObject var controller: AppController
    @Binding var showOnboarding: Bool
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(controller.isListening ? "Pause Listening" : "Start Listening") {
            controller.isListening ? controller.stopListening() : { _ = controller.startListening() }()
        }
        Divider()

        Menu("Dictation Shortcut") {
            // fn is offered here too — unlike the Python app it actually works.
            ForEach(Hotkey.allCases, id: \.self) { key in
                Button {
                    controller.updateHotkey(key)
                } label: {
                    Label(key.displayName, systemImage: controller.settings.hotkey == key ? "checkmark" : "")
                }
            }
        }

        Menu("AI Cleanup") {
            ForEach(Backend.allCases, id: \.self) { backend in
                Button(backend.rawValue.capitalized) {
                    controller.settings.backend = backend
                    controller.settings.save()
                }
            }
        }

        Button("Setup & Permissions…") { openWindow(id: "onboarding") }
        Divider()
        Button("Quit OpenVoiceFlow") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
