import Foundation
import WhisperKit

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

    init(model: String = "base.en") {
        self.modelName = model
    }

    /// Switch the transcription model at runtime so a Settings change takes
    /// effect without an app restart: drop the loaded model and reload the new
    /// one. Best-effort — if the reload fails, the next `transcribe` re-tries
    /// warmUp (and can recover a truncated download). Note the shipped default
    /// `base.en` is English-only; a non-English language needs a multilingual
    /// model (the Settings picker offers them).
    func setModel(_ name: String) async {
        guard name != modelName else { return }
        modelName = name
        kit = nil
        try? await warmUp()
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

        var total: Int64 = 0
        let track: DownloadProgressObserver = { received, expected in
            if expected > 0 { total = expected }
            observer(received, expected)
        }
        do {
            kit = try await downloadAndLoad(progress: track)
        } catch {
            purgeDownloadedModel()
            kit = try await downloadAndLoad(progress: track)
        }
        // Land the bar exactly on full rather than wherever the last callback
        // happened to fire.
        observer(max(total, 1), max(total, 1))
    }

    private func downloadAndLoad(progress observer: @escaping DownloadProgressObserver) async throws -> WhisperKit {
        let modelFolder = try await WhisperKit.download(variant: modelName) { progress in
            observer(progress.completedUnitCount, progress.totalUnitCount)
        }
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

    /// Remove every on-disk variant of this model from WhisperKit's default
    /// download location so the retry starts with fresh model files.
    private func purgeDownloadedModel() {
        let fm = FileManager.default
        let repo = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appending(path: "huggingface/models/argmaxinc/whisperkit-coreml")
        guard let variants = try? fm.contentsOfDirectory(
            at: repo, includingPropertiesForKeys: nil
        ) else { return }
        for variant in variants where variant.lastPathComponent.hasSuffix(modelName) {
            try? fm.removeItem(at: variant)
        }
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
