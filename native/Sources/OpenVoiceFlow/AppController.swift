import AppKit
import Combine
import Foundation
import os

/// Orchestrates the dictation loop and owns app state. The single source of
/// truth wired into the menu bar, HUD, and dashboard.
///
///   idle → (hotkey down) recording → (hotkey up) transcribing → cleaning
///        → pasting → idle
@MainActor
final class AppController: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var isRecording = false
    @Published private(set) var isWorking = false
    @Published private(set) var pausedUntil: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var wordsToday = 0
    @Published var settings: Settings

    private let log = Logger(subsystem: "app.openvoiceflow", category: "controller")
    private let hotkey: HotkeyEngine
    private let audio = AudioCapture()
    private let transcriber: Transcriber
    private let hud = HUDController()

    /// Hard ceiling so a missed hotkey-up can't record forever (Python H2).
    private let maxRecordingSeconds: Double = 300
    private var maxRecordTask: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    private var pressTime = Date.distantPast
    private var lastSamples: [Float] = []

    /// Menu-bar icon state derived from the controller state (design 02).
    var iconState: StatusIconState {
        if lastError != nil { return .error }
        if pausedUntil != nil { return .paused }
        if isRecording { return .listening }
        if isWorking { return .working }
        return .idle
    }

    var isPaused: Bool { pausedUntil != nil }

    init(settings: Settings = .load()) {
        self.settings = settings
        self.hotkey = HotkeyEngine(hotkey: settings.hotkey)
        self.transcriber = Transcriber(model: settings.whisperModel)
        hotkey.onPress = { [weak self] in self?.startRecording() }
        hotkey.onRelease = { [weak self] in self?.stopAndProcess() }
        audio.onLevel = { [weak self] level in
            Task { @MainActor [weak self] in self?.hud.updateLevel(level) }
        }
        NotificationCenter.default.addObserver(
            forName: .ovfRetryTranscription, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.retryLastTranscription() }
        }
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
        lastError = nil
        Task { try? await transcriber.warmUp() }  // preload model off the hot path
        return true
    }

    func stopListening() {
        hotkey.stop()
        isListening = false
        if isRecording { _ = audio.stop(); isRecording = false }
    }

    /// "Pause for 1 hour" (design 02, item 4). Hotkey is ignored while paused.
    func pause(for interval: TimeInterval = 3600) {
        stopListening()
        pausedUntil = Date().addingTimeInterval(interval)
        resumeTask?.cancel()
        resumeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(interval))
            if !Task.isCancelled { self?.resume() }
        }
    }

    func resume() {
        resumeTask?.cancel()
        pausedUntil = nil
        _ = startListening()
    }

    func updateHotkey(_ newHotkey: Hotkey) {
        settings.hotkey = newHotkey
        settings.save()
        if isListening { stopListening(); startListening() }
    }

    // MARK: dictation loop

    private func startRecording() {
        guard !isRecording, pausedUntil == nil else { return }
        pressTime = Date()
        do {
            try audio.start()
            isRecording = true
            hud.show(.recording(hotkey: settings.hotkey))
            maxRecordTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(self?.maxRecordingSeconds ?? 300))
                if !Task.isCancelled { self?.stopAndProcess() }  // finish + insert, never drop audio
            }
        } catch {
            log.error("audio start failed: \(error.localizedDescription)")
            lastError = "Microphone unavailable"
            hud.show(.error(.microphone))
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
        lastSamples = samples
        hud.show(.transcribing)
        Task { await process(samples) }
    }

    private func retryLastTranscription() {
        guard !lastSamples.isEmpty else { return }
        hud.show(.transcribing)
        Task { await process(lastSamples) }
    }

    private func process(_ samples: [Float]) async {
        isWorking = true
        defer { isWorking = false }
        do {
            let raw = try await transcriber.transcribe(samples, language: settings.language)
            guard !raw.isEmpty else {
                hud.show(.error(.timeout))
                return
            }
            hud.show(.cleaning)
            let provider = CleanupFactory.make(settings)
            let cleaned = (try? await provider.cleanup(raw, style: settings.style)) ?? raw
            let words = cleaned.split(whereSeparator: \.isWhitespace).count
            if settings.autoPaste { Paster.paste(cleaned) }
            wordsToday += words
            lastError = nil
            // Success holds ~1.8 s in the design's sequencing.
            hud.show(.result(words: words), autoHideAfter: 1.8)
        } catch {
            log.error("dictation failed: \(error.localizedDescription)")
            lastError = "Dictation failed"
            hud.show(.error(.timeout))
        }
    }
}
