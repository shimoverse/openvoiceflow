"""Production-hardening regression tests (audit follow-up).

Covers the runtime, data-loss, and security fixes from the end-to-end audit:
recorder stream-leak, max-duration watchdog, guarded stop, transcribe error
path, clipboard non-text preservation, orphan-kill, secure-write symlink
refusal, capped HTTP reads, and local-URL validation. All hermetic — no
macOS, no real subprocess, no network.
"""
from __future__ import annotations

import subprocess
import sys

import pytest

from voiceflow.config import DEFAULTS

# ─────────────────────────────────────────────────────────────────────
# recorder.stop() — leak-proof (H3)
# ─────────────────────────────────────────────────────────────────────


def test_recorder_stop_releases_stream_even_when_close_raises() -> None:
    from voiceflow.recorder import AudioRecorder

    class BadStream:
        def __init__(self) -> None:
            self.stopped = False
            self.closed = False

        def stop(self):
            self.stopped = True
            raise OSError("device unplugged")

        def close(self):
            self.closed = True

    rec = AudioRecorder()
    stream = BadStream()
    rec._stream = stream
    rec.is_recording = True

    rec.stop()  # must not raise

    assert rec._stream is None, "stream reference must be cleared (no leak on next start)"
    assert stream.closed is True, "close() must still run after stop() raised"
    assert rec.is_recording is False


# ─────────────────────────────────────────────────────────────────────
# transcribe() — binary vanished (L2)
# ─────────────────────────────────────────────────────────────────────


def test_transcribe_returns_none_when_binary_missing(monkeypatch) -> None:
    from voiceflow import transcriber

    monkeypatch.setattr(transcriber, "find_whisper_cpp", lambda: "/opt/homebrew/bin/whisper-cli")
    monkeypatch.setattr(transcriber, "get_model_path", lambda m: "/models/x.bin")
    monkeypatch.setattr(transcriber.os.path, "exists", lambda p: True)

    def gone(*a, **k):
        raise FileNotFoundError("no such binary")

    monkeypatch.setattr(transcriber.subprocess, "run", gone)
    out = transcriber.transcribe("/tmp/a.wav", {"whisper_model": "base.en", "language": "en"})
    assert out is None  # not a raised exception


# ─────────────────────────────────────────────────────────────────────
# clipboard — non-text preservation + no empty-clobber (security M2, M3)
# ─────────────────────────────────────────────────────────────────────


def test_pasteboard_nontext_probe_false_without_appkit(monkeypatch) -> None:
    from voiceflow import clipboard
    monkeypatch.setitem(sys.modules, "AppKit", None)  # import → ImportError
    assert clipboard._pasteboard_has_nontext_only() is False


def test_capture_skips_entirely_when_clipboard_is_nontext(monkeypatch) -> None:
    from voiceflow import clipboard
    monkeypatch.setattr(clipboard, "_pasteboard_has_nontext_only", lambda: True)

    def forbid(*a, **k):
        raise AssertionError("must not touch the clipboard when it holds non-text")

    monkeypatch.setattr(clipboard.subprocess, "run", forbid)
    assert clipboard.capture_selected_text() is None


def test_capture_never_restores_empty_clipboard(monkeypatch) -> None:
    """Original was empty/non-text → must NOT pbcopy "" over the selection."""
    from voiceflow import clipboard
    monkeypatch.setattr(clipboard, "_pasteboard_has_nontext_only", lambda: False)

    reads = iter(["", "the selected text"])  # original empty, then post-copy
    monkeypatch.setattr(clipboard, "_read_clipboard", lambda: next(reads))
    monkeypatch.setattr(clipboard.time, "sleep", lambda s: None)

    class OK:
        returncode = 0

    monkeypatch.setattr(clipboard.subprocess, "run", lambda *a, **k: OK())
    writes: list = []
    monkeypatch.setattr(clipboard, "_write_clipboard", lambda t: writes.append(t))

    result = clipboard.capture_selected_text()
    assert result == "the selected text"
    assert writes == [], "must not write empty text back over the clipboard"


