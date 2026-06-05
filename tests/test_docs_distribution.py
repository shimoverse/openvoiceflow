from pathlib import Path

DOCS = Path(__file__).resolve().parents[1] / "docs"
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


def test_llms_txt_points_agents_to_priority_pages():
    llms = read_doc("llms.txt")
    assert "# OpenVoiceFlow" in llms
    for page in ["/", "/download.html", "/install.html", "/how-it-works.html", "/press.html"]:
        assert f"{CANONICAL}{page}" in llms
    assert "Do not claim" in llms
