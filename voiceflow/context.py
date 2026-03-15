"""Per-app context detection for OpenVoiceFlow.

Detects the frontmost macOS application and maps it to a dictation style,
enabling automatic style switching as the user moves between apps.

PyObjC is an optional dependency (also used by overlay.py).  Falls back
gracefully when unavailable (non-macOS or missing optional deps).
"""

# ---------------------------------------------------------------------------
# Frontmost app detection
# ---------------------------------------------------------------------------

try:
    from AppKit import NSWorkspace
    _HAS_NSWORKSPACE = True
except ImportError:
    _HAS_NSWORKSPACE = False


def get_frontmost_app() -> str:
    """Return the localized name of the frontmost application.

    Uses ``NSWorkspace.sharedWorkspace().frontmostApplication()`` (PyObjC)
    for a near-instant, deterministic result that works across Spaces and
    full-screen apps.

    Returns an empty string when PyObjC is unavailable or detection fails so
    callers can fall back to the global style without crashing.

    Example return values: ``"Code"``, ``"Xcode"``, ``"Slack"``, ``"Mail"``,
    ``"Terminal"``.
    """
    if not _HAS_NSWORKSPACE:
        return ""
    try:
        ws = NSWorkspace.sharedWorkspace()
        app = ws.frontmostApplication()
        if app is None:
            return ""
        name = app.localizedName()
        return str(name) if name else ""
    except Exception:
        return ""


# ---------------------------------------------------------------------------
# Style resolution
# ---------------------------------------------------------------------------

def get_style_for_app(app_name: str, config: dict) -> str:
    """Resolve the dictation style for a given frontmost app.

    Looks up *app_name* in ``config["app_styles"]`` (exact match first, then
    case-insensitive).  When ``auto_style`` is ``False`` in config, or no
    mapping exists, returns the global ``config["style"]`` value.

    Args:
        app_name: The localized application name (e.g. ``"Code"``, ``"Slack"``).
        config:   The loaded OpenVoiceFlow config dict.

    Returns:
        A style string: one of ``"default"``, ``"casual"``, ``"formal"``,
        ``"code"``, or ``"email"``.
    """
    global_style: str = config.get("style", "default")

    if not app_name:
        return global_style

    if not config.get("auto_style", True):
        return global_style

    app_styles: dict = config.get("app_styles", {})

    # 1. Exact match
    if app_name in app_styles:
        return app_styles[app_name]

    # 2. Case-insensitive fallback
    lower = app_name.lower()
    for key, style in app_styles.items():
        if key.lower() == lower:
            return style

    return global_style


# ---------------------------------------------------------------------------
# LLM context fragment
# ---------------------------------------------------------------------------

# Per-style human-readable usage hints injected into the LLM prompt.
_STYLE_HINTS: dict[str, str] = {
    "code": "writing code, a commit message, or a developer note",
    "email": "composing an email",
    "casual": "sending a chat or instant message",
    "formal": "writing a formal document",
    "default": "general dictation",
}


def get_app_context_prompt(app_name: str, style: str = "") -> str:
    """Return a short LLM context fragment describing the active app.

    Example output::

        "\\nThe user is currently dictating in VS Code (writing code, a commit
        message, or a developer note). Adjust your output accordingly."

    Args:
        app_name: The localized application name.
        style:    The resolved style string (enriches the hint when known).

    Returns:
        A non-empty string when *app_name* is provided; empty string otherwise.
    """
    if not app_name:
        return ""

    hint = _STYLE_HINTS.get(style, "")
    if hint:
        return (
            f"\nThe user is currently dictating in {app_name} "
            f"({hint}). Adjust your output accordingly."
        )
    return f"\nThe user is currently dictating in {app_name}. Adjust your output accordingly."
