"""Contracts that keep the AGPL-3.0 + commercial dual-licensing coherent."""
import os
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]

# The website lives in the private openvoiceflow-web repo. Licensing copy has to
# stay coherent across both halves, so the site assertions run whenever that repo
# is checked out alongside this one (CI there sets OVF_WEB_ROOT) and skip here,
# where only the app half exists.
WEB_ROOT = Path(os.environ["OVF_WEB_ROOT"]) if os.environ.get("OVF_WEB_ROOT") else ROOT
DOCS = WEB_ROOT / "docs"
SITE_AVAILABLE = DOCS.is_dir()
requires_site = pytest.mark.skipif(
    not SITE_AVAILABLE,
    reason="site content lives in shimoverse/openvoiceflow-web; set OVF_WEB_ROOT to include it",
)


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def one_line(text: str) -> str:
    """Normalize prose so Markdown wrapping does not weaken the contract."""
    return " ".join(text.split())


AGPL_TITLE = "GNU AFFERO GENERAL PUBLIC LICENSE"


def test_root_license_is_verbatim_agpl3():
    """LICENSE must be the unmodified FSF text. Editing it is not permitted."""
    text = read(ROOT / "LICENSE")
    assert AGPL_TITLE in text
    assert "Version 3, 19 November 2007" in text
    # Section 13 is what makes this the Affero variant rather than plain GPL.
    assert "13. Remote Network Interaction" in text
    assert "Copyright (C) 2007 Free Software Foundation" in text
    # No project-specific text may be spliced into the license document.
    assert "OpenVoiceFlow" not in text, "LICENSE must stay verbatim AGPL-3.0"
    assert "Shimoverse" not in text, "LICENSE must stay verbatim AGPL-3.0"


def test_notice_carries_section_7_terms_and_commercial_path():
    notice = one_line(read(ROOT / "NOTICE"))
    assert "Copyright (C) 2025-2026 Shimoverse Studios" in notice
    assert "GNU Affero General Public License" in notice
    # The two additional terms must be present and labelled with their
    # authorising subsection, so a reader can check they are permitted.
    assert "Section 7(b) and 7(c)" in notice
    assert "Section 7(e)" in notice
    assert "Based on OpenVoiceFlow by Shimoverse Studios" in notice
    assert "https://github.com/shimoverse/openvoiceflow" in notice
    assert "contact@openvoiceflow.com" in notice
    assert "dual-licensed" in notice
    # The commercial license must be described as optional, never as a
    # precondition for ordinary or organizational use.
    assert "Buying a commercial license is optional" in notice


def test_license_surfaces_name_agpl_and_the_optional_commercial_path():
    for rel in ["README.md", "LICENSING.md", "PRIVACY.md", "SECURITY.md", "SUPPORT.md"]:
        text = one_line(read(ROOT / rel))
        # Either prose spelling is fine; what must not drift is which license.
        assert "GNU Affero General Public License" in text, rel
        assert "commercial license" in text.casefold(), rel
        assert "contact@openvoiceflow.com" in text, rel


# Release notes record what the license said at the time of each release.
# Rewriting them would falsify the changelog, so they are exempt from the
# stale-copy guards below. docs/release-notes/ is excluded by not being
# globbed; releases.html aggregates the same history and is named here.
HISTORICAL_PAGES = {"releases.html"}


def test_no_surface_claims_organizational_use_needs_permission():
    """The whole point of the relicense: organizational use is now granted.

    Any surviving copy that tells a reader they must ask permission, or pay,
    to use OpenVoiceFlow at work contradicts the AGPL-3.0 grant.
    """
    surfaces = [
        ROOT / rel
        for rel in [
            "README.md", "LICENSING.md", "PRIVACY.md", "SECURITY.md", "SUPPORT.md",
            "TRADEMARKS.md", "COMPLIANCE.md", "CONTRIBUTING.md", "PRD.md",
            "pyproject.toml", "NOTICE", "native/Info.plist",
            "legal/DPA-template.md", "legal/THIRD_PARTY_NOTICES.md",
            "voiceflow/__init__.py", "voiceflow/__main__.py", "voiceflow/onboarding.py",
        ]
    ]
    if SITE_AVAILABLE:
        surfaces += [
            DOCS / "llms.txt",
            WEB_ROOT / "scripts" / "docs_content.py",
            *(DOCS / "docs").glob("*.html"),
            *(page for page in DOCS.glob("*.html") if page.name not in HISTORICAL_PAGES),
        ]
    forbidden = [
        "personal use only",
        "free for personal use",
        "personal-use-only",
        "commercial or organizational use requires",
        "organizational use requires separate",
        "commercial use requires",
        "commercial license required",
        "separate written permission or a separate written license",
        "not an open-source license",
        "not an open source license",
        "personal and reciprocal source license",
    ]
    # LICENSING.md must name the superseded licenses to explain that their
    # grants survive; that historical mention is required, not stale.
    historical_ok = {"personal and reciprocal source license"}
    for surface in surfaces:
        text = one_line(read(surface)).casefold()
        for phrase in forbidden:
            if surface == ROOT / "LICENSING.md" and phrase in historical_ok:
                continue
            assert phrase not in text, f"{surface}: stale pre-AGPL phrase {phrase!r}"


