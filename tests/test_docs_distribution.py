from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
CANONICAL = "https://openvoiceflow.vercel.app"
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
        "downloads/OpenVoiceFlow-0.2.0-arm64.dmg",
        "downloads/OpenVoiceFlow-0.2.0-x86_64.dmg",
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


def test_download_page_uses_website_hosted_assets_and_checksums():
    html = read_doc("download.html")
    assert "downloads/OpenVoiceFlow-0.2.0-arm64.dmg" in html
    assert "downloads/OpenVoiceFlow-0.2.0-x86_64.dmg" in html
    assert "github.com/shimoverse/openvoiceflow/releases/download" not in html
    assert "653b2da2ff971642a6a35add1e07c7a3823e4c2c8edb4c0efa0d15712c21e2a4" in html
    assert "553f893e5bc7ddbbdfbad75a20047128816138027ebbd30997730583021a1118" in html


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
