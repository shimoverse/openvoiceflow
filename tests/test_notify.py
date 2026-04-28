"""Tests for `voiceflow.notify` — the unified user-visible event emitter.

Architecture: every "tell the user something" path in OpenVoiceFlow routes
through this module. It surfaces messages via:

  1. macOS Notification Center (osascript display notification) — always.
  2. Floating overlay HUD (voiceflow.overlay) — when PyObjC available.
  3. stderr — always (CLI users see this; menubar users don't).

For ``tip(once_key="…")``, the module persists "shown" keys to
``~/.openvoiceflow/_seen_tips.json`` so the same tip never fires twice.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from unittest.mock import patch

import pytest


@pytest.fixture
def isolated_seen_tips(monkeypatch, tmp_path: Path):
    """Redirect _seen_tips.json to a tmpdir."""
    tips_dir = tmp_path / ".openvoiceflow"
    tips_dir.mkdir()
    tips_path = tips_dir / "_seen_tips.json"
    import voiceflow.notify as nf
    monkeypatch.setattr(nf, "SEEN_TIPS_PATH", str(tips_path))
    return tips_path


@pytest.fixture
def silent_emitters(monkeypatch):
    """Suppress real osascript + overlay calls during tests."""
    notif_calls: list[dict] = []
    overlay_calls: list[tuple] = []

    import voiceflow.notify as nf

    def fake_post_notification(title: str, message: str, **kwargs) -> None:
        notif_calls.append({"title": title, "message": message, **kwargs})

    def fake_overlay(method: str, *args, **kwargs) -> None:
        overlay_calls.append((method, args, kwargs))

    monkeypatch.setattr(nf, "_post_macos_notification", fake_post_notification)
    monkeypatch.setattr(nf, "_overlay_show", fake_overlay)
    return notif_calls, overlay_calls


def test_info_notification(silent_emitters, capsys) -> None:
    notif, overlay = silent_emitters
    from voiceflow import notify

    notify.info("Setup is starting", title="OpenVoiceFlow")

    assert len(notif) == 1
    assert notif[0]["title"] == "OpenVoiceFlow"
    assert notif[0]["message"] == "Setup is starting"
    # info is silent on stderr (no warning/error noise in CLI mode).
    err = capsys.readouterr().err
    assert "Setup is starting" not in err


def test_warn_notifies_and_logs(silent_emitters, capsys) -> None:
    notif, overlay = silent_emitters
    from voiceflow import notify

    notify.warn("Heads up: rate limit hit")

    assert len(notif) == 1
    err = capsys.readouterr().err
    assert "⚠" in err and "Heads up" in err


def test_error_notifies_logs_and_overlays(silent_emitters, capsys) -> None:
    notif, overlay = silent_emitters
    from voiceflow import notify

    notify.error("Auto-paste failed — grant Accessibility access")

    assert len(notif) == 1
    err = capsys.readouterr().err
    assert "❌" in err and "Auto-paste failed" in err
    # Errors get overlay treatment too (so menubar users see them).
    assert any(call[0] == "show_error" for call in overlay), (
        f"error() must call overlay.show_error; calls: {overlay}"
    )


def test_success_emits(silent_emitters) -> None:
    notif, overlay = silent_emitters
    from voiceflow import notify

    notify.success("Auto-learn picked up 'Meer' for you")

    assert len(notif) == 1
    assert "Meer" in notif[0]["message"]


def test_tip_with_once_key_fires_only_once(isolated_seen_tips, silent_emitters) -> None:
    notif, _ = silent_emitters
    from voiceflow import notify

    notify.tip("Try saying 'comma' for ,", once_key="voice_commands_intro")
    notify.tip("Try saying 'comma' for ,", once_key="voice_commands_intro")
    notify.tip("Try saying 'comma' for ,", once_key="voice_commands_intro")

    # Only the first call should have hit the emitter.
    assert len(notif) == 1


def test_tip_without_once_key_fires_every_time(isolated_seen_tips, silent_emitters) -> None:
    notif, _ = silent_emitters
    from voiceflow import notify

    notify.tip("This is a regular tip")
    notify.tip("This is a regular tip")

    assert len(notif) == 2


def test_seen_tips_persisted_atomically(isolated_seen_tips, silent_emitters) -> None:
    from voiceflow import notify

    notify.tip("First tip", once_key="tip_a")
    notify.tip("Second tip", once_key="tip_b")

    on_disk = json.loads(Path(isolated_seen_tips).read_text())
    assert set(on_disk.get("seen", [])) == {"tip_a", "tip_b"}


def test_seen_tips_file_is_mode_600(isolated_seen_tips, silent_emitters) -> None:
    from voiceflow import notify

    notify.tip("First tip", once_key="tip_secure_io")
    mode = os.stat(isolated_seen_tips).st_mode & 0o777
    assert mode == 0o600, f"_seen_tips.json mode {oct(mode)} != 0o600"


def test_corrupted_seen_tips_recovers_gracefully(isolated_seen_tips, silent_emitters) -> None:
    """If _seen_tips.json is corrupted, treat as empty and don't crash."""
    Path(isolated_seen_tips).write_text("not valid json {")
    from voiceflow import notify

    # Should fire (since the corrupted file is treated as empty).
    notify.tip("Recover-and-fire", once_key="recover")
    # File should be rewritten cleanly.
    on_disk = json.loads(Path(isolated_seen_tips).read_text())
    assert "recover" in on_disk["seen"]


def test_action_button_url(silent_emitters) -> None:
    """Errors with an action attach a fix URL the surface can render."""
    notif, _ = silent_emitters
    from voiceflow import notify

    notify.error(
        "Microphone access required",
        action=("Open System Settings", "x-apple.systempreferences:com.apple.preference.security?Microphone"),
    )

    assert notif[0]["action_label"] == "Open System Settings"
    assert "x-apple.systempreferences" in notif[0]["action_url"]
