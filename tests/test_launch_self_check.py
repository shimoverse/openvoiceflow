"""Phase B2: ``validate_setup`` should surface FAILs as user-visible notifications.

The audit's UX_REVIEW.md theme C: every silent thing should have a place
to surface. ``validate_setup`` already prints to stderr; this test pins
that on FAIL it ALSO calls ``notify.error`` so menubar users — who never
see stderr — get a visible signal.
"""
from __future__ import annotations

import pytest


@pytest.fixture
def stub_validate_setup_inputs(monkeypatch, tmp_path):
    """Make validate_setup run against fake inputs so the test is hermetic."""
    import voiceflow.app as appmod

    # Build an OpenVoiceFlow instance with a synthetic config — no real recorder.
    monkeypatch.setattr(appmod, "AudioRecorder", lambda *a, **kw: object())

    return appmod


def test_validate_setup_fail_calls_notify_error(stub_validate_setup_inputs, monkeypatch) -> None:
    appmod = stub_validate_setup_inputs

    # whisper.cpp is missing → FAIL
    monkeypatch.setattr(appmod, "find_whisper_cpp", lambda: None)
    # model file path → missing
    monkeypatch.setattr(appmod, "get_model_path", lambda name: "/tmp/nope-no-such-file")
    monkeypatch.setattr(appmod.os.path, "exists", lambda p: False)

    notify_calls: list = []
    import voiceflow.notify as notify
    monkeypatch.setattr(
        notify, "error", lambda msg, **kw: notify_calls.append(("error", msg, kw))
    )
    monkeypatch.setattr(
        notify, "warn", lambda msg, **kw: notify_calls.append(("warn", msg, kw))
    )

    monkeypatch.setattr(
        appmod, "load_config",
        lambda: {"llm_backend": "none", "whisper_model": "base.en",
                 "sample_rate": 16000, "channels": 1},
    )

    vf = appmod.OpenVoiceFlow()
    ok = vf.validate_setup()

    assert ok is False, "missing whisper.cpp should make validate_setup return False"
    error_calls = [c for c in notify_calls if c[0] == "error"]
    assert error_calls, (
        f"validate_setup must call notify.error on FAIL; got: {notify_calls}"
    )


def test_validate_setup_pass_no_notify(stub_validate_setup_inputs, monkeypatch) -> None:
    appmod = stub_validate_setup_inputs

    # Stub the audio backend so the happy path is hermetic on hosts
    # without PortAudio (e.g. Linux CI).
    import sys
    import types
    monkeypatch.setitem(sys.modules, "sounddevice", types.ModuleType("sounddevice"))

    monkeypatch.setattr(appmod, "find_whisper_cpp", lambda: "/opt/homebrew/bin/whisper-cli")
    monkeypatch.setattr(appmod, "get_model_path", lambda name: "/fake/model")
    monkeypatch.setattr(appmod.os.path, "exists", lambda p: True)
    monkeypatch.setattr(appmod.os.path, "getsize", lambda p: 142_000_000)
    monkeypatch.setattr(
        appmod, "load_config",
        lambda: {"llm_backend": "none", "whisper_model": "base.en",
                 "sample_rate": 16000, "channels": 1},
    )

    notify_calls: list = []
    import voiceflow.notify as notify
    monkeypatch.setattr(notify, "error", lambda msg, **kw: notify_calls.append(("error", msg)))
    monkeypatch.setattr(notify, "warn", lambda msg, **kw: notify_calls.append(("warn", msg)))

    vf = appmod.OpenVoiceFlow()
    ok = vf.validate_setup()

    assert ok is True
    error_calls = [c for c in notify_calls if c[0] == "error"]
    assert not error_calls, f"happy path should not call notify.error; got: {error_calls}"


def test_validate_setup_accessibility_failure_links_to_settings(
    stub_validate_setup_inputs, monkeypatch
) -> None:
    """A missing Accessibility grant must provide a one-click settings URL."""
    appmod = stub_validate_setup_inputs

    monkeypatch.setattr(appmod, "find_whisper_cpp", lambda: "/opt/homebrew/bin/whisper-cli")
    monkeypatch.setattr(appmod, "get_model_path", lambda name: "/fake/model")
    monkeypatch.setattr(appmod.os.path, "exists", lambda p: True)
    monkeypatch.setattr(appmod.os.path, "getsize", lambda p: 142_000_000)
    monkeypatch.setattr(appmod, "_is_accessibility_trusted", lambda: False)
    monkeypatch.setattr(
        appmod,
        "load_config",
        lambda: {
            "llm_backend": "none",
            "whisper_model": "base.en",
            "sample_rate": 16000,
            "channels": 1,
        },
    )

    notify_calls: list = []
    import voiceflow.notify as notify

    monkeypatch.setattr(
        notify,
        "error",
        lambda msg, **kw: notify_calls.append((msg, kw)),
    )

    vf = appmod.OpenVoiceFlow()
    assert vf.validate_setup() is False
    assert notify_calls
    action = notify_calls[-1][1]["action"]
    assert action == (
        "Open Accessibility Settings",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
    )
