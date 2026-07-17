"""OpenVoiceFlow main application controller."""

from __future__ import annotations

import os
import re
import subprocess
import sys
import tempfile
import threading
import time

from . import platform_support
from .config import load_config
from .llm import cleanup_text
from .recorder import AudioRecorder
from .snippets import match_snippet
from .stats import record_dictation
from .system import (
    clear_recording_indicator,
    insert_recording_indicator,
    log_transcript,
    paste_text,
    play_sound,
)
from .transcriber import find_whisper_cpp, get_model_path, transcribe

# ─────────────────────────────────────────────────────────────────────
# Voice-command tutor (Phase C2 — UX_REVIEW.md Theme B)
# ─────────────────────────────────────────────────────────────────────

# Word-boundary phoneme detector: catches the punctuation phrases a user
# would have benefited from voice-command substitution on.
_PUNCT_PHONEMES = re.compile(
    r"\b(comma|period|full stop|question mark|exclamation (?:mark|point)|"
    r"semicolon|colon|new paragraph|new line|newline)\b",
    re.IGNORECASE,
)


def _has_punct_phoneme(text: str) -> bool:
    """True iff the raw transcript contains a punctuation phoneme."""
    if not text:
        return False
    return bool(_PUNCT_PHONEMES.search(text))


def _maybe_voice_command_tutor(text_before: str, text_after: str) -> None:
    """Show a one-shot educational nudge if appropriate.

    - If apply_commands actually substituted (text_before != text_after):
      fire a positive-reinforcement tip ("OpenVoiceFlow heard a voice
      command and converted it"). once_key='voice_command_first_fire'.
    - Else, if the raw transcript contains a punctuation phoneme but
      no substitution occurred (commands disabled, or phoneme wasn't a
      configured trigger): fire an educational tip
      ("Try saying 'comma' for ,"). once_key='voice_commands_intro'.
    - Else: silent.

    Both tips fire ONCE total per machine (the once_key persists in
    ~/.openvoiceflow/_seen_tips.json).
    """
    from . import notify
    if text_before != text_after:
        notify.tip(
            "✓ OpenVoiceFlow heard a voice command and converted it. "
            "Try also: 'period', 'question mark', 'new paragraph'. "
            "Run `openvoiceflow --list-commands` for all 24.",
            once_key="voice_command_first_fire",
        )
    elif _has_punct_phoneme(text_before):
        notify.tip(
            "💡 Tip: try saying 'comma' or 'period' — OpenVoiceFlow types it "
            "for you. We have 24 voice commands built in. "
            "Run `openvoiceflow --list-commands` to see them.",
            once_key="voice_commands_intro",
        )


# Same deep link the doctor's Input Monitoring fix uses.
_INPUT_MONITORING_SETTINGS_URL = (
    "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
)


def _is_accessibility_trusted() -> bool:
    """Return True when the process is trusted for macOS Accessibility APIs."""
    status = platform_support.accessibility_status()
    # If we cannot query trust state (None), don't block startup on this check.
    return status is not False


