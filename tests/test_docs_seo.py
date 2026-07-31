"""SEO/AEO contracts for the public website.

The blog exists to bring search and AI-assistant traffic to the site. Each
test here pins the plumbing that quietly breaks that goal when a page is
added or edited: a missing canonical splits ranking signal across URL
variants, a page absent from the sitemap can go unindexed for weeks, an
article without analytics is invisible in the numbers, and a broken
llms.txt link teaches AI assistants to cite 404s. None of these failures
are visible on the rendered page — which is exactly why they're tests.
"""
import json
import re
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
CANONICAL = "https://openvoiceflow.com"

MAIN_PAGES = [
    "index.html",
    "mission.html",
    "download.html",
    "install.html",
    "how-it-works.html",
    "privacy.html",
]
ARTICLES = sorted(
    p.name for p in (DOCS / "blog").glob("*.html") if p.name != "index.html"
)
ALL_PAGES = MAIN_PAGES + ["blog/index.html"] + [f"blog/{name}" for name in ARTICLES]


def read(rel: str) -> str:
    return (DOCS / rel).read_text(encoding="utf-8")


def expected_url(rel: str) -> str:
    """index.html pages canonicalize to their directory URL, others to .html."""
    if rel == "index.html":
        return f"{CANONICAL}/"
    if rel == "blog/index.html":
        return f"{CANONICAL}/blog/"
    return f"{CANONICAL}/{rel}"


def test_blog_launch_set_is_present():
    # The six launch articles. If one is renamed, every reference below —
    # sitemap, llms.txt, homepage cards — must move with it; start here.
    assert ARTICLES == sorted([
        "best-dictation-software-mac.html",
        "wispr-flow-alternative.html",
        "how-to-dictate-on-mac.html",
        "whisper-models-for-dictation.html",
        "offline-dictation-mac.html",
        "voice-typing-for-developers.html",
    ])


def test_every_public_page_has_exactly_one_matching_canonical():
    """Vercel serves /blog/ and /blog/index.html as the same content; the
    canonical tag is what stops search engines treating them as duplicates."""
    for rel in ALL_PAGES:
        html = read(rel)
        tags = re.findall(r'<link rel="canonical" href="([^"]+)"', html)
        assert tags == [expected_url(rel)], f"{rel}: canonical is {tags}"


def test_every_public_page_has_a_real_meta_description():
    # Search snippets and AI answer engines read this. Empty or runaway
    # descriptions get rewritten by Google into something we didn't choose.
    for rel in ALL_PAGES:
        html = read(rel)
        m = re.search(r'<meta name="description" content="([^"]*)"', html)
        assert m, f"{rel}: missing meta description"
        assert 40 <= len(m.group(1)) <= 200, f"{rel}: description length {len(m.group(1))}"


def test_every_public_page_has_social_cards_and_analytics():
    """A shared page with no OG image renders as a bare link in Slack and
    social feeds; a page without analytics is a page whose traffic the
    maintainers can't see. Both regressions are silent in the browser."""
    for rel in ALL_PAGES:
        html = read(rel)
        assert 'property="og:image"' in html, f"{rel}: missing og:image"
        assert 'name="viewport"' in html, f"{rel}: missing viewport"
        assert "va.vercel-scripts.com/v1/script.js" in html, f"{rel}: missing analytics"
        assert "/_vercel/speed-insights/script.js" in html, f"{rel}: missing speed insights"


def test_sitemap_lists_exactly_the_public_pages():
    sitemap = read("sitemap.xml")
    listed = set(re.findall(r"<loc>([^<]+)</loc>", sitemap))
    expected = {expected_url(rel) for rel in ALL_PAGES}
    assert listed == expected, (
        f"missing from sitemap: {expected - listed}; stale in sitemap: {listed - expected}"
    )
    for lastmod in re.findall(r"<lastmod>([^<]+)</lastmod>", sitemap):
        date.fromisoformat(lastmod)  # raises on garbage


def test_robots_txt_still_points_at_the_sitemap():
    robots = read("robots.txt")
    assert "Allow: /" in robots
    assert f"Sitemap: {CANONICAL}/sitemap.xml" in robots


def test_every_article_carries_its_structured_data():
    """BlogPosting + FAQPage JSON-LD is how articles become rich results and
    AI-assistant citations rather than plain blue links."""
    for name in ARTICLES:
        html = read(f"blog/{name}")
        assert '"@type": "BlogPosting"' in html, f"{name}: missing BlogPosting schema"
        assert '"datePublished"' in html, f"{name}: missing datePublished"
        assert '"@type": "FAQPage"' in html, f"{name}: missing FAQPage schema"
        blobs = re.findall(
            r'<script type="application/ld\+json">\s*(\{.*?\})\s*</script>', html, re.S
        )
        assert blobs, f"{name}: no JSON-LD blocks"
        for blob in blobs:
            json.loads(blob)  # malformed JSON-LD is silently ignored by crawlers


