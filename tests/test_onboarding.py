"""SS6 regression test: onboarding "Personalize" button surfaces errors.

Background: ``onboarding.OnboardingWizard.launch_interview_then_close`` wrapped
``run_interview()`` in ``try/except: pass``. If interview ever raised
(broken import, runtime error, AppKit absence on a CI runner), the
flagship "Personalize OpenVoiceFlow ✨" button silently did nothing, and
the user had no way to know why.

This test pins down: when ``run_interview`` raises, the error must be
visible to the user via stderr and (when tkinter is available)
``messagebox.showerror``.
"""
from __future__ import annotations

import importlib
import json
from pathlib import Path


def test_interview_error_is_surfaced_to_stderr(monkeypatch, capsys) -> None:
    """A failure in interview.run_interview must print to stderr."""
    import voiceflow.onboarding as ob

    importlib.reload(ob)  # reset module-level state if any

    def boom() -> None:
        raise RuntimeError("interview module is broken")

    # Pre-import the interview module so we can monkey-patch it.
    import voiceflow.interview as iv
    monkeypatch.setattr(iv, "run_interview", boom, raising=True)

    # Also stub out messagebox.showerror so the test doesn't pop a dialog
    # on a developer machine. We assert it was called below.
    showerror_calls: list[tuple] = []
    if ob.HAS_TKINTER:
        monkeypatch.setattr(
            ob.messagebox,
            "showerror",
            lambda *args, **kwargs: showerror_calls.append((args, kwargs)),
        )

    ob._launch_interview()  # module-level helper, see implementation

    captured = capsys.readouterr()
    assert "interview module is broken" in captured.err, (
        f"Expected the underlying error message in stderr; got:\n{captured.err!r}"
    )

    if ob.HAS_TKINTER:
        assert showerror_calls, "messagebox.showerror was not invoked"
        # Verify the error message was passed to the dialog.
        first_call_args = showerror_calls[0][0]
        assert any(
            "interview module is broken" in str(arg) for arg in first_call_args
        ), f"showerror args did not contain the underlying error: {first_call_args}"


def test_silent_pass_pattern_is_gone() -> None:
    """Static check: the literal ``except Exception: \\n  pass`` block in
    launch_interview_then_close must not survive."""
    from pathlib import Path

    src = (Path(__file__).resolve().parent.parent / "voiceflow" / "onboarding.py").read_text()
    # Find the launch_interview_then_close method body.
    marker = "def launch_interview_then_close"
    idx = src.find(marker)
    assert idx >= 0, "launch_interview_then_close method not found"
    # Read forward to the next def at the same indentation level.
    body = src[idx:src.find("\n    def ", idx + len(marker))]
    assert "except Exception:\n            pass" not in body, (
        "launch_interview_then_close still uses `except Exception: pass`. "
        "Surface the error instead (stderr + messagebox)."
    )


class _Value:
    def __init__(self, value: str) -> None:
        self.value = value

    def get(self) -> str:
        return self.value


def test_finish_setup_applies_legacy_streaming_migration(monkeypatch, tmp_path: Path) -> None:
    """Onboarding must not stamp schema v1 while retaining v0.3.2 streaming."""
    import voiceflow.onboarding as ob

    config_dir = tmp_path / ".openvoiceflow"
    config_dir.mkdir()
    config_path = config_dir / "config.json"
    config_path.write_text(json.dumps({"streaming": True, "style": "formal"}))
    monkeypatch.setattr(ob, "CONFIG_DIR", config_dir)
    monkeypatch.setattr(ob, "CONFIG_PATH", config_path)

    wizard = object.__new__(ob.OnboardingWizard)
    wizard.config = {}
    wizard.selected_backend = _Value("none")
    wizard.selected_hotkey = _Value("right_cmd")
    wizard.api_key = _Value("")
    wizard._prefill_key = ""
    wizard._prefill_backend = ""
    wizard.show_success = lambda: None

    wizard.save_and_finish()

    saved = json.loads(config_path.read_text())
    assert saved["streaming"] is False
    assert saved["_config_version"] == 1
    assert saved["style"] == "formal"
