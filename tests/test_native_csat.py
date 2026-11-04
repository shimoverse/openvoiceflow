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

        func show(_ at: Date, first: Date?, takes: Int, next: Date?, submitted: Date? = nil) -> Bool {
            CsatPrompt.shouldShow(now: at, firstUseDate: first, dictationsCompleted: takes,
                                  nextPromptAt: next, submittedAt: submitted)
        }

        // Enough use, never shown → show.
        precondition(show(now, first: tenDaysIn, takes: 10, next: nil))
        // Too few takes, or too new, or never dictated → no.
        precondition(!show(now, first: tenDaysIn, takes: 9, next: nil))
        precondition(!show(now, first: now.addingTimeInterval(-2 * day), takes: 50, next: nil))
        precondition(!show(now, first: nil, takes: 50, next: nil))
        // Exactly three days is enough.
        precondition(show(now, first: now.addingTimeInterval(-3 * day), takes: 10, next: nil))

        // An actual impression, not an eligibility check, starts a 24-hour interval.
        precondition(show(now, first: tenDaysIn, takes: 10, next: nil))
        let shown = CsatPrompt.nextPrompt(afterShownAt: now)
        precondition(shown.timeIntervalSince(now) == day)
        precondition(!show(now.addingTimeInterval(day - 1), first: tenDaysIn, takes: 99, next: shown))
        precondition(show(now.addingTimeInterval(day), first: tenDaysIn, takes: 99, next: shown))
        // An ignored card recurs at the next opportunity, even across relaunches.
        struct Persisted: Codable { var nextPromptAt: Date? }
        let restored = try! JSONDecoder().decode(Persisted.self, from: JSONEncoder().encode(Persisted(nextPromptAt: shown)))
        precondition(!show(now, first: tenDaysIn, takes: 99, next: restored.nextPromptAt))
        precondition(show(now.addingTimeInterval(day), first: tenDaysIn, takes: 99, next: restored.nextPromptAt))

        // Explicit dismissal gets a 15-day snooze, inclusive at its boundary.
        let dismissed = CsatPrompt.nextPrompt(afterDismissAt: now)
        precondition(dismissed.timeIntervalSince(now) == 15 * day)
        precondition(!show(now.addingTimeInterval(15 * day - 1), first: tenDaysIn, takes: 99, next: dismissed))
        precondition(show(now.addingTimeInterval(15 * day), first: tenDaysIn, takes: 99, next: dismissed))

        // A successful submission permanently excludes automatic prompts,
        // including after the old four-month cooldown and a settings round trip.
        let submitted = try! JSONDecoder().decode(PersistedSubmission.self,
            from: JSONEncoder().encode(PersistedSubmission(submittedAt: now))).submittedAt
        precondition(!show(now.addingTimeInterval(500 * day), first: tenDaysIn,
                           takes: 99, next: nil, submitted: submitted))
        // Only the old confirmed-submission counter permits migration; a legacy
        // dismissal timestamp alone never masquerades as a successful send.
        precondition(CsatPrompt.confirmedSubmissionAt(submittedAt: nil, legacySubmitCount: 0,
                       legacyNextPromptAt: dismissed) == nil)
        let legacy = now.addingTimeInterval(120 * day)
        precondition(CsatPrompt.confirmedSubmissionAt(submittedAt: nil, legacySubmitCount: 1,
                       legacyNextPromptAt: legacy) != nil)
        precondition(CsatPrompt.confirmedSubmissionAt(submittedAt: now, legacySubmitCount: 0,
                       legacyNextPromptAt: nil) == now)
        // Network rejection/timeout cannot create the permanent success marker;
        // a retry can succeed without treating its failed predecessor as success.
        precondition(CsatPrompt.submissionDate(accepted: false, at: now) == nil)
        precondition(CsatPrompt.submissionDate(accepted: true, at: now) == now)
    }

    private struct PersistedSubmission: Codable {
        var submittedAt: Date?
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


def test_card_is_offered_only_in_active_dashboard_and_never_mid_take() -> None:
    dashboard = _read("DashboardView.swift")
    offer = dashboard.split("private func offerCsatIfDue()", 1)[1].split("\n    }\n", 1)[0]

    assert "CsatPrompt.shouldShow(" in offer
    assert "controller.isRecording" in offer and "controller.isWorking" in offer
    assert "guard !showCsat" in offer
    assert "NSApp.isActive" in offer
    assert "csatNextPromptAt =" not in offer.split("guard forced ||", 1)[1]
    card = dashboard.split("CsatView(controller: controller)", 1)[1].split(".padding(20)", 1)[0]
    assert ".onAppear" in card
    assert "CsatPrompt.nextPrompt(afterShownAt:" in card
    assert "record(.csatPromptShown)" in card
    assert "csatSubmittedAt" in offer
    # Called from window appearance and app reactivation, not a timer that fronts it.
    on_appear = dashboard.split(".onAppear {\n            updater.refreshUpdateStatus()", 1)[1].split("\n        }\n", 1)[0]
    assert "offerCsatIfDue()" in on_appear
    assert "NSApplication.didBecomeActiveNotification" in dashboard
    assert "NSWindow.didBecomeKeyNotification" in dashboard


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
    # Attempts/failures do not mark a confirmed submission; accepted responses do.
    assert "record(.csatSubmitAttempted)" in send
    assert "record(.csatSubmitFailed)" in send
    assert "record(.csatSubmitSucceeded)" in send
    assert send.index("submissionDate(accepted: ok") < send.index("csatSubmittedAt =")
    assert "csatNextPromptAt = CsatPrompt.nextPrompt(afterDismissAt:" in view
    assert "record(.csatPromptDismissed)" in view
    assert "csatNextPromptAt" in _read("Settings.swift")
    assert "csatSubmittedAt = try c.decodeIfPresent" in _read("Settings.swift")


def test_prompt_event_wire_keys_are_closed_aggregate_counters() -> None:
    counters = _read("UsageCounters.swift")
    for name, key in (
        ("csatPromptShown", "csat_prompt_shown"),
        ("csatPromptDismissed", "csat_prompt_dismissed"),
        ("csatSubmitAttempted", "csat_submit_attempted"),
        ("csatSubmitSucceeded", "csat_submit_succeeded"),
        ("csatSubmitFailed", "csat_submit_failed"),
    ):
        assert f'case {name} = "{key}"' in counters
    analytics = _read("AnalyticsStore.swift")
    assert 'guard controller.settings.shareAnalytics else { return false }' in analytics
    assert '"events": controller.usageCounters.payload' in analytics


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
