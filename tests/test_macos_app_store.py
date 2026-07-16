import json
import plistlib
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STORE = ROOT / "macos" / "AppStore"
MODEL_SHA256 = "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"
WHISPER_XCFRAMEWORK_SHA256 = "8c3ecbe73f48b0cb9318fc3058264f951ab336fd530e82c4ccdd2298d1311a4c"


def test_store_target_has_separate_xcodegen_project_and_bundle_identifier():
    project = (STORE / "project.yml").read_text(encoding="utf-8")

    assert "OpenVoiceFlowStore" in project
    assert "com.shimoverse.openvoiceflow" in project
    assert "macOS: \"13.3\"" in project
    assert "CODE_SIGN_STYLE: Manual" in project
    assert 'CODE_SIGN_IDENTITY: "3rd Party Mac Developer Application"' in project
    assert 'PROVISIONING_PROFILE_SPECIFIER: "OpenVoiceFlow Mac App Store Profile"' in project
    assert "PRODUCT_BUNDLE_IDENTIFIER: com.shimoverse.openvoiceflow" in project


def test_store_entitlements_are_sandboxed_and_minimal():
    with (STORE / "Config" / "OpenVoiceFlowStore.entitlements").open("rb") as handle:
        entitlements = plistlib.load(handle)

    assert entitlements["com.apple.security.app-sandbox"] is True
    assert entitlements["com.apple.security.device.audio-input"] is True
    assert "com.apple.security.automation.apple-events" not in entitlements
    assert "com.apple.security.temporary-exception.apple-events" not in entitlements
    assert "com.apple.security.files.user-selected.read-write" not in entitlements


def test_store_info_and_privacy_manifests_explain_microphone_use():
    with (STORE / "Config" / "Info.plist").open("rb") as handle:
        info = plistlib.load(handle)
    with (STORE / "Resources" / "PrivacyInfo.xcprivacy").open("rb") as handle:
        privacy = plistlib.load(handle)

    assert info["CFBundleDisplayName"] == "OpenVoiceFlow"
    assert "transcrib" in info["NSMicrophoneUsageDescription"].lower()
    assert info["LSApplicationCategoryType"] == "public.app-category.productivity"
    assert info["ITSAppUsesNonExemptEncryption"] is False
    assert privacy["NSPrivacyTracking"] is False
    assert privacy["NSPrivacyCollectedDataTypes"] == []


def test_whisper_runtime_and_model_are_version_and_checksum_pinned():
    package = (STORE / "WhisperPackage" / "Package.swift").read_text(encoding="utf-8")
    manifest = json.loads((STORE / "Resources" / "ModelManifest.json").read_text(encoding="utf-8"))
    prepare_script = (STORE / "Scripts" / "prepare-model.sh").read_text(encoding="utf-8")

    assert "whisper-v1.9.1-xcframework.zip" in package
    assert WHISPER_XCFRAMEWORK_SHA256 in package
    assert manifest == {
        "filename": "ggml-base.en.bin",
        "source": "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin",
        "sha256": MODEL_SHA256,
        "bytes": 147964211,
    }
    assert MODEL_SHA256 in prepare_script
    assert "shasum -a 256" in prepare_script
    assert "BuildResources/Models/ggml-base.en.bin" in prepare_script


def test_store_runtime_does_not_bootstrap_or_inject_into_other_apps():
    source = "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted((STORE / "Sources").glob("*.swift"))
    )
    forbidden = [
        "launcher.sh",
        "brew install",
        "pip install",
        "/bin/bash",
        "Process(",
        "AXIsProcessTrusted",
        "IOHIDRequestAccess",
        "CGEvent.post",
        "osascript",
    ]

    assert "RegisterEventHotKey" in source
    assert "NSPasteboard.general" in source
    for marker in forbidden:
        assert marker not in source


def test_native_store_app_has_local_first_dashboard_and_onboarding_surfaces():
    source = "\n".join(
        path.read_text(encoding="utf-8")
        for path in sorted((STORE / "Sources").glob("*.swift"))
    )

    for marker in [
        "NavigationSplitView",
        "OnboardingView",
        "Insights",
        "Dictionary",
        "English only",
        "LocalStore",
        "Profile",
        "Nothing is sent",
    ]:
        assert marker in source


def test_store_submission_metadata_and_public_policy_pages_exist():
    required_store_files = [
        "README.md",
        "Metadata/en-US/name.txt",
        "Metadata/en-US/subtitle.txt",
        "Metadata/en-US/description.txt",
        "Metadata/en-US/keywords.txt",
        "Metadata/review-notes.md",
        "Metadata/privacy-labels.md",
        "Metadata/submission-checklist.md",
    ]
    for relative in required_store_files:
        assert (STORE / relative).is_file(), relative

    for name in ["privacy.html", "support.html", "terms.html"]:
        page = ROOT / "docs" / name
        assert page.is_file(), name
        html = page.read_text(encoding="utf-8")
        assert "OpenVoiceFlow" in html
        assert '<link rel="canonical"' in html

    sitemap = (ROOT / "docs" / "sitemap.xml").read_text(encoding="utf-8")
    for name in ["privacy.html", "support.html", "terms.html"]:
        assert f"https://openvoiceflow.vercel.app/{name}" in sitemap


def test_store_build_resources_are_not_committed():
    ignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
    model = STORE / "BuildResources" / "Models" / "ggml-base.en.bin"

    assert "macos/AppStore/BuildResources/" in ignore
    tracked = subprocess.run(
        ["git", "ls-files", "--error-unmatch", str(model.relative_to(ROOT))],
        cwd=ROOT,
        capture_output=True,
        text=True,
    )
    assert tracked.returncode != 0


def test_archive_script_pins_full_xcode_installation():
    script = (STORE / "Scripts" / "archive-app-store.sh").read_text(encoding="utf-8")

    assert "DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer" in script
    assert "xcodebuild" in script
    export_options = (STORE / "Config" / "ExportOptions.plist").read_text(encoding="utf-8")
    assert "3rd Party Mac Developer Application" in export_options
    assert "3rd Party Mac Developer Installer" in export_options
    assert "OpenVoiceFlow Mac App Store Profile" in export_options
