"""Regression contracts for the native feedback and Personalize UX."""

import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
NATIVE_SOURCES = ROOT / "native" / "Sources" / "OpenVoiceFlow"


def source(name: str) -> str:
    return (NATIVE_SOURCES / name).read_text(encoding="utf-8")


def test_feedback_uses_an_always_visible_optional_email_field() -> None:
    feedback = source("FeedbackView.swift")

    assert 'TextField("Email (optional)", text: $contact)' in feedback
    assert "includeContact" not in feedback
    assert "contact: contact.trimmingCharacters(in: .whitespacesAndNewlines)" in feedback


def test_feedback_uses_a_centered_native_modal() -> None:
    dashboard = source("DashboardView.swift")
    feedback = source("FeedbackView.swift")

    assert ".sheet(isPresented: $showFeedback)" in dashboard
    assert ".popover(isPresented: $showFeedback)" not in dashboard
    assert "private var feedbackOverlay" not in dashboard
    assert "FeedbackView(controller: controller, onDismiss:" in dashboard
    assert "let onDismiss: () -> Void" in feedback


def test_know_me_is_a_personalize_tab_not_a_sidebar_pane() -> None:
    dashboard = source("DashboardView.swift")

    pane_block = dashboard.split("enum Pane:", 1)[1].split("enum PersonalizeTab:", 1)[0]
    tab_block = dashboard.split("enum PersonalizeTab:", 1)[1].split("private var dark:", 1)[0]

    assert "case knowMe" not in pane_block
    assert 'case knowMe = "Know Me"' in tab_block
    assert "case .knowMe: knowMe" in dashboard


def test_leaderboard_alias_is_one_token_and_migrates_only_legacy_defaults(tmp_path: Path) -> None:
    if shutil.which("xcrun") is None:
        pytest.skip("Swift contract requires the macOS Xcode toolchain")

    alias_source = NATIVE_SOURCES / "LeaderboardAlias.swift"
    harness = tmp_path / "main.swift"
    harness.write_text(
        """
import Foundation

precondition(LeaderboardAlias.make(adjective: "Keen", noun: "Coral", number: 13) == "KeenCoral13")
precondition(LeaderboardAlias.compactLegacyDefault("Keen Coral 13") == "KeenCoral13")
precondition(LeaderboardAlias.compactLegacyDefault("Mohit Jain") == "Mohit Jain")
precondition(LeaderboardAlias.compactLegacyDefault("keen coral 13") == "keen coral 13")
precondition(LeaderboardAlias.compactLegacyDefault("Keen Coral 13 ") == "Keen Coral 13 ")
precondition(LeaderboardAlias.compactLegacyDefault("Keen\\tCoral\\t13") == "Keen\\tCoral\\t13")
precondition(LeaderboardAlias.compactLegacyDefault("Keen  Coral 13") == "Keen  Coral 13")
for _ in 0..<100 {
    precondition(!LeaderboardAlias.random().contains(where: { $0.isWhitespace }))
}
print("ok")
""",
        encoding="utf-8",
    )
    binary = tmp_path / "alias-contract"

    compile_result = subprocess.run(
        ["xcrun", "swiftc", str(alias_source), str(harness), "-o", str(binary)],
        text=True,
        capture_output=True,
        check=False,
    )
    assert compile_result.returncode == 0, compile_result.stderr

    run_result = subprocess.run([str(binary)], text=True, capture_output=True, check=False)
    assert run_result.returncode == 0, run_result.stderr
    assert run_result.stdout.strip() == "ok"

    analytics = source("AnalyticsStore.swift")
    assert "LeaderboardAlias.compactLegacyDefault" in analytics
    assert "LeaderboardAlias.random()" in analytics
