import AVFoundation
import Foundation

/// Converts microphone input to 16 kHz mono and streams it to a private CAF.
/// A reader is reopened for each bounded chunk: an AVAudioFile reader snapshots
/// the length at open, even while the writer continues appending.
final class MeetingRecorder {
    enum RecordingError: LocalizedError {
        case microphoneAccessDenied, alreadyRecording, invalidDestination, destinationExists, couldNotStart, captureFailed
        var errorDescription: String? {
            switch self {
            case .microphoneAccessDenied: return "Microphone access is required to record a meeting."
            case .alreadyRecording: return "A meeting is already being recorded."
            case .invalidDestination: return "The meeting recording needs a local CAF file destination."
            case .destinationExists: return "The meeting recording destination already exists."
            case .couldNotStart: return "The microphone could not start recording."
            case .captureFailed: return "Audio capture failed; the recording saved so far is available."
            }
        }
    }

    private let lock = NSLock()
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                             channels: 1, interleaved: false)!
    private var engine: AVAudioEngine?
    private var writer: AVAudioFile?
    private var converter: AVAudioConverter?
    private var destination: URL?
    private var framesWritten: AVAudioFramePosition = 0
    private(set) var readFramePosition: AVAudioFramePosition = 0
    private var captureError: Error?

    var isRecording: Bool { lock.lock(); defer { lock.unlock() }; return writer != nil }
    var duration: Double { lock.lock(); defer { lock.unlock() }; return Double(framesWritten) / 16_000 }

    static func requestPermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                AVCaptureDevice.requestAccess(for: .audio) { continuation.resume(returning: $0) }
            }
        default: return false
        }
    }

    func start(at url: URL) throws {
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            throw RecordingError.microphoneAccessDenied
        }
        let newEngine = AVAudioEngine()
        let input = newEngine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        try start(at: url, feeding: inputFormat)
        do {
            input.installTap(onBus: 0, bufferSize: 4_096, format: inputFormat) { [weak self] buffer, _ in
                do { try self?.append(buffer) }
                catch { self?.recordCaptureError(error) }
            }
            newEngine.prepare()
            try newEngine.start()
            engine = newEngine
        } catch {
            input.removeTap(onBus: 0)
            _ = stop()
            throw error
        }
    }

    /// Accept a PCM source through the same conversion/write path used by the mic tap.
    /// This also permits paced source capture without requesting a physical microphone.
    func start(at url: URL, feeding inputFormat: AVAudioFormat) throws {
        lock.lock(); defer { lock.unlock() }
        guard writer == nil else { throw RecordingError.alreadyRecording }
        guard url.isFileURL, url.pathExtension.lowercased() == "caf" else { throw RecordingError.invalidDestination }
        guard !FileManager.default.fileExists(atPath: url.path) else { throw RecordingError.destinationExists }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let conversion = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw RecordingError.couldNotStart
        }
        // AVAudioFile creates the file, so protect it before any sample is written.
        let file = try AVAudioFile(forWriting: url, settings: outputFormat.settings,
                                   commonFormat: .pcmFormatFloat32, interleaved: false)
        do { try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path) }
        catch { try? FileManager.default.removeItem(at: url); throw error }
        writer = file
        converter = conversion
        destination = url
        framesWritten = 0
        readFramePosition = 0
        captureError = nil
    }

    func append(_ input: AVAudioPCMBuffer) throws {
        lock.lock(); defer { lock.unlock() }
        guard let writer, let converter else { throw RecordingError.couldNotStart }
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat,
                frameCapacity: AVAudioFrameCount(ceil(Double(input.frameLength) * 16_000 / input.format.sampleRate) + 256)) else {
            throw RecordingError.captureFailed
        }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied { inputStatus.pointee = .noDataNow; return nil }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }
        if let conversionError { throw conversionError }
        guard status != .error else { throw RecordingError.captureFailed }
        if output.frameLength > 0 {
            try writer.write(from: output)
            framesWritten += AVAudioFramePosition(output.frameLength)
        }
    }

    /// Returns no more than maxFrames, never loads the full take. A new reader
    /// sees the latest CAF length while the writer remains open.
    func readAvailable(maxFrames: Int) throws -> [Float] {
        precondition(maxFrames > 0 && maxFrames <= 5 * 16_000)
        lock.lock()
        let failure = captureError
        let url = destination
        let position = readFramePosition
        lock.unlock()
        if let failure { throw failure }
        guard let url else { return [] }
        let reader = try AVAudioFile(forReading: url)
        guard position < reader.length else { return [] }
        reader.framePosition = position
        let count = AVAudioFrameCount(min(Int64(maxFrames), reader.length - position))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: reader.processingFormat, frameCapacity: count) else {
            throw RecordingError.captureFailed
        }
        try reader.read(into: buffer, frameCount: count)
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return [] }
        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        lock.lock()
        readFramePosition += AVAudioFramePosition(buffer.frameLength)
        lock.unlock()
        return samples
    }

    private func recordCaptureError(_ error: Error) {
        lock.lock(); defer { lock.unlock() }
        if captureError == nil { captureError = error }
    }

    @discardableResult func stop() -> Double {
        // Detach the callback before dropping the writer. append and reads share
        // a lock, so closing cannot interleave with a file write.
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            self.engine = nil
        }
        lock.lock(); defer { lock.unlock() }
        if let converter, let writer {
            for _ in 0..<8 {
                guard let tail = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: 4_096) else { break }
                var conversionError: NSError?
                let status = converter.convert(to: tail, error: &conversionError) { _, inputStatus in
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                if tail.frameLength > 0 {
                    do {
                        try writer.write(from: tail)
                        framesWritten += AVAudioFramePosition(tail.frameLength)
                    } catch { captureError = error; break }
                }
                if status == .endOfStream || status == .error || tail.frameLength == 0 { break }
            }
        }
        let seconds = Double(framesWritten) / 16_000
        writer = nil
        converter = nil
        return seconds
    }

    deinit { _ = stop() }
}
