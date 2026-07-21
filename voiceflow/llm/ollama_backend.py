"""Ollama backend for fully local transcript cleanup ($0 cost)."""

from __future__ import annotations

import json
import urllib.error
import urllib.request

from .base import LLMBackend, read_json_capped, sanitize_local_url


class OllamaBackend(LLMBackend):
    name = "ollama"
    default_model = "llama3.2"
    _DEFAULT_URL = "http://localhost:11434"

    def __init__(self, config: dict):
        super().__init__(config)
        self.base_url = sanitize_local_url(
            config.get("ollama_url", self._DEFAULT_URL), self._DEFAULT_URL
        )
        # ollama uses ollama_model key specifically; override base class model
        self.model = config.get("ollama_model", self.default_model)

    def validate(self) -> tuple[bool, str]:
        try:
            req = urllib.request.Request(f"{self.base_url}/api/tags")
            with urllib.request.urlopen(req, timeout=3) as resp:
                data = read_json_capped(resp)
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
        prompt_text = self._make_prompt(
            raw_text,
            context=context,
            app_context=app_context,
            override_style=override_style,
        )
        payload = {
            "model": self.model,
            "prompt": prompt_text,
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
            # Generous timeout: with stream=False Ollama sends nothing until
            # generation completes, and a cold model load alone can take
            # longer than 30 s.
            with urllib.request.urlopen(req, timeout=120) as resp:
                data = read_json_capped(resp)
                return data.get("response", raw_text).strip()
        except Exception as e:
            print(f"❌ Ollama error: {e}")
            return raw_text
