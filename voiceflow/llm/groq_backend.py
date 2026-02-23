"""Groq backend for transcript cleanup (OpenAI-compatible API)."""
import json
import os
import urllib.request
import urllib.error
from .base import LLMBackend


class GroqBackend(LLMBackend):
    name = "groq"
    default_model = "llama-3.3-70b-versatile"

    def __init__(self, config: dict):
        super().__init__(config)
        self.api_key = (
            config.get("groq_api_key")
            or os.environ.get("GROQ_API_KEY", "")
        )

    def validate(self) -> tuple[bool, str]:
        if not self.api_key:
            return False, "No Groq API key. Get one free at https://console.groq.com/keys"
        return True, f"Groq ({self.model})"

    def cleanup(self, raw_text: str) -> str:
        if not self.api_key:
            return raw_text

        url = "https://api.groq.com/openai/v1/chat/completions"
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": self.prompt},
                {"role": "user", "content": raw_text},
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
            error_body = e.read().decode()
            print(f"❌ Groq API error ({e.code}): {error_body}")
            return raw_text
        except Exception as e:
            print(f"❌ Groq error: {e}")
            return raw_text
