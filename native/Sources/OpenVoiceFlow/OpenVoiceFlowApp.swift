import AppKit
import SwiftUI

/// Entry point. A menu-bar (`LSUIElement`) app: no Dock icon by default, a
/// `MenuBarExtra` for control (design phase 02), a dashboard window (phase
/// 03), and first-run onboarding (phase 04).
@main
struct OpenVoiceFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var icon = StatusIconAnimator()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(controller: delegate.controller, showOnboarding: delegate.showOnboarding)
        } label: {
            MenuBarLabel(controller: delegate.controller, icon: icon)
        }

        Window("OpenVoiceFlow", id: "dashboard") {
            DashboardView(controller: delegate.controller)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1000, height: 660)
    }
}

/// Owns the first-run window because accessory/menu-bar apps do not reliably
/// present dormant SwiftUI Window scenes at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        #if DEBUG
        let forceOnboarding = ProcessInfo.processInfo.arguments.contains("-ovf-force-onboarding")
        #else
        let forceOnboarding = false
        #endif
        guard forceOnboarding || !controller.settings.didOnboard else { return }
        DispatchQueue.main.async { [weak self] in self?.showOnboarding() }
    }

    func showOnboarding() {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to OpenVoiceFlow"
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: OnboardingView(controller: controller))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow = window
    }
}

/// The template status icon, animated while listening/working (design 02).
private struct MenuBarLabel: View {
    @ObservedObject var controller: AppController
    @ObservedObject var icon: StatusIconAnimator

    var body: some View {
        Image(nsImage: icon.image)
            .onAppear { icon.set(controller.iconState) }
            .onChange(of: controller.iconState) { icon.set($0) }
    }
}

/// The dropdown, item-for-item from the design (phase 02 §2). System menu
/// rendering (menu-style MenuBarExtra) keeps it HIG-native; the design's
/// custom blur panel is a later window-style upgrade if ever wanted.
private struct MenuContent: View {
    @ObservedObject var controller: AppController
    let showOnboarding: () -> Void
    @Environment(\.openWindow) private var openWindow

    /// The models the design's picker offers (WhisperKit names + sizes).
    private static let models: [(id: String, label: String)] = [
        ("tiny", "tiny — 39 MB"),
        ("small", "small — 466 MB"),
        ("medium", "medium — 1.5 GB"),
        ("large-v3-turbo", "large-v3-turbo — 1.6 GB"),
    ]

    var body: some View {
        // 1. Header (non-interactive state summary).
        Text(headerTitle)
        Text(headerSubtitle)
        Divider()

        // 3–4. Primary actions.
        Button(controller.isListening || controller.isWorking ? "Stop Dictation" : "Start Dictation") {
            if controller.isListening { controller.stopListening() } else { _ = controller.startListening() }
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])

        Button(controller.isPaused ? "Resume" : "Pause for 1 hour") {
            controller.isPaused ? controller.resume() : controller.pause()
        }
        Divider()

        // 6. Hotkey picker.
        Menu("Hotkey — \(controller.settings.hotkey.displayName)") {
            ForEach(Hotkey.allCases, id: \.self) { key in
                Toggle(isOn: .constant(controller.settings.hotkey == key)) {
                    Text(key == .rightCommand ? "\(key.displayName)  (default)" : key.displayName)
                }
                .onTapGesture { controller.updateHotkey(key) }
            }
            Divider()
            Text("Hold to talk · release to transcribe")
        }

        // 7. Model picker.
        Menu("Model — \(controller.settings.whisperModel)") {
            ForEach(Self.models, id: \.id) { model in
                Button {
                    controller.settings.whisperModel = model.id
                    controller.settings.save()
                } label: {
                    if controller.settings.whisperModel == model.id {
                        Label(model.label, systemImage: "checkmark")
                    } else {
                        Text(model.label)
                    }
                }
            }
            Divider()
            Text("Runs on this Mac — downloads once")
        }

        // 8. Cleanup picker (design order: on-device first).
        Menu("Cleanup — \(cleanupLabel(controller.settings.backend))") {
            ForEach([Backend.ollama, .anthropic, .openai, .groq, .openrouter, .none], id: \.self) { backend in
                Button {
                    controller.settings.backend = backend
                    controller.settings.save()
                } label: {
                    if controller.settings.backend == backend {
                        Label(cleanupLabel(backend), systemImage: "checkmark")
                    } else {
                        Text(cleanupLabel(backend))
                    }
                }
            }
            Divider()
            Text("Cloud keys live in your Keychain")
        }
        Divider()

        // 10–11. Windows + updates.
        Button("Open Dashboard…") { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }
            .keyboardShortcut("d")
        Button("Setup & Permissions…") { showOnboarding() }
        Button("Check for Updates…") {
            // Sparkle wiring is a Mac-build step (BUILD_RUNBOOK.md phase 4).
            NSWorkspace.shared.open(URL(string: "https://openvoiceflow.vercel.app/download.html")!)
        }
        Divider()

        // 13. Quit, always last, behind a separator.
        Button("Quit OpenVoiceFlow") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var headerTitle: String {
        if controller.lastError != nil { return controller.lastError! }
        if let until = controller.pausedUntil {
            return "Paused until \(until.formatted(date: .omitted, time: .shortened))"
        }
        if controller.isRecording { return "Listening…" }
        if controller.isWorking { return "Transcribing…" }
        return "Ready"
    }

    private var headerSubtitle: String {
        if controller.lastError != nil { return "Pick an input in Sound settings" }
        if controller.isPaused { return "Hotkey ignored while paused" }
        if controller.isRecording { return "Release to transcribe" }
        if controller.isWorking { return "On-device Whisper" }
        return "Hold \(controller.settings.hotkey.glyph) to dictate"
    }

    private func cleanupLabel(_ backend: Backend) -> String {
        switch backend {
        case .ollama: return "On-device · Ollama"
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .groq: return "Groq"
        case .openrouter: return "OpenRouter"
        case .none: return "None — raw transcript"
        }
    }
}
