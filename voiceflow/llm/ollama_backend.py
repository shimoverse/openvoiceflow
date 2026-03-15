"""Ollama backend for fully local transcript cleanup ($0 cost)."""
import json
import urllib.request
import urllib.error
from .base import LLMBackend


class OllamaBackend(LLMBackend):
    name = "ollama"
    default_model = "llama3.2"

    def __init__(self, config: dict):
        super().__init__(config)
        self.base_url = config.get("ollama_url", "http://localhost:11434")
        # ollama uses ollama_model key specifically; override base class model
        self.model = config.get("ollama_model", self.default_model)

    def validate(self) -> tuple[bool, str]:
        try:
            req = urllib.request.Request(f"{self.base_url}/api/tags")
            with urllib.request.urlopen(req, timeout=3) as resp:
                data = json.loads(resp.read().decode())
                models = [m["name"] for m in data.get("models", [])]
                if not models:
                    return False, "Ollama running but no models. Run: ollama pull llama3.2"
                return True, f"Ollama ({self.model}) — fully local"
        except Exception:
            return False, "Ollama not running. Install from https://ollama.com then run: ollama serve"

    def cleanup(
        self,
        raw_text: str,
        context: str | None = None,
        app_context: str | None = None,
        override_style: str | None = None,
    ) -> str:
        url = f"{self.base_url}/api/generate"
        payload = {
            "model": self.model,
            "prompt": self._make_prompt(raw_text, context=context, app_context=app_context, override_style=override_style),
            "stream": False,
            "options": {"temperature": 0.1},
        }
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                data = json.loads(resp.read().decode())
                return data.get("response", raw_text).strip()
        except Exception as e:
            print(f"❌ Ollama error: {e}")
            return raw_text