def test_capture_restores_genuine_prior_text(monkeypatch) -> None:
    from voiceflow import clipboard
    monkeypatch.setattr(clipboard, "_pasteboard_has_nontext_only", lambda: False)
    reads = iter(["important note", "selection"])
    monkeypatch.setattr(clipboard, "_read_clipboard", lambda: next(reads))
    monkeypatch.setattr(clipboard.time, "sleep", lambda s: None)

    class OK:
        returncode = 0

    monkeypatch.setattr(clipboard.subprocess, "run", lambda *a, **k: OK())
    writes: list = []
    monkeypatch.setattr(clipboard, "_write_clipboard", lambda t: writes.append(t))

    assert clipboard.capture_selected_text() == "selection"
    assert writes == ["important note"], "genuine prior text must be restored"


def test_write_clipboard_kills_child_on_timeout(monkeypatch) -> None:
    from voiceflow import clipboard

    class HangingProc:
        def __init__(self) -> None:
            self.killed = False

        def communicate(self, data, timeout):
            raise subprocess.TimeoutExpired("pbcopy", timeout)

        def kill(self):
            self.killed = True

        def wait(self, *a, **k):
            return 0

    proc = HangingProc()
    monkeypatch.setattr(clipboard.subprocess, "Popen", lambda *a, **k: proc)
    clipboard._write_clipboard("x")  # must not raise
    assert proc.killed is True, "a hung pbcopy must be reaped, not orphaned"


# ─────────────────────────────────────────────────────────────────────
# _secure_io — symlink-safe secrets write (security L3)
# ─────────────────────────────────────────────────────────────────────


def test_secure_write_json_roundtrip_mode_600(tmp_path) -> None:
    import json
    import os

    from voiceflow._secure_io import secure_write_json

    p = tmp_path / "config.json"
    secure_write_json(str(p), {"a": 1, "b": "two"})
    assert json.loads(p.read_text()) == {"a": 1, "b": "two"}
    assert (os.stat(p).st_mode & 0o777) == 0o600


def test_secure_write_json_refuses_symlinked_temp(tmp_path) -> None:
    """A pre-planted symlink at the temp path must not be followed and
    clobber its target; the write still succeeds at the real path."""
    import json
    import os

    from voiceflow._secure_io import secure_write_json

    target = tmp_path / "config.json"
    victim = tmp_path / "victim.txt"
    victim.write_text("do not overwrite me")

    tmp_link = f"{target}.tmp{os.getpid()}"
    os.symlink(str(victim), tmp_link)

    secure_write_json(str(target), {"ok": True})

    assert victim.read_text() == "do not overwrite me", "symlink target must be untouched"
    assert json.loads(target.read_text()) == {"ok": True}


# ─────────────────────────────────────────────────────────────────────
# llm.base — capped reads + local-url validation (security L1, L2)
# ─────────────────────────────────────────────────────────────────────


def test_read_json_capped_accepts_small_body() -> None:
    from voiceflow.llm.base import read_json_capped

    class Resp:
        def read(self, n):
            return b'{"response": "hi"}'

    assert read_json_capped(Resp(), max_bytes=1000) == {"response": "hi"}


def test_read_json_capped_rejects_oversized_body() -> None:
    from voiceflow.llm.base import read_json_capped

    class Flood:
        def read(self, n):
            return b"x" * n  # always returns exactly the requested cap+1

    with pytest.raises(ValueError):
        read_json_capped(Flood(), max_bytes=8)


def test_sanitize_local_url_rejects_non_http_scheme() -> None:
    from voiceflow.llm.base import sanitize_local_url

    default = "http://localhost:11434"
    assert sanitize_local_url("file:///etc/passwd", default) == default
    assert sanitize_local_url("ftp://host/x", default) == default
    assert sanitize_local_url("not a url", default) == default


