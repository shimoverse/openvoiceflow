"""Regression tests for the 2026-07 code-review fixes.

Each test pins a specific defect found in the review so it can't return:

- commands: custom replacements with backslashes crashed re.sub; expansions
  were re-processed by later commands.
- snippets: a bare prefix match let a trigger swallow an unrelated dictation.
- config: a corrupt config.json crashed every CLI entry point.
- _secure_io: writes were non-atomic and briefly world-readable.
- updater: GitHub API strings were interpolated unescaped into AppleScript,
  and pre-release tags parsed as (0,).
- llm: empty backend responses erased the dictation; system/user backends
  dropped app_context/override_style.
- app: streaming+snippet dictations died on a NameError; auto_learn fell
  back to True at the enforcement point.
"""
from __future__ import annotations

import json
import os
import stat

import pytest

# ── commands.py ──────────────────────────────────────────────────────────

def test_apply_commands_backslash_replacement_does_not_crash():
    from voiceflow.commands import apply_commands
    commands = {"my folder": "C:\\Users\\me", "latex today": "\\today"}
    out = apply_commands("open my folder now", commands)
    assert out == "open C:\\Users\\me now"
    # Replacements starting with punctuation consume the preceding space
    # (same rule as "," / "."), and the backslash must survive literally.
    out = apply_commands("insert latex today", commands)
    assert out == "insert\\today"


def test_apply_commands_expansion_not_reprocessed():
    from voiceflow.commands import apply_commands
    commands = {
        "insert address": "12 Period Lane",
        "period": ".",
    }
    out = apply_commands("insert address please", commands)
    # "Period" inside the expansion must NOT be rewritten to "."
    assert out == "12 Period Lane please"


def test_apply_commands_defaults_still_work():
    from voiceflow.commands import DEFAULT_COMMANDS, apply_commands
    out = apply_commands("hello comma world period", DEFAULT_COMMANDS)
    assert out == "hello, world."
    # Whitespace replacements don't consume surrounding spaces (pre-existing
    # behavior; the LLM cleanup pass normalizes them)
    out = apply_commands("first line new line second line", DEFAULT_COMMANDS)
    assert out == "first line \n second line"
    out = apply_commands("NEW PARAGRAPH indeed", DEFAULT_COMMANDS)
    assert "\n\n" in out


# ── snippets.py ──────────────────────────────────────────────────────────

def test_snippet_prefix_requires_word_boundary(monkeypatch):
    import voiceflow.snippets as snippets
    monkeypatch.setattr(
        snippets, "load_snippets",
        lambda: {"sig": "Best regards,\nAlex"},
    )
    # A dictation *starting with* the trigger as a word-prefix must not match
    assert snippets.match_snippet("significant delays are expected") is None
    # Exact match, trailing punctuation, and follow-on words still match
    assert snippets.match_snippet("sig") is not None
    assert snippets.match_snippet("Sig.") is not None
    assert snippets.match_snippet("sig please") is not None


# ── config.py ────────────────────────────────────────────────────────────

def test_corrupt_config_recovers_with_defaults(tmp_path, monkeypatch):
    import voiceflow.config as config
    cfg_dir = tmp_path / ".openvoiceflow"
    cfg_dir.mkdir()
    cfg_path = cfg_dir / "config.json"
    cfg_path.write_text("{ this is not json")
    monkeypatch.setattr(config, "CONFIG_DIR", str(cfg_dir))
    monkeypatch.setattr(config, "CONFIG_PATH", str(cfg_path))

    loaded = config.load_config()

    assert loaded["hotkey"] == config.DEFAULTS["hotkey"]
    # The corrupt file is preserved for manual recovery
    assert (cfg_dir / "config.json.corrupt").exists()
    # And a fresh valid config was written
    assert json.loads(cfg_path.read_text())["hotkey"] == config.DEFAULTS["hotkey"]


# ── _secure_io.py ────────────────────────────────────────────────────────

def test_secure_write_json_is_0600_and_leaves_no_temp(tmp_path):
    from voiceflow._secure_io import secure_write_json
    target = tmp_path / "config.json"
    secure_write_json(target, {"openrouter_api_key": "secret"})

    mode = stat.S_IMODE(os.stat(target).st_mode)
    assert mode == 0o600
    assert json.loads(target.read_text())["openrouter_api_key"] == "secret"
    leftovers = [p for p in os.listdir(tmp_path) if ".tmp" in p]
    assert leftovers == []


def test_secure_write_json_failure_preserves_original(tmp_path):
    from voiceflow._secure_io import secure_write_json
    target = tmp_path / "config.json"
    secure_write_json(target, {"ok": True})

    class Unserializable:
        pass

    with pytest.raises(TypeError):
        secure_write_json(target, {"bad": Unserializable()})

    # Original content intact — the failed write never touched the target
    assert json.loads(target.read_text()) == {"ok": True}


