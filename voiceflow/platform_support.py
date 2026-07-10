"""Operating-system and hardware detection for OpenVoiceFlow.

Single source of truth for "are we on a supported platform?" questions.
OpenVoiceFlow supports macOS 12+ only; every helper here degrades to an
informative answer (never an exception) so callers can gate features and
print friendly guidance instead of crashing with a traceback on Linux,
Windows, or an unsupported macOS release.

See docs/COMPATIBILITY.md for the support matrix.
"""

from __future__ import annotations

import ctypes
import platform
import subprocess
import sys
from typing import Optional

# Minimum supported macOS release (Monterey). Below this we refuse politely.
MIN_MACOS = (12, 0)

# Highest macOS major release the maintainers have exercised on real
# hardware. Newer releases are expected to work; the doctor reports them
# as untested rather than unsupported. Keep in sync with COMPATIBILITY.md.
LATEST_TESTED_MACOS = 15


def is_macos() -> bool:
    """True when running on macOS (any version)."""
    return sys.platform == "darwin"


def macos_version() -> Optional[tuple]:
    """Return the macOS version as an int tuple (e.g. ``(14, 5)``).

    Returns None off-macOS or when the version cannot be parsed.
    """
    if not is_macos():
        return None
    ver = platform.mac_ver()[0]
    try:
        parts = tuple(int(p) for p in ver.split(".") if p)
    except ValueError:
        return None
    return parts or None


def os_label() -> str:
    """Friendly OS name for user-facing messages (e.g. ``macOS 14.5``)."""
    if is_macos():
        ver = platform.mac_ver()[0]
        return f"macOS {ver}".strip()
    system = platform.system() or "an unknown operating system"
    release = platform.release()
    return f"{system} {release}".strip()


def arch() -> str:
    """Machine architecture of the running interpreter (arm64, x86_64, ...)."""
    return platform.machine()


def is_rosetta_translated() -> bool:
    """True when this process is x86_64 code translated on Apple Silicon."""
    if not is_macos():
        return False
    try:
        result = subprocess.run(
            ["sysctl", "-n", "sysctl.proc_translated"],
            capture_output=True, text=True, timeout=2,
        )
        return result.stdout.strip() == "1"
    except (subprocess.SubprocessError, OSError):
        return False


def is_apple_silicon() -> bool:
    """True on Apple Silicon hardware, even when running under Rosetta."""
    if not is_macos():
        return False
    return arch() == "arm64" or is_rosetta_translated()


# ─────────────────────────────────────────────────────────────────────
# macOS permission probes (best-effort; None = could not determine)
# ─────────────────────────────────────────────────────────────────────


def accessibility_status() -> Optional[bool]:
    """Whether the process is trusted for the Accessibility APIs.

    Returns True/False when determinable, None when the query itself is
    unavailable (off-macOS, or the framework could not be loaded).
    """
    if not is_macos():
        return None
    try:
        from ApplicationServices import AXIsProcessTrusted  # type: ignore
        return bool(AXIsProcessTrusted())
    except Exception:
        pass
    try:
        app_services = ctypes.CDLL(
            "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
        )
        app_services.AXIsProcessTrusted.restype = ctypes.c_bool
        return bool(app_services.AXIsProcessTrusted())
    except Exception:
        return None


def input_monitoring_status() -> Optional[bool]:
    """Whether Input Monitoring (keyboard event listening) is granted.

    Uses ``IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)`` (macOS 10.15+).
    Returns True when granted, False when denied, None when undetermined
    (macOS will prompt on first use) or when the query is unavailable.
    """
    if not is_macos():
        return None
    try:
        iokit = ctypes.CDLL("/System/Library/Frameworks/IOKit.framework/IOKit")
        iokit.IOHIDCheckAccess.restype = ctypes.c_uint32
        iokit.IOHIDCheckAccess.argtypes = [ctypes.c_uint32]
        status = iokit.IOHIDCheckAccess(1)  # kIOHIDRequestTypeListenEvent
        if status == 0:  # kIOHIDAccessTypeGranted
            return True
        if status == 1:  # kIOHIDAccessTypeDenied
            return False
        return None  # kIOHIDAccessTypeUnknown — not yet requested
    except Exception:
        return None


def microphone_status() -> Optional[bool]:
    """Whether Microphone access is granted.

    Requires pyobjc-framework-AVFoundation (not part of our extras), so
    this commonly returns None; treat None as "will be requested on first
    recording", not as an error.
    """
    if not is_macos():
        return None
    try:
        from AVFoundation import (  # type: ignore
            AVCaptureDevice,
            AVMediaTypeAudio,
        )
        status = AVCaptureDevice.authorizationStatusForMediaType_(AVMediaTypeAudio)
        if status == 3:  # AVAuthorizationStatusAuthorized
            return True
        if status in (1, 2):  # Restricted / Denied
            return False
        return None  # NotDetermined — macOS prompts on first use
    except Exception:
        return None


# ─────────────────────────────────────────────────────────────────────
# User-facing guidance
# ─────────────────────────────────────────────────────────────────────


def unsupported_os_message() -> str:
    """Explain why OpenVoiceFlow cannot run here, and how to remove it."""
    return (
        f"OpenVoiceFlow only runs on macOS {MIN_MACOS[0]} or newer — this machine is "
        f"running {os_label()}.\n"
        "\n"
        "The app depends on macOS-only services (the AppKit menu bar, pbcopy/pbpaste,\n"
        "osascript key events, and the Accessibility APIs), so dictation cannot work\n"
        "here. Nothing was started and nothing is running in the background.\n"
        "\n"
        "To remove OpenVoiceFlow from this machine:\n"
        "  pip uninstall openvoiceflow\n"
        "  rm -rf ~/.openvoiceflow\n"
        "\n"
        "Diagnostics still work: openvoiceflow --doctor / --show-config\n"
        "Support matrix: https://github.com/shimoverse/openvoiceflow/blob/main/docs/COMPATIBILITY.md"
    )


def old_macos_warning() -> Optional[str]:
    """A warning string when this macOS is older than the supported floor."""
    ver = macos_version()
    if ver is None or ver >= MIN_MACOS:
        return None
    return (
        f"⚠️  {os_label()} is older than the supported minimum (macOS {MIN_MACOS[0]}). "
        "OpenVoiceFlow may not work correctly — please upgrade macOS."
    )