def test_sanitize_local_url_allows_loopback_and_passes_off_box() -> None:
    from voiceflow.llm.base import sanitize_local_url

    default = "http://localhost:11434"
    assert sanitize_local_url("http://127.0.0.1:11434", default) == "http://127.0.0.1:11434"
    # Off-box is allowed (user may intend it) but returned unchanged.
    assert sanitize_local_url("http://10.0.0.9:11434", default) == "http://10.0.0.9:11434"


# ─────────────────────────────────────────────────────────────────────
# app controller — watchdog, guarded stop, thread-start rollback (H1/H2/H3/L1)
# ─────────────────────────────────────────────────────────────────────


@pytest.fixture
def vf(monkeypatch):
    import voiceflow.app as appmod

    class FakeRecorder:
        def __init__(self, *a, **k) -> None:
            self.started = False
            self.stopped = False
            self.is_recording = False
            self.duration = 1.0

        def start(self):
            self.started = True
            self.is_recording = True

        def stop(self):
            self.stopped = True
            self.is_recording = False

    monkeypatch.setattr(appmod, "AudioRecorder", FakeRecorder)
    monkeypatch.setattr(appmod, "load_config", lambda: dict(DEFAULTS))
    monkeypatch.setattr(appmod, "play_sound", lambda *a, **k: None)
    return appmod.OpenVoiceFlow(use_overlay=False)


def test_max_duration_watchdog_forces_stop_only_while_recording(vf, monkeypatch) -> None:
    calls: list = []
    monkeypatch.setattr(vf, "stop_and_process", lambda: calls.append(1))

    vf.is_recording = False
    vf._on_max_duration()
    assert calls == []  # nothing to stop

    vf.is_recording = True
    vf._on_max_duration()
    assert calls == [1]  # a runaway recording is force-stopped


def test_stop_and_process_is_idempotent(vf) -> None:
    """Only one caller (release / watchdog / abort) may drive the stop."""
    vf.is_recording = False
    vf.stop_and_process()  # must return immediately, touch nothing
    assert vf.recorder.stopped is False
    assert vf.processing is False


def test_start_processing_rolls_back_when_thread_cannot_start(vf, monkeypatch) -> None:
    import voiceflow.app as appmod

    def no_threads(*a, **k):
        raise RuntimeError("can't start thread")

    monkeypatch.setattr(appmod.threading, "Thread", no_threads)
    vf._start_processing(lambda: None, ())
    assert vf.processing is False, "a failed thread-start must not wedge the hotkey"


def test_stop_and_process_surfaces_recorder_stop_failure(vf, monkeypatch) -> None:
    import voiceflow.notify as notify

    errors: list = []
    monkeypatch.setattr(notify, "error", lambda m, **k: errors.append(m))
    spawned: list = []
    monkeypatch.setattr(vf, "_start_processing", lambda *a: spawned.append(a))

    vf.is_recording = True
    vf._streaming_active = False

    def device_gone():
        vf.recorder.is_recording = False
        raise OSError("device gone")

    vf.recorder.stop = device_gone
    vf.stop_and_process()

    assert errors and "unexpectedly" in errors[0]
    assert spawned == [], "must not spawn processing when the recorder failed to stop"
    assert vf.processing is False


def test_start_recording_arms_mic_before_context_capture(vf, monkeypatch) -> None:
    """H1: the mic is armed on the event-tap thread; the ~150ms osascript
    context capture is moved to a worker so it can't wedge the tap."""
    import voiceflow.app as appmod

    monkeypatch.setattr(vf, "_start_max_duration_timer", lambda: None)
    captured: list = []
    monkeypatch.setattr(vf, "_capture_context", lambda: captured.append("ran"))

    threads: list = []
    real_thread = appmod.threading.Thread

    def track_thread(*a, **k):
        t = real_thread(*a, **k)
        threads.append(k.get("name", ""))
        return t

    monkeypatch.setattr(appmod.threading, "Thread", track_thread)

    vf._last_press_time = 0
    vf.start_recording()

    assert vf.recorder.started is True, "mic must be armed synchronously"
    assert vf.is_recording is True
    assert "ovf-context-capture" in threads, "context capture must run on a worker thread"
