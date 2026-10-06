import Foundation
import CryptoKit
import Darwin

/// Experimental, opt-in adapter for a separately downloaded vendor executable.
/// Neither the executable nor model weights are distributed with OpenVoiceFlow.
enum WhistleError: LocalizedError {
    case unsupportedLanguage, unsupportedArchitecture, notDownloaded, integrity, sandboxUnavailable, failed, timedOut, cancelled

    var errorDescription: String? {
        switch self {
        case .unsupportedLanguage: return "Whistle supports English, French, German, Spanish, Italian, Dutch, and Polish only. Select another language or use WhisperKit."
        case .unsupportedArchitecture: return "This experimental Whistle executable supports Apple Silicon Macs only. Use WhisperKit on this Mac."
        case .notDownloaded: return "Whistle is not downloaded. Select it and download it explicitly in Settings."
        case .integrity: return "Whistle download failed SHA-256 verification."
        case .sandboxUnavailable: return "Whistle needs macOS sandbox-exec; no unsandboxed fallback is allowed."
        case .failed: return "Whistle did not return a valid committed transcript."
        case .timedOut: return "Whistle timed out."
        case .cancelled: return "Whistle was cancelled."
        }
    }
}

private final class WhistleDownloadDelegate: NSObject, URLSessionDownloadDelegate, URLSessionTaskDelegate, @unchecked Sendable {
    let report: @Sendable (Int64, Int64) -> Void
    let maximum: Int64
    init(maximum: Int64, report: @escaping @Sendable (Int64, Int64) -> Void) {
        self.maximum = maximum; self.report = report
    }
    private static func allowed(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", url.user == nil, url.password == nil,
              let host = url.host?.lowercased(), url.port == nil else { return false }
        return ["huggingface.co", "cdn-lfs.huggingface.co", "cdn-lfs-us-1.hf.co",
                "cdn-lfs-eu-1.hf.co", "cas-bridge.xethub.hf.co",
                "us.aws.cdn.hf.co", "eu.aws.cdn.hf.co"].contains(host)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(Self.allowed(request.url) ? request : nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesWritten <= maximum,
              totalBytesExpectedToWrite <= maximum else { downloadTask.cancel(); return }
        report(totalBytesWritten, totalBytesExpectedToWrite)
    }
}

/// Process handle shared across the cancellation boundary; no audio is ever
/// written to a regular file. The sole filesystem audio path is a 0600 FIFO.
final class WhistleRun: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
    private var timedOut = false
    private var overflowed = false

    var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    var isTimedOut: Bool { lock.lock(); defer { lock.unlock() }; return timedOut }
    var isOverflowed: Bool { lock.lock(); defer { lock.unlock() }; return overflowed }
    func attach(_ process: Process) throws {
        lock.lock()
        self.process = process
        let cancelled = stopped
        lock.unlock()
        if cancelled { throw WhistleError.cancelled }
    }
    func cancel() {
        lock.lock()
        stopped = true
        let current = process
        lock.unlock()
        if let current {
            if current.isRunning { current.terminate() }
            // A faulty vendor process may ignore TERM. Never leave the FIFO
            // writer or the stdout reader waiting on it indefinitely.
            DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(1)) {
                if current.isRunning { kill(current.processIdentifier, SIGKILL) }
            }
        }
    }
    func timeout() {
        lock.lock()
        timedOut = true
        lock.unlock()
        cancel()
    }
    func overflow() {
        lock.lock(); overflowed = true; lock.unlock()
        cancel()
    }
}

