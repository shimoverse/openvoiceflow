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
import sys

import pytest


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
