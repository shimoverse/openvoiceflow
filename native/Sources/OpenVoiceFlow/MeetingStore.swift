import AVFoundation
import Combine
import Darwin
import Foundation

struct MeetingRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var createdAt: Date
    var duration: Double
    var transcript: String
    var notes: String
    var audioFilename: String
    var generatedNotes: String = ""
    var titleWasEdited: Bool = false

    enum CodingKeys: String, CodingKey { case id, title, createdAt, duration, transcript, notes, audioFilename, generatedNotes, titleWasEdited }
    init(id: UUID, title: String, createdAt: Date, duration: Double, transcript: String, notes: String, audioFilename: String) {
        self.id = id; self.title = title; self.createdAt = createdAt; self.duration = duration
        self.transcript = transcript; self.notes = notes; self.audioFilename = audioFilename
    }
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        id = try box.decode(UUID.self, forKey: .id)
        title = try box.decode(String.self, forKey: .title)
        createdAt = try box.decode(Date.self, forKey: .createdAt)
        duration = try box.decode(Double.self, forKey: .duration)
        transcript = try box.decode(String.self, forKey: .transcript)
        notes = try box.decode(String.self, forKey: .notes)
        audioFilename = try box.decode(String.self, forKey: .audioFilename)
        generatedNotes = try box.decodeIfPresent(String.self, forKey: .generatedNotes) ?? ""
        // Legacy records may already carry a user title; treat them as owned.
        titleWasEdited = try box.decodeIfPresent(Bool.self, forKey: .titleWasEdited) ?? true
    }
}

private enum MeetingError: LocalizedError {
    case busy, missing, invalidAudio, invalidRecord, damagedLibrary
    var errorDescription: String? {
        switch self {
        case .busy: return "Finish the current meeting operation first."
        case .missing: return "This meeting or its audio file is missing."
        case .invalidAudio: return "This audio file could not be opened."
        case .invalidRecord: return "This meeting cannot be changed."
        case .damagedLibrary: return "Meeting library could not be loaded. No changes were made."
        }
    }
}

/// Reads at most 30 seconds of 16 kHz float samples per invocation. AVAudioConverter
/// downsamples and mixes imported audio on demand, without loading the whole file.
private final class MeetingAudioChunks: @unchecked Sendable {
    // Converter invokes its callback synchronously; this box transfers the
    // callback's read failure back to the caller without a captured mutable var.
    private final class ReadFailure: @unchecked Sendable { var error: Error? }
    private let file: AVAudioFile
    private let converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000, channels: 1, interleaved: false)!
    private var exhausted = false
    private var deliveredFrames = 0

    init(url: URL) throws {
        file = try AVAudioFile(forReading: url)
        guard file.length > 0, file.processingFormat.channelCount > 0 else { throw MeetingError.invalidAudio }
        if file.processingFormat.sampleRate == 16_000 && file.processingFormat.channelCount == 1 {
            converter = nil
        } else {
            guard let conversion = AVAudioConverter(from: file.processingFormat, to: outputFormat) else {
                throw MeetingError.invalidAudio
            }
            converter = conversion
        }
    }

    func next() throws -> [Float]? {
        guard !exhausted else { return nil }
        let limit = AVAudioFrameCount(30 * 16_000)
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: limit) else {
            throw MeetingError.invalidAudio
        }
        if let converter {
            var conversionError: NSError?
            let readFailure = ReadFailure()
            let status = converter.convert(to: output, error: &conversionError) { [self] _, inputStatus in
                guard let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 8_192) else {
                    inputStatus.pointee = .noDataNow
                    return nil
                }
                guard file.framePosition < file.length else {
                    inputStatus.pointee = .endOfStream
                    return nil
                }
                do {
                    try file.read(into: input)
                    if input.frameLength == 0 {
                        inputStatus.pointee = .endOfStream
                        return nil
                    }
                    inputStatus.pointee = .haveData
                    return input
                } catch {
                    readFailure.error = error
                    inputStatus.pointee = .endOfStream
                    return nil
                }
            }
            if let readError = readFailure.error { throw readError }
            if let conversionError { throw conversionError }
            if status == .error { throw MeetingError.invalidAudio }
            if status == .endOfStream || output.frameLength == 0 { exhausted = true }
        } else {
            // AVAudioFile can throw at an exact chunk-aligned EOF instead of
            // returning an empty buffer. Check the cursor before asking to read.
            guard file.framePosition < file.length else {
                exhausted = true
                return nil
            }
            try file.read(into: output, frameCount: limit)
            if output.frameLength < limit { exhausted = true }
        }
        guard let channel = output.floatChannelData?[0], output.frameLength > 0 else { return nil }
        deliveredFrames += Int(output.frameLength)
        return Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
    }

    var elapsed: Double { Double(deliveredFrames) / 16_000 }
}

