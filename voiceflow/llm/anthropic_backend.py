"""Anthropic Claude backend for transcript cleanup."""
import json
import os
import urllib.request
import urllib.error
from .base import LLMBackend


class AnthropicBackend(LLMBackend):
    name = "anthropic"
    default_model = "claude-3-5-haiku-20241022"

    def __init__(self, config: dict):
        super().__init__(config)
        self.api_key = (
            config.get("anthropic_api_key")
            or os.environ.get("ANTHROPIC_API_KEY", "")
        )

    def validate(self) -> tuple[bool, str]:
        if not self.api_key:
            return False, "No Anthropic API key. Get one at https://console.anthropic.com/"
        return True, f"Claude ({self.model})"

    def cleanup(self, raw_text: str) -> str:
        if not self.api_key:
            return raw_text

        url = "https://api.anthropic.com/v1/messages"
        payload = {
            "model": self.model,
            "max_tokens": 2048,
            "system": self.prompt,
            "messages": [{"role": "user", "content": raw_text}],
        }
        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Content-Type": "application/json",
                "x-api-key": self.api_key,
                "anthropic-version": "2023-06-01",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read().decode())
                return data["content"][0]["text"].strip()
        except urllib.error.HTTPError as e:
            error_body = e.read().decode()
            print(f"❌ Anthropic API error ({e.code}): {error_body}")
            return raw_text
        except Exception as e:
            print(f"❌ Anthropic error: {e}")
            return raw_text
