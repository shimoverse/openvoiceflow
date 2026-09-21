from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def test_github_actions_use_node_24_compatible_major_versions():
    combined = "\n".join(read(path) for path in WORKFLOWS.glob("*.yml"))

    assert "actions/checkout@v6" in combined
    assert "actions/setup-python@v6" in combined
    assert "actions/checkout@v4" not in combined
    assert "actions/setup-python@v5" not in combined


def test_pyproject_packages_agpl_with_notice_and_legacy_license_files():
    pyproject = read(ROOT / "pyproject.toml")

    # SPDX id, not a LicenseRef: the project is on a standard OSI license now.
    assert 'license = "AGPL-3.0-only"' in pyproject
    # PEP 639 forbids License:: classifiers alongside an SPDX expression --
    # setuptools>=77 refuses to build if one is present. Keep them out.
    assert "License :: OSI Approved" not in pyproject
    # NOTICE carries the Section 7 additional terms, so it must ship in the
    # wheel alongside LICENSE; LEGACY_MIT_PORTIONS keeps the MIT provenance.
    assert (
        'license-files = ["LICENSE", "NOTICE", "legal/LEGACY_MIT_PORTIONS.md"]'
        in pyproject
    )
    assert 'license = {file = "LICENSE"}' not in pyproject
    assert 'license = "MIT"' not in pyproject
    assert "License :: OSI Approved :: MIT License" not in pyproject
    assert "LicenseRef-OpenVoiceFlow-Personal-Reciprocal" not in pyproject


def test_dmg_build_declares_icon_and_optional_apple_signing_pipeline():
    build_script = read(ROOT / "build-dmg.sh")
    release_workflow = read(WORKFLOWS / "release.yml")

    assert (ROOT / "assets" / "OpenVoiceFlow.icns").exists()
    assert (ROOT / "assets" / "openvoiceflow-icon-1024.png").exists()
    assert "CFBundleIconFile" in build_script
    assert "OpenVoiceFlow.icns" in build_script
    assert "OVF_SIGN_IDENTITY" in build_script
    assert "codesign" in build_script
    assert "OVF_NOTARIZE" in build_script
    assert "xcrun notarytool submit" in build_script
    assert "xcrun stapler staple" in build_script
    assert "spctl" in build_script
    assert "context:primary-signature" in build_script

    assert "APPLE_DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64" in release_workflow
    assert "APPLE_NOTARY_KEY_BASE64" in release_workflow
    assert "OVF_SIGN_IDENTITY" in release_workflow
    assert "OVF_NOTARIZE=1" in release_workflow
