"""Behavior contracts for native leaderboard identity and failure handling."""

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
    assert r"ForEach(Array(board.top.enumerated()), id: \.offset)" in dashboard

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
