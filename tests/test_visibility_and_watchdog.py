"""Visibility & dead-hotkey fixes: the app must never look Ready while dead.

Root cause pinned here: to capture the global hotkey, pynput needs macOS
Input Monitoring; without it the listener starts cleanly and then receives
NOTHING — the menu said "Ready — Hold ⌘" while the hotkey was silently
dead, and validate_setup never checked Input Monitoring at all (the doctor
did, the startup gate didn't).

Design rules pinned by these tests:
  - Input Monitoring denied → warn loudly, NEVER block (Accessibility trust
    often also grants listen access, so a denied probe can be a false
    negative — a hard gate would strand working setups).
  - The dead-listener watchdog escalates only when the static probe AND
    reality agree (no key events at all); an idle user alone gets a gentle
    one-time tip, not an alarm.
"""
from __future__ import annotations

import types

import pytest


@pytest.fixture
def app_module(monkeypatch):
    """voiceflow.app with a stubbed recorder + happy-path validate inputs."""
    import sys

    import voiceflow.app as appmod

    monkeypatch.setattr(appmod, "AudioRecorder", lambda *a, **kw: object())
    monkeypatch.setattr(
        appmod, "load_config",
        lambda: {"llm_backend": "none", "whisper_model": "base.en",
                 "sample_rate": 16000, "channels": 1, "hotkey": "right_cmd"},
    )
    monkeypatch.setattr(appmod, "find_whisper_cpp", lambda: "/opt/homebrew/bin/whisper-cli")
    monkeypatch.setattr(appmod, "get_model_path", lambda name: "/fake/model")
    monkeypatch.setattr(appmod.os.path, "exists", lambda p: True)
    monkeypatch.setattr(appmod.os.path, "getsize", lambda p: 142_000_000)
    monkeypatch.setattr(appmod, "_is_accessibility_trusted", lambda: True)
    monkeypatch.setitem(sys.modules, "sounddevice", types.ModuleType("sounddevice"))
    return appmod


@pytest.fixture
def notify_calls(monkeypatch):
    """Record every notify call as (kind, message, kwargs)."""
    import voiceflow.notify as notify

    calls: list = []
    for kind in ("error", "warn", "tip"):
        monkeypatch.setattr(
            notify, kind,
            lambda msg, *, _kind=kind, **kw: calls.append((_kind, msg, kw)),
        )
    return calls


# ─────────────────────────────────────────────────────────────────────
# validate_setup: Input Monitoring is checked, loudly, but never blocks
# ─────────────────────────────────────────────────────────────────────


def test_input_monitoring_denied_warns_but_does_not_block(
    app_module, notify_calls, monkeypatch
) -> None:
    monkeypatch.setattr(
        app_module.platform_support, "input_monitoring_status", lambda: False
    )
    vf = app_module.OpenVoiceFlow()
    assert vf.validate_setup() is True, "a denied probe must never block startup"
    assert any(kind == "input_monitoring" for kind, _ in vf.setup_warnings)
    warns = [c for c in notify_calls if c[0] == "warn"]
    assert warns, "denied Input Monitoring must produce a visible warning"
    assert warns[-1][2]["action"] == (
        "Open Input Monitoring Settings",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
    )


def test_input_monitoring_unknown_stays_silent(
    app_module, notify_calls, monkeypatch
) -> None:
    """None (cannot probe — e.g. Linux CI) is not a warning."""
    monkeypatch.setattr(
        app_module.platform_support, "input_monitoring_status", lambda: None
    )
    vf = app_module.OpenVoiceFlow()
    assert vf.validate_setup() is True
    assert vf.setup_warnings == []
    assert not [c for c in notify_calls if c[0] == "warn"]


def test_setup_errors_exposed_for_menubar_alert(app_module, notify_calls, monkeypatch) -> None:
    """The menubar's modal alert needs the error list, not just False."""
    monkeypatch.setattr(app_module, "_is_accessibility_trusted", lambda: False)
    monkeypatch.setattr(app_module, "_prompt_accessibility_consent", lambda: None)
    vf = app_module.OpenVoiceFlow()
    assert vf.validate_setup() is False
    assert any("Accessibility permission" in e for e in vf.setup_errors)


