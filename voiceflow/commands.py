"""Voice command replacement for OpenVoiceFlow.

Translates spoken punctuation/formatting phrases (e.g. "new line", "period")
into their text equivalents BEFORE the LLM cleanup pass, so the LLM sees
already-formatted text and the replacement adds zero latency.
"""

from __future__ import annotations

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

    All phrases are matched in a single pass with one combined pattern:
    longest phrase first, so "new paragraph" is matched before either "new"
    or "paragraph" could interfere, and text produced by one replacement is
    never re-scanned by another (a custom expansion containing the word
    "period" stays intact).

    Matching is case-insensitive and uses word boundaries so "comma" does not
    accidentally match inside "uncomma ndable" or similar edge cases.

    Replacements are inserted literally (via a callback), so custom commands
    containing backslashes or "\\1"-style sequences cannot break the regex.
    """
    if not commands or not text:
        return text

    lookup = {phrase.lower(): replacement for phrase, replacement in commands.items()}
    # Sort descending by phrase length to prevent partial matches; regex
    # alternation tries branches left to right.
    sorted_phrases = sorted(lookup.keys(), key=len, reverse=True)
    alternation = "|".join(re.escape(p) for p in sorted_phrases)
    pattern = re.compile(r"( *)\b(" + alternation + r")\b", re.IGNORECASE)

    def _replace(match: re.Match) -> str:
        spaces, phrase = match.group(1), match.group(2)
        replacement = lookup[phrase.lower()]
        # For punctuation replacements, consume the preceding space so
        # "hello comma world" becomes "hello, world" rather than "hello , world".
        if replacement and not replacement[0].isalnum() and not replacement[0].isspace():
            return replacement
        return spaces + replacement

    return pattern.sub(_replace, text)