actor WhistleEngine {
    static let modelID = "whistle"
    typealias Fetcher = @Sendable (URL, URL, String, Int, Int64,
                                  @escaping @Sendable (Int64, Int64) -> Void) async throws -> Void
    /// No implicit reads of user files, network, or writes. Only the verified
    /// binary/model, private FIFO and macOS runtime resources are readable.
    static func sandboxProfile(executable: String, model: String, fifo: String) -> String {
        func literal(_ path: String) -> String {
            "\"" + path.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return "(version 1)(deny default)" +
            "(allow process-exec)(deny process-fork)(allow sysctl-read)" +
            "(allow file-read* (literal \"/\") (subpath \"/System/Library\") (subpath \"/usr/lib\")" +
            " (subpath \"/private/var/db/dyld\") (literal \"/dev/urandom\")" +
            " (literal \(literal(executable))) (literal \(literal(model))) (literal \(literal(fifo))))"
    }
    static let executableSHA256 = "342fa2c6f140e702354a99c4201c9057535ec908eed35c7382e911a19d1d2724"
    static let weightsSHA256 = "b6e02f048568ac5d01a2042556c658061e699acbc0aa2a1439f52f3d461dffeb"
    private static let executableURL = URL(string: "https://huggingface.co/Cactus-Compute/needle3/resolve/2ae11323dc000f5e70c49f7403efa6af12ba9e67/macos-arm64/needle")!
    private static let weightsURL = URL(string: "https://huggingface.co/Cactus-Compute/whistle/resolve/b358ddadd89b7a713b5aa131f23032d3cca1b251/whistle.cact")!
    private let directory: URL
    private let fetcher: Fetcher
    private var downloadTask: Task<Void, Error>?
    private var cancelledDownload: Task<Void, Error>?
    private var downloadToken = UUID()
    private var activeRun: WhistleRun?

    init(directory: URL? = nil, fetcher: @escaping Fetcher = { url, destination, digest, permissions, maximum, progress in
        try await WhistleEngine.fetch(url, destination, digest, permissions, maximum, progress)
    }) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenVoiceFlow/Whistle", isDirectory: true)
        self.fetcher = fetcher
    }

    static func supports(language: String) -> Bool {
        ["en", "fr", "de", "es", "it", "pl", "nl"].contains(language)
    }

    /// The CLI only needs streaming once the 16 kHz recording exceeds 30s.
    static func usesStreaming(sampleCount: Int) -> Bool {
        sampleCount > 30 * 16_000
    }

    /// Keep the launched Process configuration in one place so descriptor and
    /// argument contracts can be exercised without downloading vendor assets.
    static func vendorProcess(executable: String, model: String, fifo: String,
                              language: String, streaming: Bool, home: String, output: Pipe) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        process.arguments = ["-p", sandboxProfile(executable: canonical(executable), model: canonical(model), fifo: fifo), canonical(executable), "--model", canonical(model),
                             "--audio", fifo, "--audio-language", language] + (streaming ? ["--audio-stream"] : [])
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": home, "TMPDIR": home,
                               "NEEDLE_TELEMETRY": "0", "DO_NOT_TRACK": "1"]
        // The sandbox cannot un-inherit a pre-opened fd 0 (e.g. a shell pipe
        // or terminal containing private data). Never pass it to the vendor.
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        return process
    }

    static func verify(_ data: Data, expected: String) -> Bool {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == expected
    }

    private var executable: URL { directory.appendingPathComponent("needle") }
    private var weights: URL { directory.appendingPathComponent("whistle.cact") }

    func isReady() -> Bool {
        #if !arch(arm64)
        return false
        #else
        return Self.secureDirectory(directory, permissions: 0o500)
            && Self.sandboxAvailable()
            && Self.verifiedFile(executable, digest: Self.executableSHA256, permissions: 0o500, maximum: 50_000_000)
            && Self.verifiedFile(weights, digest: Self.weightsSHA256, permissions: 0o400, maximum: 300_000_000)
        #endif
    }

    private static func sandboxAvailable() -> Bool {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/sandbox-exec") else { return false }
        let probe = Process()
        probe.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        probe.arguments = ["-p", sandboxProfile(executable: "/usr/bin/true", model: "/usr/bin/true", fifo: "/usr/bin/true"), "/usr/bin/true"]
        probe.standardOutput = FileHandle.nullDevice
        probe.standardError = FileHandle.nullDevice
        do { try probe.run(); probe.waitUntilExit(); return probe.terminationStatus == 0 }
        catch { return false }
    }

    private static func attributes(_ path: String) -> stat? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        return info
    }

    private static func secureDirectory(_ url: URL, permissions: mode_t) -> Bool {
        guard let info = attributes(url.path) else { return false }
        return (info.st_mode & S_IFMT) == S_IFDIR && info.st_uid == getuid()
            && (info.st_mode & 0o7777) == permissions && secureParents(url)
    }

    private static func secureParents(_ url: URL) -> Bool {
        var parent = url.deletingLastPathComponent()
        while parent.path != "/" {
            guard let info = attributes(parent.path) else {
                if errno == ENOENT { parent = parent.deletingLastPathComponent(); continue }
                return false
            }
            if (info.st_mode & S_IFMT) == S_IFLNK {
                // /var and /tmp are root-owned system aliases for /private paths.
                guard (parent.path == "/var" || parent.path == "/tmp"), info.st_uid == 0 else { return false }
            } else if (info.st_mode & S_IFMT) != S_IFDIR ||
                        (info.st_uid != 0 && info.st_uid != getuid()) ||
                        ((info.st_mode & 0o022) != 0 && (info.st_mode & S_ISVTX) == 0) {
                return false
            }
            parent = parent.deletingLastPathComponent()
        }
        return true
    }

    private static func canonical(_ path: String) -> String {
        // Foundation leaves macOS's /var alias intact, while the sandbox
        // resolves it to /private/var when matching literal file grants.
        path.hasPrefix("/var/") ? "/private" + path : path
    }

    private static func verifiedFile(_ url: URL, digest: String, permissions: mode_t, maximum: Int64) -> Bool {
        guard let before = attributes(url.path), (before.st_mode & S_IFMT) == S_IFREG,
              before.st_uid == getuid(), before.st_nlink == 1,
              (before.st_mode & 0o7777) == permissions,
              before.st_size > 0, before.st_size <= maximum else { return false }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var opened = stat()
        guard fstat(fd, &opened) == 0, opened.st_dev == before.st_dev,
              opened.st_ino == before.st_ino, opened.st_size == before.st_size else { return false }
        var hash = SHA256()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var readCount: Int64 = 0
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 { if errno == EINTR { continue }; return false }
            if count == 0 { break }
            readCount += Int64(count)
            if readCount > maximum { return false }
            hash.update(data: Data(buffer[..<count]))
        }
        guard readCount == before.st_size, fstat(fd, &opened) == 0,
              opened.st_size == before.st_size,
              opened.st_mtimespec.tv_sec == before.st_mtimespec.tv_sec,
              opened.st_mtimespec.tv_nsec == before.st_mtimespec.tv_nsec else { return false }
        return hash.finalize().map { String(format: "%02x", $0) }.joined() == digest
    }

    private static func verifiedTemporary(_ url: URL, digest: String, maximum: Int64) -> Bool {
        guard let info = attributes(url.path), (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size > 0, info.st_size <= maximum else { return false }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var opened = stat()
        guard fstat(fd, &opened) == 0, opened.st_dev == info.st_dev,
              opened.st_ino == info.st_ino, opened.st_size == info.st_size else { return false }
        var hash = SHA256()
        var buffer = [UInt8](repeating: 0, count: 65_536)
        var total: Int64 = 0
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 { if errno == EINTR { continue }; return false }
            if count == 0 { break }
            total += Int64(count)
            if total > maximum { return false }
            hash.update(data: Data(buffer[..<count]))
        }
        return total == info.st_size && hash.finalize().map { String(format: "%02x", $0) }.joined() == digest
    }

    /// Called only after an explicit model selection. Downloads are pinned by
    /// immutable repository revisions AND SHA-256; incomplete files are removed.
    func download(progress: @escaping @Sendable (Int64, Int64) -> Void = { _, _ in }) async throws {
        #if !arch(arm64)
        throw WhistleError.unsupportedArchitecture
        #endif
        if isReady() { progress(1, 1); return }
        // Cancellation is a one-way transition. A rapid A→B→A selection must
        // never join the cancelled transfer still unwinding from B.
        if let downloadTask, !downloadTask.isCancelled { return try await downloadTask.value }
        let previous = cancelledDownload
        let task = Task { [directory, fetcher] in
            // Wait for the cancelled transfer to finish its deferred directory
            // cleanup before a replacement touches that same private cache.
            if let previous { _ = try? await previous.value }
            try Task.checkCancellation()
            guard Self.secureParents(directory) else { throw WhistleError.integrity }
            if let existing = Self.attributes(directory.path),
               (existing.st_mode & S_IFMT) != S_IFDIR { throw WhistleError.integrity }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            guard Self.secureDirectory(directory, permissions: 0o700) ||
                  Self.secureDirectory(directory, permissions: 0o500) else { throw WhistleError.integrity }
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            defer { try? FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path) }
            let binary = directory.appendingPathComponent("needle")
            if try !Self.cacheIsVerifiedOrClear(binary, Self.executableSHA256, 0o500, 50_000_000) {
                try await fetcher(Self.executableURL, binary,
                                  Self.executableSHA256, 0o500, 50_000_000, { received, expected in
                                         if expected > 0 { progress(Int64(min(499, Double(received) / Double(expected) * 500)), 1000) }
                                     })
            }
            try Task.checkCancellation()
            progress(500, 1000)
            let model = directory.appendingPathComponent("whistle.cact")
            if try !Self.cacheIsVerifiedOrClear(model, Self.weightsSHA256, 0o400, 300_000_000) {
                try await fetcher(Self.weightsURL, model,
                                  Self.weightsSHA256, 0o400, 300_000_000, { received, expected in
                                         if expected > 0 { progress(Int64(min(999, 500 + Double(received) / Double(expected) * 500)), 1000) }
                                     })
            }
            progress(1000, 1000)
        }
        let token = UUID()
        downloadToken = token
        downloadTask = task
        defer { if downloadToken == token { downloadTask = nil } }
        try await task.value
    }

    /// Only an owned, single-linked regular file may be removed on Retry.
    /// Suspicious paths (symlinks, hard links, foreign ownership) fail closed.
    private static func cacheIsVerifiedOrClear(_ destination: URL, _ digest: String,
                                               _ permissions: Int, _ maximum: Int64) throws -> Bool {
        guard let cached = attributes(destination.path) else { return false }
        if verifiedFile(destination, digest: digest, permissions: mode_t(permissions), maximum: maximum) {
            return true
        }
        guard (cached.st_mode & S_IFMT) == S_IFREG,
              cached.st_uid == getuid(), cached.st_nlink == 1 else { throw WhistleError.integrity }
        try Task.checkCancellation()
        try FileManager.default.removeItem(at: destination)
        return false
    }

    private static func fetch(_ url: URL, _ destination: URL, _ digest: String, _ permissions: Int, _ maximum: Int64,
                              _ progress: @escaping @Sendable (Int64, Int64) -> Void) async throws {
        if try cacheIsVerifiedOrClear(destination, digest, permissions, maximum) { return }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.httpMaximumConnectionsPerHost = 1
        let delegate = WhistleDownloadDelegate(maximum: maximum, report: progress)
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (temporary, response) = try await session.download(from: url, delegate: delegate)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              verifiedTemporary(temporary, digest: digest, maximum: maximum) else { throw WhistleError.integrity }
        let stage = destination.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).part")
        defer { try? FileManager.default.removeItem(at: stage) }
        try FileManager.default.copyItem(at: temporary, to: stage)
        try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: stage.path)
        guard verifiedFile(stage, digest: digest, permissions: mode_t(permissions), maximum: maximum),
              attributes(destination.path) == nil else { throw WhistleError.integrity }
        try FileManager.default.moveItem(at: stage, to: destination)
    }

    func cancel() {
        activeRun?.cancel()
        if let downloadTask {
            cancelledDownload = downloadTask
            downloadTask.cancel()
            self.downloadTask = nil
        }
    }

    func transcribe(_ samples: [Float], language: String) async throws -> String {
        #if !arch(arm64)
        throw WhistleError.unsupportedArchitecture
        #endif
        guard Self.supports(language: language) else { throw WhistleError.unsupportedLanguage }
        guard Self.sandboxAvailable() else { throw WhistleError.sandboxUnavailable }
        guard isReady() else { throw WhistleError.notDownloaded }
        let run = WhistleRun()
        activeRun?.cancel()
        activeRun = run
        defer { if activeRun === run { activeRun = nil } }
        let command = executable.path
        let model = weights.path
        let cacheDirectory = directory
        let streaming = Self.usesStreaming(sampleCount: samples.count)
        let wav = Self.wav(samples)
        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try Self.execute(run: run, directory: cacheDirectory, executable: command, model: model, wav: wav,
                                 language: language, streaming: streaming)
            }.value
        } onCancel: { run.cancel() }
    }

    private static func wav(_ samples: [Float]) -> Data {
        var data = Data(capacity: 44 + samples.count * 2)
        func word(_ n: UInt32) {
            let bytes = n.littleEndian
            withUnsafeBytes(of: bytes) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8)
        word(UInt32(36 + samples.count * 2))
        data.append(contentsOf: "WAVEfmt ".utf8)
        word(16)
        data.append(contentsOf: [1, 0, 1, 0]) // signed PCM, mono
        word(16_000)
        word(32_000)
        data.append(contentsOf: [2, 0, 16, 0])
        data.append(contentsOf: "data".utf8)
        word(UInt32(samples.count * 2))
        for sample in samples {
            let value = Int16((sample.isFinite ? max(-1, min(1, sample)) : 0) * 32767)
            let bytes = value.littleEndian
            withUnsafeBytes(of: bytes) { data.append(contentsOf: $0) }
        }
        return data
    }

    private static func execute(run: WhistleRun, directory: URL, executable: String, model: String, wav: Data,
                                language: String, streaming: Bool) throws -> String {
        if run.isStopped { throw WhistleError.cancelled }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ovf-whistle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: dir) }
        let fifo = canonical(dir.appendingPathComponent("audio.fifo").path)
        guard mkfifo(fifo, 0o600) == 0 else { throw WhistleError.failed }
        // Recheck the cache just before execution, after preparing the FIFO.
        guard secureDirectory(directory, permissions: 0o500),
              verifiedFile(URL(fileURLWithPath: executable), digest: executableSHA256, permissions: 0o500, maximum: 50_000_000),
              verifiedFile(URL(fileURLWithPath: model), digest: weightsSHA256, permissions: 0o400, maximum: 300_000_000)
        else { throw WhistleError.integrity }
        let output = Pipe()
        let process = vendorProcess(executable: executable, model: model, fifo: fifo,
                                    language: language, streaming: streaming, home: dir.path, output: output)
        try run.attach(process)
        if run.isStopped { throw WhistleError.cancelled }
        try process.run()
        if run.isStopped { run.cancel() }
        // O_RDWR avoids an uninterruptible writer waiting for the child's FIFO
        // open, and prevents SIGPIPE if the child exits before the writer does.
        let fd = open(fifo, O_RDWR | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else { run.cancel(); throw WhistleError.failed }
        let writer = DispatchGroup()
        writer.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { close(fd); writer.leave() }
            wav.withUnsafeBytes { bytes in
                var index = 0
                while index < bytes.count && !run.isStopped && process.isRunning {
                    let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: index), min(65536, bytes.count - index))
                    if count > 0 { index += count }
                    else if errno != EAGAIN && errno != EINTR { break }
                    if count <= 0 { usleep(5_000) }
                }
            }
        }
        let seconds = max(90, min(900, Int(ceil(Double(wav.count - 44) / 32_000 * 3))))
        let deadline = ProcessInfo.processInfo.systemUptime + Double(seconds)
        let bytes = readOutput(output, run: run, seconds: Double(seconds))
        // EOF can precede child exit; the same monotonic deadline bounds both.
        if run.isStopped { run.cancel() }
        try awaitExit(process, run: run, deadline: deadline)
        writer.wait()
        if run.isTimedOut { throw WhistleError.timedOut }
        if run.isOverflowed { throw WhistleError.failed }
        if run.isStopped { throw WhistleError.cancelled }
        guard process.terminationStatus == 0,
              let text = decodeOutput(bytes, streaming: streaming) else { throw WhistleError.failed }
        return text
    }

    /// EOF does not imply child exit. Reap only after exit; never block past
    /// the monotonic deadline and bounded TERM/SIGKILL escalation.
    static func awaitExit(_ process: Process, run: WhistleRun, deadline: TimeInterval) throws {
        var escalation: TimeInterval?
        while process.isRunning {
            let now = ProcessInfo.processInfo.systemUptime
            if escalation == nil && now >= deadline {
                run.timeout()
                escalation = now
            }
            if let escalation, now - escalation >= 1 {
                kill(process.processIdentifier, SIGKILL)
                if now - escalation >= 2 { throw WhistleError.timedOut }
            }
            usleep(10_000)
        }
        process.waitUntilExit()
    }

    /// Nonblocking read makes the deadline independent of EOF: even an
    /// inherited stdout handle cannot hold a cancellation/timeout forever.
    static func readOutput(_ output: Pipe, run: WhistleRun, seconds: Double) -> Data {
        let fd = output.fileHandleForReading.fileDescriptor
        let oldFlags = fcntl(fd, F_GETFL)
        guard oldFlags >= 0, fcntl(fd, F_SETFL, oldFlags | O_NONBLOCK) == 0 else {
            run.cancel(); return Data()
        }
        defer { _ = fcntl(fd, F_SETFL, oldFlags) }
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        var bytes = Data()
        let limit = 2_000_000
        while true {
            if run.isStopped { break }
            if ProcessInfo.processInfo.systemUptime >= deadline { run.timeout(); break }
            var chunk = [UInt8](repeating: 0, count: min(65_536, limit - bytes.count + 1))
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count == 0 { break }
            if count > 0 {
                if bytes.count + count > limit { run.overflow(); break }
                bytes.append(contentsOf: chunk[..<count])
            } else if errno != EAGAIN && errno != EINTR { run.cancel(); break }
            if count < 0 { usleep(10_000) }
        }
        return bytes
    }

    static func decodeOutput(_ data: Data, streaming: Bool) -> String? {
        guard let output = String(data: data, encoding: .utf8) else { return nil }
        let lines = output.split(whereSeparator: \.isNewline)
        guard !lines.isEmpty else { return nil }
        var committed: [String] = []
        for (index, line) in lines.enumerated() {
            guard let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let text = json["text"] as? String else { return nil }
            if streaming {
                guard let pending = json["pending"] as? String else { return nil }
                if index == lines.count - 1 && !pending.isEmpty { return nil }
            }
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { committed.append(text) }
        }
        guard streaming || lines.count == 1 else { return nil }
        return committed.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
