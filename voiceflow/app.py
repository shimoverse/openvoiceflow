"""OpenVoiceFlow main application controller."""
import os
import sys
import time
import tempfile
import threading
from .config import load_config, save_config, get_api_key
from .recorder import AudioRecorder
from .transcriber import find_whisper_cpp, get_model_path, download_model, transcribe
from .llm import cleanup_text
from .snippets import match_snippet
from .system import paste_text, play_sound, log_transcript
from .stats import record_dictation


class OpenVoiceFlow:
    """Main OpenVoiceFlow application."""

    def __init__(self, use_overlay=True):
        self.config = load_config()
        self.recorder = AudioRecorder(
            sample_rate=self.config["sample_rate"],
            channels=self.config["channels"],
        )
        self.is_recording = False
        self.processing = False
        # BUG-005 fix: use separate timestamps for press and release
        self._last_press_time = 0
        self._last_release_time = 0
        # Floating overlay for visual feedback
        self._overlay = None
        if use_overlay:
            try:
                from .overlay import get_overlay
                self._overlay = get_overlay()
            except Exception:
                pass  # Overlay is optional

    def validate_setup(self) -> bool:
        """Check that all dependencies are ready."""
        errors = []

        # whisper.cpp
        whisper_bin = self.config.get("whisper_cpp_path") or find_whisper_cpp()
        if not whisper_bin:
            errors.append("whisper.cpp not found. Install with: brew install whisper-cpp")
        else:
            print(f"✅ whisper.cpp found: {whisper_bin}")

        # Model
        model_path = get_model_path(self.config["whisper_model"])
        if os.path.exists(model_path):
            size_mb = os.path.getsize(model_path) / (1024 * 1024)
            print(f"✅ Model: {self.config['whisper_model']} ({size_mb:.0f} MB)")
        else:
            print(f"⚠️  Model not found. Will download on first use.")

        # LLM backend
        backend = self.config.get("llm_backend", "gemini")
        if backend == "none":
            print(f"✅ LLM cleanup: disabled (raw transcripts only)")
        else:
            from .llm import get_backend
            b = get_backend(self.config)
            if b:
                ok, msg = b.validate()
                if ok:
                    print(f"✅ LLM: {msg}")
                else:
                    errors.append(msg)
            else:
                errors.append(f"Unknown LLM backend: {backend}")

        # Audio
        try:
            import sounddevice
            print("✅ Audio input available")
        except ImportError:
            errors.append("sounddevice not installed. Run: pip install sounddevice")

        if errors:
            print("\n❌ Setup issues:")
            for e in errors:
                print(f"   • {e}")
            return False
        return True

    def _get_key_map(self):
        """Build hotkey map for available pynput keys."""
        from pynput.keyboard import Key
        definitions = {
            "right_cmd": "cmd_r", "left_cmd": "cmd_l",
            "right_alt": "alt_r", "left_alt": "alt_l",
            "right_ctrl": "ctrl_r",
            "f5": "f5", "f6": "f6", "f7": "f7", "f8": "f8",
            "f9": "f9", "f10": "f10", "f11": "f11", "f12": "f12",
        }
        key_map = {}
        for name, attr in definitions.items():
            if hasattr(Key, attr):
                key_map[name] = getattr(Key, attr)
        return key_map

    def on_key_press(self, key):
        try:
            hotkey = self.config["hotkey"]
            target = self._get_key_map().get(hotkey)
            if target and key == target and not self.is_recording and not self.processing:
                self.start_recording()
        except Exception:
            pass

    def on_key_release(self, key):
        try:
            hotkey = self.config["hotkey"]
            target = self._get_key_map().get(hotkey)
            if target and key == target and self.is_recording:
                self.stop_and_process()
        except Exception:
            pass

    def start_recording(self):
        """Start recording — debounced to prevent double-press."""
        now = time.time()
        if now - self._last_press_time < 0.5:
            return
        self._last_press_time = now
        self.is_recording = True
        self.recorder.start()
        if self.config["sound_feedback"]:
            play_sound("start")
        if self._overlay:
            self._overlay.show_recording()
        print("🔴 Recording...")

    def stop_and_process(self):
        """Stop recording and process — no debounce, use press timestamp for duration check."""
        self.is_recording = False
        self.recorder.stop()
        if self.config["sound_feedback"]:
            play_sound("stop")

        duration = self.recorder.duration
        print(f"⏹️  Stopped ({duration:.1f}s)")

        # BUG-005 fix: warn on short recordings but do NOT silently drop
        if duration < 0.3:
            print("⚠️  Recording too short (< 0.3s). Skipping — hold the key longer next time.")
            return

        self.processing = True
        thread = threading.Thread(target=self._process_audio, daemon=True)
        thread.start()

    def _process_audio(self):
        temp_path = None
        try:
            with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as f:
                temp_path = f.name

            # BUG-008 fix: check save_wav() return value
            if not self.recorder.save_wav(temp_path):
                print("⚠️ No audio captured.")
                return

            if self._overlay:
                self._overlay.show_processing()
            print("🔄 Transcribing...")
            t0 = time.time()
            raw_text = transcribe(temp_path, self.config)
            t1 = time.time()

            if not raw_text:
                print("⚠️  No speech detected.")
                if self._overlay:
                    self._overlay.show_error("No speech detected")
                if self.config["sound_feedback"]:
                    play_sound("error")
                return

            print(f"📝 Raw ({t1-t0:.1f}s): {raw_text}")

            # Check for snippet match before LLM cleanup
            snippet_expansion = match_snippet(raw_text)
            if snippet_expansion:
                cleaned_text = snippet_expansion
                print(f"📌 Snippet matched: {cleaned_text[:60]}...")
            else:
                print("✨ Cleaning up...")
                t2 = time.time()
                cleaned_text = cleanup_text(raw_text, self.config)
                t3 = time.time()
                print(f"✅ Clean ({t3-t2:.1f}s): {cleaned_text}")

            if self._overlay:
                self._overlay.show_result(cleaned_text)

            if self.config["auto_paste"]:
                paste_text(cleaned_text)
                if self.config["sound_feedback"]:
                    play_sound("done")

            log_transcript(raw_text, cleaned_text, self.config)
            record_dictation(cleaned_text, self.recorder.duration)

        except Exception as e:
            print(f"❌ Error: {e}")
            if self.config["sound_feedback"]:
                play_sound("error")
        finally:
            if temp_path and os.path.exists(temp_path):
                os.unlink(temp_path)
            self.processing = False

    def run(self):
        """Start the OpenVoiceFlow listener (CLI mode)."""
        from pynput.keyboard import Listener

        print("=" * 50)
        print("🎙️  OpenVoiceFlow — Voice Dictation")
        print("=" * 50)

        if not self.validate_setup():
            print("\n⚠️  Fix the above issues and try again.")
            sys.exit(1)

        hotkey = self.config["hotkey"]
        print(f"\n🎤 Ready! Hold [{hotkey}] to dictate, release to process.")
        print(f"   Press Ctrl+C to quit.\n")

        with Listener(
            on_press=self.on_key_press,
            on_release=self.on_key_release,
        ) as listener:
            try:
                listener.join()
            except KeyboardInterrupt:
                print("\n👋 OpenVoiceFlow stopped.")
