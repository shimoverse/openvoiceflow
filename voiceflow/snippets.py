"""Voice snippets — say a trigger phrase and it expands to a text block."""
import json
import os
from .config import CONFIG_DIR

SNIPPETS_PATH = os.path.join(CONFIG_DIR, "snippets.json")


def load_snippets() -> dict[str, str]:
    """Load snippets as {trigger_phrase: expansion_text}."""
    if not os.path.exists(SNIPPETS_PATH):
        return {}
    try:
        with open(SNIPPETS_PATH) as f:
            return json.load(f)
    except (json.JSONDecodeError, ValueError):
        return {}


def save_snippets(snippets: dict[str, str]):
    """Save snippets to disk."""
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(SNIPPETS_PATH, "w") as f:
        json.dump(snippets, f, indent=2)


def add_snippet(trigger: str, expansion: str):
    """Add or update a snippet.

    Args:
        trigger: The voice trigger phrase (e.g., "insert signature").
        expansion: The text to expand to.
    """
    snippets = load_snippets()
    snippets[trigger.lower().strip()] = expansion
    save_snippets(snippets)


def remove_snippet(trigger: str) -> bool:
    """Remove a snippet. Returns True if found."""
    snippets = load_snippets()
    key = trigger.lower().strip()
    if key not in snippets:
        return False
    del snippets[key]
    save_snippets(snippets)
    return True


def list_snippets() -> dict[str, str]:
    """Return all snippets."""
    return load_snippets()


def match_snippet(text: str) -> str | None:
    """Check if the transcribed text matches a snippet trigger.

    Matches if the cleaned/lowered text equals or starts with a trigger phrase.
    Returns the expansion text or None.
    """
    snippets = load_snippets()
    if not snippets:
        return None

    normalized = text.lower().strip()
    # Exact match first
    if normalized in snippets:
        return snippets[normalized]

    # Check if text starts with a trigger (e.g., "insert signature please")
    for trigger, expansion in sorted(snippets.items(), key=lambda x: -len(x[0])):
        if normalized.startswith(trigger):
            return expansion

    return None


def get_snippets_prompt_fragment() -> str:
    """Build a prompt fragment telling the LLM about available snippets.

    Returns empty string if no snippets exist.
    """
    snippets = load_snippets()
    if not snippets:
        return ""

    lines = []
    for trigger in snippets:
        lines.append(f'  - "{trigger}"')

    return (
        "\n\nVoice snippets — if the user says EXACTLY one of these trigger phrases "
        "(and nothing else meaningful), output the trigger phrase unchanged so the "
        "system can expand it:\n"
        + "\n".join(lines)
    )
