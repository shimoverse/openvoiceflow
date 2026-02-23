"""Audio recording using sounddevice."""
import wave
import numpy as np
import sounddevice as sd


class AudioRecorder:
    """Records audio from the default microphone."""

    def __init__(self, sample_rate=16000, channels=1):
        self.sample_rate = sample_rate
        self.channels = channels
        self.frames = []
        self.is_recording = False
        self._stream = None

    def start(self):
        """Start recording audio."""
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
        """Stop recording audio."""
        self.is_recording = False
        if self._stream:
            self._stream.stop()
            self._stream.close()
            self._stream = None

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
