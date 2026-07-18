"""The Fn / Globe key can't be a hotkey (pynput has no fn on macOS), so the
app must (a) surface that immediately via the modal path, not a slow
suppressible tip, and (b) not offer fn in the picker unless it's already set.
"""
from __future__ import annotations

from voiceflow.config import DEFAULTS


def _make_app(monkeypatch):
    import voiceflow.app as appmod

    monkeypatch.setattr(appmod, "AudioRecorder", lambda *a, **k: object())
    monkeypatch.setattr(appmod, "load_config", lambda: dict(DEFAULTS))
    return appmod.OpenVoiceFlow(use_overlay=False)


def test_fn_hotkey_surfaces_immediately_through_modal(monkeypatch) -> None:
    app = _make_app(monkeypatch)
    app.config["hotkey"] = "left_fn"
    app._fn_probe_started = False

    modal_messages: list = []
    app.start_hotkey_runtime_checks(on_dead_hotkey=lambda m: modal_messages.append(m))

    assert modal_messages, "fn hotkey must be surfaced synchronously, not after a 12s watch"
    assert "Right Command" in modal_messages[0]
    assert "Fn" in modal_messages[0] or "Globe" in modal_messages[0]


def test_non_fn_hotkey_does_not_fire_the_fn_modal(monkeypatch) -> None:
    app = _make_app(monkeypatch)
    app.config["hotkey"] = "right_cmd"
    app._fn_probe_started = False

    modal_messages: list = []
    app.start_hotkey_runtime_checks(on_dead_hotkey=lambda m: modal_messages.append(m))
    assert modal_messages == []


def test_hotkey_picker_hides_fn_unless_it_is_current() -> None:
    from voiceflow.menubar import _hotkey_choices

    ids = [h for h, _, _ in _hotkey_choices("right_cmd")]
    assert "left_fn" not in ids, "fn must not be offered as a fresh choice"

    ids_when_set = [h for h, _, _ in _hotkey_choices("left_fn")]
    assert "left_fn" in ids_when_set, "must still show fn (marked) so a stuck user can switch off it"


def test_onboarding_does_not_offer_fn() -> None:
    import inspect

    from voiceflow import onboarding

    src = inspect.getsource(onboarding)
    # The selectable onboarding hotkey list must not include the fn option.
    assert '("left_fn"' not in src
