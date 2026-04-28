"""Phase C2: voice-command tutor (one-shot educational nudge).

Background — UX_REVIEW.md Theme B (educate via micro-moments, not docs):
v0.2 ships 24 voice commands but a lazy user never discovers them. This
test pins the heuristic + the once_key contract:

  - If voice commands DID fire on this dictation, show a positive
    reinforcement tip ("✓ OpenVoiceFlow heard a voice command…") with
    once_key="voice_command_first_fire" — the user sees evidence that
    the magic happened.
  - If voice commands DIDN'T fire but the raw whisper transcript
    contains a punctuation phoneme ("comma", "period", "question mark",
    "new paragraph"), show an educational tip
    once_key="voice_commands_intro" — the user learns the commands
    exist on the very dictation where they would have benefited.
  - Both tips fire ONCE total, ever (the once_key persists in
    ~/.openvoiceflow/_seen_tips.json).
"""
from __future__ import annotations

import pytest


def test_punct_phoneme_detection() -> None:
    from voiceflow.app import _has_punct_phoneme

    # Positive cases
    assert _has_punct_phoneme("hello comma world")
    assert _has_punct_phoneme("comma in middle")
    assert _has_punct_phoneme("end with period.")
    assert _has_punct_phoneme("a question mark would help")
    assert _has_punct_phoneme("new paragraph please")
    assert _has_punct_phoneme("FULL STOP at end")  # case-insensitive

    # Negative cases — substrings shouldn't trigger (word-boundary check)
    assert not _has_punct_phoneme("uncommandable")  # 'comma' is inside the word
    assert not _has_punct_phoneme("hello world")
    assert not _has_punct_phoneme("")
    # NOTE: "the period of time" intentionally false-positives. Distinguishing
    # "period" the command from "period" the noun would need real NLU; the
    # cost of the false positive is one one-shot tip notification, which the
    # user can ignore. Trade-off accepted in v0.3.x.


def test_tutor_fires_positive_on_command_match(monkeypatch) -> None:
    """When apply_commands actually substituted, fire the positive tip."""
    from voiceflow.app import _maybe_voice_command_tutor

    tip_calls: list[dict] = []
    import voiceflow.notify as notify
    monkeypatch.setattr(
        notify, "tip",
        lambda msg, once_key=None, **kw: tip_calls.append({"msg": msg, "once_key": once_key}),
    )

    _maybe_voice_command_tutor(
        text_before="hello comma world",
        text_after="hello, world",  # commands fired
    )

    assert len(tip_calls) == 1
    assert tip_calls[0]["once_key"] == "voice_command_first_fire"


def test_tutor_fires_intro_on_unfired_phoneme(monkeypatch) -> None:
    """When raw text had a phoneme but commands didn't fire, fire the intro tip."""
    from voiceflow.app import _maybe_voice_command_tutor

    tip_calls: list[dict] = []
    import voiceflow.notify as notify
    monkeypatch.setattr(
        notify, "tip",
        lambda msg, once_key=None, **kw: tip_calls.append({"msg": msg, "once_key": once_key}),
    )

    # commands disabled by config; both before/after are identical
    _maybe_voice_command_tutor(
        text_before="hello comma world",
        text_after="hello comma world",
    )

    assert len(tip_calls) == 1
    assert tip_calls[0]["once_key"] == "voice_commands_intro"


def test_tutor_silent_when_no_phoneme(monkeypatch) -> None:
    """No phoneme + no firing → no tip."""
    from voiceflow.app import _maybe_voice_command_tutor

    tip_calls: list = []
    import voiceflow.notify as notify
    monkeypatch.setattr(notify, "tip", lambda *a, **kw: tip_calls.append((a, kw)))

    _maybe_voice_command_tutor(
        text_before="just a normal sentence",
        text_after="just a normal sentence",
    )

    assert tip_calls == []
