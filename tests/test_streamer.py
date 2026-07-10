"""Regression tests for the whisper-stream subprocess wrapper."""

from __future__ import annotations

import threading

from voiceflow.streamer import StreamingTranscriber


class _TrailingStdout:
    """Yield one final non-newline transcript only after process shutdown."""

    def __init__(self) -> None:
        self.released = threading.Event()
        self.emitted = False

    def __iter__(self):
        return self

    def __next__(self) -> str:
        if not self.released.wait(timeout=1.0):
            raise StopIteration
        if self.emitted:
            raise StopIteration
        self.emitted = True
        return " final words"

    def close(self) -> None:
        pass


class _ProcessWithTrailingStdout:
    def __init__(self) -> None:
        self.stdout = _TrailingStdout()
        self.stopped = False

    def poll(self):
        return 0 if self.stopped else None

    def send_signal(self, _signal) -> None:
        self.stopped = True
        self.stdout.released.set()

    def wait(self, timeout=None) -> int:
        return 0

    def kill(self) -> None:
        self.stopped = True
        self.stdout.released.set()


def test_stop_drains_unterminated_final_transcript() -> None:
    """Text flushed without a newline must survive a normal stop."""
    streamer = StreamingTranscriber("model.bin")
    streamer._proc = _ProcessWithTrailingStdout()
    streamer._running = True
    streamer._reader_thread = threading.Thread(target=streamer._read_output)
    streamer._reader_thread.start()

    assert streamer.stop() == "final words"
