"""Wave 2A: every ``~/.openvoiceflow/`` artifact is mode 600 on save.

API keys, the user profile, dictionary, snippets, stats, and daily
transcript logs all live in ``~/.openvoiceflow/`` (or ``~/OpenVoiceFlow/``
in v0.1). Default macOS umask is 022, which gives mode 644 — world-readable.
This test pins down that every save site applies mode 0o600 right after writing.
"""
from __future__ import annotations

import os
from pathlib import Path

import pytest


@pytest.fixture
def isolated_home(monkeypatch, tmp_path: Path):
    """Redirect every voiceflow path constant to a tmpdir."""
    cfg_dir = tmp_path / ".openvoiceflow"
    cfg_dir.mkdir()
    log_dir = cfg_dir / "logs"

    import voiceflow.config as cfg
    monkeypatch.setattr(cfg, "CONFIG_DIR", str(cfg_dir))
    monkeypatch.setattr(cfg, "CONFIG_PATH", str(cfg_dir / "config.json"))
    monkeypatch.setattr(cfg, "LOG_DIR", log_dir)
    monkeypatch.setattr(cfg, "MODELS_DIR", cfg_dir / "models")

    # Per-feature path constants (each module imports these at module level
    # via `from .config import CONFIG_DIR`, so we have to monkeypatch each
    # module's local binding).
    import voiceflow.profile as prof
    monkeypatch.setattr(prof, "PROFILE_PATH", str(cfg_dir / "profile.json"))
    import voiceflow.dictionary as dct
    monkeypatch.setattr(dct, "DICTIONARY_PATH", str(cfg_dir / "dictionary.json"))
    import voiceflow.snippets as snp
    monkeypatch.setattr(snp, "SNIPPETS_PATH", str(cfg_dir / "snippets.json"))
    import voiceflow.stats as st
    monkeypatch.setattr(st, "STATS_PATH", str(cfg_dir / "stats.json"))
    import voiceflow.system as sys_mod
    monkeypatch.setattr(sys_mod, "LOG_DIR", log_dir)

    return cfg_dir


def _assert_mode_600(path: str) -> None:
    actual = os.stat(path).st_mode & 0o777
    assert actual == 0o600, (
        f"{path} has mode {oct(actual)}; expected 0o600 (read+write owner only)"
    )


def test_config_save_is_mode_600(isolated_home: Path) -> None:
    from voiceflow.config import CONFIG_PATH, save_config
    save_config({"hotkey": "right_cmd"})
    _assert_mode_600(CONFIG_PATH)


def test_profile_save_is_mode_600(isolated_home: Path) -> None:
    from voiceflow import profile
    profile.save_profile({"name": "Alice"})
    _assert_mode_600(profile.PROFILE_PATH)


def test_dictionary_save_is_mode_600(isolated_home: Path) -> None:
    from voiceflow import dictionary
    dictionary.save_dictionary([{"word": "OpenAI", "aliases": ["openai"]}])
    _assert_mode_600(dictionary.DICTIONARY_PATH)


def test_snippets_save_is_mode_600(isolated_home: Path) -> None:
    from voiceflow import snippets
    snippets.save_snippets({"sig": "Best,\nAlice"})
    _assert_mode_600(snippets.SNIPPETS_PATH)


def test_stats_save_is_mode_600(isolated_home: Path) -> None:
    from voiceflow import stats
    stats.save_stats({"total_dictations": 5})
    _assert_mode_600(stats.STATS_PATH)


def test_log_transcript_files_are_mode_600(isolated_home: Path) -> None:
    from voiceflow.system import log_transcript
    config = {"log_transcripts": True}
    log_transcript("raw text", "cleaned text", config)
    # Two files expected: YYYY-MM-DD.jsonl and YYYY-MM-DD.md
    log_dir = isolated_home / "logs"
    files = list(log_dir.glob("*.jsonl")) + list(log_dir.glob("*.md"))
    assert files, "No transcript log files written"
    for f in files:
        _assert_mode_600(str(f))
