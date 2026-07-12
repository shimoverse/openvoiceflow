"""Cross-platform compatibility guarantees.

OpenVoiceFlow is macOS-only, but it must never CRASH elsewhere: a user who
pip-installs it on Linux or Windows gets a clear "unsupported OS" message
with uninstall guidance, and the diagnostic commands (--doctor,
--show-config) keep working so they can inspect state first.

These tests run on any host — macOS behavior is simulated via monkeypatch.
"""
from __future__ import annotations

import sys

import pytest

# ─────────────────────────────────────────────────────────────────────
# platform_support primitives
# ─────────────────────────────────────────────────────────────────────


def test_is_macos_matches_sys_platform() -> None:
    from voiceflow import platform_support
    assert platform_support.is_macos() == (sys.platform == "darwin")


def test_macos_version_is_none_off_macos(monkeypatch) -> None:
    from voiceflow import platform_support
    monkeypatch.setattr(platform_support, "is_macos", lambda: False)
    assert platform_support.macos_version() is None


def test_macos_version_parses_tuple(monkeypatch) -> None:
    from voiceflow import platform_support
    monkeypatch.setattr(platform_support, "is_macos", lambda: True)
    monkeypatch.setattr(
        platform_support.platform, "mac_ver", lambda: ("14.5", ("", "", ""), "arm64")
    )
    assert platform_support.macos_version() == (14, 5)


def test_unsupported_message_names_os_and_uninstall() -> None:
    from voiceflow import platform_support
    msg = platform_support.unsupported_os_message()
    assert "macOS" in msg
    assert "pip uninstall openvoiceflow" in msg
    assert ".openvoiceflow" in msg


def test_permission_probes_never_raise() -> None:
    """Best-effort probes must return True/False/None, never raise."""
    from voiceflow import platform_support
    for probe in (
        platform_support.accessibility_status,
        platform_support.input_monitoring_status,
        platform_support.microphone_status,
    ):
        assert probe() in (True, False, None)


# ─────────────────────────────────────────────────────────────────────
# CLI entry-point gate
# ─────────────────────────────────────────────────────────────────────


def test_main_refuses_to_run_off_macos(monkeypatch, capsys) -> None:
    """Bare `openvoiceflow` on a non-Mac exits 1 with guidance, no traceback."""
    import voiceflow.__main__ as cli
    monkeypatch.setattr(cli.platform_support, "is_macos", lambda: False)
    monkeypatch.setattr(sys, "argv", ["openvoiceflow"])

    with pytest.raises(SystemExit) as excinfo:
        cli.main()

    assert excinfo.value.code == 1
    err = capsys.readouterr().err
    assert "macOS" in err
    assert "pip uninstall openvoiceflow" in err


def test_main_gate_blocks_menubar_too(monkeypatch, capsys) -> None:
    import voiceflow.__main__ as cli
    monkeypatch.setattr(cli.platform_support, "is_macos", lambda: False)
    monkeypatch.setattr(sys, "argv", ["openvoiceflow", "--menubar"])

    with pytest.raises(SystemExit) as excinfo:
        cli.main()
    assert excinfo.value.code == 1
    assert "macOS" in capsys.readouterr().err


def test_main_allows_show_config_off_macos(monkeypatch, capsys) -> None:
    """Diagnostics survive the gate so users can inspect state pre-uninstall."""
    import voiceflow.__main__ as cli
    from voiceflow.config import DEFAULTS

    monkeypatch.setattr(cli.platform_support, "is_macos", lambda: False)
    monkeypatch.setattr(cli, "load_config", lambda: dict(DEFAULTS))
    monkeypatch.setattr(sys, "argv", ["openvoiceflow", "--show-config"])

    cli.main()  # must not raise SystemExit
    out = capsys.readouterr().out
    assert '"hotkey"' in out


def test_main_allows_doctor_off_macos(monkeypatch, capsys) -> None:
    import json

    import voiceflow.__main__ as cli
    from voiceflow import doctor
    from voiceflow.config import DEFAULTS

    monkeypatch.setattr(cli.platform_support, "is_macos", lambda: False)
    monkeypatch.setattr(doctor.platform_support, "is_macos", lambda: False)
    monkeypatch.setattr(cli, "load_config", lambda: dict(DEFAULTS))
    monkeypatch.setattr(sys, "argv", ["openvoiceflow", "--doctor", "--json"])

    with pytest.raises(SystemExit) as excinfo:
        cli.main()

    assert excinfo.value.code == 1  # OS check FAILs — that's the diagnosis
    parsed = json.loads(capsys.readouterr().out)
    assert parsed["checks"][0]["status"] == "FAIL"
    assert "macOS" in parsed["checks"][0]["description"]


# ─────────────────────────────────────────────────────────────────────
# Import safety — no module import may require macOS-only runtime pieces
# ─────────────────────────────────────────────────────────────────────


def test_recorder_imports_without_sounddevice(monkeypatch) -> None:
    """recorder must import even when sounddevice can't (missing PortAudio).

    This is the crash every non-Mac user hit: `import sounddevice` raises
    OSError at module level without the PortAudio C library.
    """
    monkeypatch.setitem(sys.modules, "sounddevice", None)  # import → ImportError
    monkeypatch.delitem(sys.modules, "voiceflow.recorder", raising=False)

    import voiceflow.recorder  # must not raise

    rec = voiceflow.recorder.AudioRecorder()
    with pytest.raises(Exception):
        rec.start()  # failure surfaces at use time, where app.py handles it


def test_get_key_map_empty_when_pynput_unavailable(monkeypatch) -> None:
    import voiceflow.app as appmod

    monkeypatch.setattr(appmod, "AudioRecorder", lambda *a, **kw: object())
    monkeypatch.setitem(sys.modules, "pynput", None)
    monkeypatch.setitem(sys.modules, "pynput.keyboard", None)

    vf = appmod.OpenVoiceFlow(use_overlay=False)
    assert vf._get_key_map() == {}


# ─────────────────────────────────────────────────────────────────────
# Feature modules refuse politely off-macOS
# ─────────────────────────────────────────────────────────────────────


def test_autostart_requires_macos(monkeypatch) -> None:
    from voiceflow import autostart
    monkeypatch.setattr(autostart.platform_support, "is_macos", lambda: False)
    success, msg = autostart.set_autostart(True)
    assert success is False
    assert "macOS" in msg


def test_find_whisper_cpp_never_spawns_which(monkeypatch) -> None:
    """Discovery must use shutil.which — a `which` subprocess crashes on
    Windows (FileNotFoundError) and is slower everywhere."""
    from voiceflow import transcriber

    def forbid_run(*args, **kwargs):  # pragma: no cover - only on regression
        raise AssertionError(f"unexpected subprocess call: {args}")

    monkeypatch.setattr(transcriber.subprocess, "run", forbid_run)
    monkeypatch.setattr(transcriber.shutil, "which", lambda name: None)
    monkeypatch.setattr(transcriber.os.path, "isfile", lambda p: False)

    assert transcriber.find_whisper_cpp() is None
