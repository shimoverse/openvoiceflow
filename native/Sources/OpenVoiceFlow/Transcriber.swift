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
    func warmUp() async throws {
        guard kit == nil else { return }
        // On the Mac, prefer a bundled model directory so first run is offline:
        //   WhisperKitConfig(modelFolder: Bundle.main.resourceURL?.appending(path: "models"))
        // Falling back to WhisperKit's managed download during development.
        kit = try await WhisperKit(WhisperKitConfig(model: modelName))
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
