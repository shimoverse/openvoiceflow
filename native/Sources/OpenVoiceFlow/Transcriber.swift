import Foundation
import WhisperKit

/// On-device transcription via WhisperKit (CoreML/Metal). Replaces the
/// whisper.cpp subprocess + HuggingFace model download of the Python app;
/// the model is managed by WhisperKit and can be bundled for offline use.
actor Transcriber {
    private var kit: WhisperKit?
    private let modelName: String

    init(model: String = "base.en") {
        self.modelName = model
    }

    /// Load the model once (lazily). Safe to call repeatedly.
    ///
    /// Self-heals a corrupt model: an interrupted HuggingFace download leaves
    /// a truncated `.mlmodelc`, and CoreML then fails to "build the model
    /// execution plan" (error −14) on every launch forever. On the first load
    /// failure we delete the on-disk model variant and retry once with a
    /// clean re-download; only a second failure is surfaced to the UI.
    func warmUp() async throws {
        guard kit == nil else { return }
        // On the Mac, prefer a bundled model directory so first run is offline:
        //   WhisperKitConfig(modelFolder: Bundle.main.resourceURL?.appending(path: "models"))
        // Falling back to WhisperKit's managed download during development.
        do {
            kit = try await WhisperKit(WhisperKitConfig(model: modelName))
        } catch {
            purgeDownloadedModel()
            kit = try await WhisperKit(WhisperKitConfig(model: modelName))
        }
    }

    /// Remove every on-disk variant of this model from WhisperKit's default
    /// download location (~/Documents/huggingface/models/argmaxinc/
    /// whisperkit-coreml/), so the retry starts from a clean download instead
    /// of recompiling the same corrupt files.
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
