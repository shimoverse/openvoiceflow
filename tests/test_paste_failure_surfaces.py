"""Phase B1: paste failures must surface as a notification, not a stderr line.

Background: ``system.paste_text`` calls osascript to send Cmd+V. If the
user hasn't granted Accessibility access, the osascript exits non-zero
and v0.2 just printed a hint to stderr — invisible to menubar users.

v0.3.x: route through ``notify.error`` with a click-to-fix URL pointing
at System Settings → Privacy & Security → Accessibility.
"""
from __future__ import annotations


def test_paste_failure_calls_notify_error(monkeypatch) -> None:
    import voiceflow.notify as notify
    import voiceflow.system as sysmod

    notify_calls: list[dict] = []

    def fake_error(message, **kwargs):
        notify_calls.append({"message": message, **kwargs})

    monkeypatch.setattr(notify, "error", fake_error)

    # Stub pbcopy so the test doesn't actually touch the user's clipboard.
    class FakePopen:
        def __init__(self, *args, **kwargs):
            pass
        def communicate(self, data=None, timeout=None):
            return None, None

    monkeypatch.setattr(sysmod.subprocess, "Popen", FakePopen)

    # Stub osascript to fail (returncode != 0).
    class FakeResult:
        returncode = 1
        stderr = b"not authorized to send Apple events"
    monkeypatch.setattr(
        sysmod.subprocess, "run",
        lambda *a, **kw: FakeResult(),
    )

    # Stub play_sound so the test doesn't open afplay.
    monkeypatch.setattr(sysmod, "play_sound", lambda *a, **kw: None)

    sysmod.paste_text("hello world")

    assert len(notify_calls) == 1, (
        f"paste_text must call notify.error exactly once on osascript failure; "
        f"got {len(notify_calls)} calls"
    )
    msg = notify_calls[0]["message"]
    assert "Accessibility" in msg or "Apple Events" in msg, (
        f"error message should reference the missing permission; got: {msg!r}"
    )
    assert notify_calls[0].get("action") is not None, (
        "error must offer a click-to-fix action (label, url)"
    )
    label, url = notify_calls[0]["action"]
    assert "System Settings" in label or "Settings" in label
    assert url.startswith("x-apple.systempreferences:") or url.startswith("https://"), url


def test_paste_success_does_not_notify(monkeypatch) -> None:
    """Happy path: no notify calls."""
    import voiceflow.notify as notify
    import voiceflow.system as sysmod

    notify_calls: list = []
    monkeypatch.setattr(notify, "error", lambda *a, **kw: notify_calls.append(("error", a, kw)))
    monkeypatch.setattr(notify, "warn", lambda *a, **kw: notify_calls.append(("warn", a, kw)))

    class FakePopen:
        def __init__(self, *args, **kwargs):
            pass
        def communicate(self, data=None, timeout=None):
            return None, None
    monkeypatch.setattr(sysmod.subprocess, "Popen", FakePopen)

    class FakeResult:
        returncode = 0
        stderr = b""
    monkeypatch.setattr(sysmod.subprocess, "run", lambda *a, **kw: FakeResult())
    monkeypatch.setattr(sysmod, "play_sound", lambda *a, **kw: None)

    sysmod.paste_text("hello")

    assert notify_calls == [], f"happy path should not notify; got {notify_calls}"
