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

        # Streaming transcription state
        self._streamer = None           # StreamingTranscriber instance (when active)
        self._streaming_active = False  # True while whisper-stream owns the mic
        self._streaming_raw_text = ""   # Accumulated transcript from whisper-stream
        self._streaming_warned = False  # Warn once if binary missing

        # Per-dictation context state (reset each start_recording call)
        self._current_app = ""
        self._current_style = ""
        self._selected_text_context = None  # captured selected text

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

    def _streaming_enabled(self) -> bool:
        """Return True if streaming mode is configured and the binary is available."""
        if not self.config.get("streaming", True):
            return False
        from .streamer import find_whisper_stream
        if find_whisper_stream():
            return True
        if not self._streaming_warned:
            self._streaming_warned = True
            print("⚠️  whisper-stream binary not found — falling back to batch mode.")
        return False

    def _on_partial_transcript(self, text: str):
        """Callback invoked by StreamingTranscriber on each new partial text chunk."""
        self._streaming_raw_text = text
        if self._overlay:
            self._overlay.show_streaming_text(text)

    def start_recording(self):
        """Start recording — debounced to prevent double-press."""
        now = time.time()
        if now - self._last_press_time < 0.5:
            return
        self._last_press_time = now

        # ── Feature: Selected text context (Feature 4) ─────────────────────
        # Capture selected text BEFORE starting audio (Cmd+C takes ~150ms).
        # Done first so the clipboard is restored before we begin recording.
        self._selected_text_context = None
        if self.config.get("selected_text_context", True):
            try:
                from .clipboard import capture_selected_text
                self._selected_text_context = capture_selected_text()
            except Exception:
                pass  # Never let clipboard capture block recording

        # ── Feature: Per-app context detection (Feature 2) ─────────────────
        self._current_app = ""
        self._current_style = self.config.get("style", "default")
        if self.config.get("auto_style", True):
            try:
                from .context import get_frontmost_app, get_style_for_app
                self._current_app = get_frontmost_app()
                self._current_style = get_style_for_app(self._current_app, self.config)
            except Exception:
                pass  # Never let app detection block recording

        self.is_recording = True

        if self._streaming_enabled():
            # ── Feature: Streaming transcription (Feature 1) ────────────────
            # whisper-stream owns the mic entirely — do NOT start AudioRecorder
            from .streamer import StreamingTranscriber
            from .transcriber import get_model_path
            model_path = get_model_path(self.config["whisper_model"])
            step_ms = self.config.get("streaming_step_ms", 3000)
            language = self.config.get("language", "en")
            self._streamer = StreamingTranscriber(
                model_path=model_path,
                language=language,
                step_ms=step_ms,
            )
            started = self._streamer.start(callback=self._on_partial_transcript)
            if started:
                self._streaming_active = True
                self._streaming_raw_text = ""
                _style_info = f" [{self._current_style}]" if self._current_app else ""
                _ctx_info = " (with context)" if self._selected_text_context else ""
                print("🔴 Recording (streaming)" + _style_info + _ctx_info + "...")
            else:
                # Binary vanished at runtime — fall back silently to batch
                self._streamer = None
                self._streaming_active = False
                self.recorder.start()
                _style_info = f" [{self._current_style}]" if self._current_app else ""
                print("🔴 Recording (batch fallback)" + _style_info + "...")
        else:
            # Batch mode: AudioRecorder captures WAV as before
            self._streaming_active = False
            self.recorder.start()
            _style_info = f" [{self._current_style}]" if self._current_app else ""
            _ctx_info = " (with context)" if self._selected_text_context else ""
            print("🔴 Recording..." + _style_info + _ctx_info)

        if self.config["sound_feedback"]:
            play_sound("start")
        if self._overlay:
            self._overlay.show_recording(
                style_label=self._current_style if self._current_app else None,
                with_context=bool(self._selected_text_context),
            )

    def stop_and_process(self):
        """Stop recording and process — no debounce, use press timestamp for duration check."""
        self.is_recording = False

        # Snapshot context so it's consistent across the whole process call
        current_app = self._current_app
        current_style = self._current_style
        selected_context = self._selected_text_context

        if self._streaming_active and self._streamer:
            # ── Streaming stop path ─────────────────────────────────────────
            raw_text_from_stop = self._streamer.stop()
            self._streaming_active = False
            self._streamer = None

            if self.config["sound_feedback"]:
                play_sound("stop")

            duration = time.time() - self._last_press_time
            print(f"⏹️  Stopped streaming ({duration:.1f}s)")

            if duration < 0.3:
                print("⚠️  Recording too short (< 0.3s). Skipping.")
                return

            # Prefer callback-accumulated text (more complete); fall back to stop() return
            raw_text = self._streaming_raw_text or raw_text_from_stop
            if not raw_text:
                print("⚠️  No speech detected (streaming).")
                if self._overlay:
                    self._overlay.show_error("No speech detected")
                if self.config["sound_feedback"]:
                    play_sound("error")
                return

            self.processing = True
            thread = threading.Thread(
                target=self._process_streaming_result,
                args=(raw_text, duration, current_app, current_style, selected_context),
                daemon=True,
            )
            thread.start()
        else:
            # ── Batch stop path ─────────────────────────────────────────────
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
            thread = threading.Thread(
                target=self._process_audio,
                args=(current_app, current_style, selected_context),
                daemon=True,
            )
            thread.start()

    def _process_streaming_result(
        self,
        raw_text: str,
        duration: float,
        current_app: str = "",
        current_style: str = "",
        selected_context: str | None = None,
    ):
        """LLM cleanup + paste for text collected in streaming mode.

        No WAV file is available in streaming mode; that's acceptable per spec.
        """
        try:
            if self._overlay:
                self._overlay.show_processing()
            print(f"📝 Raw (streaming): {raw_text}")

            # ── Feature: Voice commands (Feature 3) ─────────────────────────
            from .commands import load_commands, apply_commands
            raw_text = apply_commands(raw_text, load_commands(self.config))

            # Snippet match before LLM cleanup
            snippet_expansion = match_snippet(raw_text)
            if snippet_expansion:
                cleaned_text = snippet_expansion
                print(f"📌 Snippet matched: {cleaned_text[:60]}...")
            else:
                # ── Feature: App context (Feature 2) ────────────────────────
                app_ctx = None
                if current_app:
                    from .context import get_app_context_prompt
                    app_ctx = get_app_context_prompt(current_app, current_style)

                _ctx_info = f" [app: {current_app}]" if current_app else ""
                _sel_info = " [selected context]" if selected_context else ""
                print("✨ Cleaning up..." + _ctx_info + _sel_info)
                t0 = time.time()
                # ── Feature: Selected text context (Feature 4) ───────────────
                cleaned_text = cleanup_text(
                    raw_text, self.config,
                    context=selected_context,
                    app_context=app_ctx,
                    style=current_style or None,
                )
                t1 = time.time()
                print(f"✅ Clean ({t1-t0:.1f}s): {cleaned_text}")

            if self._overlay:
                self._overlay.show_result(cleaned_text)

            if self.config["auto_paste"]:
                paste_text(cleaned_text)
                if self.config["sound_feedback"]:
                    play_sound("done")

            # No WAV file in streaming mode — log raw text directly
            log_transcript(raw_text, cleaned_text, self.config)
            record_dictation(cleaned_text, duration)

        except Exception as e:
            print(f"❌ Error (streaming): {e}")
            if self.config["sound_feedback"]:
                play_sound("error")
        finally:
            self.processing = False

    def _process_audio(
        self,
        current_app: str = "",
        current_style: str = "",
        selected_context: str | None = None,
    ):
        """Batch mode: read WAV, transcribe, apply all features, paste."""
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

            # ── Feature: Voice commands (Feature 3) ─────────────────────────
            # Apply spoken punctuation/formatting replacements before LLM cleanup.
            from .commands import load_commands, apply_commands
            raw_text = apply_commands(raw_text, load_commands(self.config))

            # Check for snippet match before LLM cleanup
            snippet_expansion = match_snippet(raw_text)
            if snippet_expansion:
                cleaned_text = snippet_expansion
                print(f"📌 Snippet matched: {cleaned_text[:60]}...")
            else:
                # ── Feature: App context (Feature 2) ────────────────────────
                app_ctx = None
                if current_app:
                    from .context import get_app_context_prompt
                    app_ctx = get_app_context_prompt(current_app, current_style)

                _ctx_info = f" [app: {current_app}]" if current_app else ""
                _sel_info = " [selected context]" if selected_context else ""
                print("✨ Cleaning up..." + _ctx_info + _sel_info)
                t2 = time.time()
                # ── Feature: Selected text context (Feature 4) ───────────────
                cleaned_text = cleanup_text(
                    raw_text, self.config,
                    context=selected_context,
                    app_context=app_ctx,
                    style=current_style or None,
                )
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
