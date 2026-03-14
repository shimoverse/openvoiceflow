"""Style/tone presets for LLM cleanup.

Each preset appends a style instruction to the base LLM prompt,
adjusting the tone and formatting of the output text.
"""
from .config import VALID_STYLES

# Style suffix added to the base prompt for each mode.
STYLE_PROMPTS: dict[str, str] = {
    "default": "",
    "casual": (
        "\nUse a casual, friendly tone. Contractions are fine. "
        "Keep it conversational and natural-sounding."
    ),
    "formal": (
        "\nUse formal, professional language. Avoid contractions. "
        "Write as you would in a business document or report."
    ),
    "code": (
        "\nPreserve all technical terms, function names, variable names, "
        "class names, and code references exactly as spoken. "
        "Format as a developer would write in a code comment, docstring, "
        "commit message, or README."
    ),
    "email": (
        "\nFormat as professional email text. If the speaker included a "
        "greeting or sign-off, preserve and format it appropriately. "
        "Use clear paragraph breaks where natural."
    ),
}

STYLE_LABELS: dict[str, str] = {
    "default": "Default",
    "casual": "Casual 😊",
    "formal": "Formal 👔",
    "code": "Code 💻",
    "email": "Email ✉️",
}


def get_style_prompt(style: str) -> str:
    """Return the style suffix for a given style name.

    Args:
        style: One of VALID_STYLES. Falls back to empty string if unknown.

    Returns:
        Style-specific prompt suffix to append to the base cleanup prompt.
    """
    return STYLE_PROMPTS.get(style, "")


def get_style_label(style: str) -> str:
    """Return a human-readable label for a style."""
    return STYLE_LABELS.get(style, style.capitalize())


def list_styles() -> list[dict[str, str]]:
    """Return all styles as a list of dicts with 'id' and 'label' keys."""
    return [
        {"id": s, "label": get_style_label(s)}
        for s in VALID_STYLES
    ]
