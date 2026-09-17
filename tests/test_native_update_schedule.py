"""Behavior contracts for the daily automatic update: 3 PM Pacific, installed while idle.

Support question these prevent: "I turned on automatic updates, why am I still
on last month's build until I click Check for Updates?" Sparkle downloads
silently but installs *on quit*, and a menu-bar app never quits — the update
sat staged until Sparkle's week-long impatient interval finally asked.
"""

import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
NATIVE_SOURCES = ROOT / "native" / "Sources" / "OpenVoiceFlow"


def _updater_source() -> str:
    return (NATIVE_SOURCES / "Updater.swift").read_text(encoding="utf-8")


def test_schedule_is_three_pm_pacific_with_catch_up(tmp_path: Path) -> None:
    """A deadline that passed while the Mac was off is due at the next launch."""
    if shutil.which("xcrun") is None:
        pytest.skip("Swift contract requires the macOS Xcode toolchain")

    harness = tmp_path / "main.swift"
    harness.write_text(
        r"""
import Foundation

@main
struct Runner {
    static func main() {
        let iso = ISO8601DateFormatter()
        func at(_ s: String) -> Date { iso.date(from: s)! }

        // 2026-09-16 is PDT (UTC-7): 3 PM Pacific is 22:00Z.
        let deadline = at("2026-09-16T22:00:00Z")
        precondition(UpdateSchedule.lastDeadline(before: at("2026-09-16T23:00:00Z")) == deadline)
        precondition(UpdateSchedule.nextDeadline(after: at("2026-09-16T23:00:00Z")) == at("2026-09-17T22:00:00Z"))
        // Before today's 3 PM, the last deadline is yesterday's and the next is today's.
        precondition(UpdateSchedule.lastDeadline(before: at("2026-09-16T20:00:00Z")) == at("2026-09-15T22:00:00Z"))
        precondition(UpdateSchedule.nextDeadline(after: at("2026-09-16T20:00:00Z")) == deadline)
        // Exactly at the deadline counts as passed.
        precondition(UpdateSchedule.lastDeadline(before: deadline) == deadline)

        // Never checked → due. Checked this morning, launched at 4 PM → due.
        precondition(UpdateSchedule.isCheckDue(now: at("2026-09-16T23:00:00Z"), lastCheck: nil))
        precondition(UpdateSchedule.isCheckDue(now: at("2026-09-16T23:00:00Z"), lastCheck: at("2026-09-16T16:00:00Z")))
        // Checked at 3:01 PM, still the same afternoon → not due again.
        precondition(!UpdateSchedule.isCheckDue(now: at("2026-09-16T23:00:00Z"), lastCheck: at("2026-09-16T22:01:00Z")))
        // Off for three days → due once, not three times.
        precondition(UpdateSchedule.isCheckDue(now: at("2026-09-19T01:00:00Z"), lastCheck: at("2026-09-16T22:01:00Z")))

        // Pacific is the zone, not an offset: in December (PST, UTC-8) 3 PM is 23:00Z.
        precondition(UpdateSchedule.nextDeadline(after: at("2026-12-10T12:00:00Z")) == at("2026-12-10T23:00:00Z"))
    }
}
""",
        encoding="utf-8",
    )
    binary = tmp_path / "schedule-contract"
    result = subprocess.run(
        [
            "xcrun",
            "swiftc",
            "-parse-as-library",
            str(NATIVE_SOURCES / "UpdateSchedule.swift"),
            str(harness),
            "-o",
            str(binary),
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    run_result = subprocess.run([str(binary)], text=True, capture_output=True, check=False)
    assert run_result.returncode == 0, run_result.stderr


def test_scheduled_check_uses_the_downloading_driver_and_survives_sleep() -> None:
    """The deadline check must stage the update, not just look, and re-arm on wake."""
    source = _updater_source()
    body = source.split("func runScheduledCheckIfDue(", 1)[1].split("// MARK: Automatic install", 1)[0]

    assert "UpdateSchedule.isCheckDue(" in body
    # checkForUpdateInformation only probes; the background check is the one
    # that downloads under SUAutomaticallyUpdate.
    assert "checkForUpdatesInBackground()" in body
    assert "checkForUpdateInformation()" not in body
    assert "UpdateSchedule.nextDeadline(" in body
    # Timers that sleep through their fire date are not reliable; wake re-runs it.
    assert "NSWorkspace.didWakeNotification" in source
    # The opt-out silences the schedule too.
    assert "guard controller.updater.automaticallyChecksForUpdates else { return }" in body


def test_staged_update_installs_without_waiting_for_quit() -> None:
    """Take Sparkle's install-on-quit handoff and fire it once the app is idle."""
    source = _updater_source()

    hook = source.split("willInstallUpdateOnQuit", 1)[1].split("\n    }\n", 1)[0]
    assert "return true" in hook, "returning false leaves the install waiting on a quit that never comes"

    install = source.split("private func installPendingUpdateWhenIdle()", 1)[1].split("\n    }\n", 1)[0]
    assert "isBusy()" in install, "a relaunch mid-dictation would lose the take"
    assert "pendingInstall = nil" in install.split("install()", 1)[0], "the handler must fire once"

    app = (NATIVE_SOURCES / "OpenVoiceFlowApp.swift").read_text(encoding="utf-8")
    busy = app.split("UpdaterController.shared.isBusy = {", 1)[1].split("\n        }\n", 1)[0]
    assert "isRecording" in busy and "isWorking" in busy


def test_sparkle_interval_is_only_a_safety_net() -> None:
    """The plist must not also run a competing daily check."""
    plist = (ROOT / "native" / "Info.plist").read_text(encoding="utf-8")
    assert "<key>SUAutomaticallyUpdate</key><true/>" in plist
    assert "<key>SUScheduledCheckInterval</key><integer>604800</integer>" in plist