# ─────────────────────────────────────────────────────────────────────
# Dead-listener watchdog
# ─────────────────────────────────────────────────────────────────────


def test_watchdog_silent_when_key_events_seen(app_module, notify_calls) -> None:
    vf = app_module.OpenVoiceFlow()
    vf._any_key_event_seen = True
    vf._check_dead_listener(on_dead_hotkey=lambda msg: notify_calls.append(("cb", msg, {})))
    assert notify_calls == []


def test_watchdog_dead_listener_calls_menubar_callback(
    app_module, notify_calls, monkeypatch
) -> None:
    monkeypatch.setattr(
        app_module.platform_support, "input_monitoring_status", lambda: False
    )
    vf = app_module.OpenVoiceFlow()
    callback_messages: list = []
    vf._check_dead_listener(on_dead_hotkey=callback_messages.append)
    assert callback_messages and "Input Monitoring" in callback_messages[0]
    assert not [c for c in notify_calls if c[0] == "error"], (
        "when the menubar callback handles it, no duplicate notification"
    )


def test_watchdog_dead_listener_cli_fallback_notifies(
    app_module, notify_calls, monkeypatch
) -> None:
    monkeypatch.setattr(
        app_module.platform_support, "input_monitoring_status", lambda: False
    )
    vf = app_module.OpenVoiceFlow()
    vf._check_dead_listener(on_dead_hotkey=None)
    errors = [c for c in notify_calls if c[0] == "error"]
    assert errors and errors[-1][2]["action"] == (
        "Open Input Monitoring Settings",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
    )


def test_watchdog_idle_user_gets_gentle_tip_not_alarm(
    app_module, notify_calls, monkeypatch
) -> None:
    """No events but permission looks fine → the user may just be idle."""
    monkeypatch.setattr(
        app_module.platform_support, "input_monitoring_status", lambda: True
    )
    vf = app_module.OpenVoiceFlow()
    vf._check_dead_listener(on_dead_hotkey=lambda msg: pytest.fail("must not alarm"))
    tips = [c for c in notify_calls if c[0] == "tip"]
    assert tips and tips[-1][2]["once_key"] == "hotkey_no_events"
    assert not [c for c in notify_calls if c[0] == "error"]


def test_any_key_event_flag_set_on_press_and_release(app_module) -> None:
    vf = app_module.OpenVoiceFlow()
    assert vf._any_key_event_seen is False
    vf.on_key_press(object())
    assert vf._any_key_event_seen is True
    vf._any_key_event_seen = False
    vf.on_key_release(object())
    assert vf._any_key_event_seen is True


def test_watchdog_thread_started_for_default_hotkey(app_module, monkeypatch) -> None:
    """The fn-only probe never covered right_cmd; the watchdog must."""
    created: list = []

    class _FakeThread:
        def __init__(self, *a, **kw):
            created.append(kw)

        def start(self):
            pass

    monkeypatch.setattr(app_module.threading, "Thread", _FakeThread)
    vf = app_module.OpenVoiceFlow()
    vf.start_hotkey_runtime_checks()
    assert any(kw.get("name") == "ovf-hotkey-watchdog" for kw in created)


# ─────────────────────────────────────────────────────────────────────
# Menubar helpers + Dock config default
# ─────────────────────────────────────────────────────────────────────


def test_settings_pane_for_accessibility_error() -> None:
    from voiceflow.menubar import _settings_pane_for_errors

    pane = _settings_pane_for_errors(
        ["Accessibility permission not granted. Enable OpenVoiceFlow ..."]
    )
    assert pane is not None
    label, url = pane
    assert label == "Open Accessibility Settings"
    assert url.endswith("Privacy_Accessibility")


def test_settings_pane_none_for_non_permission_errors() -> None:
    from voiceflow.menubar import _settings_pane_for_errors

    assert _settings_pane_for_errors(["whisper.cpp not found."]) is None
    assert _settings_pane_for_errors([]) is None


def test_default_config_shows_dock_icon() -> None:
    """Dock presence defaults on: a notch can hide a menu-bar-only icon."""
    from voiceflow.config import DEFAULTS

    assert DEFAULTS["show_dock_icon"] is True
