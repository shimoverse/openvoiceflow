from hashlib import sha256
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
CANONICAL = "https://openvoiceflow.vercel.app"
RELEASE_VERSION = "0.3.0"
ARM64_SHA256 = "52116ab4447e6957f11132fdb157d2ac5156eb5ea7a89d14ec28a986316f8fc7"
X86_64_SHA256 = "2ab7b1d4ed9a809cef16bea8479ff118d98943c5c1f58434d786f2bd32bc06e9"
PUBLIC_PAGES = ["", "download.html", "install.html", "how-it-works.html", "press.html"]


def read_doc(name: str) -> str:
    return (DOCS / name).read_text(encoding="utf-8")


def test_distribution_pages_and_crawler_files_exist():
    for name in [
        "download.html",
        "install.html",
        "how-it-works.html",
        "press.html",
        "llms.txt",
        "robots.txt",
        "site.js",
        f"downloads/OpenVoiceFlow-{RELEASE_VERSION}-arm64.dmg",
        f"downloads/OpenVoiceFlow-{RELEASE_VERSION}-x86_64.dmg",
    ]:
        assert (DOCS / name).exists(), f"missing docs/{name}"


def test_sitemap_includes_public_growth_pages():
    sitemap = read_doc("sitemap.xml")
    for page in PUBLIC_PAGES:
        url = f"{CANONICAL}/{page}"
        assert f"<loc>{url}</loc>" in sitemap


def test_homepage_has_answer_first_positioning_and_internal_growth_links():
    html = read_doc("index.html")
    assert "OpenVoiceFlow is a free push-to-talk voice dictation app for macOS" in html
    for href in ["download.html", "install.html", "how-it-works.html", "press.html"]:
        assert f'href="{href}"' in html
    assert "No cloud. No subscription. No compromises." not in html


def test_growth_pages_have_metadata_canonicals_and_structured_data():
    expected = {
        "index.html": "SoftwareApplication",
        "download.html": "SoftwareApplication",
        "install.html": "HowTo",
        "how-it-works.html": "FAQPage",
        "press.html": "Organization",
    }
    for name, schema_type in expected.items():
        html = read_doc(name)
        assert "<title>" in html
        assert '<meta name="description"' in html
        assert '<link rel="canonical"' in html
        assert 'application/ld+json' in html
        assert schema_type in html


def test_public_pages_have_mobile_first_navigation_and_touch_targets():
    css = read_doc("style.css")
    site_js = read_doc("site.js")

    assert '<meta name="viewport" content="width=device-width, initial-scale=1.0" />' in read_doc("index.html")
    for name in ["index.html", "download.html", "install.html", "how-it-works.html", "press.html"]:
        html = read_doc(name)
        assert 'class="nav-hamburger"' in html, f"missing mobile hamburger on {name}"
        assert 'aria-expanded="false"' in html, f"hamburger state missing on {name}"
        assert 'aria-controls="navDrawer"' in html, f"hamburger drawer relation missing on {name}"
        assert 'class="nav-drawer"' in html, f"missing mobile drawer on {name}"
        assert 'Download for Mac' in html, f"mobile drawer CTA missing on {name}"
        assert '<meta name="viewport" content="width=device-width, initial-scale=1.0" />' in html
        if name != "index.html":
            assert '<script src="site.js"></script>' in html

    assert "width: 44px;" in css
    assert "min-height: 44px;" in css
    assert "min-height: 100svh;" in css
    assert "@media (max-width: 640px)" in css
    assert ".btn { white-space: normal; }" in css
    assert ".code-block { white-space: pre-wrap; overflow-wrap: anywhere; }" in css
    assert "hamburger.setAttribute('aria-expanded'" in site_js
    assert "Escape" in site_js


def test_public_pages_include_web_analytics_and_download_event_tracking():
    site_js = read_doc("site.js")
    for name in ["index.html", "download.html", "install.html", "how-it-works.html", "press.html"]:
        html = read_doc(name)
        assert 'https://va.vercel-scripts.com/v1/script.js' in html, f"missing Vercel Web Analytics on {name}"
        assert "vitals.vercel-analytics.com/v1/view?dsn=" in html, f"missing Vercel pageview endpoint on {name}"
        assert "vitals.vercel-analytics.com/v1/event?dsn=" in html, f"missing Vercel event endpoint on {name}"
        assert "window.va = window.va || function" in html, f"missing Vercel analytics queue on {name}"
        assert '<script src="site.js"></script>' in html, f"missing site.js analytics hooks on {name}"

    assert "download_click" in site_js
    assert "install_guide_click" in site_js
    assert "source_path" in site_js
    assert "window.va('event'" in site_js
    assert "/downloads/" in site_js


