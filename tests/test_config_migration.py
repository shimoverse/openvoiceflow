"""SS5 regression test: ``cleanup_prompt`` → ``llm_prompt`` migration.

Background: v0.1.0 stored the user's custom cleanup prompt under the key
``cleanup_prompt``. v0.2.0 renamed it to ``llm_prompt``. The rename
shipped without migration code, so v0.1.0 users upgrading silently lost
their custom prompt — they ended up using the default without being told.

These tests pin down the four semantics:
  1. Old key only → migrate to new key, drop old, persist.
  2. Both keys → keep new key, drop old, persist.
  3. New key only → no-op.
  4. Neither → no-op.
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

import voiceflow.config as cfg


@pytest.fixture
def isolated_config(monkeypatch, tmp_path: Path):
    """Redirect CONFIG_DIR/CONFIG_PATH to a tmpdir for the duration of a test."""
    cfg_dir = tmp_path / ".openvoiceflow"
    cfg_dir.mkdir()
    cfg_path = cfg_dir / "config.json"
    monkeypatch.setattr(cfg, "CONFIG_DIR", str(cfg_dir))
    monkeypatch.setattr(cfg, "CONFIG_PATH", str(cfg_path))
    monkeypatch.setattr(cfg, "LOG_DIR", cfg_dir / "logs")
    monkeypatch.setattr(cfg, "MODELS_DIR", cfg_dir / "models")
    return cfg_path


def _write(path: Path, data: dict) -> None:
    path.write_text(json.dumps(data))


def test_cleanup_prompt_migrates_to_llm_prompt(isolated_config: Path) -> None:
    """v0.1.0 user with `cleanup_prompt` upgrades and keeps their prompt."""
    _write(isolated_config, {"cleanup_prompt": "MY CUSTOM PROMPT"})

    config = cfg.load_config()

    assert config["llm_prompt"] == "MY CUSTOM PROMPT", (
        "load_config must copy cleanup_prompt → llm_prompt"
    )
    assert "cleanup_prompt" not in config, (
        "load_config must drop cleanup_prompt from the merged config"
    )

    # Persisted version reflects the migration too.
    on_disk = json.loads(isolated_config.read_text())
    assert "cleanup_prompt" not in on_disk
    assert on_disk["llm_prompt"] == "MY CUSTOM PROMPT"


def test_both_keys_keeps_llm_prompt_drops_cleanup(isolated_config: Path) -> None:
    """If both keys exist (e.g. a manual edit), llm_prompt wins, cleanup is dropped."""
    _write(
        isolated_config,
        {"cleanup_prompt": "OLD ONE", "llm_prompt": "NEW ONE"},
    )

    config = cfg.load_config()

    assert config["llm_prompt"] == "NEW ONE"
    assert "cleanup_prompt" not in config

    on_disk = json.loads(isolated_config.read_text())
    assert "cleanup_prompt" not in on_disk
    assert on_disk["llm_prompt"] == "NEW ONE"


def test_only_llm_prompt_is_noop(isolated_config: Path) -> None:
    """v0.2.0+ users with the new key are unaffected."""
    _write(isolated_config, {"llm_prompt": "ALREADY MIGRATED"})

    config = cfg.load_config()

    assert config["llm_prompt"] == "ALREADY MIGRATED"
    assert "cleanup_prompt" not in config


def test_neither_key_is_noop(isolated_config: Path) -> None:
    """A config without either key uses the default (None) and is left alone."""
    _write(isolated_config, {"hotkey": "f5"})

    config = cfg.load_config()

    # llm_prompt comes from DEFAULTS (None) and cleanup_prompt should not appear.
    assert config["llm_prompt"] is None
    assert "cleanup_prompt" not in config
    assert config["hotkey"] == "f5"  # other keys preserved


def test_gemini_backend_migrates_to_openrouter(isolated_config: Path) -> None:
    """Retired Gemini backend configs are moved to OpenRouter without copying keys."""
    _write(
        isolated_config,
        {"llm_backend": "gemini", "gemini_api_key": "old-google-key"},
    )

    config = cfg.load_config()

    assert config["llm_backend"] == "openrouter"
    assert config["openrouter_api_key"] is None
    assert "gemini_api_key" not in config

    on_disk = json.loads(isolated_config.read_text())
    assert on_disk["llm_backend"] == "openrouter"
    assert "gemini_api_key" not in on_disk
