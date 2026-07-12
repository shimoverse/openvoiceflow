"""Launch at login support via macOS LaunchAgent.

Creates or removes a LaunchAgent plist in ~/Library/LaunchAgents/ so
OpenVoiceFlow starts automatically on macOS login.

Supports macOS 12+ on both Apple Silicon and Intel.
"""

from __future__ import annotations

import os
import plistlib
import shutil
import subprocess
import sys
from pathlib import Path

from . import platform_support

LAUNCH_AGENTS_DIR = Path.home() / "Library" / "LaunchAgents"
PLIST_NAME = "com.openvoiceflow.app.plist"
PLIST_PATH = LAUNCH_AGENTS_DIR / PLIST_NAME
LABEL = "com.openvoiceflow.app"


def _get_executable() -> str | None:
    """Return the path to the openvoiceflow executable, or None if not found.

    A bare command name is useless here: launchd resolves it only against the
    plist's hardcoded PATH, so a source/venv install would silently never
    start at login while `--autostart on` reports success.
    """
    # Prefer the executable next to this Python interpreter
    venv_bin = Path(sys.executable).parent
    candidate = venv_bin / "openvoiceflow"
    if candidate.exists():
        return str(candidate)
    return shutil.which("openvoiceflow")


def _build_plist(executable: str) -> str:
    """Generate a LaunchAgent plist XML string.

    Built with plistlib so a path containing XML metacharacters (``&``,
    ``<``) can't produce an invalid plist. The log files are pre-created
    with mode 600: launchd would otherwise create them world-readable, and
    stdout includes dictated text.
    """
    log_dir = Path.home() / ".openvoiceflow" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    stdout_log = log_dir / "launchagent.log"
    stderr_log = log_dir / "launchagent-error.log"
    for log_file in (stdout_log, stderr_log):
        try:
            log_file.touch(exist_ok=True)
            os.chmod(log_file, 0o600)
        except OSError:
            pass

    plist = {
        "Label": LABEL,
        "ProgramArguments": [executable, "--menubar"],
        "RunAtLoad": True,
        "KeepAlive": False,
        "StandardOutPath": str(stdout_log),
        "StandardErrorPath": str(stderr_log),
        "EnvironmentVariables": {
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
        },
    }
    return plistlib.dumps(plist).decode("utf-8")


def set_autostart(enabled: bool) -> tuple[bool, str]:
    """Enable or disable launch at login.

    Args:
        enabled: True to enable, False to disable.

    Returns:
        (success, message) tuple.
    """
    if not platform_support.is_macos():
        return False, (
            "Launch at login uses macOS LaunchAgents and is not available on "
            f"{platform_support.os_label()}."
        )
    if enabled:
        return _enable_autostart()
    else:
        return _disable_autostart()


def _launchctl(modern_args: list, legacy_args: list) -> subprocess.CompletedProcess:
    """Run launchctl with the modern subcommand, falling back to the legacy one.

    ``bootstrap``/``bootout`` are the supported interface on macOS 10.11+;
    ``load``/``unload`` are deprecated but still function. Trying modern
    first keeps us working when Apple eventually removes the legacy verbs,
    and the fallback keeps us working everywhere they still exist.
    """
    # timeout: a wedged launchd would otherwise hang the CLI indefinitely
    # with no output. TimeoutExpired propagates to the callers' broad
    # except handlers, which surface it as a (False, message) result.
    result = subprocess.run(
        ["launchctl"] + modern_args, capture_output=True, text=True, timeout=15,
    )
    if result.returncode != 0:
        result = subprocess.run(
            ["launchctl"] + legacy_args, capture_output=True, text=True, timeout=15,
        )
    return result


def _enable_autostart() -> tuple[bool, str]:
    """Install the LaunchAgent plist and load it."""
    try:
        LAUNCH_AGENTS_DIR.mkdir(parents=True, exist_ok=True)
        executable = _get_executable()
        if not executable:
            return False, (
                "Could not find the openvoiceflow executable "
                f"(looked next to {sys.executable} and on PATH). "
                "Autostart needs an installed command to launch at login."
            )
        plist_content = _build_plist(executable)
        PLIST_PATH.write_text(plist_content, encoding="utf-8")

        gui_domain = f"gui/{os.getuid()}"
        # Unload first (ignore error if not loaded)
        _launchctl(
            ["bootout", gui_domain, str(PLIST_PATH)],
            ["unload", str(PLIST_PATH)],
        )
        # Load the agent
        result = _launchctl(
            ["bootstrap", gui_domain, str(PLIST_PATH)],
            ["load", str(PLIST_PATH)],
        )
        if result.returncode != 0:
            err = result.stderr.strip() or result.stdout.strip()
            # macOS 12+ may show a benign warning — still succeeds
            if "already loaded" not in err.lower():
                return False, f"launchctl load failed: {err}"

        return True, str(PLIST_PATH)
    except Exception as e:
        return False, str(e)


def _disable_autostart() -> tuple[bool, str]:
    """Unload and remove the LaunchAgent plist."""
    try:
        if PLIST_PATH.exists():
            _launchctl(
                ["bootout", f"gui/{os.getuid()}", str(PLIST_PATH)],
                ["unload", str(PLIST_PATH)],
            )
            PLIST_PATH.unlink()
            return True, "LaunchAgent removed"
        else:
            return True, "LaunchAgent was not installed"
    except Exception as e:
        return False, str(e)


def get_autostart_status() -> bool:
    """Return True if the LaunchAgent plist exists (autostart is enabled)."""
    return PLIST_PATH.exists()
