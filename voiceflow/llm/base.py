"""Abstract base class for LLM cleanup backends."""
from abc import ABC, abstractmethod

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
            app_context:    Optional context fragment from
                            :func:`~voiceflow.context.get_app_context_prompt`,
                            describing the active app + style hint.
            override_style: When per-app detection resolves a different style
                            than the global config default, pass it here to
                            rebuild the style suffix on the fly.
        """
        # Start from the base prompt
        base_prompt = self.prompt

        # Apply per-dictation style override when auto_style resolved a
        # different style than the global default baked into self.prompt.
        if override_style and override_style != self.config.get("style", "default"):
            base = self.config.get("llm_prompt") or DEFAULT_PROMPT
            from ..dictionary import get_dictionary_prompt_fragment
            from ..snippets import get_snippets_prompt_fragment
            from ..profile import get_profile_prompt_fragment
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
