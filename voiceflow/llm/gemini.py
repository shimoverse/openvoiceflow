"""Google Gemini backend for transcript cleanup."""
import json
import os
import urllib.request
import urllib.error
from .base import LLMBackend


class GeminiBackend(LLMBackend):
    name = "gemini"
    default_model = "gemini-2.0-flash-lite"

    def __init__(self, config: dict):
        super().__init__(config)
        self.api_key = (
            config.get("gemini_api_key")
            or os.environ.get("GEMINI_API_KEY", "")
        )

    def validate(self) -> tuple[bool, str]:
        if not self.api_key:
            return False, "No Gemini API key. Get one free at https://aistudio.google.com/apikey"
        return True, f"Gemini ({self.model})"

    def cleanup(self, raw_text: str) -> str:
        if not self.api_key:
            return raw_text

        url = (
            f"https://generativelanguage.googleapis.com/v1beta/models/"
            f"{self.model}:generateContent?key={self.api_key}"
        )
        payload = {
            "contents": [{"parts": [{"text": self._make_prompt(raw_text)}]}],
            "generationConfig": {"temperature": 0.1, "maxOutputTokens": 2048},
        }
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read().decode())
                return data["candidates"][0]["content"]["parts"][0]["text"].strip()
        except urllib.error.HTTPError as e:
            error_body = e.read().decode()
            print(f"❌ Gemini API error ({e.code}): {error_body}")
            return raw_text
        except Exception as e:
            print(f"❌ Gemini error: {e}")
            return raw_text
