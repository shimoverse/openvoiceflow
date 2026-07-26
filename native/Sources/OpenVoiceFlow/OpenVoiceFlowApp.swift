import AppKit
import ServiceManagement
import SwiftUI
import os

/// Launch-at-login via SMAppService. Register/unregister are status-guarded
/// so applying an unchanged setting at every launch stays a no-op instead of
/// an error or a duplicate registration.
@MainActor
enum LoginItem {
    static func apply(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled, service.status != .enabled {
                try service.register()
            } else if !enabled, service.status == .enabled {
                try service.unregister()
            }
        } catch {
            // Not worth an alert: the user can flip the Settings toggle again,
            // and System Settings ▸ Login Items always shows the truth.
            Logger(subsystem: "app.openvoiceflow", category: "loginitem")
                .error("apply(\(enabled)) failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}

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
        .defaultSize(width: 1000, height: 768)
    }
}

/// Owns the first-run window because accessory/menu-bar apps do not reliably
/// present dormant SwiftUI Window scenes at launch.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = AppController()
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The app launches as an accessory (LSUIElement) so the dashboard scene
        // stays dormant; promoting to .regular here adds the Dock icon without
        // auto-presenting that window. Settings ▸ Show in Dock flips it back.
        if controller.settings.showInDock { NSApp.setActivationPolicy(.regular) }
        // Start Sparkle at launch so background appcast checks run on schedule.
        _ = UpdaterController.shared
        #if DEBUG
        let forceOnboarding = ProcessInfo.processInfo.arguments.contains("-ovf-force-onboarding")
        #else
        let forceOnboarding = false
        #endif
        if forceOnboarding || !controller.settings.didOnboard {
            DispatchQueue.main.async { [weak self] in self?.showOnboarding() }
        } else {
            // The hotkey must work from the moment the app is running. Before
            // 0.5.1 nothing started the listener on relaunch, so every launch
            // after onboarding came up deaf until the user found Start
            // Dictation in the menu. If the event tap can't start (a
            // permission was revoked since last run), the menu header and the
            // dashboard's Permissions card both show the way back.
            _ = controller.startListening()
            // Survive reboots: a menu-bar utility that vanishes on restart
            // reads as broken. Status-guarded, so this is a no-op when the
            // registration already matches the setting.
            LoginItem.apply(controller.settings.launchAtLogin)
        }
    }

    /// Clicking the Dock icon (or reopening the app) brings up the dashboard —
    /// the thing a Dock icon is expected to do. During first run it re-presents
    /// onboarding instead, so the setup flow is never stranded behind the Dock.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !controller.settings.didOnboard {
            showOnboarding()
        } else {
            NotificationCenter.default.post(name: .ovfOpenDashboard, object: nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    func showOnboarding() {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 470),
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

extension Notification.Name {
    /// Posted when something outside SwiftUI (a Dock-icon click) wants the
    /// dashboard. `MenuBarLabel` is always alive, so it holds the `openWindow`
    /// action that can actually present the Window scene.
    static let ovfOpenDashboard = Notification.Name("ovfOpenDashboard")
    /// Posted by onboarding's welcome step: the menu-bar glyph waves once so
    /// "I live up there" has something to point at. MenuBarLabel owns the
    /// animator, so it does the playing.
    static let ovfPlayHello = Notification.Name("ovfPlayHello")
}

/// The template status icon, animated while listening/working (design 02).
private struct MenuBarLabel: View {
    @ObservedObject var controller: AppController
    @ObservedObject var icon: StatusIconAnimator
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(nsImage: icon.image)
            .onAppear { icon.set(controller.iconState) }
            .onChange(of: controller.iconState) { icon.set($0) }
            .onReceive(NotificationCenter.default.publisher(for: .ovfOpenDashboard)) { _ in
                openWindow(id: "dashboard")
            }
            .onReceive(NotificationCenter.default.publisher(for: .ovfPlayHello)) { _ in
                icon.playHello()
            }
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

        // 3–4. Primary actions. Listening starts itself at launch, so there is
        // no Start/Stop toggle — Pause is the one deliberate off-switch. The
        // recovery button appears only in the state that needs it: the tap
        // failed to start (a permission was revoked), which auto-start can't
        // fix on its own.
        if !controller.isListening && !controller.isPaused {
            Button("Turn On Dictation") { _ = controller.startListening() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
        }
        Button(controller.isPaused ? "Resume" : "Pause for 1 hour") {
            controller.isPaused ? controller.resume() : controller.pause()
        }
        Divider()

        // 6. Hotkey picker.
        Menu("Hotkey — \(controller.settings.hotkey.displayName)") {
            ForEach(Hotkey.allCases, id: \.self) { key in
                Toggle(isOn: .constant(controller.settings.hotkey == key)) {
                    Text(key == .fn ? "\(key.displayName)  (default)" : key.displayName)
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
        Button("Check for Updates…") { UpdaterController.shared.checkForUpdates() }
            .disabled(!UpdaterController.shared.canCheckForUpdates)
        Divider()

        // 13. Quit, always last, behind a separator.
        Button("Quit OpenVoiceFlow") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var headerTitle: String {
        if let lastError = controller.lastError { return lastError }
        if let until = controller.pausedUntil {
            return "Paused until \(until.formatted(date: .omitted, time: .shortened))"
        }
        if controller.isRecording { return "Listening…" }
        if controller.isWorking { return "Transcribing…" }
        // Before 0.5.1 this said "Ready" even when the key listener was dead.
        if !controller.isListening { return "Dictation is off" }
        return "Ready"
    }

    private var headerSubtitle: String {
        if controller.lastError != nil { return "Pick an input in Sound settings" }
        if controller.isPaused { return "Hotkey ignored while paused" }
        if controller.isRecording { return "Release to transcribe" }
        if controller.isWorking { return "On-device Whisper" }
        if !controller.isListening { return "Check Setup & Permissions below" }
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
