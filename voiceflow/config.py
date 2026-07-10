"""OpenVoiceFlow configuration management."""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

CONFIG_DIR = os.path.expanduser("~/.openvoiceflow")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.json")

LOG_DIR = Path(CONFIG_DIR) / "logs"
MODELS_DIR = Path(CONFIG_DIR) / "models"

CONFIG_SCHEMA_VERSION = 1
_STREAMING_DEFAULT_MIGRATION_VERSION = 1

DEFAULTS = {
    "_config_version": CONFIG_SCHEMA_VERSION,
    "hotkey": "right_cmd",
    "whisper_model": "base.en",
    "whisper_cpp_path": None,
    "llm_backend": "openrouter",
    "openrouter_api_key": None,
    "openrouter_model": "google/gemma-4-31b-it",
    "openai_api_key": None,
    "anthropic_api_key": None,
    "groq_api_key": None,
    "sound_feedback": True,
    "auto_paste": True,
    # Privacy defaults: opt-in only. Existing users who had this on keep it
    # because load_config merges DEFAULTS first then `stored`.
    "log_transcripts": False,
    "sample_rate": 16000,
    "channels": 1,
    "llm_prompt": None,  # Custom cleanup prompt; None = use default
    "language": "en",  # Transcription language (en, es, de, ja, auto, etc.)
    "style": "default",  # Output style: default, casual, formal, code, email
    "launch_at_login": False,  # Auto-start on macOS login
    # Per-app automatic style detection (Feature 2)
    "auto_style": True,  # Automatically switch style based on the frontmost app
    "app_styles": {
        # Coding environments -> code style
        "Code": "code",           # VS Code (macOS app name is "Code")
        "Xcode": "code",
        "Terminal": "code",
        "iTerm2": "code",
        "IntelliJ IDEA": "code",
        "PyCharm": "code",
        "WebStorm": "code",
        "RubyMine": "code",
        "GoLand": "code",
        "CLion": "code",
        "Zed": "code",
        "Nova": "code",
        "BBEdit": "code",
        # Email clients -> email style
        "Mail": "email",
        "Gmail": "email",
        "Outlook": "email",
        "Mimestream": "email",
        "Airmail 5": "email",
        "Superhuman": "email",
        # Chat / messaging apps -> casual style
        "Slack": "casual",
        "Discord": "casual",
        "Messages": "casual",
        "WhatsApp": "casual",
        "Telegram": "casual",
        "Signal": "casual",
        "Texts": "casual",
        # Document editors -> default style
        "Microsoft Word": "default",
        "Google Chrome": "default",
        "Safari": "default",
        "Pages": "default",
        "Notion": "default",
    },
    # Voice command replacement (Feature 3)
    "voice_commands": True,   # Replace spoken punctuation phrases pre-LLM
    "custom_commands": {},    # User-defined phrase → replacement overrides
    # Selected text context capture (Feature 4)
    "selected_text_context": True,  # Capture selected text as LLM context on hotkey press
    # Real-time streaming transcription (Feature 1)
    # Opt-in until whisper-stream can reliably finalize sub-step dictations.
    "streaming": False,            # Use whisper-stream for real-time transcription
    "streaming_step_ms": 3000,     # Audio step size in milliseconds for streaming
    # Auto-learn corrections from user edits after paste.
    # Strong privilege (reads focused text field via Accessibility API for
    # 30 s post-paste). Opt-in only — gated by the Know Me interview.
    "auto_learn": False,
    # Typed 🎙 recording indicator. Opt-in: it edits the frontmost document
    # (paste on start, backspace on stop) and can misfire when focus changes
    # mid-dictation. The overlay HUD is the default recording feedback.
    "recording_indicator": False,
    # Auto-update notifier
    "update_check": True,          # On launch, check GitHub Releases for a newer version
}

VALID_HOTKEYS = [
    "right_cmd", "left_fn", "left_cmd", "right_alt", "left_alt", "right_ctrl",
    "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
]

VALID_MODELS = [
    "tiny.en", "base.en", "small.en", "medium.en",  # English-only
    "tiny", "base", "small", "medium", "large",  # Multilingual
]
VALID_BACKENDS = ["openrouter", "openai", "anthropic", "groq", "ollama", "none"]
VALID_STYLES = ["default", "casual", "formal", "code", "email"]


def _migrate_cleanup_to_llm_prompt(stored: dict) -> bool:
    """Rename ``cleanup_prompt`` → ``llm_prompt`` for v0.1.x → v0.2+ upgrade.

    Returns True if ``stored`` was mutated. The merged config still drops
    the legacy key, but mutating ``stored`` lets the caller persist the
    migrated form so it's a one-time event.
    """
    if "cleanup_prompt" not in stored:
        return False
    if "llm_prompt" not in stored:
        stored["llm_prompt"] = stored["cleanup_prompt"]
    del stored["cleanup_prompt"]
    return True


