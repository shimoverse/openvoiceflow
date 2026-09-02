"""Behavior contracts for native leaderboard identity and failure handling."""

import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
NATIVE_SOURCES = ROOT / "native" / "Sources" / "OpenVoiceFlow"


def test_leaderboard_display_name_normalizes_once_at_commit(tmp_path: Path) -> None:
    """Client normalization must match the server's public-name boundary."""
    if shutil.which("xcrun") is None:
        pytest.skip("Swift contract requires the macOS Xcode toolchain")

    harness = tmp_path / "main.swift"
    harness.write_text(
        r"""
import Foundation

@main
struct Runner {
    static func main() {
        precondition(LeaderboardDisplayName.normalize("  Mac Mini  ") == "Mac Mini")
        precondition(LeaderboardDisplayName.normalize("A\nB") == "AB")
        precondition(LeaderboardDisplayName.normalize("   ") == nil)
        precondition(LeaderboardDisplayName.normalize(String(repeating: "x", count: 45))?.count == 40)
    }
}
""",
        encoding="utf-8",
    )
    binary = tmp_path / "name-contract"
    result = subprocess.run(
        [
            "xcrun",
            "swiftc",
            "-parse-as-library",
            str(NATIVE_SOURCES / "LeaderboardDisplayName.swift"),
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


def test_nickname_commit_syncs_once_and_failures_are_retryable() -> None:
    """The field must not upload keystrokes or hide a failed leaderboard request."""
    dashboard = (NATIVE_SOURCES / "DashboardView.swift").read_text(encoding="utf-8")
    analytics = (NATIVE_SOURCES / "AnalyticsStore.swift").read_text(encoding="utf-8")

    assert "@State private var leaderboardNameDraft" in dashboard
    assert "@FocusState private var leaderboardNameFocused" in dashboard
    assert 'TextField("Display name", text: $leaderboardNameDraft)' in dashboard
    assert ".onSubmit { commitLeaderboardName() }" in dashboard
    assert ".onChange(of: leaderboardNameFocused)" in dashboard
    assert "func commitLeaderboardName()" in dashboard
    assert "await analyticsClient.syncNow(controller: controller)" in dashboard
    assert "await analyticsClient.fetchLeaderboard" in dashboard
    assert 'button: "Try again"' in dashboard
    assert "analyticsClient.leaderboardError" in dashboard
    assert "analyticsClient.syncError" in dashboard
    assert "displayNameBinding" not in dashboard
    assert r"ForEach(Array(revealed.enumerated()), id: \.offset)" in dashboard

    assert "@Published private(set) var leaderboardError: String?" in analytics
    assert "@Published private(set) var syncError: String?" in analytics
    assert "func syncNow(controller: AppController) async -> Bool" in analytics
    assert "(200..<300).contains(http.statusCode)" in analytics


def test_opening_leaderboard_republishes_saved_totals_before_fetching() -> None:
    """Existing installations must restore their row without another dictation."""
    dashboard = (NATIVE_SOURCES / "DashboardView.swift").read_text(encoding="utf-8")

    pane = dashboard.split("@ViewBuilder private var leaderboardPane", 1)[1].split(
        "@ViewBuilder private func leaderboardCard", 1
    )[0]
    refresh = dashboard.split("private func refreshLeaderboard() async", 1)[1].split(
        "private func commitLeaderboardName()", 1
    )[0]

    assert "await refreshLeaderboard()" in pane
    assert refresh.index("await analyticsClient.syncNow(controller: controller)") < refresh.index(
        "await analyticsClient.fetchLeaderboard"
    )


def _masked_tail_source(dashboard: str, *, code_only: bool = False) -> str:
    """The body of MaskedBoardTail, optionally with comments stripped."""
    body = dashboard.split("private struct MaskedBoardTail: View", 1)[1].split(
        "\n/// A single-field", 1
    )[0]
    if not code_only:
        return body
    return "\n".join(
        line for line in body.splitlines() if not line.lstrip().startswith("//")
    )


def test_board_height_never_doubles_as_a_headcount() -> None:
    """A card sized to the response publishes the user count the API hides.

    api/leaderboard.js caps and filters rows so the endpoint can't be counted.
    Rendering exactly what came back gave that straight back to anyone looking
    at the window: four rows read as four users. The card holds a fixed number
    of slots and masks the rest.
    """
    dashboard = (NATIVE_SOURCES / "DashboardView.swift").read_text(encoding="utf-8")

    assert "private static let boardSlots = 7" in dashboard
    assert "MaskedBoardTail(count: Self.boardSlots - revealed.count," in dashboard
    assert "private struct MaskedBoardTail: View" in dashboard
    assert "Array(board.top.prefix(Self.boardSlots))" in dashboard


def test_masked_rows_withhold_rather_than_invent() -> None:
    """The tail must never render a name, a rank or a total.

    A masked slot stands for a withheld entry. The moment it can draw text it
    can draw a person who isn't there, which is a different product — and a
    dishonest one — from a board that declines to name everyone.
    """
    dashboard = (NATIVE_SOURCES / "DashboardView.swift").read_text(encoding="utf-8")
    tail = _masked_tail_source(dashboard, code_only=True)

    assert "Text(" not in tail, "masked leaderboard rows must not render text"
    assert "displayName" not in tail
    assert "minutesSaved" not in tail
    assert "row.rank" not in tail and "you.rank" not in tail


def test_masked_tail_respects_reduce_motion() -> None:
    """The shimmer is decoration; it stops when the system asks it to."""
    dashboard = (NATIVE_SOURCES / "DashboardView.swift").read_text(encoding="utf-8")
    tail = _masked_tail_source(dashboard)

    assert r"@Environment(\.accessibilityReduceMotion) private var reduceMotion" in tail
    assert "if reduceMotion {" in tail
    assert "rows(t: 0)" in tail


def test_card_does_not_publish_the_reveal_threshold() -> None:
    """Naming the bar lets a reader turn visible names back into a population.

    api/leaderboard.js reveals only rows past REVEAL_MINUTES_SAVED. Printing
    that bar in the card would have told anyone counting the names exactly what
    they were counting — people past an hour — which is most of the way back to
    the headcount the fixed-height board is there to hide.
    """
    dashboard = (NATIVE_SOURCES / "DashboardView.swift").read_text(encoding="utf-8")
    pane = dashboard.split("// MARK: Leaderboard", 1)[1].split("// MARK: Personalize", 1)[0]
    strings = re.findall(r'Text\("((?:[^"\\]|\\.)*)"', pane)

    for shown in strings:
        assert "hour" not in shown.lower(), f"card copy states the reveal bar: {shown!r}"
        assert "60" not in shown, f"card copy states the reveal bar: {shown!r}"
