import Foundation
import WhisperKit
import os

/// On-device transcription via WhisperKit (CoreML/Metal). Replaces the
/// whisper.cpp subprocess + HuggingFace model download of the Python app;
/// the model is managed by WhisperKit and can be bundled for offline use.
actor Transcriber {
    /// Reports raw byte counts, not a fraction: onboarding shows "412 of 981 MB
    /// · 5.4 MB/s · 2 min left", and a rate and an ETA can't be derived from a
    /// percentage. `expected` is 0 while the total is still unknown.
    typealias DownloadProgressObserver = @Sendable (_ received: Int64, _ expected: Int64) -> Void

    private var kit: WhisperKit?
    private var modelName: String
    /// The one in-flight download+load. Single-flight is the whole point:
    /// onboarding's engine chooser can fire warmUp while another warmUp is
    /// mid-download (actor re-entrancy at the awaits), and two concurrent
    /// downloads plus the purge-and-retry path deleting the cache folder the
    /// other is writing into produced the cold-run "That stopped" failures.
    private var loadTask: Task<WhisperKit, Error>?
    /// Identity for the task above — Task is a struct, so ownership of the
    /// slot is tracked by token, not by reference comparison.
    private var loadToken = UUID()
    private let log = Logger(subsystem: "app.openvoiceflow", category: "transcriber")

    init(model: String = "base.en") {
        self.modelName = model
    }

    /// Switch the transcription model: drop the loaded model, cancel any
    /// in-flight load of the old one, and leave loading to the next warmUp —
    /// callers decide when the download starts (onboarding debounces it; the
    /// Settings path warms up immediately). Note the shipped default `base.en`
    /// is English-only; a non-English language needs a multilingual model.
    func setModel(_ name: String) async {
        guard name != modelName else { return }
        modelName = name
        kit = nil
        loadTask?.cancel()
        loadTask = nil
    }

    /// True once the model is loaded in memory — lets onboarding skip the
    /// progress card entirely on a reinstall.
    var isReady: Bool { kit != nil }

    /// Load the model once (lazily). The observer receives only actual
    /// WhisperKit transfer progress, as raw byte counts.
    ///
    /// An interrupted HuggingFace download can leave a truncated `.mlmodelc`.
    /// On the first load failure, remove that cached variant and retry with a
    /// fresh download; a second failure is returned to the caller.
    func warmUp(progress observer: @escaping DownloadProgressObserver = { _, _ in }) async throws {
        guard kit == nil else {
            observer(1, 1)  // already resident — report complete
            return
        }

        // Join the in-flight load rather than starting a second one. The
        // joiner gets no byte progress (rare path — e.g. transcribe racing
        // onboarding); correctness over cosmetics.
        if let inFlight = loadTask {
            kit = try await inFlight.value
            observer(1, 1)
            return
        }

        let model = modelName
        let task = Task { () throws -> WhisperKit in
            do {
                return try await self.downloadAndLoad(model: model, progress: observer)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // The first failure must leave a trace: without it, a machine
                // that fails twice presents only the second error, and the
                // truncated-download recovery path is invisible in the log.
                self.log.error("model \(model, privacy: .public) load failed, purging and retrying: \(error.localizedDescription, privacy: .public)")
                self.purgeDownloadedModel(matching: model)
                try Task.checkCancellation()
                return try await self.downloadAndLoad(model: model, progress: observer)
            }
        }
        let token = UUID()
        loadToken = token
        loadTask = task
        // Clear only our own slot: a setModel during the await may already
        // have replaced it with a newer load that must not be evicted.
        defer { if loadToken == token { loadTask = nil } }

        let loaded = try await task.value
        // A setModel that raced this load already cancelled the task; this
        // guard covers the narrow window where the swap lands between the
        // last await and here — a stale model must never become `kit`.
        guard model == modelName else { throw CancellationError() }
        kit = loaded
        // No synthetic final callback: tracking the running total in a captured
        // var races WhisperKit's progress thread (a hard error under Swift 6).
        // The caller lands the bar on full instead — see DownloadMeter.complete().
    }

    private func downloadAndLoad(model: String, progress observer: @escaping DownloadProgressObserver) async throws -> WhisperKit {
        let modelFolder = try await WhisperKit.download(variant: model) { progress in
            observer(progress.completedUnitCount, progress.totalUnitCount)
        }
        try Task.checkCancellation()
        return try await WhisperKit(
            WhisperKitConfig(
                modelFolder: modelFolder.path,
                verbose: false,
                prewarm: true,
                load: true,
                download: false
            )
        )
    }

    /// Remove every on-disk variant of one model from WhisperKit's default
    /// download location so the retry starts with fresh model files. Takes the
    /// model explicitly so a purge can never race a swap and delete the folder
    /// a *different* model's download is writing into.
    private func purgeDownloadedModel(matching model: String) {
        let fm = FileManager.default
        let repo = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "huggingface/models/argmaxinc/whisperkit-coreml")
        guard let variants = try? fm.contentsOfDirectory(
            at: repo, includingPropertiesForKeys: nil
        ) else { return }
        for variant in variants where variant.lastPathComponent.hasSuffix(model) {
            try? fm.removeItem(at: variant)
        }
    }

    /// Transcribe an in-progress buffer for a live preview.
    ///
    /// Returns nil rather than waiting when the model isn't resident or the
    /// buffer is too short to say anything: a partial is a nicety, and it must
    /// never delay or fail the real transcription that follows.
    func partial(_ samples: [Float], language: String = "en") async -> String? {
        guard kit != nil, samples.count > 16_000 / 2 else { return nil }
        return try? await transcribe(samples, language: language)
    }

    /// Transcribe 16 kHz mono float samples to text. Returns "" for silence.
    func transcribe(_ samples: [Float], language: String = "en") async throws -> String {
        try await warmUp()
        guard let kit else { return "" }
        let options = DecodingOptions(
            language: language == "auto" ? nil : language,
            temperature: 0.0,
            withoutTimestamps: true
        )
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map { $0.text }.joined(separator: " ")
        return text
            .replacingOccurrences(of: "[BLANK_AUDIO]", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
