"""OpenVoiceFlow configuration management."""
import json
import os
from pathlib import Path

CONFIG_DIR = os.path.expanduser("~/.openvoiceflow")
CONFIG_PATH = os.path.join(CONFIG_DIR, "config.json")

LOG_DIR = Path(CONFIG_DIR) / "logs"
MODELS_DIR = Path(CONFIG_DIR) / "models"

DEFAULTS = {
    "hotkey": "right_cmd",
    "whisper_model": "base.en",
    "whisper_cpp_path": None,
    "llm_backend": "gemini",
    "gemini_api_key": None,
    "openai_api_key": None,
    "anthropic_api_key": None,
    "groq_api_key": None,
    "sound_feedback": True,
    "auto_paste": True,
    "log_transcripts": True,
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
    "streaming": True,             # Use whisper-stream for real-time transcription
    "streaming_step_ms": 3000,     # Audio step size in milliseconds for streaming
    # Auto-learn corrections from user edits after paste
    "auto_learn": True,            # Watch for post-paste corrections and add to dictionary
}

VALID_HOTKEYS = [
    "right_cmd", "left_cmd", "right_alt", "left_alt", "right_ctrl",
    "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
]

VALID_MODELS = [
    "tiny.en", "base.en", "small.en", "medium.en",  # English-only
    "tiny", "base", "small", "medium", "large",  # Multilingual
]
VALID_BACKENDS = ["gemini", "openai", "anthropic", "groq", "ollama", "none"]
VALID_STYLES = ["default", "casual", "formal", "code", "email"]


def load_config() -> dict:
    os.makedirs(CONFIG_DIR, exist_ok=True)
    if not os.path.exists(CONFIG_PATH):
        save_config(DEFAULTS)
        return dict(DEFAULTS)
    with open(CONFIG_PATH) as f:
        stored = json.load(f)
    # Merge with defaults so new fields are always present
    config = dict(DEFAULTS)
    config.update(stored)
    return config


def save_config(config: dict):
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(CONFIG_PATH, "w") as f:
        json.dump(config, f, indent=2)


def get_api_key(config: dict, backend: str) -> str | None:
    key_map = {
        "gemini": "gemini_api_key",
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
        "gemini_api_key": "GEMINI_API_KEY",
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
