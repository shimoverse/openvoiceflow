"""OpenVoiceFlow — User profile management for personalized LLM context.

The profile captures who the user is — their name, occupation, the people
they mention, industry jargon, and communication style. This context is
injected into every LLM cleanup call so the very first dictation already
knows how to spell your kid's name.

Profile is stored at ~/.openvoiceflow/profile.json and never leaves the
user's machine.
"""

from __future__ import annotations

import json
from pathlib import Path

PROFILE_DIR = Path.home() / ".openvoiceflow"
PROFILE_PATH = PROFILE_DIR / "profile.json"


def load_profile() -> dict | None:
    """Load profile from disk.

    Returns:
        Parsed profile dict, or None if profile.json does not exist.
    """
    if not PROFILE_PATH.exists():
        return None
    try:
        with open(PROFILE_PATH) as f:
            data = json.load(f)
    except (json.JSONDecodeError, ValueError, OSError):
        return None
    # A profile must be a JSON object; any other shape would crash the
    # prompt builder inside LLMBackend.__init__ — i.e. every dictation.
    if not isinstance(data, dict):
        return None
    return data


def save_profile(profile: dict) -> None:
    """Persist profile to ~/.openvoiceflow/profile.json.

    Args:
        profile: Profile dict to save.
    """
    from ._secure_io import secure_write_json
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    secure_write_json(PROFILE_PATH, profile)


def has_profile() -> bool:
    """Return True if a profile file exists on disk."""
    return PROFILE_PATH.exists()


def clear_profile() -> None:
    """Delete profile.json if it exists."""
    if PROFILE_PATH.exists():
        PROFILE_PATH.unlink()


def _get_str(profile: dict, key: str) -> str:
    """Read a string field defensively: null / wrong types become ''."""
    value = profile.get(key, "")
    return value.strip() if isinstance(value, str) else ""


def _get_str_list(profile: dict, key: str) -> list[str]:
    """Read a list-of-strings field defensively, dropping non-string items."""
    value = profile.get(key, [])
    if not isinstance(value, list):
        return []
    return [item.strip() for item in value if isinstance(item, str) and item.strip()]


def get_profile_prompt_fragment() -> str:
    """Build a rich LLM system prompt fragment from the stored profile.

    Returns an empty string when no profile exists so existing behavior
    is completely unchanged for users who skip the interview.

    Returns:
        A formatted string ready to be appended to the LLM system prompt.
    """
    profile = load_profile()
    if not profile:
        return ""

    lines = ["\n\nPERSONAL CONTEXT —"]

    # Name + occupation
    name = _get_str(profile, "name")
    occupation = _get_str(profile, "occupation")
    industry = _get_str(profile, "industry")

    intro_parts = []
    if name:
        intro_parts.append(f"The user's name is {name}.")
    if occupation:
        # Occupation stands on its own — a profile without a name still
        # benefits from the work context.
        if industry:
            intro_parts.append(f"They work as a {occupation} ({industry} industry).")
        else:
            intro_parts.append(f"They work as a {occupation}.")
    elif industry:
        intro_parts.append(f"They work in the {industry} industry.")
    if intro_parts:
        lines.append(" ".join(intro_parts))

    # Names they mention
    work_names = _get_str_list(profile, "work_names")
    home_names = _get_str_list(profile, "home_names")

    if work_names or home_names:
        lines.append("Names they frequently mention:")
        if work_names:
            lines.append(f"  - Work: {', '.join(work_names)}")
        if home_names:
            lines.append(f"  - Home: {', '.join(home_names)}")

    # Technical / domain-specific terms
    technical_terms = _get_str_list(profile, "technical_terms")
    if technical_terms:
        lines.append(f"Technical terms to spell correctly: {', '.join(technical_terms)}")

    # Communication style
    style = _get_str(profile, "communication_style")
    if style:
        lines.append(f"Communication style preference: {style}")

    # Free-form context
    additional = _get_str(profile, "additional_context")
    if additional:
        lines.append(f"Additional context: {additional}")

    lines.append(
        "Always use these exact name spellings. "
        "When in doubt about a word, consider the user's industry and role for context."
    )

    return "\n".join(lines)


def profile_to_dictionary(profile: dict) -> list[str]:
    """Extract all names and technical terms for auto-populating the dictionary.

    This gives BOTH dictionary-level spelling correction AND profile-level
    LLM context — the double coverage that makes the magic happen.

    Args:
        profile: Profile dict (as returned by load_profile()).

    Returns:
        Deduplicated list of words to add to the personal dictionary.
    """
    words: list[str] = []

    for name in _get_str_list(profile, "work_names"):
        if name not in words:
            words.append(name)

    for name in _get_str_list(profile, "home_names"):
        if name not in words:
            words.append(name)

    for term in _get_str_list(profile, "technical_terms"):
        if term not in words:
            words.append(term)

    # Also add the user's own name (may be multi-word; add each part)
    own_name = _get_str(profile, "name")
    if own_name:
        for part in own_name.split():
            part = part.strip()
            if part and part not in words:
                words.append(part)

    return words