# ── updater.py ───────────────────────────────────────────────────────────

def test_parse_version_tolerates_prerelease_suffixes():
    from voiceflow.updater import _parse_version
    assert _parse_version("v1.0.0-rc1") == (1, 0, 0)
    assert _parse_version("0.4.0.dev1") == (0, 4, 0)
    assert _parse_version("0.3.0") == (0, 3, 0)
    assert _parse_version("garbage") == (0,)


def test_update_notification_escapes_applescript(monkeypatch):
    import voiceflow.updater as updater

    captured = {}

    def fake_run(cmd, **kwargs):
        captured["script"] = cmd[2]

    monkeypatch.setattr("subprocess.run", fake_run)
    updater._send_notification('1.0" & do shell script "open -a Calculator', "https://x")
    # The malicious quote must arrive escaped, not as a literal AppleScript quote
    assert '\\"' in captured["script"]
    assert '"1.0" &' not in captured["script"]


# ── llm ──────────────────────────────────────────────────────────────────

def _backend_config(backend="openrouter"):
    from voiceflow.config import DEFAULTS
    cfg = dict(DEFAULTS)
    cfg["llm_backend"] = backend
    cfg[f"{backend}_api_key"] = "test-key"
    return cfg


def test_cleanup_text_empty_response_returns_raw(monkeypatch):
    import voiceflow.llm as llm

    class EmptyBackend:
        def cleanup(self, text, **kwargs):
            return "   "

    monkeypatch.setattr(llm, "get_backend", lambda config: EmptyBackend())
    assert llm.cleanup_text("what I said", {}) == "what I said"


@pytest.mark.parametrize("backend_name", ["openai", "anthropic", "groq"])
def test_system_prompt_backends_apply_app_context_and_style(backend_name, monkeypatch):
    """OpenAI/Anthropic/Groq must send app_context + override_style upstream."""
    import urllib.request

    from voiceflow.llm import BACKENDS

    cfg = _backend_config(backend_name)
    backend = BACKENDS[backend_name](cfg)

    sent = {}

    class FakeResponse:
        def __enter__(self):
            return self

        def __exit__(self, *a):
            return False

        def read(self):
            if backend_name == "anthropic":
                return json.dumps({"content": [{"text": "cleaned"}]}).encode()
            return json.dumps(
                {"choices": [{"message": {"content": "cleaned"}}]}
            ).encode()

    def fake_urlopen(req, timeout=None):
        sent["payload"] = json.loads(req.data.decode())
        return FakeResponse()

    monkeypatch.setattr(urllib.request, "urlopen", fake_urlopen)

    result = backend.cleanup(
        "raw words",
        app_context="\nUser is dictating in Slack.",
        override_style="casual",
    )
    assert result == "cleaned"

    payload = sent["payload"]
    if backend_name == "anthropic":
        system_prompt = payload["system"]
    else:
        system_prompt = payload["messages"][0]["content"]
    assert "Slack" in system_prompt, "app_context was dropped"
    assert "casual" in system_prompt.lower(), "override_style was dropped"


# ── app.py ───────────────────────────────────────────────────────────────

def test_streaming_snippet_result_no_nameerror(monkeypatch):
    """Snippet match in streaming mode must not blow up on timing vars."""
    import voiceflow.app as app_mod

    vf = app_mod.OpenVoiceFlow.__new__(app_mod.OpenVoiceFlow)
    vf.config = {
        "sound_feedback": False,
        "auto_paste": False,
        "log_transcripts": False,
        "auto_learn": False,
    }

    class FakeOverlay:
        def __init__(self):
            self.calls = []

        def show_processing(self):
            self.calls.append("processing")

        def show_result(self, text, timing=None):
            self.calls.append(("result", text, timing))

        def show_error(self, message, duration=3.0):
            self.calls.append(("error", message))

    vf._overlay = FakeOverlay()
    vf.processing = True

    monkeypatch.setattr(app_mod, "match_snippet", lambda text: "EXPANDED")
    monkeypatch.setattr(app_mod, "log_transcript", lambda *a, **kw: None)
    monkeypatch.setattr(app_mod, "record_dictation", lambda *a, **kw: None)

    vf._process_streaming_result("insert sig", duration=1.0)

    assert ("result", "EXPANDED", None) in vf._overlay.calls
    assert not any(c[0] == "error" for c in vf._overlay.calls if isinstance(c, tuple))
    assert vf.processing is False


def test_auto_learn_enforcement_defaults_off():
    """The .get() fallback at the enforcement sites must be False (opt-in)."""
    import inspect

    import voiceflow.app as app_mod
    import voiceflow.menubar as menubar_mod

    for module in (app_mod, menubar_mod):
        source = inspect.getsource(module)
        assert 'get("auto_learn", True)' not in source, (
            f"{module.__name__} defaults auto_learn ON when the key is "
            "missing — the privileged watcher must be opt-in"
        )
