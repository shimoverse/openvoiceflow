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

    @MainActor private static func run(in root: URL) async throws {
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
