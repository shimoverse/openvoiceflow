import AVFoundation
import Foundation

/// Captures microphone audio and hands back a 16 kHz mono `Float` buffer —
/// exactly what WhisperKit expects — using `AVAudioEngine` (no subprocess,
/// no temp WAV files like the Python path).
final class AudioCapture {
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private let lock = NSLock()
    private var isRunning = false

    /// WhisperKit's expected input format.
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    /// Request microphone access; the completion runs on an arbitrary queue.
    static func requestAccess(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { completion($0) }
        default: completion(false)
        }
    }

    static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    /// Begin capturing. Throws if the engine can't start (device busy/missing).
    func start() throws {
        guard !isRunning else { return }
        lock.withLock { samples.removeAll(keepingCapacity: true) }

        let input = engine.inputNode
        let inputFormat = input.inputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.append(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    /// Stop capturing and return the mono 16 kHz samples collected.
    @discardableResult
    func stop() -> [Float] {
        guard isRunning else { return [] }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        return lock.withLock { samples }
    }

    /// Seconds of audio captured so far (for the "too short" guard).
    var duration: TimeInterval {
        lock.withLock { Double(samples.count) / 16_000.0 }
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let converter else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var error: NSError?
        var supplied = false
        converter.convert(to: out, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.floatChannelData?[0] else { return }
        let frames = Int(out.frameLength)
        let chunk = Array(UnsafeBufferPointer(start: channel, count: frames))
        lock.withLock { samples.append(contentsOf: chunk) }
    }
}