def test_plain_language_guide_explains_agpl_obligations_and_limits():
    guide = one_line(read(ROOT / "LICENSING.md"))
    for phrase in [
        "free and open source",
        "OSI-approved",
        "AGPL-3.0",
        "dual-licensed",
        "Section 13",
        "complete corresponding source",
        "Based on OpenVoiceFlow by Shimoverse Studios",
        "TRADEMARKS.md",
        "LEGACY_MIT_PORTIONS.md",
        "THIRD_PARTY_NOTICES.md",
        "cannot be withdrawn",
    ]:
        assert phrase in guide, phrase
    # The guide must say plainly that working use needs no purchase, since
    # that is the single most likely thing for a reader to get wrong.
    assert "you do not need it" in guide.casefold()


def test_package_metadata_declares_agpl():
    pyproject = read(ROOT / "pyproject.toml")
    assert 'license = "AGPL-3.0-only"' in pyproject
    # PEP 639: the SPDX expression replaces the classifier, and setuptools>=77
    # refuses to build a project that declares both.
    assert "License :: OSI Approved" not in pyproject
    assert "Personal-Reciprocal" not in pyproject
    assert '"NOTICE"' in pyproject, "NOTICE must ship in the wheel's license-files"


def test_contributing_discloses_the_dual_license_asymmetry():
    """The CLA is what enables commercial relicensing; say so, don't bury it."""
    text = one_line(read(ROOT / "CONTRIBUTING.md"))
    assert "relicense that contribution" in text
    assert "separate commercial licenses" in text
    assert "you give slightly more than you get back" in text


def test_compliance_copy_matches_native_analytics_posture():
    compliance = one_line(read(ROOT / "COMPLIANCE.md")).casefold()
    for stale_claim in [
        "no vendor-side service exists",
        "we hold no personal data on a server",
        "there is no central server",
        "we don't sync, mirror, back up, or telemeter",
        "we do not retain anything centrally",
    ]:
        assert stale_claim not in compliance
    assert "analytics/leaderboard api" in compliance
    assert "never receives audio or dictated text" in compliance
    assert "anonymous usage sharing is enabled" in compliance


@requires_site
def test_public_pages_do_not_make_stale_or_unqualified_claims():
    pages = [
        *(p for p in DOCS.glob("*.html") if p.name not in HISTORICAL_PAGES),
        *((DOCS / "docs").glob("*.html")),
        *((DOCS / "blog").glob("*.html")),
    ]
    forbidden = ["MIT-licensed", "MIT open source", "personal use only"]
    for page in pages:
        text = read(page).casefold()
        for phrase in forbidden:
            assert phrase.lower() not in text, f"{page}: stale {phrase!r}"


def test_attribution_surfaces_require_visible_credit_and_original_link():
    for rel in ["NOTICE", "LICENSING.md", "README.md", "TRADEMARKS.md"]:
        text = one_line(read(ROOT / rel))
        assert "Based on OpenVoiceFlow by Shimoverse Studios" in text, rel
        assert "https://github.com/shimoverse/openvoiceflow" in text, rel


def test_legacy_grants_are_preserved_not_rewritten():
    """Relicensing is prospective. Old grants cannot be withdrawn, and the
    docs must keep saying so."""
    guide = one_line(read(ROOT / "LICENSING.md"))
    assert "cannot be withdrawn" in guide
    assert "not retroactive" in guide
    legacy = one_line(read(ROOT / "legal" / "LEGACY_MIT_PORTIONS.md"))
    assert "MIT" in legacy
