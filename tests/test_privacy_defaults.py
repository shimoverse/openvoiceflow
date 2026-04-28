"""Wave 2B / 2C: privacy-by-default for fresh installs.

Background: v0.2 shipped ``log_transcripts: True`` and ``auto_learn: True``
in DEFAULTS, so a brand-new user immediately had every dictation written
to ``~/.openvoiceflow/logs/`` AND their focused text field was being read
by the auto-learner for 30 s post-paste — without explicit consent.

v0.3 default is False for both. Existing users who had set either to True
keep their setting (load_config merges DEFAULTS first, then ``stored``).
"""
from __future__ import annotations

import json
from pathlib import Path

import pytest

import voiceflow.config as cfg


@pytest.fixture
def isolated_config(monkeypatch, tmp_path: Path):
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


def test_log_transcripts_default_off_for_fresh_install(isolated_config: Path) -> None:
    """No config file → DEFAULTS used → log_transcripts is False."""
    config = cfg.load_config()
    assert config["log_transcripts"] is False, (
        "Fresh installs must NOT log transcripts by default. The user opts in "
        "via the onboarding wizard, not by surprise."
    )


def test_log_transcripts_existing_true_is_preserved(isolated_config: Path) -> None:
    """A v0.2 user who had log_transcripts: True keeps it on upgrade."""
    _write(isolated_config, {"log_transcripts": True})
    config = cfg.load_config()
    assert config["log_transcripts"] is True


def test_log_transcripts_existing_false_is_preserved(isolated_config: Path) -> None:
    """A user who set log_transcripts: False stays off."""
    _write(isolated_config, {"log_transcripts": False})
    config = cfg.load_config()
    assert config["log_transcripts"] is False


def test_auto_learn_default_off_for_fresh_install(isolated_config: Path) -> None:
    """No config file → DEFAULTS used → auto_learn is False (consent-gated)."""
    config = cfg.load_config()
    assert config["auto_learn"] is False, (
        "auto_learn requires Accessibility-API access to read focused text fields "
        "for 30 s after every paste. That's strong; opt-in only via the Know Me interview."
    )


def test_auto_learn_existing_true_is_preserved(isolated_config: Path) -> None:
    """A v0.2 user who had auto_learn: True keeps it on upgrade."""
    _write(isolated_config, {"auto_learn": True})
    config = cfg.load_config()
    assert config["auto_learn"] is True


def test_default_dict_reflects_privacy_defaults() -> None:
    """``DEFAULTS`` itself encodes the privacy posture; no leakage via direct read."""
    assert cfg.DEFAULTS["log_transcripts"] is False
    assert cfg.DEFAULTS["auto_learn"] is False
