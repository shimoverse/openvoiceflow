"""Unified user-visible event emitter.

The architectural primitive for "make the silent visible." Every part of
OpenVoiceFlow that wants to surface a status, success, warning, or error
to the user routes through here so the experience is consistent across:

  - macOS Notification Center  (always — works without PyObjC)
  - Floating overlay HUD       (when PyObjC is available)
  - stderr                     (always — visible to CLI users)

For one-time tips (``tip(once_key="…")``), the module persists "shown"
keys to ``~/.openvoiceflow/_seen_tips.json`` so the same tip never fires
twice. This is how the v0.3.x voice-command tutor / per-app context
introduction / first-paste guidance get implemented without spamming the
user on every dictation.

Public API:

    notify.info(message, *, title="OpenVoiceFlow")
    notify.success(message, *, title="OpenVoiceFlow")
    notify.warn(message, *, title="OpenVoiceFlow", action=None)
    notify.error(message, *, title="OpenVoiceFlow", action=None)
    notify.tip(message, *, title="OpenVoiceFlow", once_key=None)

``action`` is an optional ``(label, url)`` tuple. Common URLs:

  - "x-apple.systempreferences:com.apple.preference.security?Microphone"
  - "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
  - "x-apple.systempreferences:com.apple.preference.security?Privacy_AppleEvents"
  - "https://aistudio.google.com/apikey"
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
from typing import Optional, Tuple

# Path constants — overridable for tests.
SEEN_TIPS_PATH: str = os.path.join(
    os.path.expanduser("~/.openvoiceflow"), "_seen_tips.json"
)

DEFAULT_TITLE = "OpenVoiceFlow"


# ─────────────────────────────────────────────────────────────────────
# Internal: surface emitters
# ─────────────────────────────────────────────────────────────────────


def _post_macos_notification(
    title: str,
    message: str,
    *,
    subtitle: Optional[str] = None,
    sound: Optional[str] = None,
    action_label: Optional[str] = None,
    action_url: Optional[str] = None,
) -> None:
    """Emit via osascript display notification.

    macOS Notification Center notifications require the user to grant
    Notifications permission. The action_label/action_url are encoded
    in the subtitle for visibility — full action-button support
    requires an NSUserNotification (Swift sidecar).
    """
    if action_label and action_url:
        subtitle = f"{subtitle or ''} · {action_label}".strip(" ·")
    parts = [
        f'display notification "{_esc(message)}"',
        f'with title "{_esc(title)}"',
    ]
    if subtitle:
        parts.append(f'subtitle "{_esc(subtitle)}"')
    if sound:
        parts.append(f'sound name "{_esc(sound)}"')
    script = " ".join(parts)
    try:
        subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            timeout=3,
            check=False,
        )
    except (subprocess.SubprocessError, OSError, FileNotFoundError):
        pass


def _esc(s: str) -> str:
    """Escape a string for AppleScript literal context."""
    return s.replace("\\", "\\\\").replace('"', '\\"')


def _overlay_show(method: str, *args, **kwargs) -> None:
    """Forward to the floating overlay HUD if PyObjC is available.

    Defined as a module-level function (not a direct call) so tests can
    monkeypatch the surface without touching AppKit. Real implementation
    lazy-imports voiceflow.overlay so the module-load doesn't bind.
    """
    try:
        from .overlay import get_overlay
    except Exception:
        return
    try:
        overlay = get_overlay()
        fn = getattr(overlay, method, None)
        if fn is not None:
            fn(*args, **kwargs)
    except Exception:
        # Overlay is best-effort. A failure here must never break
        # the caller's flow.
        pass


def _stderr(prefix: str, message: str) -> None:
    print(f"{prefix} {message}", file=sys.stderr)


# ─────────────────────────────────────────────────────────────────────
# Internal: seen-tips persistence (one-time tip de-duplication)
# ─────────────────────────────────────────────────────────────────────


def _load_seen_tips() -> set:
    try:
        with open(SEEN_TIPS_PATH) as f:
            data = json.load(f)
        if not isinstance(data, dict):
            return set()
        seen = data.get("seen", [])
        if not isinstance(seen, list):
            return set()
        return {s for s in seen if isinstance(s, str)}
    except (FileNotFoundError, json.JSONDecodeError, OSError, ValueError):
        return set()


def _save_seen_tips(seen: set) -> None:
    """Persist the seen-tips set with mode 0o600 (atomic, like the other
    ~/.openvoiceflow artifacts — no umask window, no truncate-then-crash)."""
    path = SEEN_TIPS_PATH
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        from ._secure_io import secure_write_json
        secure_write_json(path, {"seen": sorted(seen)})
    except OSError:
        pass


# ─────────────────────────────────────────────────────────────────────
# Public API
# ─────────────────────────────────────────────────────────────────────


def info(message: str, *, title: str = DEFAULT_TITLE) -> None:
    """Non-blocking status update. No stderr noise."""
    _post_macos_notification(title, message)
    _overlay_show("show_info", message)


def success(message: str, *, title: str = DEFAULT_TITLE) -> None:
    """Positive feedback (auto-learn fired, profile applied, etc.)."""
    _post_macos_notification(title, message, sound="Glass")
    _overlay_show("show_learned", message)


def warn(
    message: str,
    *,
    title: str = DEFAULT_TITLE,
    action: Optional[Tuple[str, str]] = None,
) -> None:
    """Heads-up with optional click-to-fix action."""
    action_label, action_url = (action or (None, None))
    _post_macos_notification(
        title,
        message,
        action_label=action_label,
        action_url=action_url,
    )
    _stderr("⚠", message)


def error(
    message: str,
    *,
    title: str = DEFAULT_TITLE,
    action: Optional[Tuple[str, str]] = None,
) -> None:
    """Visible failure with optional click-to-fix action."""
    action_label, action_url = (action or (None, None))
    _post_macos_notification(
        title,
        message,
        sound="Basso",
        action_label=action_label,
        action_url=action_url,
    )
    _stderr("❌", message)
    _overlay_show("show_error", message)


def tip(
    message: str,
    *,
    title: str = DEFAULT_TITLE,
    once_key: Optional[str] = None,
) -> None:
    """One-time educational nudge.

    If ``once_key`` is supplied and has been seen before, the tip is
    silently suppressed. Implements the voice-command tutor, per-app
    context introduction, auto-learn-just-fired moment, etc., without
    code-level state in each call site.
    """
    if once_key:
        seen = _load_seen_tips()
        if once_key in seen:
            return
        seen.add(once_key)
        _save_seen_tips(seen)
    _post_macos_notification(title, message)
    _overlay_show("show_info", message)
