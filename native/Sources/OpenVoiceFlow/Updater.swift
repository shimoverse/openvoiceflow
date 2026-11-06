import AppKit
import Combine
import Foundation
import Sparkle

/// Where the app sends people for release notes.
///
/// The same page backs Sparkle's "Version History" button — the appcast's
/// `sparkle:fullReleaseNotesLink` points here, and Sparkle offers that button
/// on the "You're up to date!" alert. Kept in one place so the in-app link and
/// the feed can't drift onto different pages. The page itself is generated
/// from CHANGELOG.md by scripts/build_releases.py.
enum ReleaseNotes {
    static let historyURL = URL(string: "https://openvoiceflow.com/releases.html")!

    /// The notes for one specific version, as an anchored card on that page.
    static func url(forVersion version: String) -> URL {
        URL(string: "https://openvoiceflow.com/releases.html#v\(version)") ?? historyURL
    }
}

/// Receives Sparkle's appcast results.
///
/// Sparkle wants its delegate at construction time, before `UpdaterController`
/// finishes initializing, so this is a small forwarding object rather than the
/// controller itself. The protocol is main-actor annotated, hence `@MainActor`.
@MainActor
private final class UpdaterProbe: NSObject, SPUUpdaterDelegate {
    var onFound: ((SUAppcastItem) -> Void)?
    var onAppcastLoaded: (() -> Void)?
    var onNotFound: ((Bool) -> Void)?
    var onAborted: ((Bool, Bool) -> Void)?
    var onFinished: ((Bool) -> Void)?
    var onReadyToInstall: ((SUAppcastItem, @escaping () -> Void) -> Void)?
    var onPostponeRelaunch: ((@escaping () -> Void) -> Bool)?

    // Sparkle 2.9.4 SUErrors.h: the ObjC enum cases are not exported as
    // top-level Swift symbols. Keep these pinned to the framework version.
    private let noUpdateCode = 1001
    private let userCanceledInstallationCode = 4007

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        onFound?(item)
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        onAppcastLoaded?()
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        let reason = (error as NSError).userInfo[SPUNoUpdateFoundReasonKey] as? NSNumber
        onNotFound?((reason?.intValue ?? -1) == SPUNoUpdateFoundReason.onLatestVersion.rawValue)
    }

    /// Every ended check lands here, including the ones that ended badly — an
    /// appcast that wouldn't load or parse reports neither found nor
    /// not-found, so this is the only signal that the check told us nothing.
    /// "No update found" aborts through here too; the controller tells the
    /// cases apart by whether a result already arrived.
    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let code = (error as NSError).code
        onAborted?(code == noUpdateCode, code == userCanceledInstallationCode)
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
        let code = (error as NSError?)?.code
        onFinished?(error != nil && code != noUpdateCode && code != userCanceledInstallationCode)
    }

    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        onPostponeRelaunch?(installHandler) ?? false
    }

    /// Sparkle has downloaded and verified an update and would, by default,
    /// install it when the app quits. A menu-bar app never quits, so left
    /// alone the update sat on disk until Sparkle's week-long "impatient"
    /// interval finally raised a dialog — the "it only updates when I check by
    /// hand" report. Returning true takes ownership: the controller invokes
    /// the handler as soon as the app is idle, which installs and relaunches.
    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        onReadyToInstall?(item, immediateInstallHandler)
        return true
    }
}

/// In-app updates via Sparkle 2 with an EdDSA-signed appcast.
///
/// `SUFeedURL` (the appcast) and `SUPublicEDKey` (the signature-verification
/// key) live in Info.plist; the matching private key signs each build in the
/// release pipeline. Created once at launch. The daily check runs at 3 PM
/// Pacific (`UpdateSchedule`), catching up on launch or wake if that passed
/// while the Mac was off; a downloaded update installs and relaunches as soon
/// as no dictation is in flight. Sparkle's own interval-based scheduler stays
/// on as a weekly safety net (SUScheduledCheckInterval). The menu-bar "Check
/// for Updates…" item drives a manual check.
///
/// Ships in the *notarized DMG* path only — a menu-bar app with a global event
/// tap can't be sandboxed, so it updates itself via Sparkle rather than the App
/// Store (native/README.md). Until an appcast is hosted and `SUPublicEDKey` is
/// set, checks simply find nothing — Sparkle refuses unsigned updates by design.
@MainActor
final class UpdaterController: ObservableObject {
    static let shared = UpdaterController()

    private let controller: SPUStandardUpdaterController
    private let probe: UpdaterProbe
    private var canCheckObservation: NSKeyValueObservation?

