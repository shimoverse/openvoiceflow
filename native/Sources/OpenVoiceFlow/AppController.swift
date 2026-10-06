import AppKit
import Combine
import Foundation
import os

/// Dashboard Settings preparation status, scoped to the current selection.
@MainActor
final class ModelPreparationStatus: ObservableObject {
    @Published private(set) var message: String?
    @Published private(set) var errorDetail: String?
    @Published private(set) var canRetry = false
    private var generation = 0
    private var target: String?
    private var task: Task<Void, Never>?

    func selectionChanged(to model: String) {
        guard target != model else { return }
        generation += 1
        task?.cancel()
        task = nil
        target = nil
        message = nil
        errorDetail = nil
        canRetry = false
    }

    func choose(_ model: String, controller: AppController) {
        generation += 1
        let current = generation
        task?.cancel()
        target = model
        message = "Downloading…"
        errorDetail = nil
        canRetry = false
        task = Task {
            do {
                let selection = try await controller.selectModel(model)
                guard !Task.isCancelled, current == generation else { return }
                if !(await controller.isModelReady(model, generation: selection)) {
                    try await controller.prepareModelForOnboarding(model, generation: selection) { received, expected in
                        Task { @MainActor in
                            guard current == self.generation else { return }
                            if expected > 0, received >= expected {
                                self.message = "Preparing model…"
                            } else if expected > 0 {
                                self.message = "Downloading \(Int(min(100, max(0, Double(received) / Double(expected) * 100))))%"
                            }
                        }
                    }
                }
                guard !Task.isCancelled, current == generation else { return }
                guard await controller.isModelReady(model, generation: selection) else { throw WhistleError.notDownloaded }
                message = "Ready to transcribe"
            } catch is CancellationError {
                if current == generation {
                    message = "Download stopped"
                    errorDetail = "Try again to prepare this model."
                    canRetry = true
                }
            } catch WhistleError.unsupportedArchitecture {
                guard current == generation else { return }
                message = "Model unavailable"
                errorDetail = WhistleError.unsupportedArchitecture.localizedDescription
            } catch WhistleError.unsupportedLanguage {
                guard current == generation else { return }
                message = "Model unavailable"
                errorDetail = WhistleError.unsupportedLanguage.localizedDescription
            } catch {
                guard current == generation else { return }
                message = "Download failed"
                errorDetail = error.localizedDescription
                canRetry = true
            }
        }
    }
}

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
    /// The most recent delivered text. Lets the UI show what was actually heard
    /// (onboarding's "say hello" confirms the loop works even when the paste
    /// lands in another app).
    @Published private(set) var lastTranscript: String?
    /// Live partial transcript, published only while `streamPartials` is on.
    /// Onboarding's ink fill is the sole consumer — see `streamPartials`.
    @Published private(set) var partialTranscript: String?
    /// How long the last take was held, for onboarding's spoken-vs-typed line.
    @Published private(set) var lastSpeechSeconds: Double = 0

    /// Opt-in live partials. Off everywhere except the onboarding try-it step:
    /// re-transcribing a growing buffer every 300 ms costs real CPU, and the
    /// normal dictation path has no use for it (the HUD shows a coil, not text).
    var streamPartials = false
    @Published var settings: Settings
    let modelPreparation = ModelPreparationStatus()

    // Ported feature stores (dictionary, snippets, styles, profile, history).
    let profileStore = ProfileStore()
    let dictionaryStore = DictionaryStore()
    let snippetStore = SnippetStore()
    let styleStore = StyleStore()
    let historyStore = HistoryStore()
    let analyticsIdentity = AnalyticsIdentityStore()
    /// Which panes and features get used. Local counters; shared only under
    /// the same opt-out switch as the rest of the analytics payload.
    let usageCounters = UsageCounters()
    let analyticsClient = AnalyticsClient()
    let referralClient = ReferralClient()

    /// Today's dictated words — read straight from the persisted stats.
    var wordsToday: Int { historyStore.wordsToday }

    private let log = Logger(subsystem: "app.openvoiceflow", category: "controller")
    private let hotkey: HotkeyEngine
    private let audio = AudioCapture()
    private let transcriber: Transcriber
    private let hud = HUDController()

    /// Hard ceiling so a missed hotkey-up can't record forever (Python H2).
    private var maxRecordingSeconds: Double { settings.maxRecordingSeconds }
    /// Below this a take is too brief to transcribe reliably — nudge, don't error.
    private let minSpeakSeconds: Double = 0.5
    private var maxRecordTask: Task<Void, Never>?
    private var partialTask: Task<Void, Never>?
    private var dictationTask: Task<Void, Never>?
    private var resumeTask: Task<Void, Never>?
    private var pressTime = Date.distantPast
    private var lastSamples: [Float] = []
    private(set) var modelSelectionGeneration = 0
    private var dictationGeneration = 0

    private func invalidateDictation() {
        dictationGeneration += 1
        maxRecordTask?.cancel()
        partialTask?.cancel()
        partialTask = nil
        dictationTask?.cancel()
        dictationTask = nil
        lastSamples = [] // Do not retry audio captured under a previous model.
        if isRecording { _ = audio.stop(); isRecording = false }
        isWorking = false
        partialTranscript = nil
        hud.hide() // A hot swap is a cancellation, not a failed transcription.
    }

    private func validateSelection(_ model: String, generation: Int) throws {
        guard settings.whisperModel == model, modelSelectionGeneration == generation else {
            throw CancellationError()
        }
    }

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
        // Best-effort, once per installation — see ReferralAttributionCapture.
        ReferralAttributionCapture.captureIfNeeded(ownDeviceId: analyticsIdentity.identity.deviceId)
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

    /// Prepares the local speech engine for onboarding, forwarding WhisperKit's
    /// real byte counts so the view can show size, rate and ETA.
    func prepareModelForOnboarding(_ model: String, generation: Int,
        progress: @escaping Transcriber.DownloadProgressObserver
    ) async throws {
        try validateSelection(model, generation: generation)
        try await transcriber.downloadSelectedModel(model, progress: progress)
        try validateSelection(model, generation: generation)
    }

    /// Onboarding's engine choice. Unlike `updateModel` this awaits the swap,
    /// so the download the caller starts next fetches the chosen model instead
    /// of racing the transcriber's async set.
    @discardableResult
    func selectModel(_ name: String) async throws -> Int {
        try Task.checkCancellation()
        if name == WhistleEngine.modelID {
            #if !arch(arm64)
            throw WhistleError.unsupportedArchitecture
            #endif
            if !WhistleEngine.supports(language: settings.language) {
                throw WhistleError.unsupportedLanguage
            }
        }
        guard name != settings.whisperModel else { return modelSelectionGeneration }
        modelSelectionGeneration += 1
        let generation = modelSelectionGeneration
        invalidateDictation()
        settings.whisperModel = name
        settings.save()
        lastError = nil
        modelPreparation.selectionChanged(to: name)
        await transcriber.setModel(name, generation: generation)
        try validateSelection(name, generation: generation)
        return generation
    }

    /// Whether the speech model is already resident — lets onboarding skip the
    /// download card on a reinstall.
    func isModelReady(_ model: String, generation: Int) async -> Bool {
        guard (try? validateSelection(model, generation: generation)) != nil else { return false }
        let ready = await transcriber.isReady(for: model)
        return ready && (try? validateSelection(model, generation: generation)) != nil
    }

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
        guard newHotkey != settings.hotkey else { return }
        settings.hotkey = newHotkey
        // A new key has to be learned from scratch, so the chip comes back for
        // another 7 days rather than staying gone.
        settings.hotkeyLearnedAt = nil
        settings.save()
        if isListening { stopListening(); startListening() }
    }

    /// Change the transcription model at runtime so a Settings change takes
    /// effect without an app restart: the live `Transcriber` drops its loaded
    /// model and reloads the new one off the hot path.
    func updateModel(_ name: String) {
        guard name != settings.whisperModel else { return }
        if name == WhistleEngine.modelID {
            #if !arch(arm64)
            lastError = WhistleError.unsupportedArchitecture.localizedDescription
            return
            #endif
        }
        guard name != WhistleEngine.modelID || WhistleEngine.supports(language: settings.language) else {
            lastError = WhistleError.unsupportedLanguage.localizedDescription
            return
        }
        modelSelectionGeneration += 1
        let generation = modelSelectionGeneration
        invalidateDictation()
        settings.whisperModel = name
        settings.save()
        lastError = nil
        modelPreparation.selectionChanged(to: name)
        // setModel no longer loads (onboarding needs the swap and the download
        // decoupled); the Settings path still wants the hot-swap immediately.
        Task {
            await transcriber.setModel(name, generation: generation)
            guard (try? validateSelection(name, generation: generation)) != nil else { return }
            try? await transcriber.warmUp()
        }
    }

    // MARK: dictation loop

    private func startRecording() {
        guard !isRecording, pausedUntil == nil else { return }
        dictationTask?.cancel()
        dictationTask = nil
        dictationGeneration += 1
        pressTime = Date()
        do {
            try audio.start()
            isRecording = true
            hud.setMaxSeconds(maxRecordingSeconds)
            hud.setShowChip(shouldShowHotkeyChip)
            hud.show(.recording(hotkey: settings.hotkey))
            if streamPartials || settings.liveTranscript { startPartialStream() }
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
        partialTask?.cancel()
        partialTask = nil
        let samples = audio.stop()
        let elapsed = Date().timeIntervalSince(pressTime)
        lastSpeechSeconds = elapsed
        guard !samples.isEmpty else { hud.hide(); return }
        // Released too soon to catch speech — nudge to keep talking, don't transcribe.
        guard elapsed >= minSpeakSeconds else {
            hud.show(.tooShort)
            return
        }
        lastSamples = samples
        hud.show(.transcribing)
        let generation = dictationGeneration
        let selection = modelSelectionGeneration
        dictationTask = Task { await process(samples, generation: generation, selection: selection) }
    }

    /// Re-transcribe the growing buffer on a 300 ms beat so the ink fill has
    /// words to reveal while the key is still held. Every partial is
    /// best-effort: a failure or a slow pass is skipped, never surfaced, and
    /// never allowed to delay the real transcription on release.
    private func startPartialStream() {
        partialTranscript = nil
        partialTask?.cancel()
        partialTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(300))
                guard let self, !Task.isCancelled, self.isRecording else { return }
                let buffer = self.audio.snapshot()
                guard let text = await self.transcriber.partial(buffer, language: self.settings.language),
                      !text.isEmpty else { continue }
                if !Task.isCancelled {
                    self.partialTranscript = text
                    // Echo the words into the HUD while the key is held —
                    // unless the user turned text echo off, which covers the
                    // dictating-passwords case for live words too.
                    if self.settings.liveTranscript && self.settings.echoInsertedText {
                        self.hud.updateLiveTail(text)
                    }
                }
            }
        }
    }

    private func retryLastTranscription() {
        guard !lastSamples.isEmpty else { return }
        dictationGeneration += 1
        hud.show(.transcribing)
        let generation = dictationGeneration
        let selection = modelSelectionGeneration
        dictationTask?.cancel()
        dictationTask = Task { await process(lastSamples, generation: generation, selection: selection) }
    }

    private func process(_ samples: [Float], generation: Int, selection: Int) async {
        guard generation == dictationGeneration, selection == modelSelectionGeneration else { return }
        // Cancellation prevents subsequent paste/history; it cannot retract
        // data already sent to a remote cleanup provider before the swap.
        isWorking = true
        defer { if generation == dictationGeneration { isWorking = false } }
        let selectedModel = settings.whisperModel
        // The app the user dictated into — for per-app style + history.
        let frontApp = NSWorkspace.shared.frontmostApplication?.localizedName ?? "Unknown"
        do {
            let raw = try await transcriber.transcribe(samples, language: settings.language)
            try validateDictation(selectedModel, selection: selection, generation: generation)
            guard !raw.isEmpty else {
                // Whisper heard nothing usable (very short/quiet) — a nudge, not an error.
                hud.show(.tooShort)
                return
            }

            // Voice snippet: an exact trigger expands directly, no LLM call.
            if let expansion = snippetStore.match(raw) {
                deliver(expansion, app: frontApp)
                return
            }

            hud.show(.cleaning)
            // Per-app style overrides the manual default (design 03 "Styles").
            let style = styleStore.styleForFrontmostApp(fallback: settings.style)
            // Personal context: profile + dictionary + snippet hints.
            let context = profileStore.promptFragment
                + dictionaryStore.promptFragment
                + snippetHints()
            let provider = CleanupFactory.make(settings)
            let cleaned = (try? await provider.cleanup(raw, style: style, context: context)) ?? raw
            try validateDictation(selectedModel, selection: selection, generation: generation)
            deliver(cleaned, app: frontApp)
        } catch is CancellationError {
            if generation == dictationGeneration { hud.hide() }
        } catch WhistleError.cancelled {
            if generation == dictationGeneration { hud.hide() }
        } catch {
            guard generation == dictationGeneration, selection == modelSelectionGeneration else { return }
            log.error("dictation failed: \(error.localizedDescription)")
            lastError = error is WhistleError ? error.localizedDescription : "Dictation failed"
            hud.show(.error(.timeout))
        }
    }

    private func validateDictation(_ model: String, selection: Int, generation: Int) throws {
        try validateSelection(model, generation: selection)
        guard generation == dictationGeneration else { throw CancellationError() }
    }

    /// Paste, log to history, bump stats, and flash the success HUD.
    private func deliver(_ text: String, app: String) {
        let words = text.split(whereSeparator: \.isWhitespace).count
        // Paste (if enabled). If the synthetic ⌘V couldn't be delivered — e.g.
        // Accessibility was revoked — Paster keeps the text on the clipboard and
        // returns false, and we nudge the user to paste it manually.
        let pasted = settings.autoPaste ? Paster.paste(text) : true
        historyStore.record(app: app, text: text, words: words)
        usageCounters.record(.dictationCompleted)
        analyticsClient.syncIfDue(controller: self)
        lastError = nil
        lastTranscript = text
        partialTranscript = nil
        markFirstSuccess()
        if pasted {
            hud.setShowChip(shouldShowHotkeyChip)
            hud.show(.result(tail: Self.tail(of: text, words: words,
                                             echo: settings.echoInsertedText)))
        } else {
            hud.show(.error(.pasteBlocked))
        }
    }

    /// The last five words of what landed, ellipsised when truncated — proof
    /// rather than a receipt. Falls back to a count when the user has asked not
    /// to have their text echoed.
    static func tail(of text: String, words: Int, echo: Bool) -> String {
        guard echo else { return words == 1 ? "1 word" : "\(words.grouped) words" }
        let parts = text.split(whereSeparator: \.isWhitespace)
        guard parts.count > 5 else { return parts.joined(separator: " ") }
        return "…" + parts.suffix(5).joined(separator: " ")
    }

    /// Stamp the two "first time" dates once, on the first dictation that
    /// actually worked.
    private func markFirstSuccess() {
        var changed = false
        if settings.firstUseDate == nil {
            // Home reads "…since <month>" off this date against an all-time
            // word total, and an upgrade install arrives with months of daily
            // totals already on disk. Stamping today would credit every one of
            // those words to this minute. Backdate to the first day anything
            // was actually dictated; only a genuinely new install has none.
            settings.firstUseDate = historyStore.firstDictationDay ?? Date()
            changed = true
        }
        if settings.hotkeyLearnedAt == nil { settings.hotkeyLearnedAt = Date(); changed = true }
        if changed { settings.save() }
    }

    /// The chip is a reminder, and a reminder that never leaves is furniture:
    /// show it for 7 days from when the hotkey was learned, then never.
    private var shouldShowHotkeyChip: Bool {
        guard let learned = settings.hotkeyLearnedAt else { return true }
        return Date() < learned.addingTimeInterval(7 * 24 * 60 * 60)
    }

    /// Tell the LLM to echo a snippet trigger verbatim so match() can expand it
    /// even after cleanup rewording (mirrors get_snippets_prompt_fragment).
    private func snippetHints() -> String {
        let triggers = snippetStore.snippets.map { "  - \"\($0.trigger)\"" }
        guard !triggers.isEmpty else { return "" }
        return "\n\nVoice snippets — if the user says EXACTLY one of these triggers "
            + "(and nothing else meaningful), output the trigger unchanged:\n"
            + triggers.joined(separator: "\n")
    }
}
