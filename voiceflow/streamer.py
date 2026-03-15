"""Real-time streaming transcription using whisper-stream subprocess.

Manages a whisper-stream child process, parses its stdout for partial
transcript lines, and delivers them via a callback for live overlay updates.

Usage:
    streamer = StreamingTranscriber(model_path, language="en")
    streamer.start(callback=on_partial_text)
    # ... user speaks ...
    full_text = streamer.stop()
"""

import os
import re
import signal
import subprocess
import threading
from typing import Callable, Optional

WHISPER_STREAM_BIN = "/opt/homebrew/bin/whisper-stream"

# Regex to strip ANSI escape codes from whisper-stream output
_ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;]*[mABCDEFGHJKSTfhilmnprsu]")

# whisper-stream often prefixes lines with a timestamp like [00:00:00.000 --> 00:00:03.000]
_TIMESTAMP_PREFIX = re.compile(r"^\s*\[\d{2}:\d{2}:\d{2}\.\d{3}\s*-->\s*\d{2}:\d{2}:\d{2}\.\d{3}\]\s*")

# Lines that are noise / metadata from whisper-stream (not transcript)
_NOISE_PATTERNS = [
    re.compile(r"^\s*$"),                          # blank lines
    re.compile(r"^whisper_", re.IGNORECASE),       # init messages
    re.compile(r"^\s*\[BLANK_AUDIO\]\s*$"),        # silence marker
    re.compile(r"^\s*\(speaking\)\s*$"),           # disfluency markers
    re.compile(r"^\s*\[.*\]\s*$"),                 # any remaining bracket-only lines
    re.compile(r"^init:"),                         # init lines
    re.compile(r"^ggml_"),                         # ggml backend messages
    re.compile(r"^system_info:"),                  # system info lines
    re.compile(r"^sampling:"),                     # sampling info
    re.compile(r"^log_mel_spectrogram"),           # processing info
    re.compile(r"^whisper_full"),                  # internal whisper calls
]


def find_whisper_stream() -> Optional[str]:
    """Return path to whisper-stream binary, or None if not found."""
    if os.path.isfile(WHISPER_STREAM_BIN) and os.access(WHISPER_STREAM_BIN, os.X_OK):
        return WHISPER_STREAM_BIN
    # Fallback: check PATH
    import shutil
    found = shutil.which("whisper-stream")
    return found


def _clean_line(line: str) -> Optional[str]:
    """Strip ANSI codes, timestamps, and noise from a whisper-stream output line.

    Returns cleaned text or None if the line is noise and should be discarded.
    """
    # Remove ANSI escape sequences
    line = _ANSI_ESCAPE.sub("", line).strip()
    if not line:
        return None

    # Remove timestamp prefix if present
    line = _TIMESTAMP_PREFIX.sub("", line).strip()
    if not line:
        return None

    # Discard noise lines
    for pattern in _NOISE_PATTERNS:
        if pattern.match(line):
            return None

    return line


class StreamingTranscriber:
    """Manages a whisper-stream subprocess for real-time transcription.

    Thread-safe: start() and stop() may be called from any thread.
    The callback is invoked from a background reader thread.
    """

    def __init__(self, model_path: str, language: str = "en",
                 step_ms: int = 3000):
        self._model_path = model_path
        self._language = language
        self._step_ms = step_ms

        self._proc: Optional[subprocess.Popen] = None
        self._reader_thread: Optional[threading.Thread] = None
        self._callback: Optional[Callable[[str], None]] = None

        # Accumulated transcript lines (deduplicated)
        self._lines: list[str] = []
        self._lock = threading.Lock()
        self._running = False

        # Last text sent to callback — avoid redundant calls
        self._last_sent: str = ""

    def start(self, callback: Optional[Callable[[str], None]] = None) -> bool:
        """Launch whisper-stream subprocess and begin reading output.

        Args:
            callback: Called with the latest partial transcript string each
                      time new text is parsed (at most 2-3 Hz naturally).

        Returns:
            True if the process started successfully, False otherwise.
        """
        binary = find_whisper_stream()
        if not binary:
            print(f"⚠️  whisper-stream not found at {WHISPER_STREAM_BIN}. "
                  "Falling back to batch mode.")
            return False

        self._callback = callback
        self._lines = []
        self._last_sent = ""
        self._running = True

        cmd = [
            binary,
            "--model", self._model_path,
            "--step", str(self._step_ms),
            "--length", "10000",
            "--keep", "200",
            "--language", self._language,
            "--vad-thold", "0.60",
            "--capture", "-1",
        ]

        try:
            self._proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,  # suppress init chatter
                text=True,
                bufsize=1,  # line-buffered
            )
        except OSError as exc:
            print(f"⚠️  Failed to launch whisper-stream: {exc}")
            self._running = False
            return False

        self._reader_thread = threading.Thread(
            target=self._read_output,
            daemon=True,
            name="whisper-stream-reader",
        )
        self._reader_thread.start()
        return True

    def stop(self) -> str:
        """Stop the whisper-stream process and return accumulated transcript.

        Sends SIGTERM, waits up to 2 s for clean exit, then SIGKILL.

        Returns:
            Full raw transcript text collected during the session.
        """
        self._running = False

        if self._proc and self._proc.poll() is None:
            try:
                self._proc.send_signal(signal.SIGTERM)
                try:
                    self._proc.wait(timeout=2.0)
                except subprocess.TimeoutExpired:
                    self._proc.kill()
                    self._proc.wait()
            except ProcessLookupError:
                pass  # already exited

        if self._reader_thread and self._reader_thread.is_alive():
            self._reader_thread.join(timeout=3.0)

        self._proc = None
        self._reader_thread = None

        with self._lock:
            full_text = " ".join(self._lines).strip()
        return full_text

    def _read_output(self):
        """Background thread: read whisper-stream stdout line by line."""
        try:
            for raw_line in self._proc.stdout:
                if not self._running:
                    break
                cleaned = _clean_line(raw_line)
                if not cleaned:
                    continue

                with self._lock:
                    # Append only if it's a new/different last line
                    # whisper-stream may re-emit a refined version of the last
                    # chunk; replace the last entry if it overlaps significantly
                    if self._lines and _is_refinement(self._lines[-1], cleaned):
                        self._lines[-1] = cleaned
                    else:
                        self._lines.append(cleaned)
                    snapshot = " ".join(self._lines).strip()

                if self._callback and snapshot != self._last_sent:
                    self._last_sent = snapshot
                    try:
                        self._callback(snapshot)
                    except Exception:
                        pass  # never crash the reader thread

        except (OSError, ValueError):
            pass  # pipe closed or process gone
        finally:
            # Drain stdout cleanly
            try:
                if self._proc and self._proc.stdout:
                    self._proc.stdout.close()
            except Exception:
                pass


def _is_refinement(prev: str, current: str) -> bool:
    """Heuristic: is *current* a whisper refinement of the last emitted line?

    whisper-stream sometimes re-emits a corrected version of the chunk it
    just printed.  We consider *current* a refinement of *prev* if they share
    at least 60 % of their words (Jaccard overlap).
    """
    if not prev or not current:
        return False
    prev_words = set(prev.lower().split())
    cur_words = set(current.lower().split())
    if not prev_words or not cur_words:
        return False
    intersection = len(prev_words & cur_words)
    union = len(prev_words | cur_words)
    return (intersection / union) >= 0.60
