"""Selected text and clipboard context capture for OpenVoiceFlow.

Captures the currently selected text in the frontmost application by
temporarily simulating Cmd+C and reading the pasteboard, then restoring
the original clipboard contents to avoid disrupting the user.
"""

from __future__ import annotations

import subprocess
import time

# Maximum characters of context passed to the LLM
MAX_CONTEXT_CHARS = 2000


def _read_clipboard() -> str:
    """Read current clipboard contents via pbpaste."""
    result = subprocess.run(
        ["pbpaste"],
        capture_output=True,
        timeout=3,
    )
    if result.returncode == 0:
        return result.stdout.decode("utf-8", errors="replace")
    return ""


def _write_clipboard(text: str) -> None:
    """Write text to clipboard via pbcopy."""
    process = None
    try:
        process = subprocess.Popen(["pbcopy"], stdin=subprocess.PIPE)
        process.communicate(text.encode("utf-8"), timeout=3)
    except subprocess.TimeoutExpired:
        # communicate() does NOT reap the child on timeout — kill it so a
        # hung pbcopy doesn't leak a process + pipe fds.
        if process is not None:
            process.kill()
            process.wait()
    except Exception:
        pass


def _pasteboard_has_nontext_only() -> bool:
    """True when the clipboard holds non-text data (image/file) and no string.

    ``pbpaste`` can only render text, so a copy+restore round-trip silently
    destroys an image or file on the clipboard. When PyObjC is available we
    detect that case and skip capture entirely. Returns False (proceed) when
    PyObjC is absent or the clipboard is empty/has text.
    """
    try:
        from AppKit import NSPasteboard, NSPasteboardTypeString
    except Exception:
        return False
    try:
        pb = NSPasteboard.generalPasteboard()
        if pb.availableTypeFromArray_([NSPasteboardTypeString]) is not None:
            return False  # a string is present → safe to round-trip
        return bool(pb.pasteboardItems())  # items but no string → non-text
    except Exception:
        return False


def capture_selected_text() -> str | None:
    """Capture the currently selected text in the frontmost app.

    Simulates Cmd+C to copy the selection, reads the new clipboard value,
    then restores the original clipboard.  Returns None if nothing was
    selected or if capture fails for any reason.

    The total time cost of this function is roughly 150-200ms.
    """
    try:
        # 0. Preserve non-text clipboard contents. If the clipboard holds an
        # image or file (no text), the Cmd+C round-trip below would destroy
        # it — skip capture entirely and leave it untouched.
        if _pasteboard_has_nontext_only():
            return None

        # 1. Save original clipboard
        original_clipboard = _read_clipboard()

        # 2. Simulate Cmd+C in the frontmost application.
        # timeout: this runs on the hotkey listener thread; a blocked
        # osascript (e.g. macOS Automation consent dialog) would otherwise
        # freeze hotkey handling entirely.
        result = subprocess.run(
            [
                "osascript",
                "-e",
                'tell application "System Events" to keystroke "c" using command down',
            ],
            capture_output=True,
            timeout=5,
        )
        if result.returncode != 0:
            # osascript failed (e.g. Accessibility not granted) — bail out cleanly
            return None

        # 3. Wait for the app to populate the clipboard
        time.sleep(0.1)

        # 4. Read the (possibly) updated clipboard
        new_clipboard = _read_clipboard()

        # 5. Determine selected text: only if clipboard actually changed
        selected_text: str | None = None
        if new_clipboard != original_clipboard and new_clipboard.strip():
            selected_text = new_clipboard[:MAX_CONTEXT_CHARS]
            # 6. Restore the original clipboard — but only if it was genuine
            # prior text. Never `pbcopy ""`: an empty original means it was
            # either empty already or non-text, and writing empty would
            # replace the user's selection (now on the clipboard) with nothing.
            if original_clipboard:
                _write_clipboard(original_clipboard)

        return selected_text

    except Exception:
        # Never let clipboard capture crash the dictation flow
        return None


def get_clipboard_context() -> str | None:
    """Return current clipboard contents as context (fallback, no Cmd+C).

    Reads the clipboard directly without simulating any key press.
    Caps at MAX_CONTEXT_CHARS.  Returns None if clipboard is empty.
    """
    try:
        text = _read_clipboard()
        text = text.strip()
        if not text:
            return None
        return text[:MAX_CONTEXT_CHARS]
    except Exception:
        return None
