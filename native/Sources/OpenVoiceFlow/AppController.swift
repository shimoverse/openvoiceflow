import AppKit
import Combine
import Foundation
import os

/// Orchestrates the dictation loop and owns app state. The single source of
/// truth wired into the menu bar and HUD.
///
///   idle → (hotkey down) recording → (hotkey up) transcribing → cleaning
///        → pasting → idle
@MainActor
final class AppController: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isRecording = false
    @Published var settings: Settings

    private let log = Logger(subsystem: "app.openvoiceflow", category: "controller")
    private let hotkey: HotkeyEngine
    private let audio = AudioCapture()
    private let transcriber: Transcriber
    private let hud = HUDController()

    /// Hard ceiling so a missed hotkey-up can't record forever (Python H2).
    private let maxRecordingSeconds: Double = 300
    private var maxRecordTask: Task<Void, Never>?
    private var pressTime = Date.distantPast

    init(settings: Settings = .load()) {
        self.settings = settings
        self.hotkey = HotkeyEngine(hotkey: settings.hotkey)
        self.transcriber = Transcriber(model: settings.whisperModel)
        hotkey.onPress = { [weak self] in self?.startRecording() }
        hotkey.onRelease = { [weak self] in self?.stopAndProcess() }
    }

    // MARK: listening lifecycle

    /// Begin listening for the hotkey. Returns false if the tap couldn't start
    /// (missing Accessibility/Input Monitoring) so the UI can surface it.
    @discardableResult
    func startListening() -> Bool {
        hotkey.hotkey = settings.hotkey
        guard hotkey.start() else {
            isListening = false
            return false
        }
        isListening = true
        Task { try? await transcriber.warmUp() }  // preload model off the hot path
        return true
    }

    func stopListening() {
        hotkey.stop()
        isListening = false
        if isRecording { _ = audio.stop(); isRecording = false }
    }

    func updateHotkey(_ newHotkey: Hotkey) {
        settings.hotkey = newHotkey
        settings.save()
        if isListening { stopListening(); startListening() }
    }

    // MARK: dictation loop

    private func startRecording() {
        guard !isRecording else { return }
        pressTime = Date()
        do {
            try audio.start()
            isRecording = true
            hud.show(.recording)
            maxRecordTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(self?.maxRecordingSeconds ?? 300))
                if !Task.isCancelled { self?.stopAndProcess() }
            }
        } catch {
            log.error("audio start failed: \(error.localizedDescription)")
            hud.show(.error("Microphone unavailable"), autoHideAfter: 3)
        }
    }

    private func stopAndProcess() {
        guard isRecording else { return }
        isRecording = false
        maxRecordTask?.cancel()
        let samples = audio.stop()
        let elapsed = Date().timeIntervalSince(pressTime)
        guard elapsed >= 0.3, !samples.isEmpty else {
            hud.hide()
            return
        }
        hud.show(.transcribing)
        Task { await process(samples) }
    }

    private func process(_ samples: [Float]) async {
        do {
            let raw = try await transcriber.transcribe(samples, language: settings.language)
            guard !raw.isEmpty else {
                hud.show(.error("No speech detected"), autoHideAfter: 2)
                return
            }
            hud.show(.cleaning)
            let provider = CleanupFactory.make(settings)
            let cleaned = (try? await provider.cleanup(raw, style: settings.style)) ?? raw
            if settings.autoPaste { Paster.paste(cleaned) }
            hud.show(.result(cleaned.prefix(40).description), autoHideAfter: 2)
        } catch {
            log.error("dictation failed: \(error.localizedDescription)")
            hud.show(.error("Dictation failed"), autoHideAfter: 3)
        }
    }
}
