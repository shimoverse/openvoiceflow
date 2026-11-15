"""Navigation and shipped-product contracts for the GitHub-native user guides."""

import re
from pathlib import Path
from urllib.parse import unquote

from tests.test_markdown_links import markdown_targets

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
SPOKES = (
    "troubleshoot-dictation.md",
    "choose-cleanup.md",
    "verify-offline.md",
    "local-transcription-and-cleanup.md",
)
PAGES = (DOCS / "README.md", *(DOCS / name for name in SPOKES))
RELEASE = "native-v0.6.6"
PINNED_SHA = "f41879063e0ed8c8356dbba90c7dcb86d7844de9"


def _anchors(path):
    """GitHub-style heading slugs, including duplicates, for the headings used here."""
    anchors = set()
    counts = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        heading = re.match(r"^#{1,6}\s+(.+?)\s*#*\s*$", line)
        if not heading:
            continue
        text = re.sub(r"<[^>]+>", "", heading.group(1))
        text = re.sub(r"\[([^]]+)\]\([^)]+\)", r"\1", text)
        slug = re.sub(r"[^\w\- ]", "", text.lower()).replace(" ", "-")
        count = counts.get(slug, 0)
        counts[slug] = count + 1
        anchors.add(f"{slug}-{count}" if count else slug)
    return anchors


def test_guide_paths_fragments_and_reciprocal_navigation():
    hub = PAGES[0].read_text(encoding="utf-8")
    readme = (ROOT / "README.md").read_text(encoding="utf-8")
    assert "[Native macOS user guides](docs/README.md)" in readme
    for spoke in SPOKES:
        assert f"({spoke})" in hub
        assert "(README.md)" in (DOCS / spoke).read_text(encoding="utf-8")

    for page in PAGES:
        text = page.read_text(encoding="utf-8")
        headings = re.findall(r"^# (.+)$", text, re.MULTILINE)
        assert len(headings) == 1, f"{page} needs one descriptive H1"
        for target in markdown_targets(text):
            if "://" in target or target.startswith(("mailto:", "//")):
                continue
            path, _, fragment = target.partition("#")
            resolved = (page.parent / unquote(path)).resolve() if path else page
            assert resolved.is_relative_to(ROOT), (page, target)
            assert resolved.is_file(), (page, target)
            if fragment:
                assert unquote(fragment) in _anchors(resolved), (page, target)


def test_guides_pin_released_source_and_state_network_privacy_boundary():
    privacy = (ROOT / "PRIVACY.md").read_text(encoding="utf-8")
    settings = (ROOT / "native/Sources/OpenVoiceFlow/Settings.swift").read_text(encoding="utf-8")
    cleanup = (ROOT / "native/Sources/OpenVoiceFlow/CleanupProvider.swift").read_text(encoding="utf-8")
    ui = (ROOT / "native/Sources/OpenVoiceFlow/DashboardView.swift").read_text(encoding="utf-8")
    assert 'var backend: Backend = .none' in settings
    assert 'var shareAnalytics: Bool = true' in settings
    assert 'on ? .anthropic : .none' in ui
    assert 'baseURL = "http://localhost:11434"' in cleanup
    assert "snippet" in cleanup and "context" in cleanup
    assert "Share anonymous usage & leaderboard rank" in privacy

    for page in PAGES:
        text = page.read_text(encoding="utf-8")
        assert RELEASE in text and "November 14, 2026" in text
        assert "../PRIVACY.md" in text
        for url in re.findall(r"https://github.com/shimoverse/openvoiceflow/blob/([^/]+)/native/Sources/", text):
            assert url == PINNED_SHA, f"{page}: cite immutable released source"
    explainer = (DOCS / "local-transcription-and-cleanup.md").read_text(encoding="utf-8")
    for concept in ("transcript", "profile", "dictionary", "snippet", "Ollama", "Sparkle", "Meetings"):
        assert concept in explainer
    offline = (DOCS / "verify-offline.md").read_text(encoding="utf-8")
    assert "Ethernet" in offline and "baseline" in offline and "not a claim" in offline
    choices = (DOCS / "choose-cleanup.md").read_text(encoding="utf-8")
    assert "Anthropic" in choices and "Keychain" in choices and "localhost:11434" in choices
