"""Launch at login support via macOS LaunchAgent.

Creates or removes a LaunchAgent plist in ~/Library/LaunchAgents/ so
OpenVoiceFlow starts automatically on macOS login.

Supports macOS 12+ on both Apple Silicon and Intel.
"""
import os
import subprocess
import sys
from pathlib import Path

LAUNCH_AGENTS_DIR = Path.home() / "Library" / "LaunchAgents"
PLIST_NAME = "com.openvoiceflow.app.plist"
PLIST_PATH = LAUNCH_AGENTS_DIR / PLIST_NAME
LABEL = "com.openvoiceflow.app"


def _get_executable() -> str:
    """Return the path to the openvoiceflow executable."""
    # Prefer the executable next to this Python interpreter
    venv_bin = Path(sys.executable).parent
    candidate = venv_bin / "openvoiceflow"
    if candidate.exists():
        return str(candidate)
    # Fall back to which
    result = subprocess.run(["which", "openvoiceflow"], capture_output=True, text=True)
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()
    return "openvoiceflow"


def _build_plist(executable: str) -> str:
    """Generate a LaunchAgent plist XML string."""
    log_dir = Path.home() / ".openvoiceflow" / "logs"
    log_dir.mkdir(parents=True, exist_ok=True)
    stdout_log = log_dir / "launchagent.log"
    stderr_log = log_dir / "launchagent-error.log"

    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>{LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>{executable}</string>
        <string>--menubar</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
    <key>StandardOutPath</key>
    <string>{stdout_log}</string>
    <key>StandardErrorPath</key>
    <string>{stderr_log}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
"""


def set_autostart(enabled: bool) -> tuple[bool, str]:
    """Enable or disable launch at login.

    Args:
        enabled: True to enable, False to disable.

    Returns:
        (success, message) tuple.
    """
    if enabled:
        return _enable_autostart()
    else:
        return _disable_autostart()


def _enable_autostart() -> tuple[bool, str]:
    """Install the LaunchAgent plist and load it."""
    try:
        LAUNCH_AGENTS_DIR.mkdir(parents=True, exist_ok=True)
        executable = _get_executable()
        plist_content = _build_plist(executable)
        PLIST_PATH.write_text(plist_content, encoding="utf-8")

        # Unload first (ignore error if not loaded)
        subprocess.run(
            ["launchctl", "unload", str(PLIST_PATH)],
            capture_output=True,
        )
        # Load the agent
        result = subprocess.run(
            ["launchctl", "load", str(PLIST_PATH)],
            capture_output=True,
            text=True,
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
            subprocess.run(
                ["launchctl", "unload", str(PLIST_PATH)],
                capture_output=True,
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