@MainActor final class MeetingStore: ObservableObject {
    @Published private(set) var meetings: [MeetingRecord] = []
    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var isPaused = false
    @Published private(set) var isFinalizing = false
    @Published private(set) var notesError: String?
    @Published private(set) var notesFailureID: UUID?
    @Published private(set) var activeMeetingID: UUID?
    @Published private(set) var transcriptionStatus: String?
    @Published private(set) var errorMessage: String?

    private let directory: URL
    private let recorder: MeetingRecorder
    private let recordingLimit: Duration
    private var liveTask: Task<Void, Never>?
    private var liveGeneration: UUID?
    private var liveTranscriptionFailed = false
    private var deadlineTask: Task<Void, Never>?
    private var loadFailure = false
    private var operationBusy = false
    private let files = FileManager.default

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("OpenVoiceFlow/Meetings", isDirectory: true), recorder: MeetingRecorder = MeetingRecorder(),
         recordingLimit: Duration = .seconds(2 * 60 * 60)) {
        self.directory = directory
        self.recorder = recorder
        self.recordingLimit = recordingLimit
        do {
            try files.createDirectory(at: directory, withIntermediateDirectories: true,
                                      attributes: [.posixPermissions: 0o700])
            try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let index = directory.appendingPathComponent("meetings.json")
            if files.fileExists(atPath: index.path) {
                meetings = try JSONDecoder().decode([MeetingRecord].self, from: Data(contentsOf: index))
            }
            // An interrupted CAF take may retain a partially written tail;
            // keep its audio and index entry for recovery or later retry.
        } catch {
            loadFailure = true
            errorMessage = "Meeting library could not be loaded: \(error.localizedDescription)"
        }
    }

    func audioURL(for record: MeetingRecord) -> URL {
        // Filenames in legacy/corrupt metadata must never escape our library.
        let safe = URL(fileURLWithPath: record.audioFilename).lastPathComponent
        return directory.appendingPathComponent(safe)
    }

    /// Existing callers can start an audio-only take and transcribe later.
    func startRecording() async { await beginRecording(using: nil, feeding: nil) }

    /// A single serial task decodes bounded five-second windows as the disk file grows.
    func startRecording(using model: @escaping ([Float]) async throws -> String) async {
        await beginRecording(using: model, feeding: nil)
    }

    /// The explicit PCM source uses the identical capture path as the microphone tap.
    func startRecording(using model: @escaping ([Float]) async throws -> String,
                        feeding inputFormat: AVAudioFormat) async throws {
        await beginRecording(using: model, feeding: inputFormat)
        if !isRecording { throw MeetingError.invalidAudio }
    }

    private func beginRecording(using model: (([Float]) async throws -> String)?,
                                feeding inputFormat: AVAudioFormat?) async {
        guard !isRecording, !operationBusy, !isTranscribing, !isFinalizing, activeMeetingID == nil else {
            errorMessage = MeetingError.busy.localizedDescription; return
        }
        operationBusy = true
        defer { operationBusy = false }
        guard !loadFailure else { errorMessage = MeetingError.damagedLibrary.localizedDescription; return }
        if inputFormat == nil {
            guard await MeetingRecorder.requestPermission() else {
                errorMessage = MeetingRecorder.RecordingError.microphoneAccessDenied.localizedDescription
                return
            }
        }
        let id = UUID()
        let entry = MeetingRecord(id: id, title: "Meeting \(Date().formatted(date: .abbreviated, time: .shortened))",
                                  createdAt: Date(), duration: 0, transcript: "", notes: "",
                                  audioFilename: "\(id.uuidString).caf")
        do {
            try save(meetings + [entry])
            if let inputFormat { try recorder.start(at: audioURL(for: entry), feeding: inputFormat) }
            else { try recorder.start(at: audioURL(for: entry)) }
            activeMeetingID = id
            isRecording = true
            isPaused = false
            liveTranscriptionFailed = false
            errorMessage = nil
            transcriptionStatus = model == nil ? nil : "Listening — transcript updates every few seconds"
            if let model {
                let generation = UUID()
                liveGeneration = generation
                isTranscribing = true
                liveTask = Task { [weak self] in
                    await self?.runLive(id: id, generation: generation, using: model)
                }
            }
            deadlineTask = Task { [weak self] in
                guard let limit = self?.recordingLimit else { return }
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled else { return }
                // Automatic Stop must not cancel its own finalization task.
                self?.deadlineTask = nil
                await self?.stopRecording()
            }
        } catch {
            if !files.fileExists(atPath: audioURL(for: entry).path) {
                try? save(meetings.filter { $0.id != id })
            }
            errorMessage = error.localizedDescription
            transcriptionStatus = "Recording failed: \(error.localizedDescription)"
        }
    }

    private func runLive(id: UUID, generation: UUID,
                         using model: @escaping ([Float]) async throws -> String) async {
        do {
            while liveGeneration == generation {
                // CAF readers snapshot file length, so each read opens anew.
                // A slow model call simply causes subsequent reads to catch up;
                // neither queued tasks nor in-memory sample history accumulates.
                let start = recorder.readFramePosition
                // Keep context on disk until four seconds are available. Only Stop
                // may drain a shorter tail; mic callbacks must not cause tiny decodes.
                let samples = try recorder.readAvailable(maxFrames: 5 * 16_000,
                                                        minFrames: isRecording ? 4 * 16_000 : 1)
                if !samples.isEmpty {
                    // Keep the original audio, but do not decode acoustic
                    // silence or stationary low-level noise into invented text.
                    if !MeetingSpeechGate.shouldDecode(samples) {
                        transcriptionStatus = isRecording ? "Listening — microphone audio is quiet" : "Catching up on saved audio"
                        continue
                    }
                    transcriptionStatus = isRecording ? "Transcribing live audio" : "Catching up on saved audio"
                    let text = try await model(samples).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard liveGeneration == generation else { return }
                    if !text.isEmpty {
                        guard let index = meetings.firstIndex(where: { $0.id == id }) else { throw MeetingError.missing }
                        let seconds = Int(start / 16_000)
                        let stamp = String(format: "[%02d:%02d:%02d]", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
                        var updated = meetings
                        updated[index].transcript += (updated[index].transcript.isEmpty ? "" : "\n") + "\(stamp) \(text)"
                        try save(updated)
                    }
                } else if !isRecording {
                    break
                } else {
                    transcriptionStatus = "Listening — transcript updates every few seconds"
                    try await Task.sleep(for: .milliseconds(500))
                }
            }
            if liveGeneration == generation { transcriptionStatus = nil }
        } catch {
            if liveGeneration == generation {
                liveTranscriptionFailed = true
                transcriptionStatus = "Live transcription failed: \(error.localizedDescription). Audio is saved; retry after stopping."
                errorMessage = error.localizedDescription
            }
        }
        if liveGeneration == generation { isTranscribing = false }
    }

    func stopRecording() async {
        guard isRecording, !isFinalizing, let id = activeMeetingID else { return }
        // Stop capture immediately, even if inference is still in flight.
        isFinalizing = true
        isRecording = false
        isPaused = false
        deadlineTask?.cancel()
        deadlineTask = nil
        let duration = recorder.stop()
        if let index = meetings.firstIndex(where: { $0.id == id }) {
            var updated = meetings
            updated[index].duration = duration
            do { try save(updated) }
            catch { errorMessage = error.localizedDescription }
        }
        if let liveTask {
            transcriptionStatus = isTranscribing ? "Catching up on saved audio" : transcriptionStatus
            await liveTask.value
        }
        liveTask = nil
        liveGeneration = nil
        if let meeting = meetings.first(where: { $0.id == id }), !meeting.transcript.isEmpty,
           !liveTranscriptionFailed {
            do { try await generateNotes(for: meeting, duringFinalization: true) }
            catch {
                notesFailureID = id
                notesError = "Notes failed: \(error.localizedDescription). Retry notes below."
            }
        }
        activeMeetingID = nil
        isTranscribing = false
        isFinalizing = false
    }

    func pauseRecording() {
        guard isRecording, !isPaused else { return }
        recorder.pause()
        isPaused = true
        if !liveTranscriptionFailed { transcriptionStatus = "Paused — microphone audio is not saved" }
    }

    func resumeRecording() throws {
        guard isRecording, isPaused else { return }
        do {
            try recorder.resume()
            isPaused = false
            if !liveTranscriptionFailed { transcriptionStatus = "Listening — transcript updates every few seconds" }
        } catch { errorMessage = error.localizedDescription; throw error }
    }

    var recordedDuration: Double { recorder.duration }

    func generateNotes(for meeting: MeetingRecord, condense: MeetingSummarizer.Condense? = nil,
                       duringFinalization: Bool = false) async throws {
        guard !loadFailure else { throw MeetingError.damagedLibrary }
        guard !isRecording, !operationBusy, !isTranscribing,
              (duringFinalization ? isFinalizing && (activeMeetingID == nil || meeting.id == activeMeetingID) : !isFinalizing) else { throw MeetingError.busy }
        guard let current = meetings.first(where: { $0.id == meeting.id }) else { throw MeetingError.missing }
        let transcript = current.transcript
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if !duringFinalization { isFinalizing = true }
        defer { if !duringFinalization { isFinalizing = false } }
        do {
            let generated = try await MeetingSummarizer.generate(transcript, condense: condense)
            try Task.checkCancellation()
            guard let index = meetings.firstIndex(where: { $0.id == meeting.id }),
                  meetings[index].transcript == transcript else { throw MeetingError.busy }
            var updated = meetings
            updated[index].generatedNotes = generated.notes
            if !updated[index].titleWasEdited, let title = generated.title { updated[index].title = title }
            try save(updated)
            notesError = nil
            notesFailureID = nil
        } catch {
            notesFailureID = meeting.id
            notesError = "Notes failed: \(error.localizedDescription). Retry notes below."
            throw error
        }
    }

    /// Copies source bytes into the private library; never consumes or deletes the original.
    @discardableResult func importAudio(_ url: URL) async throws -> MeetingRecord {
        guard !loadFailure else { throw MeetingError.damagedLibrary }
        guard !operationBusy, !isRecording, !isTranscribing, !isFinalizing else { throw MeetingError.busy }
        operationBusy = true
        defer { operationBusy = false }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let source = try AVAudioFile(forReading: url)
            guard source.length > 0, source.fileFormat.sampleRate > 0 else { throw MeetingError.invalidAudio }
            let id = UUID()
            let ext = url.pathExtension.lowercased()
            let entry = MeetingRecord(id: id, title: url.deletingPathExtension().lastPathComponent,
                                      createdAt: Date(), duration: Double(source.length) / source.fileFormat.sampleRate,
                                      transcript: "", notes: "", audioFilename: "\(id.uuidString).\(ext.isEmpty ? "audio" : ext)")
            let destination = audioURL(for: entry)
            // FileManager.copyItem briefly inherits source permissions. Create
            // private 0600 output first, and stream rather than buffering imports.
            let input = try FileHandle(forReadingFrom: url)
            defer { try? input.close() }
            let fd = Darwin.open(destination.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
            guard fd >= 0 else { throw POSIXError(.EIO) }
            let output = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            do {
                while let block = try input.read(upToCount: 1_048_576), !block.isEmpty {
                    try output.write(contentsOf: block)
                }
                try output.synchronize()
                try output.close()
                try save(meetings + [entry])
            } catch {
                try? output.close()
                try? files.removeItem(at: destination)
                throw error
            }
            errorMessage = nil
            return entry
        } catch {
            errorMessage = error.localizedDescription
            throw error
        }
    }

    /// Each completed 30-second segment is committed atomically. A failed model
    /// call leaves audio and the last committed text available for retry.
    func transcribe(_ meeting: MeetingRecord, using: @escaping ([Float]) async throws -> String) async throws {
        guard !loadFailure else { throw MeetingError.damagedLibrary }
        guard !operationBusy, !isRecording, !isTranscribing, !isFinalizing else { throw MeetingError.busy }
        guard meetings.contains(where: { $0.id == meeting.id }) else { throw MeetingError.missing }
        let previousTranscript = meetings.first(where: { $0.id == meeting.id })?.transcript ?? ""
        isTranscribing = true
        defer { isTranscribing = false; isFinalizing = false }
        do {
            let reader = try MeetingAudioChunks(url: audioURL(for: meeting))
            var attempt = ""
            while let samples = try reader.next() {
                try Task.checkCancellation()
                let start = reader.elapsed - Double(samples.count) / 16_000
                // Import/retry must use exactly the same speech preflight as
                // live capture; the saved source remains unchanged.
                let text = MeetingSpeechGate.shouldDecode(samples)
                    ? try await using(samples).trimmingCharacters(in: .whitespacesAndNewlines) : ""
                try Task.checkCancellation()
                guard let index = meetings.firstIndex(where: { $0.id == meeting.id }) else { throw MeetingError.missing }
                if !text.isEmpty {
                    let seconds = Int(start)
                    let stamp = String(format: "[%02d:%02d:%02d]", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
                    attempt += (attempt.isEmpty ? "" : "\n") + "\(stamp) \(text)"
                }
                // A previous complete transcript survives both failures and
                // process termination; only an empty row gets partial progress.
                if previousTranscript.isEmpty {
                    var updated = meetings
                    updated[index].transcript = attempt
                    try save(updated)
                }
            }
            if !previousTranscript.isEmpty {
                guard let index = meetings.firstIndex(where: { $0.id == meeting.id }) else { throw MeetingError.missing }
                var updated = meetings
                updated[index].transcript = attempt
                if attempt != previousTranscript { updated[index].generatedNotes = "" }
                try save(updated)
            }
            errorMessage = nil
        } catch {
            if !previousTranscript.isEmpty, let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
                var restored = meetings
                restored[index].transcript = previousTranscript
                try save(restored)
            }
            errorMessage = error.localizedDescription
            throw error
        }
        isFinalizing = true
        isTranscribing = false
        try await generateNotes(for: meeting, duringFinalization: true)
    }

    func update(_ record: MeetingRecord) throws {
        guard !loadFailure else { throw MeetingError.damagedLibrary }
        guard let index = meetings.firstIndex(where: { $0.id == record.id }),
              meetings[index].audioFilename == record.audioFilename,
              meetings[index].createdAt == record.createdAt else { throw MeetingError.invalidRecord }
        var updated = meetings
        updated[index].title = record.title
        updated[index].notes = record.notes
        if record.title != meetings[index].title { updated[index].titleWasEdited = true }
        try save(updated)
    }

    func delete(_ record: MeetingRecord) throws {
        guard !loadFailure else { throw MeetingError.damagedLibrary }
        guard meetings.contains(where: { $0.id == record.id }), !isRecording || record.id != activeMeetingID,
              !isTranscribing, !isFinalizing else { throw MeetingError.busy }
        // Commit removal first: if unlink fails, the recoverable audio is retained
        // on disk rather than pointing the library at a deleted recording.
        try save(meetings.filter { $0.id != record.id })
        try files.removeItem(at: audioURL(for: record))
    }

    private func save(_ updated: [MeetingRecord]) throws {
        let data = try JSONEncoder().encode(updated)
        let index = directory.appendingPathComponent("meetings.json")
        let temporary = directory.appendingPathComponent(".meetings-\(UUID().uuidString).tmp")
        let descriptor = Darwin.open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { try? files.removeItem(at: temporary) }
        do {
            try data.withUnsafeBytes { raw in
                var offset = 0
                while offset < raw.count {
                    let count = Darwin.write(descriptor, raw.baseAddress!.advanced(by: offset), raw.count - offset)
                    if count <= 0 { throw POSIXError(.EIO) }
                    offset += count
                }
            }
            guard fsync(descriptor) == 0 else { throw POSIXError(.EIO) }
            guard close(descriptor) == 0 else { throw POSIXError(.EIO) }
            guard rename(temporary.path, index.path) == 0 else { throw POSIXError(.EIO) }
            let dirFD = Darwin.open(directory.path, O_RDONLY)
            if dirFD >= 0 { _ = fsync(dirFD); _ = close(dirFD) }
            meetings = updated
        } catch {
            _ = close(descriptor)
            throw error
        }
    }
}
