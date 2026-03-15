"""Auto-update checker for OpenVoiceFlow.

Checks GitHub releases on startup (non-blocking thread) and notifies the user
if a newer version is available via macOS Notification Center.
"""
import threading
import json
import urllib.request
import urllib.error
from typing import Callable

from . import __version__

GITHUB_RELEASES_API = "https://api.github.com/repos/shimoverse/openvoiceflow/releases/latest"
CHECK_TIMEOUT = 8  # seconds


def _parse_version(version_str: str) -> tuple[int, ...]:
    """Parse a semver string like '0.2.1' into a tuple for comparison."""
    v = version_str.lstrip("v").strip()
    try:
        return tuple(int(x) for x in v.split("."))
    except (ValueError, AttributeError):
        return (0,)


def _fetch_latest_release() -> dict | None:
    """Fetch the latest release info from GitHub API.

    Returns a dict with 'tag_name', 'html_url', 'body' keys, or None on error.
    """
    try:
        req = urllib.request.Request(
            GITHUB_RELEASES_API,
            headers={"User-Agent": f"OpenVoiceFlow/{__version__}"},
        )
        with urllib.request.urlopen(req, timeout=CHECK_TIMEOUT) as resp:
            if resp.status == 200:
                return json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, urllib.error.HTTPError, OSError, json.JSONDecodeError):
        pass
    return None


def check_for_updates(on_update_available: Callable[[str, str], None] | None = None) -> None:
    """Check for updates in a background thread (non-blocking).

    Args:
        on_update_available: Optional callback(latest_version, release_url).
            If None, shows a macOS notification and prints to stdout.
    """
    thread = threading.Thread(
        target=_check_worker,
        args=(on_update_available,),
        daemon=True,
        name="openvoiceflow-updater",
    )
    thread.start()


def _check_worker(on_update_available: Callable | None) -> None:
    """Background worker: fetch release and compare versions."""
    release = _fetch_latest_release()
    if not release:
        return

    latest_tag = release.get("tag_name", "")
    release_url = release.get("html_url", "https://github.com/shimoverse/openvoiceflow/releases")
    release_notes = release.get("body", "")

    latest_version = _parse_version(latest_tag)
    current_version = _parse_version(__version__)

    if latest_version <= current_version:
        return  # Already up to date

    latest_str = latest_tag.lstrip("v")
    if on_update_available:
        on_update_available(latest_str, release_url)
    else:
        # Default: print + macOS notification
        print(f"\n🆕 Update available: v{latest_str} (you have v{__version__})")
        print(f"   Download: {release_url}\n")
        _send_notification(latest_str, release_url)


def _send_notification(latest_version: str, release_url: str) -> None:
    """Show a macOS Notification Center alert for the update."""
    try:
        import subprocess
        script = (
            f'display notification "OpenVoiceFlow v{latest_version} is available. '
            f'Visit {release_url}" '
            f'with title "OpenVoiceFlow Update Available" '
            f'subtitle "You have v{__version__}" '
            f'sound name "Glass"'
        )
        subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            timeout=5,
        )
    except Exception:
        pass  # Notification is best-effort
