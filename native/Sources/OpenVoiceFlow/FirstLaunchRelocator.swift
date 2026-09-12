import AppKit
import Foundation
import os

/// Moves a copy launched from an install DMG into /Applications, relaunches
/// there, and lets that installed process eject only the source DMG.
@MainActor
enum FirstLaunchRelocator {
    private nonisolated static let logger = Logger(subsystem: "app.openvoiceflow", category: "relocate")
    private static let relocatedMarkerArgument = "--ovf-relocated-volume"

    /// Returns true when this launch has been handed off to an installed copy.
    /// The caller must stop startup because this process is terminating.
    static func relocateToApplicationsIfNeeded() -> Bool {
        #if DEBUG
        // Never hijack a Run-from-Xcode build.
        return false
        #else
        let bundleURL = Bundle.main.bundleURL.standardizedFileURL
        let path = bundleURL.path
        let sourceMount = diskImageMountPoint(containing: bundleURL)
        let translocated = path.contains("/AppTranslocation/")
        guard sourceMount != nil || translocated else { return false }

        let destination = URL(fileURLWithPath: "/Applications")
            .appendingPathComponent(bundleURL.lastPathComponent)
            .standardizedFileURL
        let fileManager = FileManager.default

        // Launch Services normally routes a second double-click to the running
        // installed copy before this code executes. Keep the fallback explicit:
        // never replace files underneath a live process.
        if let running = runningInstalledApplication(at: destination) {
            running.activate(options: [.activateAllWindows])
            logger.info("installed copy is already running; activated it without replacing the bundle")
            NSApplication.shared.terminate(nil)
            return true
        }

        if fileManager.fileExists(atPath: destination.path),
           isBuild(installedBuild(at: destination), atLeast: installedBuild(at: bundleURL)) {
            // A stale DMG must never downgrade (or needlessly rewrite) an equal
            // or newer installed build. Launch what is already installed.
            relaunch(destination, sourceMount: sourceMount)
            return true
        }

        // Copy beside the destination first, validate the complete staged app,
        // then atomically swap it into place. A failed copy can no longer erase
        // the user's working installation.
        let staging = destination.deletingLastPathComponent()
            .appendingPathComponent(".OpenVoiceFlow.installing-\(UUID().uuidString).app")
        defer { try? fileManager.removeItem(at: staging) }

        do {
            try fileManager.copyItem(at: bundleURL, to: staging)
            guard let stagedBundle = Bundle(url: staging),
                  stagedBundle.bundleIdentifier == Bundle.main.bundleIdentifier,
                  fileManager.isExecutableFile(atPath: stagedBundle.executableURL?.path ?? "") else {
                throw CocoaError(.fileReadCorruptFile)
            }

            if fileManager.fileExists(atPath: destination.path) {
                _ = try fileManager.replaceItemAt(
                    destination,
                    withItemAt: staging,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try fileManager.moveItem(at: staging, to: destination)
            }
        } catch {
            // Run in place rather than block launch, while preserving any prior
            // installed copy and cleaning the incomplete staging bundle.
            logger.error("copy to /Applications failed: \(error.localizedDescription, privacy: .public)")
            return false
        }

        relaunch(destination, sourceMount: sourceMount)
        return true
        #endif
    }

    /// Best-effort cleanup after relocation. The exact source mount is carried
    /// in argv; ordinary launches never scan or eject similarly named volumes.
    static func ejectStaleInstallVolumesIfAny() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let marker = arguments.firstIndex(of: relocatedMarkerArgument),
              arguments.indices.contains(marker + 1) else { return }

        let mountPath = URL(fileURLWithPath: arguments[marker + 1]).standardizedFileURL.path
        guard mountPath.hasPrefix("/Volumes/"),
              diskImageMountPoints().contains(mountPath) else { return }

        Task.detached(priority: .utility) {
            for attempt in 0..<2 {
                if attempt > 0 { try? await Task.sleep(for: .seconds(2)) }
                let eject = Process()
                eject.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                eject.arguments = ["eject", mountPath]
                try? eject.run()
                eject.waitUntilExit()
                if eject.terminationStatus == 0 { break }
            }
        }
    }

    private static func relaunch(_ destination: URL, sourceMount: URL?) {
        let configuration = NSWorkspace.OpenConfiguration()
        // The source process has the same bundle identifier, so a normal open
        // can merely reactivate the DMG instance. Force one installed instance,
        // then keep this process alive until Launch Services completes the handoff.
        configuration.createsNewApplicationInstance = true
        if let sourceMount {
            configuration.arguments = [relocatedMarkerArgument, sourceMount.path]
        }
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
            if let error {
                logger.error("relaunch from /Applications failed: \(error.localizedDescription, privacy: .public)")
            }
            Task { @MainActor in
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private static func runningInstalledApplication(at destination: URL) -> NSRunningApplication? {
        guard let identifier = Bundle.main.bundleIdentifier else { return nil }
        return NSRunningApplication.runningApplications(withBundleIdentifier: identifier).first {
            $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
                && $0.bundleURL?.standardizedFileURL == destination
        }
    }

    private static func installedBuild(at bundleURL: URL) -> String {
        guard let bundle = Bundle(url: bundleURL),
              let value = bundle.object(forInfoDictionaryKey: "CFBundleVersion") else { return "0" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return "0"
    }

    private static func isBuild(_ lhs: String, atLeast rhs: String) -> Bool {
        lhs.compare(rhs, options: .numeric) != .orderedAscending
    }

    private static func diskImageMountPoint(containing bundleURL: URL) -> URL? {
        let path = bundleURL.standardizedFileURL.path
        return diskImageMountPoints()
            .sorted { $0.count > $1.count }
            .first { path == $0 || path.hasPrefix($0 + "/") }
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
    }

    private static func diskImageMountPoints() -> [String] {
        let task = Process()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        task.arguments = ["info", "-plist"]
        task.standardOutput = output
        task.standardError = FileHandle.nullDevice

        do {
            try task.run()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0,
                  let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let images = plist["images"] as? [[String: Any]] else { return [] }

            return images.flatMap { image in
                (image["system-entities"] as? [[String: Any]] ?? []).compactMap {
                    ($0["mount-point"] as? String).map {
                        URL(fileURLWithPath: $0).standardizedFileURL.path
                    }
                }
            }
        } catch {
            logger.error("could not inspect mounted disk images: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
}