def _migrate_gemini_to_openrouter(stored: dict) -> bool:
    """Rename the retired Gemini default backend/key fields to OpenRouter.

    Gemini API keys cannot be reused with OpenRouter, so a legacy
    ``gemini_api_key`` is removed rather than copied. Users must configure an
    OpenRouter key via ``openrouter_api_key`` or ``OPENROUTER_API_KEY``.
    """
    migrated = False
    if stored.get("llm_backend") == "gemini":
        stored["llm_backend"] = "openrouter"
        migrated = True
    if "gemini_api_key" in stored:
        del stored["gemini_api_key"]
        migrated = True
    return migrated


def _migrate_streaming_default(stored: dict) -> bool:
    """Reset v0.3.2's persisted streaming default to reliable batch mode.

    v0.3.2 wrote the entire defaults dictionary on first launch, so nearly
    every existing config contains ``streaming: true`` even when the user did
    not opt in. Stamp the first schema version and reset streaming once. A
    later explicit opt-in is preserved because the schema marker is present.
    """
    version = stored.get("_config_version")
    if isinstance(version, int) and version >= _STREAMING_DEFAULT_MIGRATION_VERSION:
        return False
    stored["streaming"] = False
    stored["_config_version"] = CONFIG_SCHEMA_VERSION
    return True


def load_config() -> dict:
    os.makedirs(CONFIG_DIR, exist_ok=True)
    from ._secure_io import secure_dir
    secure_dir(CONFIG_DIR)
    if not os.path.exists(CONFIG_PATH):
        save_config(DEFAULTS)
        return dict(DEFAULTS)
    try:
        with open(CONFIG_PATH) as f:
            stored = json.load(f)
        if not isinstance(stored, dict):
            raise ValueError("config root is not a JSON object")
    except (json.JSONDecodeError, ValueError, OSError) as exc:
        # A corrupt config must never brick the app (including --doctor and
        # --setup, which are the tools to fix it). Preserve the bad file for
        # manual recovery and continue with defaults.
        backup_path = CONFIG_PATH + ".corrupt"
        try:
            os.replace(CONFIG_PATH, backup_path)
        except OSError:
            backup_path = None
        print(
            f"⚠️  Could not read {CONFIG_PATH} ({exc}). "
            + (f"The unreadable file was moved to {backup_path}. " if backup_path else "")
            + "Continuing with default settings — re-add your API key with "
            "`openvoiceflow --setup` or `openvoiceflow --set-key`.",
            file=sys.stderr,
        )
        save_config(DEFAULTS)
        return dict(DEFAULTS)
    prompt_migrated = _migrate_cleanup_to_llm_prompt(stored)
    backend_migrated = _migrate_gemini_to_openrouter(stored)
    streaming_migrated = _migrate_streaming_default(stored)
    migrated = prompt_migrated or backend_migrated or streaming_migrated
    # Merge with defaults so new fields are always present
    config = dict(DEFAULTS)
    config.update(stored)
    if migrated:
        # Persist so the rename is a one-time event.
        save_config(stored)
        if prompt_migrated:
            print(
                "ℹ️  Migrated config key `cleanup_prompt` → `llm_prompt` "
                "(v0.1 → v0.2+ rename). Your custom prompt is preserved."
            )
        if backend_migrated:
            print(
                "ℹ️  Migrated retired Gemini backend config to OpenRouter. "
                "Set `openrouter_api_key` or OPENROUTER_API_KEY before using cloud cleanup."
            )
        if streaming_migrated:
            print(
                "ℹ️  Reset experimental streaming to the reliable batch recorder "
                "for v0.3.3. Re-enable it from the menu bar if you prefer live results."
            )
    return config


def save_config(config: dict):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    from ._secure_io import secure_write_json
    secure_write_json(CONFIG_PATH, config)


def get_api_key(config: dict, backend: str) -> str | None:
    key_map = {
        "openrouter": "openrouter_api_key",
        "openai": "openai_api_key",
        "anthropic": "anthropic_api_key",
        "groq": "groq_api_key",
    }
    field = key_map.get(backend)
    if not field:
        return None
    # Config file takes priority, then env var
    val = config.get(field)
    if val:
        return val
    env_map = {
        "openrouter_api_key": "OPENROUTER_API_KEY",
        "openai_api_key": "OPENAI_API_KEY",
        "anthropic_api_key": "ANTHROPIC_API_KEY",
        "groq_api_key": "GROQ_API_KEY",
    }
    return os.environ.get(env_map.get(field, ""), None)


def validate_config(config: dict) -> list[str]:
    """Return a list of validation errors (empty = valid)."""
    errors = []
    if config.get("hotkey") not in VALID_HOTKEYS:
        errors.append(f"Invalid hotkey '{config.get('hotkey')}'. Valid: {VALID_HOTKEYS}")
    if config.get("whisper_model") not in VALID_MODELS:
        errors.append(f"Invalid model '{config.get('whisper_model')}'. Valid: {VALID_MODELS}")
    if config.get("llm_backend") not in VALID_BACKENDS:
        errors.append(f"Invalid backend '{config.get('llm_backend')}'. Valid: {VALID_BACKENDS}")
    return errors
