import AVFoundation
import Foundation

/// Streams a meeting directly to a 16 kHz, mono, 16-bit PCM WAV on disk.
/// The owning store is responsible for stopping the recording at two hours.
final class MeetingRecorder {
    enum RecordingError: LocalizedError {
        case microphoneAccessDenied
        case alreadyRecording
        case invalidDestination
        case destinationExists
        case couldNotStart

        var errorDescription: String? {
            switch self {
            case .microphoneAccessDenied: return "Microphone access is required to record a meeting."
            case .alreadyRecording: return "A meeting is already being recorded."
            case .invalidDestination: return "The meeting recording needs a local WAV file destination."
            case .destinationExists: return "The meeting recording destination already exists."
            case .couldNotStart: return "The microphone could not start recording."
            }
        }
    }

    private var recorder: AVAudioRecorder?

    var isRecording: Bool { recorder?.isRecording == true }

    /// Call this before `start(at:)`, so the system permission prompt can complete.
    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    continuation.resume(returning: granted)
                }
            }
        default:
            return false
        }
    }

    /// Start writing to a new file. Never overwrite a previous meeting.
    func start(at url: URL) throws {
        guard recorder == nil else { throw RecordingError.alreadyRecording }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecordingError.microphoneAccessDenied
        }
        guard url.isFileURL, url.pathExtension.lowercased() == "wav" else {
            throw RecordingError.invalidDestination
        }

        let files = FileManager.default
        guard !files.fileExists(atPath: url.path) else { throw RecordingError.destinationExists }
        try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let newRecorder = try AVAudioRecorder(url: url, settings: settings)
        guard newRecorder.prepareToRecord() else {
            try? files.removeItem(at: url)
            throw RecordingError.couldNotStart
        }
        do {
            // Keep the WAV private before the first sample reaches the file.
            try files.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            newRecorder.stop()
            try? files.removeItem(at: url)
            throw error
        }
        guard newRecorder.record() else {
            newRecorder.stop()
            try? files.removeItem(at: url)
            throw RecordingError.couldNotStart
        }
        recorder = newRecorder
    }

    /// Finalize the WAV header and return the captured audio duration in seconds.
    @discardableResult
    func stop() -> Double {
        guard let recorder else { return 0 }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        return duration
    }

    deinit {
        recorder?.stop()
    }
}
