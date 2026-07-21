import Foundation
import WhisperKit

/// On-device transcription via WhisperKit (CoreML/Metal). Replaces the
/// whisper.cpp subprocess + HuggingFace model download of the Python app;
/// the model is managed by WhisperKit and can be bundled for offline use.
actor Transcriber {
    typealias DownloadProgressObserver = @Sendable (Double) -> Void

    private var kit: WhisperKit?
    private let modelName: String

    init(model: String = "base.en") {
        self.modelName = model
    }

    /// Load the model once (lazily). The observer receives only actual
    /// WhisperKit transfer progress, normalized to 0...1.
    ///
    /// An interrupted HuggingFace download can leave a truncated `.mlmodelc`.
    /// On the first load failure, remove that cached variant and retry with a
    /// fresh download; a second failure is returned to the caller.
    func warmUp(progress observer: @escaping DownloadProgressObserver = { _ in }) async throws {
        guard kit == nil else {
            observer(1)
            return
        }

        do {
            kit = try await downloadAndLoad(progress: observer)
        } catch {
            purgeDownloadedModel()
            kit = try await downloadAndLoad(progress: observer)
        }
        observer(1)
    }

    private func downloadAndLoad(progress observer: @escaping DownloadProgressObserver) async throws -> WhisperKit {
        let modelFolder = try await WhisperKit.download(variant: modelName) { progress in
            guard progress.totalUnitCount > 0 else { return }
            let fraction = Double(progress.completedUnitCount) / Double(progress.totalUnitCount)
            observer(min(max(fraction, 0), 1))
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
