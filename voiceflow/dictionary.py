"""Personal dictionary for custom words and corrections."""
import json
import os
from .config import CONFIG_DIR

DICTIONARY_PATH = os.path.join(CONFIG_DIR, "dictionary.json")


def load_dictionary() -> list[dict]:
    """Load personal dictionary entries.

    Each entry is {"word": "correct_spelling", "aliases": ["misspelling1", ...]}.
    Simple entries can just be {"word": "OpenVoiceFlow"} with no aliases.
    """
    if not os.path.exists(DICTIONARY_PATH):
        return []
    try:
        with open(DICTIONARY_PATH) as f:
            return json.load(f)
    except (json.JSONDecodeError, ValueError):
        return []


def save_dictionary(entries: list[dict]):
    """Save personal dictionary to disk."""
    os.makedirs(CONFIG_DIR, exist_ok=True)
    with open(DICTIONARY_PATH, "w") as f:
        json.dump(entries, f, indent=2)


def add_word(word: str, aliases: list[str] | None = None):
    """Add a word to the personal dictionary.

    Args:
        word: The correct spelling of the word.
        aliases: Optional list of common misspellings/variations.
    """
    entries = load_dictionary()
    # Update existing entry if word already exists
    for entry in entries:
        if entry["word"].lower() == word.lower():
            if aliases:
                existing = set(entry.get("aliases", []))
                existing.update(aliases)
                entry["aliases"] = sorted(existing)
            save_dictionary(entries)
            return
    # Add new entry
    entry = {"word": word}
    if aliases:
        entry["aliases"] = aliases
    entries.append(entry)
    save_dictionary(entries)


def remove_word(word: str) -> bool:
    """Remove a word from the personal dictionary. Returns True if found."""
    entries = load_dictionary()
    new_entries = [e for e in entries if e["word"].lower() != word.lower()]
    if len(new_entries) == len(entries):
        return False
    save_dictionary(new_entries)
    return True


def list_words() -> list[str]:
    """Return all dictionary words as strings."""
    entries = load_dictionary()
    return [e["word"] for e in entries]


def get_dictionary_prompt_fragment() -> str:
    """Build a prompt fragment for LLM cleanup with dictionary words.

    Returns empty string if no dictionary entries exist.
    """
    entries = load_dictionary()
    if not entries:
        return ""

    lines = []
    for entry in entries:
        word = entry["word"]
        aliases = entry.get("aliases", [])
        if aliases:
            lines.append(f'  - "{word}" (may be misheard as: {", ".join(aliases)})')
        else:
            lines.append(f'  - "{word}"')

    return (
        "\n\nIMPORTANT — Personal dictionary. Always use these exact spellings:\n"
        + "\n".join(lines)
    )
