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


def test_bootstrap_does_not_copy_the_python_framework_launcher() -> None:
    """Renaming framework Python breaks its relative @executable_path lookup."""
    build_script = BUILD_SCRIPT.read_text(encoding="utf-8")

    assert 'PY_RUN="\\$PY"' in build_script
    assert 'cp "\\$PY" "\\$PY_RUN"' not in build_script


def test_native_launcher_surfaces_bootstrap_failures() -> None:
    """A bootstrap crash must show a visible error instead of silently exiting."""
    launcher_source = LAUNCHER_SOURCE.read_text(encoding="utf-8")

    assert "showBootstrapFailure" in launcher_source
    assert "Open Launcher Log" in launcher_source
    assert "task.terminationStatus != 0" in launcher_source


def test_tk_onboarding_runs_outside_the_long_lived_menu_process() -> None:
    """A native Tk abort must not take down the menu-bar application."""
    build_script = BUILD_SCRIPT.read_text(encoding="utf-8")

    assert "import subprocess" in build_script
    assert "subprocess.run([sys.executable, '-c', onboarding_code]" in build_script
    assert "Onboarding process exited with status" in build_script


def test_python_menu_process_keeps_the_openvoiceflow_app_identity() -> None:
    """The rumps child must remain a Dock-less app with the bundled icon."""
    build_script = BUILD_SCRIPT.read_text(encoding="utf-8")
    menubar = (ROOT / "voiceflow" / "menubar.py").read_text(encoding="utf-8")

    assert 'export OPENVOICEFLOW_APP_RESOURCES="\\$RESOURCES"' in build_script
    assert "NSApplicationActivationPolicyAccessory" in menubar
    assert "setActivationPolicy_" in menubar
    assert "setApplicationIconImage_" in menubar
