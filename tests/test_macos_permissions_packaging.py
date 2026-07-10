from __future__ import annotations

import plistlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = ROOT / "build-dmg.sh"
ENTITLEMENTS = ROOT / "assets" / "OpenVoiceFlow.entitlements"
LAUNCHER_SOURCE = ROOT / "packaging" / "OpenVoiceFlowLauncher.m"


def test_signed_app_is_entitled_to_capture_audio() -> None:
    """Hardened-runtime builds need explicit audio-input authorization."""
    assert ENTITLEMENTS.is_file()

    with ENTITLEMENTS.open("rb") as handle:
        entitlements = plistlib.load(handle)

    assert entitlements["com.apple.security.device.audio-input"] is True
    assert entitlements["com.apple.security.automation.apple-events"] is True

    build_script = BUILD_SCRIPT.read_text(encoding="utf-8")
    assert 'ENTITLEMENTS_FILE="$SCRIPT_DIR/assets/OpenVoiceFlow.entitlements"' in build_script
    assert '--entitlements "$ENTITLEMENTS_FILE"' in build_script


def test_launcher_requests_permissions_and_shows_only_one_fallback_dialog() -> None:
    """First launch should register both TCC services without stacked dialogs."""
    build_script = BUILD_SCRIPT.read_text(encoding="utf-8")
    launcher_source = LAUNCHER_SOURCE.read_text(encoding="utf-8")

    assert "AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio" in launcher_source
    assert "AXIsProcessTrustedWithOptions" in launcher_source
    assert "kAXTrustedCheckOptionPrompt" in launcher_source
    assert "Open Microphone Settings" in launcher_source
    assert '-framework AVFoundation' in build_script
    assert '-framework ApplicationServices' in build_script
    assert 'Contents/Resources/launcher.sh' in build_script
    assert "ask_permission_help" not in build_script
    assert "ask_permissions_menu" not in build_script
