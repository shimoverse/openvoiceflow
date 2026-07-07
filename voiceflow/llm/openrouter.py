"""OpenRouter backend for transcript cleanup using Gemma 4."""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request

from .base import LLMBackend

OPENROUTER_DEFAULT_MODEL = "google/gemma-4-31b-it"


class OpenRouterBackend(LLMBackend):
    name = "openrouter"
    default_model = OPENROUTER_DEFAULT_MODEL

    def __init__(self, config: dict):
        super().__init__(config)
        self.api_key = (
            config.get("openrouter_api_key")
            or os.environ.get("OPENROUTER_API_KEY", "")
        )
        self.model = (
            config.get("openrouter_model")
            or os.environ.get("OPENROUTER_MODEL")
            or self.default_model
        )

    def validate(self) -> tuple[bool, str]:
        if not self.api_key:
            return False, "No OpenRouter API key. Get one at https://openrouter.ai/keys"
        return True, f"OpenRouter ({self.model})"

    def cleanup(
        self,
        text: str,
        context: str | None = None,
        app_context: str | None = None,
        override_style: str | None = None,
    ) -> str:
        if not self.api_key:
            return text

        url = "https://openrouter.ai/api/v1/chat/completions"
        payload = {
            "model": self.model,
            "messages": [
                {
                    "role": "user",
                    "content": self._make_prompt(
                        text,
                        context=context,
                        app_context=app_context,
                        override_style=override_style,
                    ),
                },
            ],
            "temperature": 0.1,
            "max_tokens": 2048,
        }
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.api_key}",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read().decode())
                return data["choices"][0]["message"]["content"].strip()
        except urllib.error.HTTPError as e:
            error_body = e.read().decode("utf-8", errors="replace")
            print(f"❌ OpenRouter API error ({e.code}): {error_body}")
            return text
        except Exception as e:
            print(f"❌ OpenRouter error: {e}")
            return text
