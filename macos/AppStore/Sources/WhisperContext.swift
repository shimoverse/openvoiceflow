import Foundation
import whisper

enum WhisperFailure: LocalizedError {
    case modelMissing
    case contextCreationFailed
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .modelMissing:
            return "The bundled speech model is missing."
        case .contextCreationFailed:
            return "OpenVoiceFlow could not load its local speech model."
        case .transcriptionFailed:
            return "Local transcription failed."
        }
    }
}

actor WhisperContext {
    private let context: OpaquePointer

    private init(context: OpaquePointer) {
        self.context = context
    }

    deinit {
        whisper_free(context)
    }

    static func load(modelURL: URL) throws -> WhisperContext {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw WhisperFailure.modelMissing
        }
        var parameters = whisper_context_default_params()
        parameters.use_gpu = true
        parameters.flash_attn = true
        guard let context = whisper_init_from_file_with_params(modelURL.path, parameters) else {
            throw WhisperFailure.contextCreationFailed
        }
        return WhisperContext(context: context)
    }

    func transcribe(samples: [Float]) throws -> String {
        let threadCount = Int32(max(1, min(8, ProcessInfo.processInfo.processorCount - 2)))
        var parameters = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        parameters.print_realtime = false
        parameters.print_progress = false
        parameters.print_timestamps = false
        parameters.print_special = false
        parameters.translate = false
        parameters.n_threads = threadCount
        parameters.no_context = true
        parameters.single_segment = false

        let result: Int32 = "en".withCString { language in
            parameters.language = language
            return samples.withUnsafeBufferPointer { buffer in
                whisper_full(context, parameters, buffer.baseAddress, Int32(buffer.count))
            }
        }
        guard result == 0 else {
            throw WhisperFailure.transcriptionFailed
        }

        var text = ""
        for index in 0..<whisper_full_n_segments(context) {
            if let segment = whisper_full_get_segment_text(context, index) {
                text += String(cString: segment)
            }
        }
        return normalizeTranscript(text)
    }
}

func normalizeTranscript(_ text: String) -> String {
    text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .split(whereSeparator: { $0.isWhitespace })
        .joined(separator: " ")
}
