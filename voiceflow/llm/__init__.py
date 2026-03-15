"""LLM backends for transcript cleanup."""
from .base import LLMBackend
from .gemini import GeminiBackend
from .openai_backend import OpenAIBackend
from .anthropic_backend import AnthropicBackend
from .groq_backend import GroqBackend
from .ollama_backend import OllamaBackend

BACKENDS = {
    "gemini": GeminiBackend,
    "openai": OpenAIBackend,
    "anthropic": AnthropicBackend,
    "groq": GroqBackend,
    "ollama": OllamaBackend,
}


def get_backend(config: dict) -> LLMBackend | None:
    """Get the configured LLM backend."""
    name = config.get("llm_backend", "gemini")
    if name == "none":
        return None
    cls = BACKENDS.get(name)
    if not cls:
        print(f"❌ Unknown LLM backend: {name}")
        print(f"   Available: {', '.join(BACKENDS.keys())}, none")
        return None
    return cls(config)


def cleanup_text(
    raw_text: str,
    config: dict,
    context: str | None = None,
    app_context: str | None = None,
    style: str | None = None,
) -> str:
    """Clean up raw transcript using the configured LLM.

    Args:
        raw_text:    Raw transcript from whisper.cpp.
        config:      Loaded OpenVoiceFlow config dict.
        context:     Optional selected-text captured before dictation.
        app_context: Optional LLM context fragment from
                     :func:`~voiceflow.context.get_app_context_prompt`.
        style:       Optional per-dictation style override (from per-app
                     detection); passed as ``override_style`` to the backend.
    """
    backend = get_backend(config)
    if not backend:
        return raw_text
    try:
        return backend.cleanup(
            raw_text,
            context=context,
            app_context=app_context,
            override_style=style,
        )
    except Exception as e:
        print(f"❌ LLM cleanup failed: {e}")
        return raw_text
