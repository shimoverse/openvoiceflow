"""Abstract base class for LLM cleanup backends."""

from __future__ import annotations

import json
import sys
from abc import ABC, abstractmethod
from urllib.parse import urlparse

# Ceiling on a single LLM/Ollama HTTP response. A cleanup reply is a few KB;
# 16 MB is orders of magnitude of headroom while still bounding a hostile or
# buggy endpoint (most realistically a non-TLS local Ollama port answered by
# another process) that would otherwise stream unbounded bytes into memory
# on the dictation thread.
MAX_RESPONSE_BYTES = 16 * 1024 * 1024

_LOOPBACK_HOSTS = {"localhost", "127.0.0.1", "::1", "0.0.0.0"}


def read_json_capped(resp, max_bytes: int = MAX_RESPONSE_BYTES):
    """``json.loads`` an HTTP response, refusing bodies larger than max_bytes."""
    raw = resp.read(max_bytes + 1)
    if len(raw) > max_bytes:
        raise ValueError(f"response exceeded {max_bytes} bytes")
    return json.loads(raw.decode("utf-8"))


def sanitize_local_url(url: str, default: str) -> str:
    """Validate a user-supplied local-service base URL (e.g. ``ollama_url``).

    Rejects non-HTTP(S) schemes (``file:``/``ftp:`` would let a config edit
    redirect private prompts through urllib), falling back to *default*.
    Warns once on stderr when the host isn't loopback, since the whole
    transcript + profile would then leave the machine in the clear.
    """
    try:
        parsed = urlparse(url)
    except Exception:
        return default
    if parsed.scheme not in ("http", "https") or not parsed.hostname:
        print(
            f"⚠️  Ignoring invalid ollama_url {url!r} (must be http(s)://host). "
            f"Using {default}.",
            file=sys.stderr,
        )
        return default
    if parsed.hostname not in _LOOPBACK_HOSTS:
        print(
            f"⚠️  ollama_url points off-box ({parsed.hostname}); your transcript "
            "and profile will be sent there in the clear. Use a loopback address "
            "to keep dictation fully local.",
            file=sys.stderr,
        )
    return url

DEFAULT_PROMPT = (
    "You are a voice dictation cleanup assistant. "
    "Fix grammar, remove filler words (um, uh, like, you know), "
    "handle corrections (phrases like 'no wait', 'I mean', 'actually'), "
    "and return ONLY the cleaned text — no explanations, no quotes. "
    "Preserve the original meaning and tone. "
    "If the input is already clean, return it unchanged."
)

# Style preset prompts for tone/style modes
STYLE_PRESETS = {
    "default": "",
    "casual": "\nUse a casual, friendly tone. Contractions are fine. Keep it conversational.",
    "formal": "\nUse formal language. Avoid contractions. Use professional tone.",
    "code": "\nPreserve all technical terms, function names, and code references exactly. "
             "Format as a developer would write in a code comment or commit message.",
    "email": "\nFormat as professional email text. Use appropriate greeting/closing if present.",
}


class LLMBackend(ABC):
    name = ""
    default_model = ""

    def __init__(self, config: dict):
        self.config = config
        self.prompt = config.get("llm_prompt") or DEFAULT_PROMPT

        # Append style preset if configured
        style = config.get("style", "default")
        style_suffix = STYLE_PRESETS.get(style, "")
        if style_suffix:
            self.prompt += style_suffix

        # Append personal dictionary context
        from ..dictionary import get_dictionary_prompt_fragment
        self.prompt += get_dictionary_prompt_fragment()

        # Append snippets context
        from ..snippets import get_snippets_prompt_fragment
        self.prompt += get_snippets_prompt_fragment()

        # Append personal profile context ("Know Me" — names, occupation, style)
        from ..profile import get_profile_prompt_fragment
        self.prompt += get_profile_prompt_fragment()

        self.model = config.get(f"{self.name}_model", self.default_model)

    def _make_system_prompt(
        self,
        app_context: str | None = None,
        override_style: str | None = None,
    ) -> str:
        """Build the system prompt with per-dictation style/app context applied.

        Backends with a separate system/user message split (OpenAI, Anthropic,
        Groq) use this for the system message; :meth:`_make_prompt` builds on
        it for single-prompt backends (OpenRouter, Ollama).

        Args:
            app_context:    Optional context fragment from
                            :func:`~voiceflow.context.get_app_context_prompt`,
                            describing the active app + style hint.
            override_style: When per-app detection resolves a different style
                            than the global config default, pass it here to
                            rebuild the style suffix on the fly.
        """
        base_prompt = self.prompt

        # Apply per-dictation style override when auto_style resolved a
        # different style than the global default baked into self.prompt.
        if override_style and override_style != self.config.get("style", "default"):
            base = self.config.get("llm_prompt") or DEFAULT_PROMPT
            from ..dictionary import get_dictionary_prompt_fragment
            from ..profile import get_profile_prompt_fragment
            from ..snippets import get_snippets_prompt_fragment
            style_suffix = STYLE_PRESETS.get(override_style, "")
            base_prompt = (
                base
                + style_suffix
                + get_dictionary_prompt_fragment()
                + get_snippets_prompt_fragment()
                + get_profile_prompt_fragment()
            )

        # Append app context fragment (e.g. "User is in VS Code...")
        if app_context:
            base_prompt = base_prompt + app_context

        return base_prompt

    def _make_prompt(
        self,
        text: str,
        context: str | None = None,
        app_context: str | None = None,
        override_style: str | None = None,
    ) -> str:
        """Build the full prompt string combining system prompt and transcript.

        Args:
            text:           Raw transcript to clean up.
            context:        Optional selected-text captured before dictation
                            (from :mod:`voiceflow.clipboard`).
            app_context:    See :meth:`_make_system_prompt`.
            override_style: See :meth:`_make_system_prompt`.
        """
        base_prompt = self._make_system_prompt(
            app_context=app_context,
            override_style=override_style,
        )

        # Prepend selected-text context block when available
        if context:
            context_block = (
                f"Context - the user had this text selected: '{context}'. "
                "Clean up the following dictation taking context into account:"
            )
            return f"{base_prompt}\n\n{context_block}\n\nTranscript: {text}"

        return f"{base_prompt}\n\nTranscript: {text}"

    @abstractmethod
    def cleanup(
        self,
        text: str,
        context: str | None = None,
        app_context: str | None = None,
        override_style: str | None = None,
    ) -> str:
        """Clean up transcribed text. Returns cleaned string.

        Args:
            text:           Raw transcript.
            context:        Optional selected-text context fragment.
            app_context:    Optional app-context LLM fragment.
            override_style: Optional per-dictation style override.
        """
        ...

    @abstractmethod
    def validate(self) -> tuple[bool, str]:
        """Validate the backend is configured. Returns (ok, message)."""
        ...
