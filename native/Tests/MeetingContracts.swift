import Foundation
import AVFoundation

@main enum MeetingContracts {
    private enum FixtureError: Error { case transcriptionFailed }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    /// A real 16 kHz mono PCM WAV, long enough to require more than one transcription chunk.
    private static func wav(seconds: Int, sampleRate: Int = 16_000, channels: Int = 1) -> Data {
        let bytes = seconds * sampleRate * channels * 2
        var data = Data()
        func word(_ value: UInt16) { data.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init)) }
        func dword(_ value: UInt32) { data.append(contentsOf: withUnsafeBytes(of: value.littleEndian, Array.init)) }
        data.append(contentsOf: "RIFF".utf8)
        dword(UInt32(bytes + 36))
        data.append(contentsOf: "WAVEfmt ".utf8)
        dword(16)
        word(1) // PCM
        word(UInt16(channels))
        dword(UInt32(sampleRate))
        dword(UInt32(sampleRate * channels * 2))
        word(UInt16(channels * 2))
        word(16)
        data.append(contentsOf: "data".utf8)
        dword(UInt32(bytes))
        data.append(Data(repeating: 0, count: bytes))
        return data
    }

    private static func liveRecorderVisibility(in root: URL) throws {
        let url = root.appendingPathComponent("live.caf")
        let recorder = MeetingRecorder()
        let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false)!
        try recorder.start(at: url, feeding: source)
        let samples = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 48_000)!
        samples.frameLength = 48_000
        samples.floatChannelData![0][0] = 0.5
        samples.floatChannelData![1][0] = 0.5
        try recorder.append(samples)
        let available = try recorder.readAvailable(maxFrames: 16_000)
        check(available.count > 14_000 && available.count <= 16_000, "captured CAF was not readable while writer was open")
        check(available[0] > 0.1, "capture conversion did not preserve input sample")
        check(recorder.readFramePosition > 0, "live reader did not advance")
        _ = recorder.stop()
        let finalized = try AVAudioFile(forReading: url)
        check(finalized.length >= 15_900 && finalized.length <= 16_100,
              "capture dropped converter tail at stop")
    }

    @MainActor private static func liveStore(in root: URL) async throws {
        let recorder = MeetingRecorder()
        let store = MeetingStore(directory: root.appendingPathComponent("live-library"), recorder: recorder)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        var calls = 0
        var totalFrames = 0
        var outstanding = 0
        try await store.startRecording(using: { samples in
            calls += 1
            totalFrames += samples.count
            outstanding += 1
            check(outstanding == 1, "live model calls overlapped")
            check(samples.count > 0 && samples.count <= 5 * 16_000, "live chunk exceeded five seconds")
            try await Task.sleep(for: .milliseconds(20))
            outstanding -= 1
            return "segment \(calls)"
        }, feeding: format)
        check(store.isRecording && store.activeMeetingID != nil, "live recording did not start")
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        for i in 0..<16_000 { buffer.floatChannelData![0][i] = 0.1 }
        for _ in 0..<6 { try recorder.append(buffer) }
        for _ in 0..<30 where store.meetings[0].transcript.isEmpty {
            try await Task.sleep(for: .milliseconds(100))
        }
        check(store.isRecording && !store.meetings[0].transcript.isEmpty, "partial transcript did not persist while recording")
        var stale = store.meetings[0]
        stale.transcript = "stale editor snapshot"
        stale.title = "Renamed live meeting"
        stale.notes = "Edited while recording"
        try store.update(stale)
        check(store.meetings[0].transcript.contains("segment") && store.meetings[0].notes == stale.notes,
              "editing metadata replaced live transcript")
        let beforeStop = calls
        try recorder.append(buffer)
        await store.stopRecording()
        check(calls > beforeStop, "stop did not drain the final audio tail")
        let recorded = try AVAudioFile(forReading: store.audioURL(for: store.meetings[0]))
        check(recorded.processingFormat.sampleRate == 16_000 && recorded.processingFormat.channelCount == 1 &&
              recorded.processingFormat.commonFormat == .pcmFormatFloat32, "captured file is not decodable 16 kHz mono float")
        check(totalFrames == recorded.length, "live reader duplicated or missed frames during stop")
        check(store.activeMeetingID == nil && !store.isTranscribing, "live finalization did not finish")
        check(MeetingStore(directory: root.appendingPathComponent("live-library")).meetings[0].transcript == store.meetings[0].transcript,
              "live transcript did not persist")
    }

    @MainActor private static func silentCapture(in root: URL) async throws {
        let recorder = MeetingRecorder()
        let store = MeetingStore(directory: root.appendingPathComponent("silence-library"), recorder: recorder)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        var calls = 0
        try await store.startRecording(using: { _ in calls += 1; return "hallucination" }, feeding: format)
        let silent = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        silent.frameLength = 16_000
        for i in 0..<16_000 { silent.floatChannelData![0][i] = 0.0001 }
        for _ in 0..<6 { try recorder.append(silent) }
        await store.stopRecording()
        check(calls == 0 && store.meetings[0].transcript.isEmpty, "near-silent microphone audio reached speech model")
        check(FileManager.default.fileExists(atPath: store.audioURL(for: store.meetings[0]).path), "silent take lost audio")
    }

    @MainActor private static func failureAndRestart(in root: URL) async throws {
        let recorder = MeetingRecorder()
        let store = MeetingStore(directory: root.appendingPathComponent("failure-library"), recorder: recorder)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)!
        buffer.frameLength = 16_000
        for i in 0..<16_000 { buffer.floatChannelData![0][i] = 0.1 }
        try await store.startRecording(using: { _ in throw FixtureError.transcriptionFailed }, feeding: format)
        for _ in 0..<5 { try recorder.append(buffer) }
        for _ in 0..<30 where store.isTranscribing { try await Task.sleep(for: .milliseconds(100)) }
        check(store.isRecording && store.transcriptionStatus?.contains("failed") == true,
              "model failure did not leave capture active with visible failure")
        let failed = store.meetings[0]
        try recorder.append(buffer)
        await store.stopRecording()
        check(store.transcriptionStatus?.contains("failed") == true, "stop erased model failure")
        check(FileManager.default.fileExists(atPath: store.audioURL(for: failed).path), "failure deleted audio")
        try await store.transcribe(failed, using: { _ in "retry" })
        check(store.meetings[0].transcript.contains("retry"), "post-stop retry failed")
        // A slow in-flight model call cannot be duplicated or write into the next take.
        try await store.startRecording(using: { _ in
            try await Task.sleep(for: .milliseconds(200))
            return "slow"
        }, feeding: format)
        let second = store.activeMeetingID!
        for _ in 0..<6 { try recorder.append(buffer) }
        let stopping = Task { await store.stopRecording() }
        await Task.yield()
        check(store.activeMeetingID == second, "session identity cleared before catch-up")
        do {
            try await store.startRecording(using: { _ in "too soon" }, feeding: format)
            fatalError("new take started before prior live task drained")
        } catch { }
        check(store.meetings.count == 2, "busy start created a spurious meeting")
        await stopping.value
        check(store.meetings.first(where: { $0.id == second })?.transcript.contains("slow") == true,
              "slow decode was lost at stop")
        check(store.meetings.first(where: { $0.id == failed.id })?.transcript.contains("slow") == false,
              "later session wrote to failed take")
    }

    @MainActor private static func minimumLiveWindow(in root: URL) async throws {
        let recorder = MeetingRecorder()
        let store = MeetingStore(directory: root.appendingPathComponent("paced-library"), recorder: recorder)
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
        var liveCalls = 0
        var tailFrames = 0
        try await store.startRecording(using: { samples in
            if store.isRecording {
                check(samples.count >= 4 * 16_000, "live inference received less than four seconds of context")
                liveCalls += 1
            } else { tailFrames += samples.count }
            return "paced speech"
        }, feeding: format)
        let small = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1_600)!
        small.frameLength = 1_600
        for i in 0..<1_600 { small.floatChannelData![0][i] = 0.1 }
        for _ in 0..<10 {
            try recorder.append(small)
            try await Task.sleep(for: .milliseconds(100))
        }
        check(liveCalls == 0 && store.meetings[0].transcript.isEmpty, "tiny microphone buffers triggered live inference")
        for _ in 0..<40 { try recorder.append(small) }
        for _ in 0..<30 where liveCalls == 0 { try await Task.sleep(for: .milliseconds(100)) }
        check(liveCalls > 0 && store.isRecording, "sufficient live context was not decoded before Stop")
        try recorder.append(small)
        await store.stopRecording()
        check(tailFrames > 0 && tailFrames < 4 * 16_000, "short final tail did not drain exactly after Stop")
    }

    private static func shortCAFReads(in root: URL) throws {
        let url = root.appendingPathComponent("packetized.caf")
        let recorder = MeetingRecorder()
        let source = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 22_050, channels: 1, interleaved: false)!
        try recorder.start(at: url, feeding: source)
        let buffer = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 11_025)!
        buffer.frameLength = 11_025
        for i in 0..<11_025 { buffer.floatChannelData![0][i] = 0.1 }
        var consumed = 0
        for _ in 0..<20 {
            try recorder.append(buffer)
            let before = recorder.readFramePosition
            let samples = try recorder.readAvailable(maxFrames: 80_000, minFrames: 64_000)
            check(samples.isEmpty || samples.count >= 64_000, "CAF short read bypassed minimum context")
            check(!samples.isEmpty || recorder.readFramePosition == before, "rejected CAF read consumed audio")
            consumed += samples.count
        }
        _ = recorder.stop()
        while true {
            let tail = try recorder.readAvailable(maxFrames: 80_000)
            if tail.isEmpty { break }
            consumed += tail.count
        }
        let saved = try AVAudioFile(forReading: url)
        check(consumed == saved.length, "CAF minimum read lost or duplicated frames")
    }

    @MainActor private static func run(in root: URL) async throws {
        try shortCAFReads(in: root)
        try await minimumLiveWindow(in: root)
        try await failureAndRestart(in: root)
        try await silentCapture(in: root)
        try await liveStore(in: root)
        try liveRecorderVisibility(in: root)
        let source = root.appendingPathComponent("source.wav")
        let bytes = wav(seconds: 65)
        try bytes.write(to: source)
        let library = root.appendingPathComponent("library")
        let store = MeetingStore(directory: library)
        let imported = try await store.importAudio(source)
        let id: UUID = imported.id
        let title: String = imported.title
        let createdAt: Date = imported.createdAt
        let duration: Double = imported.duration
        let transcript: String = imported.transcript
        let notes: String = imported.notes
        let filename: String = imported.audioFilename
        check(!title.isEmpty && !filename.isEmpty && duration >= 0, "imported record fields missing")
        check(transcript.isEmpty && notes.isEmpty, "new meeting should have empty editable text")
        check(createdAt <= Date(), "meeting timestamp is in the future")
        check(store.meetings.count == 1 && store.meetings[0].id == id, "import did not register meeting")
        let savedAudio = store.audioURL(for: imported)
        check(savedAudio != source && FileManager.default.fileExists(atPath: savedAudio.path), "audio was not copied into library")
        let copiedBytes = try Data(contentsOf: savedAudio)
        check(copiedBytes == bytes, "import did not preserve audio bytes")

        var edited = imported
        edited.title = "Edited meeting"
        edited.notes = "Keep these notes"
        try store.update(edited)
        let reopened = MeetingStore(directory: library)
        check(reopened.meetings.count == 1, "meeting metadata did not survive store reinitialization")
        check(reopened.meetings[0].id == id && reopened.meetings[0].title == edited.title && reopened.meetings[0].notes == edited.notes,
              "edited meeting metadata did not round-trip on disk")
        check(FileManager.default.fileExists(atPath: reopened.audioURL(for: reopened.meetings[0]).path), "audio did not survive store reinitialization")

        // Inject transcription instead of using a model/network; the store must read the WAV in bounded chunks.
        var chunkSizes: [Int] = []
        try await reopened.transcribe(reopened.meetings[0], using: { samples in
            chunkSizes.append(samples.count)
            return "recognized"
        })
        check(chunkSizes.count > 1, "long recording was not split into chunks")
        check(chunkSizes.allSatisfy { $0 > 0 && $0 <= 30 * 16_000 }, "transcription read an oversized chunk")
        check(reopened.meetings[0].transcript.contains("recognized"), "transcription result was not persisted")
        let afterTranscription = MeetingStore(directory: library)
        check(afterTranscription.meetings[0].transcript.contains("recognized"), "transcript did not round-trip on disk")

        let originalTranscript = reopened.meetings[0].transcript
        var retryChunk = 0
        do {
            try await reopened.transcribe(reopened.meetings[0]) { _ in
                retryChunk += 1
                if retryChunk > 1 { throw FixtureError.transcriptionFailed }
                return "replacement fragment"
            }
            fatalError("late failure unexpectedly succeeded")
        } catch FixtureError.transcriptionFailed { }
        check(reopened.meetings[0].transcript == originalTranscript, "retry failure lost existing transcript")
        check(MeetingStore(directory: library).meetings[0].transcript == originalTranscript, "retry rollback not persisted")

        // Failure must not orphan or delete imported audio, and a later retry must work.
        let retrySource = root.appendingPathComponent("retry.wav")
        try wav(seconds: 1).write(to: retrySource)
        let retry = try await reopened.importAudio(retrySource)
        let retryAudio = reopened.audioURL(for: retry)
        do {
            try await reopened.transcribe(retry, using: { _ in throw FixtureError.transcriptionFailed })
            fatalError("failed transcription unexpectedly succeeded")
        } catch FixtureError.transcriptionFailed { }
        check(FileManager.default.fileExists(atPath: retryAudio.path), "failed transcription deleted recording")
        check(reopened.meetings.first(where: { $0.id == retry.id }) != nil, "failed transcription deleted meeting")
        try await reopened.transcribe(retry, using: { _ in "second attempt" })
        check(reopened.meetings.first(where: { $0.id == retry.id })?.transcript.contains("second attempt") == true,
              "retry did not save transcript")
        check(FileManager.default.fileExists(atPath: retryAudio.path), "retry deleted recording")

        try reopened.delete(retry)
        check(reopened.meetings.count == 1 && !FileManager.default.fileExists(atPath: retryAudio.path),
              "delete did not remove meeting and its audio")
        check(MeetingStore(directory: library).meetings.count == 1, "delete did not persist")

        // Conversion path: stereo 48 kHz CAF must become mono 16 kHz floats
        // before entering the model closure, not a mislabeled 48 kHz buffer.
        let stereoSource = root.appendingPathComponent("stereo.wav")
        try wav(seconds: 2, sampleRate: 48_000, channels: 2).write(to: stereoSource)
        let stereo = try await reopened.importAudio(stereoSource)
        var convertedFrames = 0
        try await reopened.transcribe(stereo, using: { samples in
            convertedFrames += samples.count
            return "stereo converted"
        })
        check(convertedFrames >= 31_000 && convertedFrames <= 33_000,
              "48 kHz stereo import must yield about 32,000 mono 16 kHz samples")
    }

    static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("meeting-contracts-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try await run(in: root)
        print("meeting disk, chunk, failure/retry and deletion contracts passed")
    }
}