    /// Mirrors Sparkle's `canCheckForUpdates` so SwiftUI re-renders the
    /// "Check for updates now" CTA when a launch/scheduled check finishes —
    /// otherwise the button, in a persistent window, could stay disabled until
    /// the view happened to reload.
    @Published private(set) var canCheckForUpdates = false

    private static let lastSuccessfulCheckKey = "OVFLastSuccessfulUpdateCheck"
    @Published private(set) var status = UpdateCheckStatus(
        lastSuccessfulCheckAt: UserDefaults.standard.object(forKey: lastSuccessfulCheckKey) as? Date
    )
    private var loadedFreshAppcast = false
    var updateAvailable: Bool {
        if case .available = status.result { return true }
        return false
    }
    var availableVersion: String? {
        if case .available(let version) = status.result { return version }
        return nil
    }
    var hasCheckedForUpdates: Bool { status.result == .current }

    /// Asked before an automatic install relaunches the app. Set by the app at
    /// launch to "a dictation is in progress"; a relaunch mid-take would lose
    /// the take, so the install waits for a quiet moment instead.
    var isBusy: () -> Bool = { false }

    /// The install handler Sparkle handed over for a downloaded, verified
    /// update, held until `isBusy` clears. Sparkle allows calling it more than
    /// once, but one relaunch is all that is wanted, so it is cleared on use.
    private var pendingInstall: (() -> Void)?
    private var pendingInstallRetry: Timer?
    private var postponedRelaunch: (() -> Void)?
    private var postponedRelaunchRetry: Timer?

    /// Fires at the next 3 PM Pacific deadline (UpdateSchedule).
    private var scheduledCheck: Timer?
    private var wakeObserver: NSObjectProtocol?
    private static let lastScheduledCheckKey = "OVFLastScheduledUpdateCheck"

