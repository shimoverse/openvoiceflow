"""Configuration management for OpenVoiceFlow."""
import json
from pathlib import Path

CONFIG_DIR = Path.home() / ".openvoiceflow"
CONFIG_PATH = CONFIG_DIR / "config.json"
MODELS_DIR = CONFIG_DIR / "models"
LOG_DIR = Path.home() / "OpenVoiceFlow" / "logs"

DEFAULT_CONFIG = {
    # Hotkey
    "hotkey": "right_cmd",  # right_cmd, right_alt, left_alt, f5, f6, etc.

    # Whisper (local transcription)
    "whisper_model": "base.en",  # tiny.en, base.en, small.en, medium.en, large-v3
    "whisper_cpp_path": "",  # auto-detected if empty

    # LLM backend for cleanup
    "llm_backend": "gemini",  # gemini, openai, anthropic, groq, ollama, none
    "llm_model": "",  # auto-selected per backend if empty

    # API keys (per backend)
    "gemini_api_key": "",
    "openai_api_key": "",
    "anthropic_api_key": "",
    "groq_api_key": "",

    # Ollama settings
    "ollama_url": "http://localhost:11434",
    "ollama_model": "llama3.2",

    # Cleanup prompt
    "cleanup_prompt": (
        "Clean up this voice dictation transcript. "
        "Remove filler words (um, uh, like, you know), "
        "fix grammar and punctuation, "
        "handle corrections (e.g. 'no wait' means discard what came before), "
        "and make it read naturally. "
        "Keep the speaker's intent and tone. "
        "Output ONLY the cleaned text, nothing else."
    ),

    # Behavior
    "sound_feedback": True,
    "auto_paste": True,
    "log_transcripts": True,
    "language": "en",

    # Audio
    "sample_rate": 16000,
    "channels": 1,
}


def ensure_dirs():
    """Create all required directories."""
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    MODELS_DIR.mkdir(parents=True, exist_ok=True)
    LOG_DIR.mkdir(parents=True, exist_ok=True)


def load_config() -> dict:
    """Load config, creating default if needed."""
    ensure_dirs()
    if CONFIG_PATH.exists():
        with open(CONFIG_PATH) as f:
            saved = json.load(f)
        return {**DEFAULT_CONFIG, **saved}
    else:
        config = DEFAULT_CONFIG.copy()
        save_config(config)
        return config


def save_config(config: dict):
    """Save config to disk."""
    ensure_dirs()
    with open(CONFIG_PATH, "w") as f:
        json.dump(config, f, indent=2)


def get_api_key(config: dict) -> str:
    """Get the API key for the active LLM backend."""
    import os
    backend = config["llm_backend"]
    key_map = {
        "gemini": ("gemini_api_key", "GEMINI_API_KEY"),
        "openai": ("openai_api_key", "OPENAI_API_KEY"),
        "anthropic": ("anthropic_api_key", "ANTHROPIC_API_KEY"),
        "groq": ("groq_api_key", "GROQ_API_KEY"),
    }
    if backend in key_map:
        config_key, env_key = key_map[backend]
        return config.get(config_key) or os.environ.get(env_key, "")
    return ""
