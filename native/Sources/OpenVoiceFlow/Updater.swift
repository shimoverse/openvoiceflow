import Sparkle

/// In-app updates via Sparkle 2 with an EdDSA-signed appcast.
///
/// `SUFeedURL` (the appcast) and `SUPublicEDKey` (the signature-verification
/// key) live in Info.plist; the matching private key signs each build in the
/// release pipeline. Created once at launch so Sparkle polls on its schedule;
/// the menu-bar "Check for Updates…" item drives a manual check.
///
/// Ships in the *notarized DMG* path only — a menu-bar app with a global event
/// tap can't be sandboxed, so it updates itself via Sparkle rather than the App
/// Store (native/README.md). Until an appcast is hosted and `SUPublicEDKey` is
/// set, checks simply find nothing — Sparkle refuses unsigned updates by design.
@MainActor
final class UpdaterController {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController

    private init() {
        // startingUpdater: true → background appcast checks begin immediately.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // Honor the user's saved preference for background checks.
        controller.updater.automaticallyChecksForUpdates = Settings.load().automaticUpdates
    }

    /// Disabled while a check is already running (drives the menu item's state).
    var canCheckForUpdates: Bool { controller.updater.canCheckForUpdates }

    /// Manual "Check for Updates…" — shows Sparkle's standard UI.
    func checkForUpdates() { controller.checkForUpdates(nil) }

    /// Toggle background appcast checks (Settings ▸ Automatic updates).
    func setAutomaticChecks(_ enabled: Bool) {
        controller.updater.automaticallyChecksForUpdates = enabled
    }
}
