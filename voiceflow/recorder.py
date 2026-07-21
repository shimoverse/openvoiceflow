"""Audio recording using sounddevice."""

from __future__ import annotations

import wave

import numpy as np


def _import_sounddevice():
    """Import sounddevice at call time, not module-import time.

    sounddevice loads the PortAudio C library the moment it is imported and
    raises OSError when it is missing (typical on non-macOS machines). A
    module-level import would make ``import voiceflow.recorder`` — and with
    it the whole app — crash before any friendly error handling can run.
    """
    import sounddevice as sd
    return sd


class AudioRecorder:
    """Records audio from the default microphone."""

    def __init__(self, sample_rate=16000, channels=1):
        self.sample_rate = sample_rate
        self.channels = channels
        self.frames = []
        self.is_recording = False
        self._stream = None

    def start(self):
        """Start recording audio.

        Raises ImportError/OSError when no audio backend is available;
        callers (``OpenVoiceFlow.start_recording``) surface that as a
        user-visible "microphone unavailable" error.
        """
        sd = _import_sounddevice()
        self.frames = []
        self.is_recording = True
        self._stream = sd.InputStream(
            samplerate=self.sample_rate,
            channels=self.channels,
            dtype="int16",
            callback=self._callback,
            blocksize=1024,
        )
        self._stream.start()

    def _callback(self, indata, frames, time_info, status):
        if self.is_recording:
            self.frames.append(indata.copy())

    def stop(self):
        """Stop recording audio.

        Always releases the PortAudio stream, even if ``stop()``/``close()``
        raise — which they do when the input device is unplugged mid-recording.
        A leaked stream keeps the microphone busy and the next ``start()``
        would overwrite ``self._stream`` without closing the old one.
        """
        self.is_recording = False
        stream, self._stream = self._stream, None
        if stream is None:
            return
        try:
            stream.stop()
        except Exception:
            pass
        try:
            stream.close()
        except Exception:
            pass

    def save_wav(self, filepath: str) -> bool:
        """Save recorded audio to a WAV file."""
        if not self.frames:
            return False
        audio_data = np.concatenate(self.frames, axis=0)
        with wave.open(filepath, "wb") as wf:
            wf.setnchannels(self.channels)
            wf.setsampwidth(2)  # 16-bit
            wf.setframerate(self.sample_rate)
            wf.writeframes(audio_data.tobytes())
        return True

    @property
    def duration(self) -> float:
        """Duration of recorded audio in seconds."""
        if not self.frames:
            return 0.0
        total = sum(f.shape[0] for f in self.frames)
        return total / self.sample_rate
