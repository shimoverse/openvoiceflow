"""Auto-update checker for OpenVoiceFlow.

Checks GitHub releases on startup (non-blocking thread) and notifies the user
if a newer version is available via macOS Notification Center.
"""

from __future__ import annotations

import json
import re
import threading
import urllib.error
import urllib.request
from typing import Callable

from . import __version__

GITHUB_RELEASES_API = "https://api.github.com/repos/shimoverse/openvoiceflow/releases/latest"
GITHUB_RELEASES_URL = "https://github.com/shimoverse/openvoiceflow/releases"
CHECK_TIMEOUT = 8  # seconds

ManualUpdateCallback = Callable[[str, str, str], None]


def _parse_version(version_str: str) -> tuple[int, ...]:
    """Parse a version string like '0.2.1' into a tuple for comparison.

    Pre-release suffixes are tolerated by taking the leading numeric part of
    each segment: 'v1.0.0-rc1' → (1, 0, 0), '0.4.0.dev1' → (0, 4, 0).
    A completely unparsable string yields (0,) so it never wins a comparison.
    """
    v = str(version_str).lstrip("vV").strip()
    parts: list[int] = []
    for segment in v.replace("-", ".").split("."):
        m = re.match(r"\d+", segment)
        if not m:
            break
        parts.append(int(m.group()))
    return tuple(parts) or (0,)


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
                data = json.loads(resp.read().decode("utf-8"))
                return data if isinstance(data, dict) else None
    except Exception:
        # Deliberately broad: this worker's caller (the menubar's manual
        # "Check for Updates…") relies on ALWAYS getting a callback to
        # re-enable the menu item. urllib can also leak exceptions outside
        # URLError — e.g. http.client.BadStatusLine through a broken proxy,
        # or UnicodeDecodeError from a captive portal answering 200 with
        # non-UTF-8 — and any escapee would kill the thread silently.
        pass
    return None


def check_for_updates(
    config: dict | None = None,
    on_update_available: Callable[[str, str], None] | None = None,
) -> None:
    """Check for updates in a background thread (non-blocking).

    Args:
        config: Optional loaded config dict. When ``config["update_check"]``
            is False, this function returns immediately without spawning a
            thread or making any network call. If ``config`` is None, loads
            it lazily; if loading fails, defaults to checking (for back-compat).
        on_update_available: Optional callback(latest_version, release_url).
            If None, shows a macOS notification and prints to stdout.
    """
    if config is None:
        try:
            from .config import load_config
            config = load_config()
        except Exception:
            config = {}
    if config.get("update_check", True) is False:
        return
    thread = threading.Thread(
        target=_check_worker,
        args=(on_update_available,),
        daemon=True,
        name="openvoiceflow-updater",
    )
    thread.start()


def check_for_updates_now(on_result: ManualUpdateCallback) -> None:
    """Run a user-requested update check without blocking the menu bar.

    Unlike the quiet startup check, this always calls ``on_result`` with one
    of ``"available"``, ``"current"``, or ``"error"`` so the menu can give
    the user a definitive answer.
    """
    thread = threading.Thread(
        target=_manual_check_worker,
        args=(on_result,),
        daemon=True,
        name="openvoiceflow-manual-updater",
    )
    thread.start()


def _check_worker(on_update_available: Callable | None) -> None:
    """Background worker: fetch release and compare versions."""
    release = _fetch_latest_release()
    if not release:
        return

    latest_tag = release.get("tag_name", "")
    release_url = release.get("html_url", "https://github.com/shimoverse/openvoiceflow/releases")

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


def _manual_check_worker(on_result: ManualUpdateCallback) -> None:
    """Fetch and classify the latest release for an explicit menu action."""
    release = _fetch_latest_release()
    if not release:
        on_result("error", "", GITHUB_RELEASES_URL)
        return

    latest_tag = release.get("tag_name", "")
    release_url = release.get("html_url", GITHUB_RELEASES_URL)
    latest_str = latest_tag.lstrip("vV")
    if _parse_version(latest_tag) > _parse_version(__version__):
        on_result("available", latest_str, release_url)
    else:
        on_result("current", latest_str or __version__, release_url)


def _send_notification(latest_version: str, release_url: str) -> None:
    """Show a macOS Notification Center alert for the update.

    Both values originate from the GitHub API response, so they are escaped
    before interpolation into the AppleScript source — an unescaped quote
    would otherwise break out of the string literal.
    """
    try:
        import subprocess

        from .notify import _esc
        script = (
            f'display notification "OpenVoiceFlow v{_esc(latest_version)} is available. '
            f'Visit {_esc(release_url)}" '
            f'with title "OpenVoiceFlow Update Available" '
            f'subtitle "You have v{_esc(__version__)}" '
            f'sound name "Glass"'
        )
        subprocess.run(
            ["osascript", "-e", script],
            capture_output=True,
            timeout=5,
        )
    except Exception:
        pass  # Notification is best-effort