def test_download_page_uses_website_hosted_assets_and_checksums():
    html = read_doc("download.html")
    site_js = read_doc("site.js")
    assert f"downloads/OpenVoiceFlow-{RELEASE_VERSION}-arm64.dmg" in html
    assert f"downloads/OpenVoiceFlow-{RELEASE_VERSION}-x86_64.dmg" in html
    assert f'"softwareVersion": "{RELEASE_VERSION}"' in html
    assert 'data-download-recommendation' in html
    assert 'data-arch="arm64"' in html
    assert 'data-arch="x86_64"' in html
    assert "Download the recommended DMG" in html
    assert "navigator.userAgentData" in site_js
    assert "applyDownloadRecommendation" in site_js
    assert "download_recommendation_detected" in site_js
    assert "github.com/shimoverse/openvoiceflow/releases/download" not in html
    assert "0.2.0" not in html
    assert "release candidate" not in html.lower()
    assert ARM64_SHA256 in html
    assert X86_64_SHA256 in html
    checksum_lines = [line for line in html.splitlines() if "sha256:" in line]
    assert len(checksum_lines) >= 2
    for line in checksum_lines[:2]:
        digest = line.split("sha256:", 1)[1].split("<", 1)[0].strip()
        assert len(digest) == 64
        int(digest, 16)


def test_download_page_avoids_duplicate_primary_ctas():
    html = read_doc("download.html")

    assert html.count('class="btn btn-primary btn-lg"') <= 1
    assert html.count('Download OpenVoiceFlow-0.3.0-arm64.dmg') == 1
    assert html.count('Download OpenVoiceFlow-0.3.0-x86_64.dmg') == 1
    assert "If we cannot confidently detect your chip" in html


def test_download_assets_match_published_checksums():
    expected = {
        f"OpenVoiceFlow-{RELEASE_VERSION}-arm64.dmg": ARM64_SHA256,
        f"OpenVoiceFlow-{RELEASE_VERSION}-x86_64.dmg": X86_64_SHA256,
    }
    for filename, digest in expected.items():
        asset = DOCS / "downloads" / filename
        assert sha256(asset.read_bytes()).hexdigest() == digest


def test_site_claims_match_current_openrouter_default():
    combined = "\n".join(path.read_text(encoding="utf-8") for path in DOCS.glob("*.html"))
    assert "OpenRouter Gemma 4" in combined
    assert "Gemini Flash" not in combined
    assert "openvoiceflow --set-key gemini" not in combined


def test_public_pages_do_not_depend_on_private_github_downloads():
    combined = "\n".join(path.read_text(encoding="utf-8") for path in DOCS.glob("*.html"))
    assert "github.com/shimoverse/openvoiceflow/releases/download" not in combined
    assert "website-hosted DMG" in combined
    assert "private GitHub repository" in combined


def test_public_pages_do_not_link_to_private_repo_or_github_assets():
    combined = "\n".join(path.read_text(encoding="utf-8") for path in DOCS.glob("*.html"))
    forbidden_public_links = [
        'href="https://github.com/shimoverse/openvoiceflow',
        "opengraph.githubassets.com/1/shimoverse/openvoiceflow",
        "img.shields.io/github",
        "Star on GitHub",
        "View on GitHub",
        'GitHub repo</a>',
    ]
    for forbidden in forbidden_public_links:
        assert forbidden not in combined


def test_public_positioning_matches_private_launch_phase():
    combined = "\n".join(path.read_text(encoding="utf-8") for path in DOCS.glob("*.html"))
    for stale_claim in [
        "open-source",
        "open source voice typing",
        "Open source",
        "MIT-licensed and open to everyone",
    ]:
        assert stale_claim not in combined
    assert "source repository stays private during this launch phase" in combined
    assert "website-hosted DMGs" in combined


def test_readme_points_public_users_to_website_downloads():
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    assert f"{CANONICAL}/download.html" in readme
    assert f"{CANONICAL}/downloads/OpenVoiceFlow-{RELEASE_VERSION}-arm64.dmg" in readme
    assert f"{CANONICAL}/downloads/OpenVoiceFlow-{RELEASE_VERSION}-x86_64.dmg" in readme
    assert "website-hosted DMG" in readme
    assert "Source install currently requires collaborator access" in readme
    assert "Grab the latest `.dmg` from [**Releases**]" not in readme
    assert "github.com/shimoverse/openvoiceflow/releases" not in readme
    assert "The only open-source voice dictation app" not in readme


def test_vercel_root_build_serves_docs_static_site():
    package_json = (ROOT / "package.json").read_text(encoding="utf-8")
    vercel_json = (ROOT / "vercel.json").read_text(encoding="utf-8")
    build_script = (ROOT / "scripts" / "vercel-build.mjs").read_text(encoding="utf-8")
    pyproject = (ROOT / "pyproject.toml").read_text(encoding="utf-8")

    assert '"vercel-build": "node scripts/vercel-build.mjs"' in package_json
    assert '"buildCommand": "npm run vercel-build"' in vercel_json
    assert '"outputDirectory": "public"' in vercel_json
    assert '"installCommand": "npm install --ignore-scripts"' in vercel_json
    assert "const sourceDir = path.join(root, \"docs\")" in build_script
    assert "const outputDir = path.join(root, \"public\")" in build_script
    assert "public/" in (ROOT / ".gitignore").read_text(encoding="utf-8")
    assert '[tool.setuptools.packages.find]' in pyproject
    assert 'include = ["voiceflow*"]' in pyproject


def test_llms_txt_points_agents_to_priority_pages():
    llms = read_doc("llms.txt")
    assert "# OpenVoiceFlow" in llms
    for page in ["/", "/download.html", "/install.html", "/how-it-works.html", "/press.html"]:
        assert f"{CANONICAL}{page}" in llms
    assert "Do not claim" in llms
