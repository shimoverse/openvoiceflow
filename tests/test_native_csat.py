"""Behavior contracts for the in-app satisfaction card (CsatView + CsatPrompt).

Support questions these prevent: "why is the app asking me to rate it on day
one?", "did it upload what I typed before I pressed Send?", and "I turned
sharing off — why is my rating tied to my leaderboard row?"
"""

import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
NATIVE_SOURCES = ROOT / "native" / "Sources" / "OpenVoiceFlow"


def _read(name: str) -> str:
    return (NATIVE_SOURCES / name).read_text(encoding="utf-8")


def test_prompt_waits_for_real_use_and_snoozes(tmp_path: Path) -> None:
    if shutil.which("xcrun") is None:
        pytest.skip("Swift contract requires the macOS Xcode toolchain")

    harness = tmp_path / "main.swift"
    harness.write_text(
        r"""
import Foundation

@main
struct Runner {
    static func main() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let day = 86_400.0
        let tenDaysIn = now.addingTimeInterval(-10 * day)

        func show(_ at: Date, first: Date?, takes: Int, next: Date?) -> Bool {
            CsatPrompt.shouldShow(now: at, firstUseDate: first, dictationsCompleted: takes, nextPromptAt: next)
        }

        // Enough use, never shown → show.
        precondition(show(now, first: tenDaysIn, takes: 10, next: nil))
        // Too few takes, or too new, or never dictated → no.
        precondition(!show(now, first: tenDaysIn, takes: 9, next: nil))
        precondition(!show(now, first: now.addingTimeInterval(-2 * day), takes: 50, next: nil))
        precondition(!show(now, first: nil, takes: 50, next: nil))
        // Exactly three days is enough.
        precondition(show(now, first: now.addingTimeInterval(-3 * day), takes: 10, next: nil))

        // Snoozed → no until the date passes.
        let dismissed = CsatPrompt.nextPrompt(afterDismissAt: now)
        precondition(dismissed.timeIntervalSince(now) == 30 * day)
        precondition(!show(now.addingTimeInterval(29 * day), first: tenDaysIn, takes: 99, next: dismissed))
        precondition(show(now.addingTimeInterval(30 * day), first: tenDaysIn, takes: 99, next: dismissed))
        // Sending snoozes longer than dismissing.
        let submitted = CsatPrompt.nextPrompt(afterSubmitAt: now)
        precondition(submitted > dismissed)
        precondition(submitted.timeIntervalSince(now) == 120 * day)
    }
}
""",
        encoding="utf-8",
    )
    binary = tmp_path / "csat-contract"
    result = subprocess.run(
        [
            "xcrun", "swiftc", "-parse-as-library",
            str(NATIVE_SOURCES / "CsatPrompt.swift"), str(harness), "-o", str(binary),
        ],
        text=True,
        capture_output=True,
        check=False,
    )
    assert result.returncode == 0, result.stderr
    run_result = subprocess.run([str(binary)], text=True, capture_output=True, check=False)
    assert run_result.returncode == 0, run_result.stderr


def test_card_is_offered_once_when_the_window_appears_and_never_mid_take() -> None:
    dashboard = _read("DashboardView.swift")
    offer = dashboard.split("private func offerCsatIfDue()", 1)[1].split("\n    }\n", 1)[0]

    assert "CsatPrompt.shouldShow(" in offer
    assert "controller.isRecording" in offer and "controller.isWorking" in offer
    # Snoozed when shown, so closing the window without touching the card is a "not now".
    assert "csatNextPromptAt = CsatPrompt.nextPrompt(afterDismissAt:" in offer
    assert "record(.csatShown)" in offer
    # Called from the window's onAppear, not from a timer or a pane change.
    on_appear = dashboard.split(".onAppear {", 1)[1].split("\n        }\n", 1)[0]
    assert "offerCsatIfDue()" in on_appear


def test_nothing_leaves_until_send_and_the_device_id_rides_the_sharing_toggle() -> None:
    view = _read("CsatView.swift")
    analytics = _read("AnalyticsStore.swift")

    # The only network call in the card is the one behind Send.
    assert view.count("submitCsat(") == 1
    send = view.split("private func send() async", 1)[1].split("\n    }\n", 1)[0]
    assert "submitCsat(" in send
    pick = view.split("private func pick(_ star: Int)", 1)[1].split("\n    }\n", 1)[0]
    assert "submitCsat" not in pick and "URLSession" not in view

    submit = analytics.split("func submitCsat(", 1)[1].split("\n    }\n", 1)[0]
    device_line = next(line for line in submit.splitlines() if '"deviceId"' in line)
    guard_line = submit.splitlines()[submit.splitlines().index(device_line) - 1]
    assert "controller.settings.shareAnalytics" in guard_line
    # Bounded before it leaves, like the display name.
    assert "prefix(CsatView.maxCommentLength)" in submit
    assert re.search(r"static let maxCommentLength = 1000", view)
    # Sending snoozes for a season and counts once.
    assert "CsatPrompt.nextPrompt(afterSubmitAt:" in send
    assert "record(.csatSubmitted)" in send


def test_celebration_respects_reduce_motion() -> None:
    dashboard = _read("DashboardView.swift")
    view = _read("CsatView.swift")

    celebrate = dashboard.split("publisher(for: .csatCelebrate)", 1)[1].split("\n        }\n", 1)[0]
    assert "guard !reduceMotion else { return }" in celebrate
    pulse = view.split("} else if star == 4", 1)[1].split("\n", 1)[0]
    assert "!reduceMotion" in pulse
    assert ".allowsHitTesting(false)" in view.split("struct ConfettiBurst", 1)[1]


def test_privacy_policy_documents_the_rating_card() -> None:
    privacy = (ROOT / "PRIVACY.md").read_text(encoding="utf-8")
    section = privacy.split("**Rating the app", 1)[1].split("**Sharing OpenVoiceFlow.**", 1)[0]
    for phrase in (
        "press **Send**", "1,000 characters", "device ID", "never shown publicly", "Delete my leaderboard data",
    ):
        assert phrase in section, phrase
