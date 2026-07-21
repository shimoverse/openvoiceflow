import json
from hashlib import sha256
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
CANONICAL = "https://openvoiceflow.vercel.app"
RELEASE_VERSION = "0.4.0"
UNIVERSAL_SHA256 = "99d75bf21da1bd5009eae5277e47614919c4ebc55b3586d9b9f08f35d998d2de"
FALLBACK = "OpenVoiceFlow-0.3.6-arm64.dmg"


def test_native_distribution_assets_exist_and_match_hashes():
    universal = DOCS / "downloads" / f"OpenVoiceFlow-{RELEASE_VERSION}.dmg"
    fallback = DOCS / "downloads" / FALLBACK
    assert universal.exists()
    assert fallback.exists(), "macOS 12–13 fallback must remain reachable"
    assert sha256(universal.read_bytes()).hexdigest() == UNIVERSAL_SHA256


def test_download_page_has_one_native_universal_primary_and_a_clear_fallback():
    html = (DOCS / "download.html").read_text(encoding="utf-8")
    assert f'"softwareVersion": "{RELEASE_VERSION}"' in html
    assert '"operatingSystem": "macOS 14+"' in html
    assert f"downloads/OpenVoiceFlow-{RELEASE_VERSION}.dmg" in html
    assert UNIVERSAL_SHA256 in html
    assert "One universal" in html
    assert FALLBACK in html
    assert "macOS 12–13" in html
    assert "OpenVoiceFlow-0.3.6-x86_64.dmg" not in html


def test_client_chooser_always_targets_the_universal_native_dmg():
    js = (DOCS / "site.js").read_text(encoding="utf-8")
    assert js.count(f"downloads/OpenVoiceFlow-{RELEASE_VERSION}.dmg") >= 2
    assert "Universal macOS DMG" in js


def test_appcast_is_present_and_signed_for_the_final_native_release():
    appcast = (DOCS / "appcast.xml").read_text(encoding="utf-8")
    assert "sparkle:shortVersionString>0.4.0" in appcast
    assert "sparkle:edSignature=" in appcast
    assert f"OpenVoiceFlow-{RELEASE_VERSION}.dmg" in appcast


def test_legacy_split_downloads_redirect_to_the_universal_native_dmg():
    redirects = {item["source"]: item for item in json.loads((ROOT / "vercel.json").read_text())["redirects"]}
    for previous in ["0.2.0", "0.3.2", "0.3.3", "0.3.4", "0.3.5"]:
        for arch in ["arm64", "x86_64"]:
            item = redirects[f"/downloads/OpenVoiceFlow-{previous}-{arch}.dmg"]
            assert item["destination"] == f"/downloads/OpenVoiceFlow-{RELEASE_VERSION}.dmg"
            assert item["permanent"] is True


def test_public_downloads_remain_website_hosted():
    combined = "\n".join((DOCS / name).read_text(encoding="utf-8") for name in ["download.html", "install.html", "how-it-works.html"])
    assert "github.com/shimoverse/openvoiceflow/releases/download" not in combined
    assert CANONICAL in (DOCS / "download.html").read_text(encoding="utf-8")