    private init() {
        let probe = UpdaterProbe()
        self.probe = probe
        // startingUpdater: true → background appcast checks begin immediately.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: probe,
            userDriverDelegate: nil
        )
        probe.onAppcastLoaded = { [weak self] in self?.loadedFreshAppcast = true }
        probe.onFound = { [weak self] item in
            guard let self else { return }
            // Sparkle can resume a cached download and emit didFindValidUpdate
            // without an appcast request. Do not misdate that as a fresh check.
            self.status.found(version: item.displayVersionString,
                              verifiedAt: self.loadedFreshAppcast ? Date() : nil)
            if self.loadedFreshAppcast { self.saveSuccessfulCheck() }
        }
        probe.onNotFound = { [weak self] isCurrent in
            guard let self else { return }
            self.status.notFound(isCurrent: isCurrent, at: Date())
            self.saveSuccessfulCheck()
        }
        probe.onAborted = { [weak self] expectedNoUpdate, userCanceled in
            self?.status.aborted(expectedNoUpdate: expectedNoUpdate, userCanceled: userCanceled)
        }
        probe.onFinished = { [weak self] errorOccurred in
            self?.status.finished(errorOccurred: errorOccurred)
            self?.loadedFreshAppcast = false
        }
        probe.onReadyToInstall = { [weak self] item, install in
            guard let self else { return }
            self.pendingInstall = install
            self.installPendingUpdateWhenIdle()
        }
        probe.onPostponeRelaunch = { [weak self] continueInstall in
            guard let self, self.isBusy() else { return false }
            self.postponedRelaunch = continueInstall
            self.resumeRelaunchWhenIdle()
            return true
        }
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
        // Sparkle explicitly allows a check on the runloop cycle that starts
        // the updater, so the sidebar label is honest from the first window.
        refreshUpdateStatus()
        // Daily deadline: check now if 3 PM Pacific has passed since the last
        // scheduled check (a launch at 4 PM catches up), then arm the timer for
        // the next one. Re-evaluated on wake, since a Timer that slept through
        // its fire date is not guaranteed to fire promptly.
        runScheduledCheckIfDue()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.runScheduledCheckIfDue() }
        }
    }

    // MARK: Daily schedule

    /// Runs the background check when a deadline has passed unmet, and always
    /// (re)arms the timer for the next deadline. Safe to call repeatedly.
    func runScheduledCheckIfDue(now: Date = Date()) {
        defer { armScheduledCheck(after: now) }
        guard controller.updater.automaticallyChecksForUpdates else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastScheduledCheckKey) as? Date
        guard UpdateSchedule.isCheckDue(now: now, lastCheck: last) else { return }
        // Sparkle drops a background check while a session is running (for
        // instance the launch probe above). The deadline stays unmet, so the
        // next timer tick or wake retries rather than skipping the day.
        guard !controller.updater.sessionInProgress else { return }
        UserDefaults.standard.set(now, forKey: Self.lastScheduledCheckKey)
        // The background driver, not the probe: with automatic downloads on
        // this is the path that fetches, verifies and stages the update, and
        // it ends in `willInstallUpdateOnQuit` above.
        loadedFreshAppcast = false
        status.begin()
        controller.updater.checkForUpdatesInBackground()
    }

    private func armScheduledCheck(after now: Date) {
        scheduledCheck?.invalidate()
        // A minute past the deadline, so the timer never lands a hair early and
        // computes "not due yet".
        let fireAt = UpdateSchedule.nextDeadline(after: now).addingTimeInterval(60)
        let timer = Timer(fire: fireAt, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.runScheduledCheckIfDue() }
        }
        timer.tolerance = 300
        RunLoop.main.add(timer, forMode: .common)
        scheduledCheck = timer
    }

    // MARK: Automatic install

    /// Installs the staged update the moment nothing would be lost by a
    /// relaunch; while a dictation is in flight, polls until it is not.
    private func installPendingUpdateWhenIdle() {
        pendingInstallRetry?.invalidate()
        pendingInstallRetry = nil
        guard let install = pendingInstall else { return }
        guard !isBusy() else {
            pendingInstallRetry = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.installPendingUpdateWhenIdle() }
            }
            return
        }
        pendingInstall = nil
        install()
    }

    /// The same idle gate covers a user-confirmed install that became unsafe
    /// after the update sheet opened; changing auto-update preferences does not
    /// cancel this user-initiated relaunch.
    private func resumeRelaunchWhenIdle() {
        postponedRelaunchRetry?.invalidate()
        postponedRelaunchRetry = nil
        guard let resume = postponedRelaunch else { return }
        guard !isBusy() else {
            postponedRelaunchRetry = Timer.scheduledTimer(withTimeInterval: 15, repeats: false) { [weak self] _ in
                Task { @MainActor in self?.resumeRelaunchWhenIdle() }
            }
            return
        }
        postponedRelaunch = nil
        resume()
    }

    /// The running app's marketing version (e.g. "0.4.2"), read from the bundle
    /// so the UI never hardcodes it.
    var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    /// Silent appcast probe: no Sparkle UI, just the delegate callbacks that
    /// tell the sidebar whether this build is the latest one.
    ///
    /// Skipped when the user has turned automatic updates off — that switch is
    /// an opt-out of background network checks, not just of silent installs —
    /// and while a check is already running, where Sparkle would ignore it.
    func refreshUpdateStatus() {
        guard controller.updater.automaticallyChecksForUpdates,
              !controller.updater.sessionInProgress else { return }
        loadedFreshAppcast = false
        status.begin()
        controller.updater.checkForUpdateInformation()
    }

    /// Manual "Check for Updates…" / "Check for updates now" — shows Sparkle's
    /// standard UI so an on-demand check always has clear feedback.
    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        // Sparkle focuses an existing update dialog instead of launching a
        // second session. Do not discard a result already received by it.
        if controller.updater.sessionInProgress {
            controller.checkForUpdates(nil)
            return
        }
        loadedFreshAppcast = false
        status.begin()
        controller.checkForUpdates(nil)
    }

    /// The sidebar's "Update" action. Sparkle owns the download, signature and
    /// notarization checks, and the relaunch, so this hands the user straight
    /// to that flow for the version the probe already found.
    func installAvailableUpdate() {
        guard updateAvailable, !isBusy() else { return }
        checkForUpdates()
    }

    /// Toggle automatic updates (Settings ▸ Automatic updates): both the daily
    /// scheduled check and the silent background download+install.
    func setAutomaticChecks(_ enabled: Bool) {
        apply(automatic: enabled)
        if enabled {
            refreshUpdateStatus()
            runScheduledCheckIfDue()
        } else {
            // A staged update whose immediate-install handler we already
            // accepted must finish: Sparkle stalls its cycle until called.
            // Turning off automatic checks prevents future checks/downloads,
            // not the already-accepted installation (also installed on quit).
            // The status was learned from a check the user has now opted out
            // of; stop asserting it rather than letting it go stale.
            status.invalidate()
        }
    }

    /// Drop what the last check established, so the footer falls back to the
    /// bare version instead of vouching for a build nothing verified.
    private func saveSuccessfulCheck() {
        UserDefaults.standard.set(status.lastSuccessfulCheckAt, forKey: Self.lastSuccessfulCheckKey)
    }

    /// "Automatic" means check on the schedule AND download+install in the
    /// background (installed on next relaunch). Sparkle requires downloads to be
    /// gated behind checks, so both flip together. Signature + notarization are
    /// still verified before any install.
    private func apply(automatic: Bool) {
        controller.updater.automaticallyChecksForUpdates = automatic
        controller.updater.automaticallyDownloadsUpdates = automatic
    }
}
