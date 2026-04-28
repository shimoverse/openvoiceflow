"""Smoke tests — package metadata loads.

Submodule import smoke (under PEP 604 union annotation regression risk) is
covered separately in test_python39_compat.py once SS3 is fixed.
"""
from __future__ import annotations


def test_package_metadata_loads() -> None:
    """`import voiceflow` exposes __version__, __author__, __app_name__."""
    import voiceflow

    assert voiceflow.__version__
    assert voiceflow.__author__
    assert voiceflow.__app_name__ == "OpenVoiceFlow"


def test_pyproject_version_matches_package() -> None:
    """Sanity: pyproject.toml version == voiceflow.__version__."""
    import re
    from pathlib import Path

    import voiceflow

    pyproject = Path(__file__).resolve().parent.parent / "pyproject.toml"
    text = pyproject.read_text()
    match = re.search(r'^version\s*=\s*"([^"]+)"', text, flags=re.MULTILINE)
    assert match, "pyproject.toml has no version field"
    assert match.group(1) == voiceflow.__version__, (
        f"pyproject {match.group(1)} != package {voiceflow.__version__}"
    )
