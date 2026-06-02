"""D10 regression test: voice-command counts in docs match the code.

Background: v0.2 docs claimed "24 voice commands" (landing page + README
feature matrix) but the README's worked-example table only listed about
14, leaving readers unsure of the real count. This test pins single
source of truth: the README's "N voice commands" claim must equal
``len(DEFAULT_COMMANDS)``, and every trigger in the code must appear
somewhere in the README.
"""
from __future__ import annotations

import re
from pathlib import Path

from voiceflow.commands import DEFAULT_COMMANDS

README = Path(__file__).resolve().parent.parent / "README.md"


def test_readme_count_matches_code() -> None:
    """README's '✅ N commands' claim equals len(DEFAULT_COMMANDS)."""
    text = README.read_text()
    matches = re.findall(r"✅\s*(\d+)\s*commands?", text)
    assert matches, "README has no `✅ N commands` claim — feature matrix?"
    counts = {int(m) for m in matches}
    expected = len(DEFAULT_COMMANDS)
    assert counts == {expected}, (
        f"README claims voice-command count(s) {counts}, "
        f"but DEFAULT_COMMANDS has {expected}."
    )


def test_every_default_trigger_appears_in_readme() -> None:
    """Every default voice-command trigger is documented somewhere in README."""
    text = README.read_text()
    missing = [
        trigger for trigger in DEFAULT_COMMANDS
        if trigger not in text
    ]
    assert not missing, (
        f"README is missing these default voice-command triggers: {missing}\n"
        "Either list them in the table or add a note pointing to "
        "`openvoiceflow --list-commands`."
    )
