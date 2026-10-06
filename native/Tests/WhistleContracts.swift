import Foundation
import Darwin

private actor DownloadAttempts {
    private(set) var count = 0
    func next() -> Int { count += 1; return count }
}

private actor ResistantFetch {
    private(set) var count = 0
    private var releaseFirst: CheckedContinuation<Void, Never>?
    private var released = false
    func enter() async {
        count += 1
        if count == 1 && !released {
            await withCheckedContinuation { releaseFirst = $0 }
        }
    }
    func release() {
        released = true
        releaseFirst?.resume()
        releaseFirst = nil
    }
}

@main enum WhistleContracts {
    private static func probeLoopback(_ port: UInt16) -> Int32 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return 78 }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: in_addr_t(INADDR_LOOPBACK).bigEndian)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        if connected == 0 { return 0 }
        return errno == EPERM || errno == EACCES ? 77 : 78
    }

    private static func inheritedStdoutFixture() throws -> (parentExited: Bool, heldOpen: Bool, eventuallyClosed: Bool) {
        let inherited = Process()
        inherited.executableURL = URL(fileURLWithPath: "/bin/sh")
        inherited.arguments = ["-c", "/bin/sleep 2 & exit 0"]
        let output = Pipe()
        inherited.standardOutput = output
        inherited.standardError = FileHandle.nullDevice
        try inherited.run()
        inherited.waitUntilExit()
        let run = WhistleRun()
        let start = ProcessInfo.processInfo.systemUptime
        _ = WhistleEngine.readOutput(output, run: run, seconds: 0.15)
        let bounded = ProcessInfo.processInfo.systemUptime - start < 1 && run.isTimedOut
        return (inherited.terminationStatus == 0, bounded, true)
    }

    static func main() async throws {
        func sandboxPath(_ path: String) -> String {
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            return resolved.hasPrefix("/var/") ? "/private" + resolved : resolved
        }
        if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--probe-sensitive-stdin" {
            let vendor = WhistleEngine.vendorProcess(
                executable: "/bin/sh", model: "/private/etc/hosts", fifo: "/private/etc/hosts",
                language: "en", streaming: false, home: "/tmp", output: Pipe())
            guard vendor.standardInput as? FileHandle === FileHandle.nullDevice else {
                fatalError("vendor CLI must explicitly replace inherited stdin descriptor 0")
            }
            // A sandbox does not revoke already-inherited descriptors. Substitute
            // a benign shell for the CLI to test the exact configured Process.
            vendor.executableURL = URL(fileURLWithPath: "/bin/sh")
            vendor.arguments = ["-c", "IFS= read -r line && test \"$line\" = PRIVATE"]
            try vendor.run()
            vendor.waitUntilExit()
            guard vendor.terminationStatus != 0,
                  FileHandle.standardInput.readDataToEndOfFile() == Data("PRIVATE\n".utf8) else {
                fatalError("sensitive parent stdin leaked to the vendor process")
            }
            print("vendor stdin descriptor isolated")
            return
        }
        if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--probe-early-eof" {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/bin/sh")
            child.arguments = ["-c", "exec 1>&-; trap '' TERM; while :; do :; done"]
            let output = Pipe()
            child.standardOutput = output
            child.standardError = FileHandle.nullDevice
            try child.run()
            let run = WhistleRun()
            try run.attach(child)
            let start = ProcessInfo.processInfo.systemUptime
            _ = WhistleEngine.readOutput(output, run: run, seconds: 0.2)
            guard child.isRunning else { fatalError("fixture child must still run after stdout EOF") }
            try WhistleEngine.awaitExit(child, run: run, deadline: start + 0.2)
            guard !child.isRunning, run.isTimedOut,
                  child.terminationReason == .uncaughtSignal, child.terminationStatus == SIGKILL,
                  ProcessInfo.processInfo.systemUptime - start < 2.5 else {
                fatalError("early EOF must not bypass child-exit deadline and escalation")
            }
            print("early EOF exit bounded")
            return
        }
        if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--probe-double-cancel" {
            let gate = ResistantFetch()
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("whistle-double-cancel-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let engine = WhistleEngine(directory: root, fetcher: { _, _, _, _, _, _ in
                await gate.enter() // Deliberately ignores cancellation until released.
                try Task.checkCancellation()
            })
            let first = Task { try await engine.download() }
            for _ in 0..<100 {
                if await gate.count > 0 { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            guard await gate.count == 1 else { fatalError("first fetch did not start") }
            await engine.cancel() // A → B
            await engine.cancel() // B → A before cancellation-resistant A unwinds
            let replacement = Task { try await engine.download() }
            try await Task.sleep(for: .milliseconds(100))
            let overlapping = await gate.count != 1
            await gate.release()
            guard !overlapping else { fatalError("replacement overlapped cancelled fetch") }
            do { try await first.value; fatalError("cancelled fetch completed") }
            catch is CancellationError { }
            try await replacement.value
            guard await gate.count == 3 else { fatalError("replacement did not fetch both stages") }
            print("double cancel serialized")
            return
        }
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--probe-loopback" {
            guard let port = UInt16(CommandLine.arguments[2]) else { exit(78) }
            exit(probeLoopback(port))
        }
        if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--probe-fork" {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
            child.arguments = ["--fork-child"]
            child.standardOutput = FileHandle.nullDevice
            child.standardError = FileHandle.nullDevice
            do { try child.run(); child.waitUntilExit(); exit(child.terminationStatus == 0 ? 0 : 78) }
            catch { exit(77) }
        }
        if CommandLine.arguments.count == 2, CommandLine.arguments[1] == "--fork-child" { exit(0) }
        func check(_ value: Bool, _ message: String) {
            guard value else { fatalError(message) }
        }
        let stdinProbe = Process()
        stdinProbe.executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
        stdinProbe.arguments = ["--probe-sensitive-stdin"]
        let sensitiveInput = Pipe()
        stdinProbe.standardInput = sensitiveInput
        try stdinProbe.run()
        sensitiveInput.fileHandleForWriting.write(Data("PRIVATE\n".utf8))
        try sensitiveInput.fileHandleForWriting.close()
        stdinProbe.waitUntilExit()
        check(stdinProbe.terminationStatus == 0, "vendor must not inherit sensitive stdin/descriptor")
        check(!WhistleEngine.usesStreaming(sampleCount: 30 * 16_000 - 1), "below 30s is non-streaming")
        check(!WhistleEngine.usesStreaming(sampleCount: 30 * 16_000), "exactly 30s is non-streaming")
        check(WhistleEngine.usesStreaming(sampleCount: 30 * 16_000 + 1), "30s + 1 sample streams")
        func vendorFlags(sampleCount: Int) -> [String] {
            WhistleEngine.vendorProcess(executable: "/bin/sh", model: "/private/etc/hosts",
                                        fifo: "/private/etc/hosts", language: "en",
                                        streaming: WhistleEngine.usesStreaming(sampleCount: sampleCount),
                                        home: "/tmp", output: Pipe()).arguments ?? []
        }
        check(!vendorFlags(sampleCount: 30 * 16_000).contains("--audio-stream"), "exactly 30s CLI must not stream")
        check(vendorFlags(sampleCount: 30 * 16_000 + 1).contains("--audio-stream"), "30s + 1 sample CLI must stream")
        check(WhistleEngine.modelID == "whistle", "stable opt-in model ID")
        check(!WhistleEngine.supports(language: "ja"), "unsupported language must fail")
        for language in ["en", "fr", "de", "es", "it", "pl", "nl"] {
            check(WhistleEngine.supports(language: language), "supported language \(language)")
        }
        check(!WhistleEngine.supports(language: "auto"), "auto cannot be silently coerced")
        check(!WhistleEngine.supports(language: "pt"), "Portuguese is not in pinned model card")
        let profile = WhistleEngine.sandboxProfile(executable: "/tmp/needle", model: "/tmp/model", fifo: "/tmp/audio.fifo")
        check(profile.contains("(deny default)") && !profile.contains("(allow default)"), "sandbox must default deny")
        check(profile.contains("(literal \"/tmp/needle\")") && profile.contains("(literal \"/tmp/audio.fifo\")"), "only explicit vendor resources")
        let secret = FileManager.default.temporaryDirectory.appendingPathComponent("whistle-secret-\(UUID().uuidString)")
        try Data("PRIVATE".utf8).write(to: secret)
        defer { try? FileManager.default.removeItem(at: secret) }
        func sandboxCat(_ path: String) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
            process.arguments = ["-p", WhistleEngine.sandboxProfile(executable: "/bin/cat", model: "/private/etc/hosts", fifo: "/private/etc/hosts"), "/bin/cat", path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
        check(try sandboxCat("/private/etc/hosts") == 0, "sandbox allows only named input")
        check(try sandboxCat(secret.path) != 0, "sandbox denies unrelated user file")
        // A local TCP listener makes the negative network assertion independent of
        // DNS, remote availability, proxies, curl settings and even nc startup.
        let listener = socket(AF_INET, SOCK_STREAM, 0)
        check(listener >= 0, "create loopback network probe")
        defer { close(listener) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr = in_addr(s_addr: in_addr_t(INADDR_LOOPBACK).bigEndian)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(listener, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        check(bound == 0 && listen(listener, 2) == 0, "listen on loopback")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(listener, $0, &length)
            }
        }
        check(named == 0, "find ephemeral loopback port")
        let port = String(UInt16(bigEndian: address.sin_port))
        func probeNetwork(sandboxed: Bool) throws -> Int32 {
            let process = Process()
            // CI's TMPDIR commonly begins /var, which the sandbox resolves to
            // /private/var before matching a literal file grant.
            let executable = sandboxPath(CommandLine.arguments[0])
            process.executableURL = URL(fileURLWithPath: sandboxed ? "/usr/bin/sandbox-exec" : executable)
            let arguments = ["--probe-loopback", port]
            process.arguments = sandboxed
                ? ["-p", WhistleEngine.sandboxProfile(executable: executable, model: "/private/etc/hosts", fifo: "/private/etc/hosts"), executable] + arguments
                : arguments
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        }
        check(try probeNetwork(sandboxed: false) == 0, "loopback control must be reachable")
        let deniedNetworkStatus = try probeNetwork(sandboxed: true)
        check(deniedNetworkStatus == 77, "vendor sandbox denies loopback connect, not probe startup (status \(deniedNetworkStatus))")
        let forkProbe = Process()
        let forkBinary = sandboxPath(CommandLine.arguments[0])
        forkProbe.executableURL = URL(fileURLWithPath: "/usr/bin/sandbox-exec")
        forkProbe.arguments = ["-p", WhistleEngine.sandboxProfile(executable: forkBinary, model: "/private/etc/hosts", fifo: "/private/etc/hosts"), forkBinary, "--probe-fork"]
        forkProbe.standardOutput = FileHandle.nullDevice
        forkProbe.standardError = FileHandle.nullDevice
        try forkProbe.run()
        forkProbe.waitUntilExit()
        check(forkProbe.terminationStatus == 77, "vendor sandbox denies child process creation")

        // A vendor process can exit while its descendant still holds stdout.
        // This fixture establishes that waiting for EOF is NOT a process timeout;
        // the production executor needs its own watchdog/cancellation path.
        let descendant = try inheritedStdoutFixture()
        check(descendant.parentExited, "fixture parent exits cleanly")
        check(descendant.heldOpen, "bounded reader times out despite descendant holding stdout after parent exit")
        // A→B→A: cancel the first transfer, then start a new request for the
        // same model while its cancelled task is still finishing cleanup.
        let attempts = DownloadAttempts()
        let downloadRoot = FileManager.default.temporaryDirectory.appendingPathComponent("whistle-aba-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: downloadRoot) }
        let downloadEngine = WhistleEngine(directory: downloadRoot, fetcher: { _, _, _, _, _, _ in
            let attempt = await attempts.next()
            if attempt == 1 { try await Task.sleep(for: .seconds(5)) }
            try Task.checkCancellation()
        })
        let oldDownload = Task { try await downloadEngine.download() }
        for _ in 0..<100 {
            if await attempts.count > 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        check(await attempts.count == 1, "first download entered pinned fetch seam")
        await downloadEngine.cancel()
        let newDownload = Task { try await downloadEngine.download() }
        do { try await oldDownload.value; fatalError("cancelled A must not complete") }
        catch is CancellationError { }
        try await newDownload.value
        check(await attempts.count == 3, "new A did not join cancelled A; both replacement stages ran")
        check(WhistleEngine.decodeOutput(Data("{\"text\":\"Hello\",\"language\":\"en\"}\n".utf8), streaming: false) == "Hello", "parse final JSON")
        check(WhistleEngine.decodeOutput(Data("{\"text\":\"one\",\"pending\":\"two\"}\n{\"text\":\"two\",\"pending\":\"\"}\n".utf8), streaming: true) == "one two", "stream only committed text")
        check(WhistleEngine.decodeOutput(Data("garbage".utf8), streaming: false) == nil, "malformed result fails")
        check(WhistleEngine.decodeOutput(Data("{\"text\":\"one\",\"pending\":\"two\"}\n".utf8), streaming: true) == nil, "unfinished stream is not a committed result")
        check(WhistleEngine.decodeOutput(Data("{\"text\":\"one\"}\n{\"text\":\"two\"}\n".utf8), streaming: false) == nil,
              "non-streaming output cannot commit multiple results")
        check(WhistleEngine.decodeOutput(Data("{\"text\":\"one\",\"pending\":\"\"}\n{\"text\":\"two\",\"pending\":\"partial\"}\n".utf8), streaming: true) == nil,
              "stream must reject uncommitted final segment")
        check(!WhistleEngine.verify(Data("wrong".utf8), expected: WhistleEngine.executableSHA256), "reject corrupt executable")
        check(!WhistleEngine.verify(Data("wrong".utf8), expected: WhistleEngine.weightsSHA256), "reject corrupt weights")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("whistle-contract-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let engine = WhistleEngine(directory: root)
        let ready = await engine.isReady()
        check(!ready, "no implicit download")
        try FileManager.default.createSymbolicLink(at: root, withDestinationURL: secret)
        check(!(await engine.isReady()), "symlinked cache root never ready")
        try FileManager.default.removeItem(at: root)
        do { _ = try await engine.transcribe([Float](repeating: 0, count: 16000), language: "ja"); fatalError("expected unsupported language") }
        catch WhistleError.unsupportedLanguage { }
        do { _ = try await engine.transcribe([Float](repeating: 0, count: 16000), language: "en"); fatalError("expected explicit download") }
        catch WhistleError.notDownloaded { }
        if ProcessInfo.processInfo.environment["WHISTLE_DOWNLOAD_TEST"] == "1" {
            try await engine.download()
            let fetchedReady = await engine.isReady()
            check(fetchedReady, "on-demand pinned downloads verify")
        }
        if let fixture = ProcessInfo.processInfo.environment["WHISTLE_FIXTURE_DIR"] {
            let source = URL(fileURLWithPath: fixture, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            for file in ["needle", "whistle.cact"] {
                try FileManager.default.copyItem(at: source.appendingPathComponent(file), to: root.appendingPathComponent(file))
                try FileManager.default.setAttributes([.posixPermissions: file == "needle" ? 0o500 : 0o400], ofItemAtPath: root.appendingPathComponent(file).path)
            }
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
            let originalWeights = root.appendingPathComponent("whistle.cact")
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try FileManager.default.removeItem(at: originalWeights)
            try FileManager.default.createSymbolicLink(at: originalWeights, withDestinationURL: source.appendingPathComponent("whistle.cact"))
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
            check(!(await engine.isReady()), "symlinked model rejected even if content is valid")
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try FileManager.default.removeItem(at: originalWeights)
            try FileManager.default.copyItem(at: source.appendingPathComponent("whistle.cact"), to: originalWeights)
            try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: originalWeights.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
            let binary = root.appendingPathComponent("needle")
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try FileManager.default.removeItem(at: binary)
            try FileManager.default.createSymbolicLink(at: binary, withDestinationURL: source.appendingPathComponent("needle"))
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
            check(!(await engine.isReady()), "symlinked executable rejected even if digest matches")
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try FileManager.default.removeItem(at: binary)
            try FileManager.default.copyItem(at: source.appendingPathComponent("needle"), to: binary)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: binary.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
            let downloadedReady = await engine.isReady()
            check(downloadedReady, "pinned fixture verification")
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: originalWeights.path)
            check(!(await engine.isReady()), "writable model weights must not execute")
            try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: originalWeights.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            let alias = root.appendingPathComponent("weight-alias")
            try FileManager.default.linkItem(at: originalWeights, to: alias)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
            check(!(await engine.isReady()), "hard-linked model weights must not execute")
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try FileManager.default.removeItem(at: alias)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
            check(await engine.isReady(), "verified fixture recovers after rejecting unsafe weights")
            // A normal truncated/corrupt cached regular file must be repairable
            // through the Settings Retry path without manual filesystem edits.
            let repairRoot = FileManager.default.temporaryDirectory.appendingPathComponent("whistle-repair-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: repairRoot) }
            try FileManager.default.createDirectory(at: repairRoot, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o500])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: repairRoot.path)
            let cachedExecutable = repairRoot.appendingPathComponent("needle")
            let cachedWeights = repairRoot.appendingPathComponent("whistle.cact")
            try FileManager.default.copyItem(at: source.appendingPathComponent("needle"), to: cachedExecutable)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: cachedExecutable.path)
            try Data("truncated".utf8).write(to: cachedWeights)
            try FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: cachedWeights.path)
            try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: repairRoot.path)
            let repairEngine = WhistleEngine(directory: repairRoot, fetcher: { _, destination, _, permissions, _, _ in
                guard !FileManager.default.fileExists(atPath: destination.path) else { throw WhistleError.integrity }
                try FileManager.default.copyItem(at: source.appendingPathComponent(destination.lastPathComponent), to: destination)
                try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: destination.path)
            })
            check(!(await repairEngine.isReady()), "corrupt cached weights are not ready")
            try await repairEngine.download()
            check(await repairEngine.isReady(), "Retry repairs a corrupt regular cached model")
            let clip = try Data(contentsOf: source.appendingPathComponent("clip.wav"))
            let samples = stride(from: 44, to: clip.count - 1, by: 2).map { offset -> Float in
                let value = Int16(bitPattern: UInt16(clip[offset]) | UInt16(clip[offset + 1]) << 8)
                return Float(value) / 32768
            }
            let short = try await engine.transcribe(samples, language: "en")
            check(short.contains("local dictation test"), "FIFO transcription returns committed text")
            let long = try await engine.transcribe(Array(repeating: samples, count: 9).flatMap { $0 }, language: "en")
            check(long.contains("local dictation test"), "streaming >30s returns committed transcript")
            let slow = Task { try await engine.transcribe(Array(repeating: samples, count: 70).flatMap { $0 }, language: "en") }
            try await Task.sleep(for: .milliseconds(500))
            let replacement = Task { try await engine.transcribe(Array(repeating: samples, count: 70).flatMap { $0 }, language: "en") }
            do { _ = try await slow.value; fatalError("replaced transcription must not commit") }
            catch WhistleError.cancelled { }
            await engine.cancel()
            do { _ = try await replacement.value; fatalError("active replacement must be cancellable") }
            catch WhistleError.cancelled { }
            let early = Task { try await engine.transcribe(Array(repeating: samples, count: 70).flatMap { $0 }, language: "en") }
            early.cancel()
            do { _ = try await early.value; fatalError("pre-launch cancellation must not commit") }
            catch WhistleError.cancelled { }
            catch is CancellationError { }
        }
        print("Whistle contracts passed")
    }
}
