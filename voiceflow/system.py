"""System integration: paste, sound feedback, transcript logging."""

from __future__ import annotations

import json
import os
import subprocess
import time
from datetime import datetime

from .config import LOG_DIR


def _kill_quietly(proc) -> None:
    """Reap a Popen child that outlived its timeout.

    ``Popen.communicate(timeout=…)`` raises but does NOT terminate the child,
    so without this a hung pbcopy leaks a process and its pipe fds.
    """
    if proc is None:
        return
    try:
        proc.kill()
        proc.wait(timeout=1)
    except Exception:
        pass


def paste_text(text: str):
    """Copy text to clipboard and paste at cursor (macOS).

    On Accessibility / Apple Events permission failure, surfaces a
    user-visible notification + overlay banner via ``voiceflow.notify``
    instead of an invisible stderr line. The user's text is still on
    the clipboard, so a manual ⌘V always works as a fallback.
    """
    process = None
    try:
        process = subprocess.Popen(["pbcopy"], stdin=subprocess.PIPE)
        process.communicate(text.encode("utf-8"), timeout=5)
        time.sleep(0.05)
        # BUG-009 fix: capture return code and report Accessibility errors clearly
        # timeout: osascript blocks indefinitely while macOS shows an
        # Automation consent dialog; without one, this worker thread hangs
        # with processing=True and the hotkey never fires again.
        result = subprocess.run(
            [
                "osascript", "-e",
                'tell application "System Events" to keystroke "v" using command down',
            ],
            capture_output=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        # osascript blocked (likely a macOS consent dialog). The text is
        # already on the clipboard, so manual ⌘V still works.
        _kill_quietly(process)
        play_sound("error")
        from . import notify
        notify.error(
            "Auto-paste timed out — your text is on the clipboard, ⌘V to paste manually. "
            "If macOS showed a permission dialog, approve it to enable auto-paste."
        )
        return
    except (OSError, subprocess.SubprocessError) as exc:
        # pbcopy/osascript missing (non-macOS or broken PATH) — never crash
        # the dictation thread over feedback plumbing.
        from . import notify
        notify.error(f"Auto-paste unavailable on this system ({exc}).")
        return
    if result.returncode != 0:
        play_sound("error")
        # System Events → Privacy_AppleEvents (this is the pane macOS opens
        # when an unauthorized osascript-keystroke call is attempted).
        from . import notify
        notify.error(
            "Auto-paste failed — your text is on the clipboard, ⌘V to paste manually. "
            "Grant Accessibility access to enable auto-paste.",
            action=(
                "Open System Settings",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            ),
        )


def insert_recording_indicator(indicator: str = "🎙") -> bool:
    """Insert a short visual marker at the current text cursor.

    Saves and restores the user's clipboard around the paste so an aborted
    dictation doesn't leave the indicator on the clipboard.

    Returns True if insertion succeeded.
    """
    process = None
    restore = None
    try:
        original = subprocess.run(["pbpaste"], capture_output=True, timeout=5)
        process = subprocess.Popen(["pbcopy"], stdin=subprocess.PIPE)
        process.communicate(indicator.encode("utf-8"), timeout=5)
        _move_caret_to_end()
        time.sleep(0.03)
        result = subprocess.run(
            [
                "osascript", "-e",
                'tell application "System Events" to keystroke "v" using command down',
            ],
            capture_output=True,
            timeout=10,
        )
        # Give the target app a moment to service the paste before restoring.
        time.sleep(0.15)
        if original.returncode == 0:
            restore = subprocess.Popen(["pbcopy"], stdin=subprocess.PIPE)
            restore.communicate(original.stdout, timeout=5)
        return result.returncode == 0
    except subprocess.TimeoutExpired:
        _kill_quietly(process)
        _kill_quietly(restore)
        return False
    except (OSError, subprocess.SubprocessError):
        return False


def clear_recording_indicator() -> bool:
    """Delete one character to remove the temporary recording marker.

    Returns True if the delete keystroke was sent successfully.
    """
    try:
        _move_caret_to_end()
        result = subprocess.run(
            [
                "osascript", "-e",
                'tell application "System Events" to key code 51',
            ],
            capture_output=True,
            timeout=10,
        )
        return result.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def _move_caret_to_end() -> None:
    """Move insertion point to end of the focused text field (best-effort)."""
    try:
        subprocess.run(
            [
                "osascript", "-e",
                'tell application "System Events" to key code 124 using command down',
            ],
            capture_output=True,
            timeout=10,
        )
    except (OSError, subprocess.SubprocessError):
        pass


def play_sound(sound_type: str = "start"):
    """Play a macOS system sound for feedback."""
    sounds = {
        "start": "/System/Library/Sounds/Pop.aiff",
        "stop": "/System/Library/Sounds/Purr.aiff",
        "error": "/System/Library/Sounds/Basso.aiff",
        "done": "/System/Library/Sounds/Glass.aiff",
    }
    path = sounds.get(sound_type)
    if path and os.path.exists(path):
        try:
            subprocess.Popen(["afplay", path])
        except OSError:
            pass  # Sound feedback is best-effort


def log_transcript(raw: str, cleaned: str, config: dict):
    """Save transcript to daily log files."""
    if not config.get("log_transcripts"):
        return

    from ._secure_io import secure_chmod, secure_dir

    # BUG-020 fix: ensure log directory exists before writing.
    # secure_dir keeps it owner-only (0700) — the date-named filenames
    # themselves reveal usage days, so the directory shouldn't be listable.
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    secure_dir(str(LOG_DIR))
    now = datetime.now()

    def _open_append_600(path):
        # Create with 0600 directly — no world-readable window between
        # creation and a later chmod.
        fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        return os.fdopen(fd, "a")

    # Machine-readable JSONL
    jsonl_file = LOG_DIR / f"{now:%Y-%m-%d}.jsonl"
    entry = {"timestamp": now.isoformat(), "raw": raw, "cleaned": cleaned}
    with _open_append_600(jsonl_file) as f:
        f.write(json.dumps(entry) + "\n")
    secure_chmod(jsonl_file)

    # Human-readable Markdown
    md_file = LOG_DIR / f"{now:%Y-%m-%d}.md"
    is_new = not md_file.exists()
    with _open_append_600(md_file) as f:
        if is_new:
            f.write(f"# OpenVoiceFlow — {now:%A, %B %d, %Y}\n\n")
        f.write(f"**{now:%I:%M %p}**\n{cleaned}\n\n")
    secure_chmod(md_file)
