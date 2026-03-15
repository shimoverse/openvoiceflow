"""OpenAI backend for transcript cleanup."""
import json
import os
import urllib.request
import urllib.error
from .base import LLMBackend


class OpenAIBackend(LLMBackend):
    name = "openai"
    default_model = "gpt-4o-mini"

    def __init__(self, config: dict):
        super().__init__(config)
        self.api_key = (
            config.get("openai_api_key")
            or os.environ.get("OPENAI_API_KEY", "")
        )

    def validate(self) -> tuple[bool, str]:
        if not self.api_key:
            return False, "No OpenAI API key. Get one at https://platform.openai.com/api-keys"
        return True, f"OpenAI ({self.model})"

    def cleanup(
        self,
        raw_text: str,
        context: str | None = None,
        app_context: str | None = None,
        override_style: str | None = None,
    ) -> str:
        if not self.api_key:
            return raw_text

        url = "https://api.openai.com/v1/chat/completions"
        # Inject context into user turn when available
        if context:
            user_content = (
                f"Context - the user had this text selected: '{context}'. "
                f"Clean up the following dictation taking context into account:\n\n{raw_text}"
            )
        else:
            user_content = raw_text
        payload = {
            "model": self.model,
            "messages": [
                {"role": "system", "content": self.prompt},
                {"role": "user", "content": user_content},
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
            print(f"❌ OpenAI API error ({e.code}): {error_body}")
            return raw_text
        except Exception as e:
            print(f"❌ OpenAI error: {e}")
            return raw_text
