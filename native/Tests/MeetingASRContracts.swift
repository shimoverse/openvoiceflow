import AVFoundation
import Foundation

@main enum MeetingASRContracts {
    private static func check(_ okay: Bool, _ message: String) {
        if !okay { fatalError(message) }
    }

    private static func noise(_ count: Int, amplitude: Float = 0.008) -> [Float] {
        var seed: UInt32 = 0x48273a12
        return (0..<count).map { _ in
            seed = 1_664_525 &* seed &+ 1_013_904_223
            return (Float(seed >> 8) / Float(0x00ff_ffff) * 2 - 1) * amplitude
        }
    }

    private static func speech(_ count: Int, amplitude: Float = 0.006) -> [Float] {
        (0..<count).map { index in
            // A short quiet, modulated voiced-like burst, not a transcript.
            let envelope = 0.05 + 0.95 * sin(Double(index) * .pi * 2 / 1200) * sin(Double(index) * .pi * 2 / 1200)
            return amplitude * Float(envelope * sin(Double(index) * .pi * 2 * 190 / 16_000))
        }
    }

    private static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func word(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func dword(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append(contentsOf: "RIFF".utf8)
        dword(UInt32(samples.count * 2 + 36))
        data.append(contentsOf: "WAVEfmt ".utf8)
        dword(16); word(1); word(1); dword(16_000); dword(32_000); word(2); word(16)
        data.append(contentsOf: "data".utf8)
        dword(UInt32(samples.count * 2))
        for sample in samples { word(UInt16(bitPattern: Int16(max(-1, min(1, sample)) * 32767))) }
        return data
    }

    @MainActor private static func run(_ root: URL) async throws {
        let silence = [Float](repeating: 0, count: 16_000 * 3)
        let stationary = noise(16_000 * 3)
        let quietBurst = [Float](repeating: 0.0002, count: 16_000 * 3) + speech(16_000 / 10) + [Float](repeating: 0.0002, count: 16_000)
        check(!MeetingSpeechGate.shouldDecode(silence), "digital silence decoded")
        check(!MeetingSpeechGate.shouldDecode(stationary), "stationary noise decoded")
        check(MeetingSpeechGate.shouldDecode(quietBurst), "quiet short speech tail lost")
        check(MeetingSpeechGate.shouldDecode(speech(16_000 / 10)), "short voiced utterance lost")
        var backgroundWithSpeech = noise(16_000 * 3)
        let burst = speech(16_000 / 10, amplitude: 0.03)
        for index in burst.indices { backgroundWithSpeech[16_000 + index] += burst[index] }
        check(MeetingSpeechGate.shouldDecode(backgroundWithSpeech), "brief speech in stationary noise lost")
        let steadyVoiced = (0..<(16_000 * 3)).map { index in
            Float(0.003 * sin(Double(index) * .pi * 2 * 190 / 16_000))
        }
        check(MeetingSpeechGate.shouldDecode(steadyVoiced), "steady quiet voiced speech rejected as stationary noise")
        var longNoiseWithSpeech = noise(16_000 * 30)
        let quietSpeech = speech(16_000 / 10, amplitude: 0.006)
        for index in quietSpeech.indices { longNoiseWithSpeech[16_000 * 15 + index] += quietSpeech[index] }
        check(MeetingSpeechGate.shouldDecode(longNoiseWithSpeech), "30-second noise percentile swallowed quiet speech burst")
        check(MeetingSpeechGate.shouldDecode([Float](repeating: 0.1, count: 16_000)), "ambiguous loud audio discarded")

        let longVoicedSource = root.appendingPathComponent("long-quiet-voice.wav")
        // Exact chunk boundaries must finish cleanly without a padded sample.
        let longOriginal = wav(longNoiseWithSpeech)
        try longOriginal.write(to: longVoicedSource)
        let longRecord = try await MeetingStore(directory: root.appendingPathComponent("long-import")).importAudio(longVoicedSource)
        let longStore = MeetingStore(directory: root.appendingPathComponent("long-import"))
        var longCalls = 0
        do {
            try await longStore.transcribe(longRecord) { samples in
                longCalls += 1
                check(samples.count == 16_000 * 30, "import altered the decoder's 30-second audio")
                return "Thank you. Thank you."
            }
        } catch { fatalError("30-second import transcribe failed: \(error); decoder calls \(longCalls); transcript \(longStore.meetings.first?.transcript ?? "nil"); \(longStore.errorMessage ?? "no store error")") }
        check(longCalls == 1, "quiet burst in a 30-second import was never decoded")
        check(longStore.meetings.first?.transcript.contains("Thank you. Thank you.") == true,
              "legitimate repeated thank you lost in noisy import")
        check(longStore.notesFailureID == nil && longStore.notesError == nil &&
              longStore.meetings.first?.generatedNotes.isEmpty == true,
              "filler-only transcription was reported as a notes failure")
        check(try Data(contentsOf: longStore.audioURL(for: longRecord)) == longOriginal, "noisy import audio bytes changed")
        let exactMinuteSource = root.appendingPathComponent("exact-minute.wav")
        try wav([Float](repeating: 0.1, count: 60 * 16_000)).write(to: exactMinuteSource)
        let minuteRecord = try await longStore.importAudio(exactMinuteSource)
        var minuteCalls = 0
        try await longStore.transcribe(minuteRecord) { samples in
            minuteCalls += 1
            check(samples.count == 30 * 16_000, "exact-minute import did not preserve chunk boundaries")
            return "Thank you."
        }
        check(minuteCalls == 2, "exact-minute import did not terminate cleanly after two chunks")

        let store = MeetingStore(directory: root.appendingPathComponent("imports"))
        let source = root.appendingPathComponent("input.wav")
        let original = wav(silence + stationary)
        try original.write(to: source)
        let empty = try await store.importAudio(source)
        var calls = 0
        try await store.transcribe(empty) { _ in calls += 1; return "Thank you. Thank you." }
        check(calls == 0 && store.meetings[0].transcript.isEmpty, "silent/noise import reached decoder or persisted hallucination")
        check(store.notesFailureID == nil && store.notesError == nil,
              "silent import was reported as a notes failure")
        check(try Data(contentsOf: store.audioURL(for: empty)) == original, "import audio bytes changed")
        check(try Data(contentsOf: source) == original, "original audio changed")

        let voiced = root.appendingPathComponent("voiced.wav")
        try wav(quietBurst).write(to: voiced)
        let record = try await store.importAudio(voiced)
        try await store.transcribe(record) { _ in calls += 1; return "Thank you. Thank you. Thank you." }
        check(calls == 1, "quiet speech import was not decoded")
        check(store.meetings.first(where: { $0.id == record.id })?.transcript.contains("Thank you. Thank you. Thank you.") == true,
              "legitimate repeated speech was text-deduplicated")

        let recorder = MeetingRecorder()
        let live = MeetingStore(directory: root.appendingPathComponent("live"), recorder: recorder)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        func append(_ samples: [Float]) throws {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count))!
            buffer.frameLength = AVAudioFrameCount(samples.count)
            for (index, sample) in samples.enumerated() { buffer.floatChannelData![0][index] = sample }
            try recorder.append(buffer)
        }
        var liveCalls = 0
        try await live.startRecording(using: { _ in liveCalls += 1; return "Thank you. Thank you." }, feeding: format)
        try append(noise(16_000 * 5))
        await live.stopRecording()
        check(liveCalls == 0 && live.meetings[0].transcript.isEmpty, "live stationary noise reached decoder")
        check(FileManager.default.fileExists(atPath: live.audioURL(for: live.meetings[0]).path), "live audio was removed")

        try await live.startRecording(using: { _ in liveCalls += 1; return "Thank you. Thank you." }, feeding: format)
        try append([Float](repeating: 0.0002, count: 16_000) + speech(16_000 / 10))
        await live.stopRecording()
        check(liveCalls == 1 && live.meetings[1].transcript.contains("Thank you. Thank you."),
              "short final live tail lost or repeated phrase censored")
        check(live.notesFailureID == nil && live.notesError == nil,
              "filler-only live finalization was reported as a notes failure")
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-asr-contracts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await run(root)
        print("meeting ASR acoustic preflight and live/import persistence contracts passed")
    }
}