def test_every_article_opens_with_a_direct_answer_and_links_to_download():
    # The answer box is the AEO contract: the first thing an extractive
    # engine sees must answer the query. The download link is the
    # conversion path — traffic without it is a library, not a funnel.
    for name in ARTICLES:
        html = read(f"blog/{name}")
        assert 'class="article-answer"' in html, f"{name}: missing answer box"
        assert '../download.html' in html, f"{name}: no path to the download page"


def test_blog_index_links_every_article_and_home_links_the_blog():
    index = read("blog/index.html")
    for name in ARTICLES:
        assert f'href="{name}"' in index, f"blog index does not link {name}"
    home = read("index.html")
    assert 'href="blog/index.html"' in home, "homepage does not link the blog"


def test_every_page_navigation_includes_the_blog():
    # Nav links are the crawl path; a section reachable only from the
    # sitemap looks orphaned to search engines and to humans alike.
    for rel in ALL_PAGES:
        html = read(rel)
        blog_href = "blog/index.html" if rel in MAIN_PAGES else "index.html"
        assert f'<li><a href="{blog_href}">Blog</a></li>' in html, f"{rel}: no Blog nav link"


def test_llms_txt_covers_the_blog_and_never_links_a_404():
    """llms.txt is what AI assistants read first; a dead link there becomes
    a hallucinated citation in someone's chat answer."""
    llms = read("llms.txt")
    assert f"{CANONICAL}/blog/" in llms
    for name in ARTICLES:
        assert f"{CANONICAL}/blog/{name}" in llms, f"llms.txt missing {name}"
    for url in re.findall(rf"{re.escape(CANONICAL)}(/[^\s)]*)", llms):
        path = url.split("#")[0]
        if path.endswith("/"):
            path += "index.html"
        assert (DOCS / path.lstrip("/")).exists(), f"llms.txt links missing file {path}"


def test_the_product_film_ships_with_its_plumbing():
    """The homepage embeds a 52s product film. A missing poster means a black
    rectangle above the fold; a missing captions track fails accessibility;
    a VideoObject whose contentUrl 404s becomes a broken rich result."""
    film = DOCS / "assets" / "openvoiceflow-demo.mp4"
    poster = DOCS / "assets" / "demo-poster.jpg"
    vtt = DOCS / "assets" / "openvoiceflow-demo.en.vtt"
    assert film.exists() and film.stat().st_size > 500_000, "film missing or truncated"
    assert poster.exists() and poster.stat().st_size > 10_000, "poster missing or truncated"
    assert vtt.exists() and vtt.read_text(encoding="utf-8").startswith("WEBVTT")

    home = read("index.html")
    assert '<video data-film' in home
    assert 'poster="assets/demo-poster.jpg"' in home
    assert 'src="assets/openvoiceflow-demo.mp4"' in home
    assert '<track kind="captions" src="assets/openvoiceflow-demo.en.vtt"' in home
    assert '"@type": "VideoObject"' in home
    assert '"contentUrl": "https://openvoiceflow.com/assets/openvoiceflow-demo.mp4"' in home

    site_js = read("site.js")
    assert "demo_play" in site_js, "film plays must be visible in analytics"


def test_the_website_ui_carries_no_github_links():
    """Maintainer decision (July 2026): the website should not send visitors
    to GitHub — no nav item, no footer Source link, no in-prose repo links,
    and no fork-promotion copy. The project stays MIT/open-source and the
    site still says so; only the links and CTAs were removed. site.js keeps
    its inert github_click handler for the observability contract."""
    for rel in ALL_PAGES:
        html = read(rel)
        assert "github" not in html.lower(), f"{rel}: GitHub reference present"
    llms = read("llms.txt")
    assert "github" not in llms.lower(), "llms.txt: GitHub reference present"
    # the credit-and-tell-us ask replaces the repo link as the reuse policy
    assert "shimoverse@gmail.com" in llms
    assert "shimoverse@gmail.com" in read("mission.html")


def test_articles_keep_the_competitor_claims_hedged():
    # AGENTS.md: claims on the website must be true of the shipped app, and
    # competitor claims must be dated. Comparison pages carry the hedge line
    # so a reader (or a competitor's lawyer) sees sourcing, not assertion.
    for name in ["wispr-flow-alternative.html", "best-dictation-software-mac.html"]:
        html = read(f"blog/{name}")
        assert "July 2026" in html, f"{name}: competitor claims lost their date hedge"
        assert "affiliation" in html.lower(), f"{name}: missing no-affiliation note"
