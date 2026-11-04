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
    @Published private(set) var errorMessage: String?

    private let directory: URL
    private let recorder = MeetingRecorder()
    private var activeID: UUID?
    private var deadlineTask: Task<Void, Never>?
    private var loadFailure = false
    private var operationBusy = false
    private let files = FileManager.default

    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("OpenVoiceFlow/Meetings", isDirectory: true)) {
        self.directory = directory
        do {
            try files.createDirectory(at: directory, withIntermediateDirectories: true,
                                      attributes: [.posixPermissions: 0o700])
            try files.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            let index = directory.appendingPathComponent("meetings.json")
            if files.fileExists(atPath: index.path) {
                meetings = try JSONDecoder().decode([MeetingRecord].self, from: Data(contentsOf: index))
            }
            // An interrupted take may leave an unfinalized WAV header; retain the
            // audio and its index entry so the user can still recover either file.
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

    func startRecording() async {
        guard !isRecording, !operationBusy, !isTranscribing else {
            errorMessage = MeetingError.busy.localizedDescription; return
        }
        operationBusy = true
        defer { operationBusy = false }
        guard !loadFailure else { errorMessage = MeetingError.damagedLibrary.localizedDescription; return }
        guard await MeetingRecorder.requestPermission() else {
            errorMessage = MeetingRecorder.RecordingError.microphoneAccessDenied.localizedDescription
            return
        }
        let id = UUID()
        let entry = MeetingRecord(id: id, title: "Meeting \(Date().formatted(date: .abbreviated, time: .shortened))",
                                  createdAt: Date(), duration: 0, transcript: "", notes: "",
                                  audioFilename: "\(id.uuidString).wav")
        do {
            // The index precedes the take, so a crash does not orphan its audio.
            try save(meetings + [entry])
            try recorder.start(at: audioURL(for: entry))
            activeID = id
            isRecording = true
            errorMessage = nil
            deadlineTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2 * 60 * 60))
                guard !Task.isCancelled else { return }
                await self?.stopRecording()
            }
        } catch {
            // A start error never removes an existing audio file; keep the entry
            // if any file was created so the user can inspect/retry extraction.
            if !files.fileExists(atPath: audioURL(for: entry).path) {
                try? save(meetings.filter { $0.id != id })
            }
            errorMessage = error.localizedDescription
        }
    }

    func stopRecording() async {
        guard isRecording, let activeID else { return }
        deadlineTask?.cancel()
        deadlineTask = nil
        let duration = recorder.stop()
        isRecording = false
        self.activeID = nil
        guard let index = meetings.firstIndex(where: { $0.id == activeID }) else { return }
        var updated = meetings
        updated[index].duration = duration
        do {
            try save(updated)
            errorMessage = nil
        } catch {
            // The pre-take index and audio survive a failed duration update.
            errorMessage = error.localizedDescription
        }
    }

    /// Copies source bytes into the private library; never consumes or deletes the original.
    @discardableResult func importAudio(_ url: URL) async throws -> MeetingRecord {
        guard !loadFailure else { throw MeetingError.damagedLibrary }
        guard !operationBusy, !isRecording, !isTranscribing else { throw MeetingError.busy }
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
        guard !operationBusy, !isRecording, !isTranscribing else { throw MeetingError.busy }
        guard meetings.contains(where: { $0.id == meeting.id }) else { throw MeetingError.missing }
        let previousTranscript = meetings.first(where: { $0.id == meeting.id })?.transcript ?? ""
        isTranscribing = true
        defer { isTranscribing = false }
        do {
            let reader = try MeetingAudioChunks(url: audioURL(for: meeting))
            var first = true
            while let samples = try reader.next() {
                try Task.checkCancellation()
                let start = reader.elapsed - Double(samples.count) / 16_000
                let text = try await using(samples).trimmingCharacters(in: .whitespacesAndNewlines)
                try Task.checkCancellation()
                guard let index = meetings.firstIndex(where: { $0.id == meeting.id }) else { throw MeetingError.missing }
                var updated = meetings
                if first { updated[index].transcript = ""; first = false }
                if !text.isEmpty {
                    let seconds = Int(start)
                    let stamp = String(format: "[%02d:%02d:%02d]", seconds / 3_600, (seconds / 60) % 60, seconds % 60)
                    updated[index].transcript += (updated[index].transcript.isEmpty ? "" : "\n") + "\(stamp) \(text)"
                }
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
    }

    func update(_ record: MeetingRecord) throws {
        guard !loadFailure else { throw MeetingError.damagedLibrary }
        guard let index = meetings.firstIndex(where: { $0.id == record.id }),
              meetings[index].audioFilename == record.audioFilename,
              meetings[index].createdAt == record.createdAt,
              !isRecording || record.id != activeID else { throw MeetingError.invalidRecord }
        var updated = meetings
        updated[index] = record
        try save(updated)
    }

    func delete(_ record: MeetingRecord) throws {
        guard !loadFailure else { throw MeetingError.damagedLibrary }
        guard meetings.contains(where: { $0.id == record.id }), !isRecording || record.id != activeID,
              !isTranscribing else { throw MeetingError.busy }
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
