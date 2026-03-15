"""Voice command replacement for OpenVoiceFlow.

Translates spoken punctuation/formatting phrases (e.g. "new line", "period")
into their text equivalents BEFORE the LLM cleanup pass, so the LLM sees
already-formatted text and the replacement adds zero latency.
"""
import re

# Default spoken-phrase → replacement mapping.
# Keys are the exact spoken words whisper.cpp will transcribe.
DEFAULT_COMMANDS: dict[str, str] = {
    # Line / paragraph breaks
    "new paragraph": "\n\n",
    "new line": "\n",
    "newline": "\n",
    # Punctuation
    "exclamation mark": "!",
    "exclamation point": "!",
    "question mark": "?",
    "open parenthesis": "(",
    "close parenthesis": ")",
    "open paren": "(",
    "close paren": ")",
    "open quotes": '"',
    "close quotes": '"',
    "open quote": '"',
    "close quote": '"',
    "dot dot dot": "...",
    "ellipsis": "...",
    "semicolon": ";",
    "full stop": ".",
    "period": ".",
    "hyphen": "-",
    "colon": ":",
    "comma": ",",
    "dash": "-",
    # Whitespace
    "tab": "\t",
}


def load_commands(config: dict) -> dict[str, str]:
    """Return merged commands dict: defaults overridden by user custom_commands.

    Merges ``config["custom_commands"]`` (a {phrase: replacement} dict) on top
    of :data:`DEFAULT_COMMANDS`.  Voice commands are skipped entirely when
    ``config["voice_commands"]`` is falsy.
    """
    if not config.get("voice_commands", True):
        return {}

    commands = dict(DEFAULT_COMMANDS)
    custom = config.get("custom_commands", {})
    if isinstance(custom, dict):
        commands.update(custom)
    return commands


def apply_commands(text: str, commands: dict[str, str]) -> str:
    """Replace spoken command phrases in *text* with their target strings.

    Processing order: longest phrase first, so "new paragraph" is matched
    before either "new" or "paragraph" could interfere.

    Matching is case-insensitive and uses word boundaries so "comma" does not
    accidentally match inside "uncomma ndable" or similar edge cases.
    """
    if not commands or not text:
        return text

    # Sort descending by phrase length to prevent partial matches
    sorted_phrases = sorted(commands.keys(), key=len, reverse=True)

    for phrase in sorted_phrases:
        replacement = commands[phrase]
        # re.escape handles any special chars a user might put in a custom phrase
        pattern = r"(?i)\b" + re.escape(phrase) + r"\b"
        text = re.sub(pattern, replacement, text, flags=re.IGNORECASE)

    return text
