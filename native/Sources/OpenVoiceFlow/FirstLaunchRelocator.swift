import AppKit
import Foundation
import os

/// Copies OpenVoiceFlow into /Applications and relaunches it from there the
/// moment someone opens it straight out of the install DMG — so double-clicking
/// the icon in the DMG window is enough; there is no separate "now drag it,
/// then go find it again" step, and no Spotlight search after the copy lands.
///
/// Dragging the icon onto the Applications shortcut still works exactly as
/// before (that copy is inert until launched, same as always). This only
/// covers the case where the app itself gets opened before anyone dragged it
/// anywhere — the thing that used to just run in place, invisibly, off a
/// disk image that vanishes on eject.
@MainActor
enum FirstLaunchRelocator {
    // Sendable and immutable — safe to touch from the non-isolated
    // completion handlers below without hopping back to the main actor.
    private nonisolated static let logger = Logger(subsystem: "app.openvoiceflow", category: "relocate")

    /// Returns true when a relocation was kicked off. The caller must stop its
    /// own startup right there — this process is on its way out.
    static func relocateToApplicationsIfNeeded() -> Bool {
        #if DEBUG
        // Never hijack a Run-from-Xcode build — it never lives on a volume
        // that matches the checks below anyway, but this keeps it explicit.
        return false
        #else
        let bundleURL = Bundle.main.bundleURL
        let path = bundleURL.path

        // A plain DMG mount shows up under /Volumes. A quarantined app opened
        // directly off that DMG (without being moved first) instead runs from
        // a randomised Gatekeeper "translocation" path — same disk image,
        // different apparent location — so both need to be caught here.
        let runningFromDiskImage = path.hasPrefix("/Volumes/") || path.contains("/AppTranslocation/")
        guard runningFromDiskImage else { return false }

        let destination = URL(fileURLWithPath: "/Applications")
            .appendingPathComponent(bundleURL.lastPathComponent)
        let fileManager = FileManager.default

        do {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: bundleURL, to: destination)
        } catch {
            // No write access to /Applications, or something unexpected about
            // the source volume: run in place rather than block launch on an
            // install step that didn't work.
            logger.error("copy to /Applications failed: \(error.localizedDescription, privacy: .public)")
            return false
        }

        // Default configuration except for one marker argument: if an older
        // copy is somehow already running (this app persists as a menu-bar
        // accessory), openApplication activates that existing instance
        // instead of launching a second one fighting it for the same hotkey
        // and microphone — and the marker tells the copy that DOES launch it
        // is safe to sweep up the install volume (see below).
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.arguments = [Self.relocatedMarkerArgument]
        NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, error in
            if let error {
                logger.error("relaunch from /Applications failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        // Ejecting the disk image is the *new* process's job, not this one's:
        // this process's own executable is still mapped from that volume, so
        // it would just get "resource busy" — and terminate() below tends to
        // end the run loop before a delayed block here ever gets to fire
        // anyway. See ejectStaleInstallVolumesIfAny().
        NSApplication.shared.terminate(nil)
        return true
        #endif
    }

    /// Passed as a launch argument to the relaunched copy so it — and only
    /// it — knows to sweep up the install volume. Without this gate, any
    /// ordinary subsequent launch (a login item, reopening from the Dock)
    /// would eject whatever "OpenVoiceFlow …" volume happens to be mounted,
    /// even one the user is still looking at for an unrelated reason.
    static let relocatedMarkerArgument = "--ovf-relocated"

    /// Best-effort cleanup right after a relocation: eject the install volume
    /// this process was just copied out of, so the desktop doesn't keep a
    /// stray disk-image icon around. Retries once, since the previous
    /// process freeing the volume can lag a beat behind its own exit.
    static func ejectStaleInstallVolumesIfAny() {
        guard ProcessInfo.processInfo.arguments.contains(relocatedMarkerArgument) else { return }
        guard let volumes = try? FileManager.default.contentsOfDirectory(atPath: "/Volumes") else { return }
        let candidates = volumes.filter { $0.hasPrefix("OpenVoiceFlow") }
        guard !candidates.isEmpty else { return }

        for name in candidates {
            Task.detached(priority: .utility) {
                for attempt in 0..<2 {
                    if attempt > 0 { try? await Task.sleep(for: .seconds(2)) }
                    let eject = Process()
                    eject.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
                    eject.arguments = ["eject", "/Volumes/\(name)"]
                    try? eject.run()
                    eject.waitUntilExit()
                    if eject.terminationStatus == 0 { break }
                }
            }
        }
    }
}
