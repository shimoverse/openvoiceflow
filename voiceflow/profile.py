"""OpenVoiceFlow — User profile management for personalized LLM context.

The profile captures who the user is — their name, occupation, the people
they mention, industry jargon, and communication style. This context is
injected into every LLM cleanup call so the very first dictation already
knows how to spell your kid's name.

Profile is stored at ~/.openvoiceflow/profile.json and never leaves the
user's machine.
"""
import json
import os
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
            return json.load(f)
    except (json.JSONDecodeError, ValueError, OSError):
        return None


def save_profile(profile: dict) -> None:
    """Persist profile to ~/.openvoiceflow/profile.json.

    Args:
        profile: Profile dict to save.
    """
    PROFILE_DIR.mkdir(parents=True, exist_ok=True)
    with open(PROFILE_PATH, "w") as f:
        json.dump(profile, f, indent=2)


def has_profile() -> bool:
    """Return True if a profile file exists on disk."""
    return PROFILE_PATH.exists()


def clear_profile() -> None:
    """Delete profile.json if it exists."""
    if PROFILE_PATH.exists():
        PROFILE_PATH.unlink()


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
    name = profile.get("name", "").strip()
    occupation = profile.get("occupation", "").strip()
    industry = profile.get("industry", "").strip()

    if name:
        line = f"The user's name is {name}."
        if occupation:
            if industry:
                line += f" They work as a {occupation} ({industry} industry)."
            else:
                line += f" They work as a {occupation}."
        lines.append(line)

    # Names they mention
    work_names = [n.strip() for n in profile.get("work_names", []) if n.strip()]
    home_names = [n.strip() for n in profile.get("home_names", []) if n.strip()]

    if work_names or home_names:
        lines.append("Names they frequently mention:")
        if work_names:
            lines.append(f"  - Work: {', '.join(work_names)}")
        if home_names:
            lines.append(f"  - Home: {', '.join(home_names)}")

    # Technical / domain-specific terms
    technical_terms = [t.strip() for t in profile.get("technical_terms", []) if t.strip()]
    if technical_terms:
        lines.append(f"Technical terms to spell correctly: {', '.join(technical_terms)}")

    # Communication style
    style = profile.get("communication_style", "").strip()
    if style:
        lines.append(f"Communication style preference: {style}")

    # Free-form context
    additional = profile.get("additional_context", "").strip()
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

    for name in profile.get("work_names", []):
        name = name.strip()
        if name:
            words.append(name)

    for name in profile.get("home_names", []):
        name = name.strip()
        if name and name not in words:
            words.append(name)

    for term in profile.get("technical_terms", []):
        term = term.strip()
        if term and term not in words:
            words.append(term)

    # Also add the user's own name (may be multi-word; add each part)
    own_name = profile.get("name", "").strip()
    if own_name:
        for part in own_name.split():
            part = part.strip()
            if part and part not in words:
                words.append(part)

    return words
