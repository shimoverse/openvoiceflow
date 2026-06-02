"""OpenRouter backend tests."""
from __future__ import annotations

import json


def test_openrouter_validate_requires_key(monkeypatch) -> None:
    from voiceflow.llm.openrouter import OpenRouterBackend

    monkeypatch.delenv("OPENROUTER_API_KEY", raising=False)
    backend = OpenRouterBackend({"llm_backend": "openrouter"})

    ok, message = backend.validate()

    assert ok is False
    assert "OpenRouter API key" in message
    assert "openrouter.ai/keys" in message


def test_openrouter_uses_env_model(monkeypatch) -> None:
    from voiceflow.llm.openrouter import OpenRouterBackend

    monkeypatch.setenv("OPENROUTER_API_KEY", "test-key")
    monkeypatch.setenv("OPENROUTER_MODEL", "google/gemma-4-31b-it")

    backend = OpenRouterBackend({"llm_backend": "openrouter"})

    assert backend.api_key == "test-key"
    assert backend.model == "google/gemma-4-31b-it"


def test_openrouter_cleanup_posts_openai_compatible_payload(monkeypatch) -> None:
    from voiceflow.llm import openrouter
    from voiceflow.llm.openrouter import OpenRouterBackend

    captured = {}

    class FakeResponse:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def read(self):
            return json.dumps({"choices": [{"message": {"content": " cleaned text "}}]}).encode()

    def fake_urlopen(req, timeout):
        captured["url"] = req.full_url
        captured["timeout"] = timeout
        captured["payload"] = json.loads(req.data.decode())
        captured["auth"] = req.headers.get("Authorization")
        return FakeResponse()

    monkeypatch.setattr(openrouter.urllib.request, "urlopen", fake_urlopen)
    backend = OpenRouterBackend(
        {
            "llm_backend": "openrouter",
            "openrouter_api_key": "test-key",
            "openrouter_model": "google/gemma-4-31b-it",
        }
    )

    result = backend.cleanup("raw words")

    assert result == "cleaned text"
    assert captured["url"] == "https://openrouter.ai/api/v1/chat/completions"
    assert captured["timeout"] == 10
    assert captured["auth"] == "Bearer test-key"
    assert captured["payload"]["model"] == "google/gemma-4-31b-it"
    assert captured["payload"]["messages"][0]["role"] == "user"
    assert "Transcript: raw words" in captured["payload"]["messages"][0]["content"]