def _prompt_accessibility_consent() -> None:
    """Request Accessibility consent and open the relevant Settings pane."""
    try:
        from ApplicationServices import (  # type: ignore
            AXIsProcessTrustedWithOptions,
            kAXTrustedCheckOptionPrompt,
        )
        AXIsProcessTrustedWithOptions({kAXTrustedCheckOptionPrompt: True})
    except Exception:
        pass

    # Best-effort direct jump to the Accessibility settings pane.
    try:
        subprocess.run(
            [
                "open",
                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            ],
            check=False,
            capture_output=True,
            timeout=10,
        )
    except Exception:
        pass


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

        # Runtime fn hotkey self-check state
        self._fn_probe_started = False
        self._fn_event_seen = False
        self._recording_indicator_inserted = False

        # Dead-listener watchdog state: True once ANY key event reaches us.
        # Without Input Monitoring, pynput's listener starts cleanly and
        # then receives nothing — this flag is how we tell "Ready" apart
        # from "silently dead".
        self._any_key_event_seen = False

        # Serializes the recording start/stop transition so the pynput
        # callback thread, the max-duration watchdog, and the menubar's
        # abort path can't drive a dictation into a half-stopped state.
        self._lifecycle_lock = threading.Lock()
        # Force-stops a recording if the key-release event is ever missed
        # (a stalled consent dialog can disable the event tap and swallow it),
        # which would otherwise leave the mic + whisper-stream running forever.
        self._max_record_timer: threading.Timer | None = None

        # validate_setup results, exposed for the menubar's alert UI.
        self.setup_errors: list[str] = []
        self.setup_warnings: list[tuple[str, str]] = []

    def validate_setup(self) -> bool:
        """Check that all dependencies are ready."""
        errors = []
        self.setup_warnings = []

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
            print("⚠️  Model not found. Will download on first use.")

        # LLM backend
        backend = self.config.get("llm_backend", "openrouter")
        if backend == "none":
            print("✅ LLM cleanup: disabled (raw transcripts only)")
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

        # Audio — sounddevice raises OSError (not ImportError) when the
        # PortAudio C library itself is missing, so catch both.
        try:
            import sounddevice  # noqa: F401  (availability check)
            print("✅ Audio input available")
        except ImportError:
            errors.append("sounddevice not installed. Run: pip install sounddevice")
        except OSError as e:
            errors.append(f"Audio backend unavailable ({e}). Reinstall with: pip install sounddevice")

        # Accessibility / input monitoring
        if _is_accessibility_trusted():
            print("✅ Accessibility permission granted")
        else:
            _prompt_accessibility_consent()
            errors.append(
                "Accessibility permission not granted. "
                "Enable OpenVoiceFlow in System Settings -> Privacy & Security -> Accessibility, "
                "then relaunch the app"
            )

        # Input Monitoring — what the global hotkey listener actually needs.
        # TCC nuance: Accessibility trust often also grants listen access,
        # so a denied probe does not always mean a dead hotkey. Warn loudly
        # but never block — a false block would strand working setups. The
        # dead-listener watchdog escalates if key events genuinely never
        # arrive.
        input_monitoring = platform_support.input_monitoring_status()
        if input_monitoring is True:
            print("✅ Input Monitoring permission granted")
        elif input_monitoring is False:
            warning = (
                "Input Monitoring permission not granted — the dictation "
                "hotkey may not respond. Enable OpenVoiceFlow in System "
                "Settings -> Privacy & Security -> Input Monitoring, then "
                "relaunch the app."
            )
            print(f"⚠️  {warning}")
            self.setup_warnings.append(("input_monitoring", warning))
            from . import notify
            notify.warn(
                warning,
                action=(
                    "Open Input Monitoring Settings",
                    _INPUT_MONITORING_SETTINGS_URL,
                ),
            )

        self.setup_errors = errors
        if errors:
            print("\n❌ Setup issues:")
            for e in errors:
                print(f"   • {e}")
            # B2: surface to menubar users + click-to-fix Notification Center.
            from . import notify
            accessibility_missing = any(
                "Accessibility permission not granted" in error for error in errors
            )
            notify.error(
                "Setup incomplete — " + (errors[0] if len(errors) == 1
                                          else f"{len(errors)} issues found"),
                action=(
                    (
                        "Open Accessibility Settings",
                        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
                    )
                    if accessibility_missing
                    else ("Run openvoiceflow --doctor", None)
                ),
            )
            return False
        return True

    def _get_key_map(self):
        """Build hotkey map for available pynput keys.

        Returns an empty map when pynput cannot load (no macOS input
        backend); callers treat a missing hotkey as "no key events".
        """
        try:
            from pynput.keyboard import Key
        except Exception:
            return {}
        definitions = {
            "left_fn": "fn",
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
            self._any_key_event_seen = True
            hotkey = self.config["hotkey"]
            target = self._get_key_map().get(hotkey)
            if hotkey == "left_fn" and target and key == target:
                self._fn_event_seen = True
            if target and key == target and not self.is_recording and not self.processing:
                self.start_recording()
        except Exception:
            pass

    # Seconds to wait for the first key event before concluding the listener
    # is receiving nothing. Long enough that a normal launch-then-type flow
    # registers an event first; short enough that a dead setup surfaces
    # while the user is still paying attention.
    _DEAD_LISTENER_WINDOW = 15

    def _check_dead_listener(self, on_dead_hotkey=None):
        """Escalate when the listener is up but macOS delivers no events.

        Fires the modal path only when the static Input Monitoring probe
        agrees the permission is denied — an idle user alone must not
        trigger the alarm (they get a one-time gentle tip instead).
        """
        if self._any_key_event_seen:
            return
        from . import notify
        if platform_support.input_monitoring_status() is False:
            message = (
                "OpenVoiceFlow isn't receiving keyboard events, and macOS "
                "reports Input Monitoring is not granted — the dictation "
                "hotkey will not work. Enable OpenVoiceFlow in System "
                "Settings > Privacy & Security > Input Monitoring, then "
                "relaunch the app."
            )
            if on_dead_hotkey is not None:
                try:
                    on_dead_hotkey(message)
                    return
                except Exception:
                    pass
            notify.error(
                message,
                action=(
                    "Open Input Monitoring Settings",
                    _INPUT_MONITORING_SETTINGS_URL,
                ),
            )
        else:
            notify.tip(
                "No key events seen yet. If the dictation hotkey doesn't "
                "respond, check System Settings > Privacy & Security > "
                "Input Monitoring and relaunch the app.",
                once_key="hotkey_no_events",
            )

    def start_hotkey_runtime_checks(self, on_dead_hotkey=None):
        """Start non-blocking runtime checks for hotkey reliability.

        ``on_dead_hotkey`` receives a message (from a daemon thread) when
        the listener has been up for the watch window without a single key
        event AND Input Monitoring is denied — the signature of a silently
        dead listener. Menubar mode passes a modal-alert callback; CLI mode
        falls back to a Notification Center error.
        """
        if self._fn_probe_started:
            return
        self._fn_probe_started = True

        def _watch_key_events():
            time.sleep(self._DEAD_LISTENER_WINDOW)
            self._check_dead_listener(on_dead_hotkey)

        watchdog = threading.Thread(
            target=_watch_key_events, daemon=True, name="ovf-hotkey-watchdog"
        )
        watchdog.start()

        if self.config.get("hotkey") != "left_fn":
            return

        # The Fn / 🌐 Globe key cannot be a hotkey with the current engine:
        # pynput's macOS backend has no fn key at all (no Key.fn, and no
        # entry in its modifier-flag table), so a fn hotkey NEVER fires. This
        # is deterministic — not a per-machine "may not respond" — so surface
        # it immediately and loudly (the old 12 s Notification Center tip was
        # both slow and easy to miss) and steer the user to a working key.
        message = (
            "The Fn / 🌐 Globe key can't be used as the dictation hotkey — "
            "macOS doesn't expose it to apps. Switch to Right Command (the "
            "default) from the menu bar under Dictation Shortcut, or run: "
            "openvoiceflow --hotkey right_cmd"
        )
        from . import notify
        if on_dead_hotkey is not None:
            try:
                on_dead_hotkey(message)  # menubar → modal alert
                return
            except Exception:
                pass
        notify.error(message)

    def on_key_release(self, key):
        try:
            self._any_key_event_seen = True
            hotkey = self.config["hotkey"]
            target = self._get_key_map().get(hotkey)
            if target and key == target and self.is_recording:
                self.stop_and_process()
        except Exception:
            pass

    def _streaming_enabled(self) -> bool:
        """Return True if streaming mode is configured and the binary is available."""
        if not self.config.get("streaming", False):
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

    def _abort_recording_start(self, reason: str):
        """Roll back recording state after a failed start (e.g. mic unavailable)."""
        self.is_recording = False
        if self._recording_indicator_inserted:
            clear_recording_indicator()
            self._recording_indicator_inserted = False
        if self._overlay:
            self._overlay.show_error(reason)
        if self.config["sound_feedback"]:
            play_sound("error")
        from . import notify
        notify.error(
            f"Could not start recording — {reason}. "
            "Check the microphone and Input Monitoring permissions."
        )

    # Hard ceiling on a single dictation. Long enough for a genuine
    # multi-minute dictation, short enough that a lost key-release doesn't
    # strand the mic + whisper-stream indefinitely.
    _MAX_RECORDING_SECONDS = 300

    def start_recording(self):
        """Start recording — debounced to prevent duplicate key events.

        The window is short (0.2 s) so a genuine immediate retry after a
        too-short attempt still works; it only filters event bounce.

        This runs on the pynput event-tap callback thread, which macOS
        disables if it blocks too long. So the microphone is armed *first*
        (fast), and the ~150 ms of ``osascript`` context capture (selected
        text, frontmost app) is moved to a short-lived worker thread — a
        stalled ``osascript`` (e.g. a consent dialog) can no longer wedge
        the event tap or delay the key-release handler.
        """
        now = time.time()
        if now - self._last_press_time < 0.2:
            return
        self._last_press_time = now

        # Stop any active correction watcher before starting a new dictation
        if hasattr(self, '_watcher') and self._watcher:
            self._watcher.stop()
            self._watcher = None

        # Reset per-dictation context; the worker below fills it in. Snapshot
        # readers (stop_and_process) tolerate it still being empty on an
        # ultra-short dictation, which is below the 0.3 s floor anyway.
        self._selected_text_context = None
        self._current_app = ""
        self._current_style = self.config.get("style", "default")
        self._recording_indicator_inserted = False

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
                try:
                    self.recorder.start()
                except Exception as e:
                    self._abort_recording_start(f"microphone unavailable ({e})")
                    return
                _style_info = f" [{self._current_style}]" if self._current_app else ""
                print("🔴 Recording (batch fallback)" + _style_info + "...")
        else:
            # Batch mode: AudioRecorder captures WAV as before
            self._streaming_active = False
            try:
                self.recorder.start()
            except Exception as e:
                self._abort_recording_start(f"microphone unavailable ({e})")
                return
            _style_info = f" [{self._current_style}]" if self._current_app else ""
            _ctx_info = " (with context)" if self._selected_text_context else ""
            print("🔴 Recording..." + _style_info + _ctx_info)

        if self.config["sound_feedback"]:
            play_sound("start")
        if self._overlay:
            self._overlay.show_recording()

        # Force-stop if the key-release is ever missed.
        self._start_max_duration_timer()

        # Capture selected-text + app context OFF the event-tap thread.
        threading.Thread(
            target=self._capture_context, daemon=True, name="ovf-context-capture",
        ).start()

    def _capture_context(self):
        """Best-effort selected-text + frontmost-app capture (worker thread).

        Runs the ~150 ms of osascript/Accessibility work off the pynput
        callback thread. Results land in instance attributes that
        stop_and_process snapshots at key-release.
        """
        if self.config.get("selected_text_context", True):
            try:
                from .clipboard import capture_selected_text
                self._selected_text_context = capture_selected_text()
            except Exception:
                pass
        if self.config.get("auto_style", True):
            try:
                from .context import get_frontmost_app, get_style_for_app
                app = get_frontmost_app()
                self._current_app = app
                self._current_style = get_style_for_app(app, self.config)
            except Exception:
                pass
        # Typed 🎙 indicator is opt-in: it edits the user's document, so it
        # also stays off the event-tap thread.
        if self.config.get("recording_indicator", False):
            try:
                self._recording_indicator_inserted = insert_recording_indicator("🎙")
            except Exception:
                pass

    def _start_max_duration_timer(self):
        self._cancel_max_duration_timer()
        timer = threading.Timer(self._MAX_RECORDING_SECONDS, self._on_max_duration)
        timer.daemon = True
        timer.name = "ovf-max-record"
        self._max_record_timer = timer
        timer.start()

    def _cancel_max_duration_timer(self):
        timer = self._max_record_timer
        self._max_record_timer = None
        if timer is not None:
            timer.cancel()

    def _on_max_duration(self):
        """Watchdog: a recording that outran the ceiling lost its key-release."""
        if not self.is_recording:
            return
        print(f"⏱️  Recording hit the {self._MAX_RECORDING_SECONDS}s ceiling — stopping.")
        try:
            from . import notify
            notify.warn(
                "Dictation reached the maximum length and was stopped "
                "automatically. Processing what was captured."
            )
        except Exception:
            pass
        self.stop_and_process()

    def stop_and_process(self):
        """Stop recording and process.

        Guarded so only one caller (the key-release, the max-duration
        watchdog, or an abort) drives the stop transition; the rest return.
        """
        with self._lifecycle_lock:
            if not self.is_recording:
                return
            self.is_recording = False
        self._cancel_max_duration_timer()
        if self._recording_indicator_inserted:
            clear_recording_indicator()
            self._recording_indicator_inserted = False

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
                if self._overlay:
                    self._overlay.hide()
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

            self._start_processing(
                self._process_streaming_result,
                (raw_text, duration, current_app, current_style, selected_context),
            )
        else:
            # ── Batch stop path ─────────────────────────────────────────────
            try:
                self.recorder.stop()
            except Exception as e:
                # Device unplugged mid-recording, etc. Surface it instead of
                # dropping the dictation silently and leaving the overlay
                # stuck on the "Recording" pill.
                print(f"❌ Failed to stop recorder: {e}")
                if self._overlay:
                    self._overlay.show_error("Recording error")
                if self.config["sound_feedback"]:
                    play_sound("error")
                from . import notify
                notify.error(f"Recording stopped unexpectedly ({e}).")
                return
            if self.config["sound_feedback"]:
                play_sound("stop")

            duration = self.recorder.duration
            print(f"⏹️  Stopped ({duration:.1f}s)")

            # BUG-005 fix: warn on short recordings but do NOT silently drop
            if duration < 0.3:
                print("⚠️  Recording too short (< 0.3s). Skipping — hold the key longer next time.")
                if self._overlay:
                    self._overlay.hide()
                return

            self._start_processing(
                self._process_audio,
                (current_app, current_style, selected_context),
            )

    def _start_processing(self, target, args):
        """Spawn a processing worker, rolling back ``processing`` if the
        thread can't start (otherwise the hotkey is wedged forever)."""
        self.processing = True
        try:
            threading.Thread(target=target, args=args, daemon=True).start()
        except Exception as e:
            self.processing = False
            print(f"❌ Could not start processing thread: {e}")
            if self._overlay:
                self._overlay.hide()

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
            from .commands import apply_commands, load_commands
            _text_before_cmds_streaming = raw_text
            raw_text = apply_commands(raw_text, load_commands(self.config))
            _maybe_voice_command_tutor(_text_before_cmds_streaming, raw_text)

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
                if snippet_expansion:
                    self._overlay.show_result(cleaned_text)
                else:
                    self._overlay.show_result(
                        cleaned_text,
                        timing=f"Cleanup {t1-t0:.1f}s",
                    )

            if self.config["auto_paste"]:
                paste_text(cleaned_text)
                if self.config["sound_feedback"]:
                    play_sound("done")
                # Auto-learn: watch for post-paste corrections (opt-in)
                if self.config.get("auto_learn", False):
                    from .learner import CorrectionWatcher
                    self._watcher = CorrectionWatcher()
                    self._watcher.start_watching(cleaned_text)

            # No WAV file in streaming mode — log raw text directly
            log_transcript(raw_text, cleaned_text, self.config)
            record_dictation(cleaned_text, duration)

        except Exception as e:
            print(f"❌ Error (streaming): {e}")
            if self._overlay:
                self._overlay.show_error("Dictation failed")
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
                if self._overlay:
                    self._overlay.hide()
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
            from .commands import apply_commands, load_commands
            _text_before_cmds_batch = raw_text
            raw_text = apply_commands(raw_text, load_commands(self.config))
            _maybe_voice_command_tutor(_text_before_cmds_batch, raw_text)

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

            # B3: per-dictation timing line — surfaces latency to user.
            if self._overlay:
                if snippet_expansion:
                    self._overlay.show_result(cleaned_text)
                else:
                    self._overlay.show_result(
                        cleaned_text,
                        timing=f"Whisper {t1-t0:.1f}s · Cleanup {t3-t2:.1f}s",
                    )

            if self.config["auto_paste"]:
                paste_text(cleaned_text)
                if self.config["sound_feedback"]:
                    play_sound("done")
                # Auto-learn: watch for post-paste corrections (opt-in)
                if self.config.get("auto_learn", False):
                    from .learner import CorrectionWatcher
                    self._watcher = CorrectionWatcher()
                    self._watcher.start_watching(cleaned_text)

            log_transcript(raw_text, cleaned_text, self.config)
            record_dictation(cleaned_text, self.recorder.duration)

        except Exception as e:
            print(f"❌ Error: {e}")
            if self._overlay:
                self._overlay.show_error("Dictation failed")
            if self.config["sound_feedback"]:
                play_sound("error")
        finally:
            if temp_path and os.path.exists(temp_path):
                os.unlink(temp_path)
            self.processing = False

    def run(self):
        """Start the OpenVoiceFlow listener (CLI mode)."""
        # pynput needs a macOS input backend; on other systems (or a broken
        # install) it can raise at import. Exit with guidance, not a traceback.
        try:
            from pynput.keyboard import Listener
        except Exception as e:
            print(f"❌ Keyboard listener unavailable ({e}).", file=sys.stderr)
            print(
                "   OpenVoiceFlow needs macOS to capture the dictation hotkey. "
                "Reinstall with: pip install pynput",
                file=sys.stderr,
            )
            sys.exit(1)

        print("=" * 50)
        print("🎙️  OpenVoiceFlow — Voice Dictation")
        print("=" * 50)

        if not self.validate_setup():
            print("\n⚠️  Fix the above issues and try again.")
            sys.exit(1)

        hotkey = self.config["hotkey"]
        print(f"\n🎤 Ready! Hold [{hotkey}] to dictate, release to process.")
        print("   Press Ctrl+C to quit.\n")
        if self.config.get("sound_feedback", True):
            play_sound("done")

        with Listener(
            on_press=self.on_key_press,
            on_release=self.on_key_release,
        ) as listener:
            self.start_hotkey_runtime_checks()
            try:
                listener.join()
            except KeyboardInterrupt:
                print("\n👋 OpenVoiceFlow stopped.")
