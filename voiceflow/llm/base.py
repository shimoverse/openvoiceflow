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


class LLMBackend(ABC):
    name = ""
    default_model = ""

    def __init__(self, config: dict):
        self.config = config
        self.prompt = config.get("llm_prompt") or DEFAULT_PROMPT
        self.model = config.get(f"{self.name}_model", self.default_model)

    def _make_prompt(self, text: str) -> str:
        """Build the full prompt string combining system prompt and transcript."""
        return f"{self.prompt}\n\nTranscript: {text}"

    @abstractmethod
    def cleanup(self, text: str) -> str:
        """Clean up transcribed text. Returns cleaned string."""
        ...

    @abstractmethod
    def validate(self) -> tuple[bool, str]:
        """Validate the backend is configured. Returns (ok, message)."""
        ...
