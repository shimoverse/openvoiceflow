"""Contracts for the sidebar's version/update footer.

The footer used to read "v0.5.20 · auto-updating" whether or not the running
build was actually the latest one — a status that told the user nothing they
could act on. The footer now distinguishes verified current, available,
checking, failed and unverified results, with a manual CTA in every state.
The executable Swift lifecycle contract owns the result transitions.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NATIVE_SOURCES = ROOT / "native" / "Sources" / "OpenVoiceFlow"


def source(name: str) -> str:
    return (NATIVE_SOURCES / name).read_text(encoding="utf-8")


def test_updater_probes_the_appcast_for_the_latest_version() -> None:
    updater = source("Updater.swift")

    # A silent probe (no Sparkle UI) is what tells the footer whether this
    # build is current.
    assert "func refreshUpdateStatus()" in updater
    assert "controller.updater.checkForUpdateInformation()" in updater
    # Sparkle reports the result through its delegate.
    assert "SPUUpdaterDelegate" in updater
    assert "didFindValidUpdate item: SUAppcastItem" in updater
    assert "func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error)" in updater


def test_updater_publishes_the_state_the_footer_renders() -> None:
    updater = source("Updater.swift")

    assert "@Published private(set) var status = UpdateCheckStatus(" in updater
    assert "var updateAvailable: Bool" in updater
    assert "var hasCheckedForUpdates: Bool" in updater
    assert "var availableVersion: String?" in updater
    assert "func installAvailableUpdate()" in updater


def test_a_failed_probe_drops_the_status_it_could_not_verify() -> None:
    """No network (or an unparseable appcast) must not read as "Up to date"."""
    updater = source("Updater.swift")

    # Sparkle reports a check that ended badly through didAbortWithError —
    # neither didFindValidUpdate nor updaterDidNotFindUpdate runs.
    assert "func updater(_ updater: SPUUpdater, didAbortWithError error: any Error)" in updater
    assert "self?.status.aborted(expectedNoUpdate: expectedNoUpdate, userCanceled: userCanceled)" in updater
    assert "self?.status.finished(errorOccurred: errorOccurred)" in updater
    # Swift executable tests prove that an abort before any result fails and
    # the normal no-update abort retains an actual successful result.
    assert "status.begin()" in updater


def test_probe_respects_the_automatic_updates_opt_out() -> None:
    """The switch is an opt-out of background checks, not just of installs."""
    updater = source("Updater.swift")

    assert "guard controller.updater.automaticallyChecksForUpdates," in updater
    assert "!controller.updater.sessionInProgress else { return }" in updater


def test_footer_offers_update_only_when_one_is_available() -> None:
    dashboard = source("DashboardView.swift")

    assert "auto-updating" not in dashboard
    assert "private var versionFooter: some View" in dashboard
    assert "if updater.updateAvailable {" in dashboard
    assert 'Button("Update") { updater.installAvailableUpdate() }' in dashboard
    assert '.disabled(!updater.canCheckForUpdates || updater.isBusy())' in dashboard


def test_footer_keeps_check_action_in_every_state_and_reserves_current_label() -> None:
    dashboard = source("DashboardView.swift")

    footer = dashboard.split("private var versionFooter: some View", 1)[1].split("private var updateStatusLabel", 1)[0]
    assert 'Button("Check for updates")' in footer
    assert 'updater.checkForUpdates()' in footer
    assert 'Last checked ' in footer
    assert 'Never checked' in footer
    labels = dashboard.split("private var updateStatusLabel", 1)[1].split("// MARK: content router", 1)[0]
    assert 'case .current: return "Up to date"' in labels
    assert 'case .failed: return "Check failed"' in labels
    assert 'case .unverified: return "Not verified"' in labels


def test_dashboard_refreshes_update_status_when_it_appears() -> None:
    """The footer must re-probe the appcast when the window comes back, or it
    reports whatever was true at launch. Asserted on the call inside `.onAppear`
    rather than on an exact one-line spelling, so adding another statement to
    that block doesn't read as removing this one."""
    dashboard = source("DashboardView.swift")

    body = dashboard.split("var body: some View", 1)[1]
    # The CSAT overlay also has an appearance hook; find the dashboard's
    # lifecycle hook rather than assuming the first nested hook belongs to it.
    on_appear = body.split("\n        .onAppear {", 1)[1].split("\n        }", 1)[0]
    assert "updater.refreshUpdateStatus()" in on_appear
