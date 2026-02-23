"""Abstract base class for LLM backends."""
from abc import ABC, abstractmethod


class LLMBackend(ABC):
    """Base class for all LLM cleanup backends."""

    name: str = "base"
    default_model: str = ""

    def __init__(self, config: dict):
        self.config = config
        self.prompt = config.get("cleanup_prompt", "")
        self.model = config.get("llm_model") or self.default_model

    @abstractmethod
    def cleanup(self, raw_text: str) -> str:
        """Clean up raw transcript text. Returns cleaned text."""
        ...

    @abstractmethod
    def validate(self) -> tuple[bool, str]:
        """Validate the backend is configured. Returns (ok, message)."""
        ...

    def _make_prompt(self, raw_text: str) -> str:
        return f"{self.prompt}\n\nTranscript:\n{raw_text}"
