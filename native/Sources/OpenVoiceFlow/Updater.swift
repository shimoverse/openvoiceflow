import Combine
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
final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController
    private var canCheckObservation: NSKeyValueObservation?

    /// Mirrors Sparkle's `canCheckForUpdates` so SwiftUI re-renders the
    /// "Check for updates now" CTA when a launch/scheduled check finishes —
    /// otherwise the button, in a persistent window, could stay disabled until
    /// the view happened to reload.
    @Published private(set) var canCheckForUpdates = false

    private init() {
        // startingUpdater: true → background appcast checks begin immediately.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // Honor the user's saved preference for automatic updates.
        apply(automatic: Settings.load().automaticUpdates)
        // Keep the published flag in sync with Sparkle's KVO-observable state.
        canCheckForUpdates = controller.updater.canCheckForUpdates
        canCheckObservation = controller.updater.observe(
            \.canCheckForUpdates, options: [.new]
        ) { [weak self] _, change in
            guard let value = change.newValue else { return }
            Task { @MainActor in self?.canCheckForUpdates = value }
        }
    }

    /// The running app's marketing version (e.g. "0.4.2"), read from the bundle
    /// so the UI never hardcodes it.
    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    /// Manual "Check for Updates…" / "Check for updates now" — shows Sparkle's
    /// standard UI so an on-demand check always has clear feedback.
    func checkForUpdates() { controller.checkForUpdates(nil) }

    /// Toggle automatic updates (Settings ▸ Automatic updates): both the daily
    /// scheduled check and the silent background download+install.
    func setAutomaticChecks(_ enabled: Bool) { apply(automatic: enabled) }

    /// "Automatic" means check on the schedule AND download+install in the
    /// background (installed on next relaunch). Sparkle requires downloads to be
    /// gated behind checks, so both flip together. Signature + notarization are
    /// still verified before any install.
    private func apply(automatic: Bool) {
        controller.updater.automaticallyChecksForUpdates = automatic
        controller.updater.automaticallyDownloadsUpdates = automatic
    }
}
