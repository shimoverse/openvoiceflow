"""Auto-learn corrections from user edits after dictation paste.

After text is pasted into the active text field, a background daemon thread
watches for word-level substitutions over the next 30 seconds.  When the user
fixes a word (e.g. "mir" → "Meer"), the corrected form is silently added to
the personal dictionary with the original as an alias.

Design principles:
- BEST EFFORT only.  Any failure → silently stop.  Never crash, never block.
- Only learn from SUBSTITUTIONS (word replaced by a similar word).
  Insertions and deletions are content edits, not corrections.
- Similarity gate prevents learning from completely unrelated changes.
- Thread is daemon=True so it dies with the app.
"""
from __future__ import annotations

import difflib
import threading
from typing import TYPE_CHECKING

# ---------------------------------------------------------------------------
# Accessibility API — optional; gracefully absent on non-macOS or missing PyObjC
# ---------------------------------------------------------------------------

try:
    from ApplicationServices import (  # type: ignore[import]
        AXUIElementCreateSystemWide,
        AXUIElementCopyAttributeValue,
        kAXFocusedUIElementAttribute,
        kAXValueAttribute,
    )
    _HAS_AX = True
except ImportError:
    _HAS_AX = False

# ---------------------------------------------------------------------------
# Similarity threshold for word-level corrections
# ---------------------------------------------------------------------------

_SIMILARITY_THRESHOLD = 0.4  # SequenceMatcher ratio must exceed this value

# Watch schedule: seconds after paste_text() at which to sample the text field
_WATCH_INTERVALS = (5, 10, 15, 20, 30)


class CorrectionWatcher:
    """Watches for user corrections after dictation paste via Accessibility API.

    After text is pasted, reads the text field content at intervals:
    5 s, 10 s, 15 s, 20 s, 30 s (5 samples over 30 seconds).
    If a word changes to a similar word, adds the correction to the personal
    dictionary.  Stops early if the user switches apps.
    """

    def __init__(self) -> None:
        self._stop_event = threading.Event()
        self._pasted_text: str = ""
        self._initial_app: str = ""
        self._thread: threading.Thread | None = None

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def start_watching(self, pasted_text: str) -> None:
        """Start the background watch thread.

        Called immediately after paste_text() succeeds.

        Args:
            pasted_text: The text that was just pasted into the target field.
        """
        self._pasted_text = pasted_text
        self._stop_event.clear()

        # Snapshot current frontmost app so we can detect app-switch
        try:
            from .context import get_frontmost_app
            self._initial_app = get_frontmost_app()
        except Exception:
            self._initial_app = ""

        self._thread = threading.Thread(
            target=self._watch_loop,
            daemon=True,
            name="ovf-correction-watcher",
        )
        self._thread.start()

    def stop(self) -> None:
        """Signal the watch loop to terminate early."""
        self._stop_event.set()

    # ------------------------------------------------------------------
    # Internal watch loop
    # ------------------------------------------------------------------

    def _watch_loop(self) -> None:
        """Background thread body: sample the text field at fixed intervals."""
        try:
            self._run_watch_loop()
        except Exception:
            pass  # BEST EFFORT — never propagate

    def _run_watch_loop(self) -> None:
        """Core sampling logic, extracted for clarity."""
        import time

        prev_interval = 0
        for interval in _WATCH_INTERVALS:
            # Sleep until the next checkpoint (relative to start of this loop)
            sleep_for = interval - prev_interval
            if self._stop_event.wait(timeout=sleep_for):
                return  # stop() was called
            prev_interval = interval

            # Check if the user has switched apps; if so, stop
            try:
                from .context import get_frontmost_app
                current_app = get_frontmost_app()
                if self._initial_app and current_app and current_app != self._initial_app:
                    return
            except Exception:
                pass  # Don't stop just because context detection failed

            # Read the focused text field
            current_text = self._read_focused_text()
            if current_text is None:
                return  # Can't read — stop silently

            if not current_text:
                continue  # Empty field; keep watching

            # Diff against the pasted text
            corrections = self._extract_corrections(self._pasted_text, current_text)
            if not corrections:
                continue

            # Persist each learned correction
            for original_word, corrected_word in corrections:
                self._learn(original_word, corrected_word)

    # ------------------------------------------------------------------
    # Accessibility API helpers
    # ------------------------------------------------------------------

    def _read_focused_text(self) -> str | None:
        """Read the current value of the focused text field via macOS AX API.

        Returns the text string, or None on any error.
        Wraps EVERYTHING in try/except — the AX API can fail for many reasons.
        """
        if not _HAS_AX:
            return None
        try:
            system = AXUIElementCreateSystemWide()
            err, focused = AXUIElementCopyAttributeValue(
                system, kAXFocusedUIElementAttribute, None
            )
            if err or not focused:
                return None
            err, value = AXUIElementCopyAttributeValue(
                focused, kAXValueAttribute, None
            )
            if err or value is None:
                return None
            return str(value)
        except Exception:
            return None

    # ------------------------------------------------------------------
    # Diff helpers
    # ------------------------------------------------------------------

    def _extract_corrections(
        self, original_text: str, current_text: str
    ) -> list[tuple[str, str]]:
        """Find word-level substitutions between *original_text* and *current_text*.

        Only considers substitutions (not insertions or deletions) where both
        sides are single words and the words are sufficiently similar.

        Args:
            original_text: The text that was pasted.
            current_text:  The text currently in the field.

        Returns:
            A list of (original_word, corrected_word) tuples.
        """
        original_words = original_text.split()
        current_words = current_text.split()

        corrections: list[tuple[str, str]] = []

        matcher = difflib.SequenceMatcher(None, original_words, current_words, autojunk=False)
        for tag, i1, i2, j1, j2 in matcher.get_opcodes():
            if tag != "replace":
                continue  # Only care about substitutions, not inserts/deletes

            orig_chunk = original_words[i1:i2]
            curr_chunk = current_words[j1:j2]

            # Must be a single-word-for-single-word replacement
            if len(orig_chunk) != 1 or len(curr_chunk) != 1:
                continue

            orig_word = orig_chunk[0]
            corr_word = curr_chunk[0]

            # Skip if identical (case-insensitive)
            if orig_word.lower() == corr_word.lower():
                continue

            # Apply similarity filter to avoid learning unrelated substitutions
            ratio = difflib.SequenceMatcher(
                None, orig_word.lower(), corr_word.lower()
            ).ratio()
            if ratio <= _SIMILARITY_THRESHOLD:
                continue

            corrections.append((orig_word, corr_word))

        return corrections

    # ------------------------------------------------------------------
    # Dictionary persistence
    # ------------------------------------------------------------------

    def _learn(self, original_word: str, corrected_word: str) -> None:
        """Add *corrected_word* to the personal dictionary with *original_word* as alias.

        Silently skips if the corrected word is already in the dictionary.
        """
        try:
            from .dictionary import load_dictionary, add_word

            # Don't re-learn words already present
            existing = [e["word"].lower() for e in load_dictionary()]
            if corrected_word.lower() in existing:
                return

            add_word(corrected_word, aliases=[original_word])
            print(f"📚 Learned: {original_word} → {corrected_word}")
        except Exception:
            pass  # BEST EFFORT
