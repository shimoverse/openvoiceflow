"""System integration: paste, sound feedback, transcript logging."""

from __future__ import annotations

import json
import os
import subprocess
import time
from datetime import datetime

from .config import LOG_DIR


def paste_text(text: str):
    """Copy text to clipboard and paste at cursor (macOS).

    On Accessibility / Apple Events permission failure, surfaces a
    user-visible notification + overlay banner via ``voiceflow.notify``
    instead of an invisible stderr line. The user's text is still on
    the clipboard, so a manual ⌘V always works as a fallback.
    """
    process = subprocess.Popen(["pbcopy"], stdin=subprocess.PIPE)
    process.communicate(text.encode("utf-8"))
    time.sleep(0.05)
    # BUG-009 fix: capture return code and report Accessibility errors clearly
    result = subprocess.run(
        [
            "osascript", "-e",
            'tell application "System Events" to keystroke "v" using command down',
        ],
        capture_output=True,
    )
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
        subprocess.Popen(["afplay", path])


def log_transcript(raw: str, cleaned: str, config: dict):
    """Save transcript to daily log files."""
    if not config.get("log_transcripts"):
        return

    from ._secure_io import secure_chmod

    # BUG-020 fix: ensure log directory exists before writing
    LOG_DIR.mkdir(parents=True, exist_ok=True)
    now = datetime.now()

    # Machine-readable JSONL
    jsonl_file = LOG_DIR / f"{now:%Y-%m-%d}.jsonl"
    entry = {"timestamp": now.isoformat(), "raw": raw, "cleaned": cleaned}
    with open(jsonl_file, "a") as f:
        f.write(json.dumps(entry) + "\n")
    secure_chmod(jsonl_file)

    # Human-readable Markdown
    md_file = LOG_DIR / f"{now:%Y-%m-%d}.md"
    is_new = not md_file.exists()
    with open(md_file, "a") as f:
        if is_new:
            f.write(f"# OpenVoiceFlow — {now:%A, %B %d, %Y}\n\n")
        f.write(f"**{now:%I:%M %p}**\n{cleaned}\n\n")
    secure_chmod(md_file)
