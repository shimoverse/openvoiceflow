"""OpenVoiceFlow macOS menu bar app using rumps."""

from __future__ import annotations

from .system import play_sound

try:
    import rumps
except ImportError:
    rumps = None


_MENU_ITEM_SPECS = {
    "open": ("Open OpenVoiceFlow", None),
    "listening": ("Listening", None),
    "status": ("Starting…", None),
    "detected_app": ("Current App: —", None),
    "shortcut": ("Dictation Shortcut", None),
    "backend": ("AI Cleanup", None),
    "style": ("Writing Style", None),
    "personalization": ("Personalization", None),
    "advanced": ("Advanced", None),
    "stats": ("Usage Statistics", None),
    "usage": ("How to Use", None),
    "updates": ("Check for Updates…", None),
    "quit": ("Quit OpenVoiceFlow", "q"),
}

_MAIN_MENU_LAYOUT = (
    "open",
    None,
    "listening",
    "status",
    "detected_app",
    None,
    "shortcut",
    "backend",
    "style",
    None,
    "personalization",
    "advanced",
    "stats",
    None,
    "usage",
    "updates",
    None,
    "quit",
)

_HOTKEY_LABELS = {
    "right_cmd": "Right Command (⌘)",
    "left_cmd": "Left Command (⌘)",
    "left_fn": "Fn",
    "right_alt": "Right Option (⌥)",
    "left_alt": "Left Option (⌥)",
    "right_ctrl": "Right Control (⌃)",
}

_BACKEND_LABELS = {
    "openrouter": "OpenRouter",
    "openai": "OpenAI",
    "anthropic": "Anthropic Claude",
    "groq": "Groq",
    "ollama": "Ollama (Local)",
    "none": "No AI Cleanup",
}

_STYLE_MENU_LABELS = {
    "default": "Default",
    "casual": "Casual",
    "formal": "Formal",
    "code": "Code",
    "email": "Email",
}

_STATUS_PRESENTATIONS = {
    "starting": ("waveform", "Starting"),
    "ready": ("waveform", "Ready"),
    "paused": ("pause.circle", "Paused"),
    "error": ("exclamationmark.triangle", "Needs attention"),
}

_CONTEXT_REFRESH_SECONDS = 2.0
_LISTENER_START_DELAY_SECONDS = 0.15


def _clear_submenu(menu) -> None:
    """Clear a rumps submenu only after its native NSMenu exists."""
    if getattr(menu, "_menu", None) is not None:
        menu.clear()


def _hotkey_label(hotkey: str) -> str:
    """Return the menu label for a configured dictation shortcut."""
    return _HOTKEY_LABELS.get(hotkey, hotkey.upper())


def _hotkey_choices(current_hotkey: str) -> list[tuple[str, str, bool]]:
    """Return every supported hotkey with its label and selected state."""
    from .config import VALID_HOTKEYS

    return [
        (hotkey, _hotkey_label(hotkey), hotkey == current_hotkey)
        for hotkey in VALID_HOTKEYS
    ]


def _backend_label(backend: str) -> str:
    return _BACKEND_LABELS.get(backend, backend.replace("_", " ").title())


def _style_label(style: str) -> str:
    return _STYLE_MENU_LABELS.get(style, style.replace("_", " ").title())


def _set_checked(item, enabled: bool) -> None:
    """Use the native NSMenuItem state instead of a checkmark in its title."""
    item.state = 1 if enabled else 0


def _alert_confirmed(result: int) -> bool:
    """Accept both native AppKit and legacy rumps first-button results."""
    try:
        from AppKit import NSAlertFirstButtonReturn

        first_button = NSAlertFirstButtonReturn
    except Exception:
        first_button = 1000
    return result in (1, first_button)


def _profile_interview_command(
    python_executable: str | None = None,
) -> list[str]:
    """Build the isolated command used for the Tk profile interview."""
    import sys

    executable = python_executable or sys.executable
    code = "from voiceflow.interview import run_interview; run_interview()"
    return [executable, "-c", code]


def _app_icon_path() -> str | None:
    """Find the branded app icon in a package or source checkout."""
    import os
    from pathlib import Path

    candidates = []
    resources = os.environ.get("OPENVOICEFLOW_APP_RESOURCES")
    if resources:
        candidates.append(Path(resources) / "OpenVoiceFlow.icns")
    candidates.extend(
        [
            Path("/Applications/OpenVoiceFlow.app/Contents/Resources/OpenVoiceFlow.icns"),
            Path.home()
            / "Applications"
            / "OpenVoiceFlow.app"
            / "Contents"
            / "Resources"
            / "OpenVoiceFlow.icns",
        ]
    )
    candidates.append(
        Path(__file__).resolve().parent.parent / "assets" / "OpenVoiceFlow.icns"
    )
    for candidate in candidates:
        if candidate.is_file():
            return str(candidate)
    return None


# True while a _show_alert dialog is on screen. NSAlert activates the app,
# which would otherwise make the Dock-activation handler pop the status
# panel on top of every alert this app shows.
_alert_active = False


def _show_alert(**kwargs):
    """Show a native alert with OpenVoiceFlow branding."""
    global _alert_active
    icon_path = _app_icon_path()
    if icon_path:
        kwargs.setdefault("icon_path", icon_path)
    _alert_active = True
    try:
        return rumps.alert(**kwargs)
    finally:
        _alert_active = False


def _show_notification(title: str, subtitle: str, message: str, **kwargs) -> None:
    """Show a notification with OpenVoiceFlow branding.

    rumps.notification raises RuntimeError on non-framework Python installs
    (no Info.plist / CFBundleIdentifier — typical for pyenv/conda; only the
    DMG bundle ships a plist). Callers rely on this for setup guidance and
    settings confirmations, so a failure must degrade to the osascript
    notification path instead of blowing up the calling rumps callback.
    """
    icon_path = _app_icon_path()
    if icon_path:
        kwargs.setdefault("icon", icon_path)
    try:
        rumps.notification(title, subtitle, message, **kwargs)
    except Exception:
        try:
            from . import notify
            notify._post_macos_notification(title, message, subtitle=subtitle or None)
        except Exception:
            import sys
            print(f"{title}: {subtitle} {message}".strip(), file=sys.stderr)


def _apply_activation_policy(show_dock_icon: bool) -> None:
    """Show or hide the Dock icon for this UI process.

    Regular puts the app in the Dock and the Cmd-Tab switcher — an
    always-visible sign it is running (a menu-bar-only icon can hide
    behind a MacBook notch). Accessory is the pre-0.3.5 Dock-less mode.
    The bundle plist keeps LSUIElement=true, so the runtime policy is the
    single source of truth for Dock presence.
    """
    try:
        from AppKit import (
            NSApplication,
            NSApplicationActivationPolicyAccessory,
            NSApplicationActivationPolicyRegular,
        )

        policy = (
            NSApplicationActivationPolicyRegular
            if show_dock_icon
            else NSApplicationActivationPolicyAccessory
        )
        NSApplication.sharedApplication().setActivationPolicy_(policy)
    except Exception:
        pass


def _configure_macos_application(show_dock_icon: bool = False) -> None:
    """Set the UI process's Dock presence and give alerts our app icon."""
    _apply_activation_policy(show_dock_icon)
    try:
        from AppKit import NSApplication, NSImage

        application = NSApplication.sharedApplication()
        icon_path = _app_icon_path()
        if icon_path:
            icon = NSImage.alloc().initWithContentsOfFile_(icon_path)
            if icon is not None:
                application.setApplicationIconImage_(icon)
    except Exception:
        pass


# Ignore app activations this soon after launch: macOS may activate the
# process once as it starts, and that must not pop the status panel.
_DOCK_ACTIVATION_GRACE_SECONDS = 5.0


def _install_dock_activation_handler(app) -> None:
    """Open the status panel when the user activates us from the Dock.

    A Dock icon that does nothing when clicked is worse than none. The app
    has no windows, so activation (Dock click or Cmd-Tab) routes to the
    same native status summary as the "Open OpenVoiceFlow" menu item.
    Registered once; the handler itself re-checks the config so toggling
    the Dock icon off also disables it.
    """
    if getattr(app, "_dock_activation_observer", None) is not None:
        return
    try:
        import time

        from AppKit import NSNotificationCenter, NSOperationQueue

        started = time.monotonic()

        def _on_did_become_active(_notification):
            if time.monotonic() - started < _DOCK_ACTIVATION_GRACE_SECONDS:
                return
            if not bool(app.config.get("show_dock_icon", True)):
                return
            if _alert_active or getattr(app, "_dock_activation_busy", False):
                return
            app._dock_activation_busy = True
            try:
                app.open_app(None)
            finally:
                app._dock_activation_busy = False

        app._dock_activation_observer = (
            NSNotificationCenter.defaultCenter()
            .addObserverForName_object_queue_usingBlock_(
                "NSApplicationDidBecomeActiveNotification",
                None,
                NSOperationQueue.mainQueue(),
                _on_did_become_active,
            )
        )
    except Exception:
        app._dock_activation_observer = None


def _is_current_process(
    process_id: int,
    current_process_id: int | None = None,
) -> bool:
    """Return whether an AppKit running application is this UI process."""
    import os

    current = os.getpid() if current_process_id is None else current_process_id
    return process_id == current


def _is_openvoiceflow_host(
    process_id: int,
    localized_name: str | None,
    bundle_id: str | None,
    current_process_id: int | None = None,
) -> bool:
    """Recognize this UI process and its native/Python helper processes."""
    if _is_current_process(process_id, current_process_id):
        return True
    name = (localized_name or "").casefold()
    identifier = (bundle_id or "").casefold()
    return name in {"openvoiceflow", "python", "python3"} or identifier in {
        "com.apple.python3",
        "com.openvoiceflow.dictation",
        "org.python.python",
    }


def _frontmost_app_is_current_process() -> bool:
    """Avoid presenting OpenVoiceFlow helper processes as the current app."""
    try:
        from AppKit import NSWorkspace

        app = NSWorkspace.sharedWorkspace().frontmostApplication()
        return bool(
            app
            and _is_openvoiceflow_host(
                int(app.processIdentifier()),
                app.localizedName(),
                app.bundleIdentifier(),
            )
        )
    except Exception:
        return False


def _settings_pane_for_errors(errors: list[str]) -> tuple[str, str] | None:
    """Pick the one-click System Settings target for a failed validation."""
    joined = " ".join(errors)
    if "Accessibility permission" in joined:
        return (
            "Open Accessibility Settings",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        )
    return None


def _status_line(running: bool, hotkey: str) -> str:
    """Return the concise status row shown below the Listening toggle."""
    if running:
        return f"Ready — Hold {_hotkey_label(hotkey)}"
    return "Listening Paused"


def _usage_instructions(hotkey: str) -> str:
    """Return concise, user-facing instructions for the active hotkey."""
    label = _hotkey_label(hotkey)
    return (
        f"Hold {label} in any text field, speak, then release to paste. "
        "OpenVoiceFlow stays in the menu bar as a waveform icon; click it "
        "for settings and status."
    )


def _show_ready_tip(hotkey: str) -> None:
    """Teach first-time users where the app lives and how to dictate."""
    try:
        from . import notify

        label = _hotkey_label(hotkey)
        notify.tip(
            f"menu bar waveform — hold {label}, speak, release to paste.",
            once_key="menubar_ready_v034",
        )
    except Exception:
        pass


def _system_symbol_image(symbol_name: str, state_label: str):
    """Create a dark-mode-safe SF Symbol image, or return None as fallback."""
    try:
        from AppKit import (
            NSFontWeightRegular,
            NSImage,
            NSImageSymbolConfiguration,
        )

        description = f"OpenVoiceFlow — {state_label}"
        image = NSImage.imageWithSystemSymbolName_accessibilityDescription_(
            symbol_name,
            description,
        )
        if image is None:
            return None
        config = NSImageSymbolConfiguration.configurationWithPointSize_weight_(
            15.0,
            NSFontWeightRegular,
        )
        configured = image.imageWithSymbolConfiguration_(config)
        if configured is not None:
            image = configured
        image.setTemplate_(True)
        return image
    except Exception:
        return None


def _apply_status_bar_state(app, state: str) -> None:
    """Apply a native status icon while keeping a visible text fallback."""
    symbol_name, state_label = _STATUS_PRESENTATIONS.get(
        state,
        _STATUS_PRESENTATIONS["error"],
    )
    image = _system_symbol_image(symbol_name, state_label)

    app._status_bar_state = state
    app._icon_nsimage = image
    app._title = None if image is not None else "OpenVoiceFlow"

    try:
        app._nsapp.setStatusBarIcon()
        app._nsapp.setStatusBarTitle()
    except Exception:
        return

    try:
        status_item = app._nsapp.nsstatusitem
        button = status_item.button()
        if button is not None:
            button.setToolTip_(f"OpenVoiceFlow — {state_label}")
            button.setAccessibilityLabel_("OpenVoiceFlow")
            button.setAccessibilityValue_(state_label)
        else:
            status_item.setToolTip_(f"OpenVoiceFlow — {state_label}")
    except Exception:
        pass


def _call_on_main_thread(callback, *args) -> None:
    """Schedule UI work on AppKit's main thread when PyObjC is available."""
    try:
        from PyObjCTools import AppHelper

        AppHelper.callAfter(callback, *args)
    except Exception:
        callback(*args)


def _call_on_main_thread_later(
    delay: float,
    callback,
    *args,
) -> None:
    """Let AppKit paint the status item before potentially slow startup."""
    try:
        from PyObjCTools import AppHelper

        AppHelper.callLater(delay, callback, *args)
    except Exception:
        callback(*args)


def _open_url(url: str) -> None:
    """Open a web or System Settings URL using the macOS default handler."""
    import subprocess

    subprocess.Popen(["open", url])


def run_menubar():
    """Launch OpenVoiceFlow as a menu bar app."""
    if rumps is None:
        print("❌ rumps not installed. Install with: pip install rumps")
        print("   Falling back to CLI mode...")
        from .app import OpenVoiceFlow

        OpenVoiceFlow().run()
        return

    from .app import OpenVoiceFlow
    from .config import (
        CONFIG_PATH,
        VALID_BACKENDS,
        VALID_STYLES,
        load_config,
        save_config,
    )
    from .stats import load_stats

    _configure_macos_application(
        bool(load_config().get("show_dock_icon", True))
    )

    def make_item(item_id: str, callback=None):
        title, key = _MENU_ITEM_SPECS[item_id]
        return rumps.MenuItem(title, callback=callback, key=key)

    class OpenVoiceFlowMenuBar(rumps.App):
        def __init__(self):
            super().__init__(
                "OpenVoiceFlow",
                title="OpenVoiceFlow",
                quit_button=None,
            )
            self.vf = None
            self.listener = None
            self.config = load_config()
            self._running = False
            self._checking_for_updates = False
            self.context_timer = rumps.Timer(
                self._refresh_detected_app,
                _CONTEXT_REFRESH_SECONDS,
            )
            _apply_status_bar_state(self, "starting")
            rumps.events.before_start.register(self._finish_status_bar_setup)

            self.open_item = make_item("open", self.open_app)
            self.listening_item = make_item("listening", self.toggle)
            _set_checked(self.listening_item, False)

            self.status_item = make_item("status")
            self.status_item.set_callback(None)
            self.detected_app_item = make_item("detected_app")
            self.detected_app_item.set_callback(None)

            self.hotkey_menu = make_item("shortcut")
            self.backend_menu = make_item("backend")
            self.style_menu = make_item("style")

            self.personalization_menu = make_item("personalization")
            self.auto_style_item = rumps.MenuItem(
                "Automatic App Style",
                callback=self.toggle_auto_style,
            )
            _set_checked(
                self.auto_style_item,
                self.config.get("auto_style", True),
            )
            self.auto_learn_item = rumps.MenuItem(
                "Learn Corrections",
                callback=self.toggle_auto_learn,
            )
            _set_checked(
                self.auto_learn_item,
                self.config.get("auto_learn", False),
            )
            self.dictionary_item = rumps.MenuItem(
                "Personal Dictionary",
                callback=self.open_dictionary,
            )
            self.snippets_item = rumps.MenuItem(
                "Voice Snippets",
                callback=self.open_snippets,
            )
            self.profile_item = rumps.MenuItem(
                "Edit Profile…",
                callback=self.open_profile,
            )
            for item in (
                self.auto_style_item,
                self.auto_learn_item,
                None,
                self.dictionary_item,
                self.snippets_item,
                self.profile_item,
            ):
                self.personalization_menu.add(item)

            self.advanced_menu = make_item("advanced")
            self.streaming_item = rumps.MenuItem(
                "Streaming Transcription",
                callback=self.toggle_streaming,
            )
            _set_checked(
                self.streaming_item,
                self.config.get("streaming", False),
            )
            self.autostart_item = rumps.MenuItem(
                "Launch at Login",
                callback=self.toggle_autostart,
            )
            _set_checked(self.autostart_item, self._autostart_enabled())
            self.dock_icon_item = rumps.MenuItem(
                "Show in Dock",
                callback=self.toggle_dock_icon,
            )
            _set_checked(
                self.dock_icon_item,
                bool(self.config.get("show_dock_icon", True)),
            )
            advanced_items = (
                self.streaming_item,
                self.autostart_item,
                self.dock_icon_item,
                None,
                rumps.MenuItem(
                    "Microphone Settings…",
                    callback=self.open_microphone_settings,
                ),
                rumps.MenuItem(
                    "Accessibility Settings…",
                    callback=self.open_accessibility_settings,
                ),
                None,
                rumps.MenuItem(
                    "Open Configuration File",
                    callback=self.open_config,
                ),
                rumps.MenuItem(
                    "Show Logs in Finder",
                    callback=self.open_logs,
                ),
            )
            for item in advanced_items:
                self.advanced_menu.add(item)

            self.stats_item = make_item("stats", self.show_stats)
            self.usage_item = make_item("usage", self.show_usage)
            self.check_updates_item = make_item(
                "updates",
                self.check_for_updates,
            )
            self.quit_item = make_item("quit", self.quit_app)

            menu_items = {
                "open": self.open_item,
                "listening": self.listening_item,
                "status": self.status_item,
                "detected_app": self.detected_app_item,
                "shortcut": self.hotkey_menu,
                "backend": self.backend_menu,
                "style": self.style_menu,
                "personalization": self.personalization_menu,
                "advanced": self.advanced_menu,
                "stats": self.stats_item,
                "usage": self.usage_item,
                "updates": self.check_updates_item,
                "quit": self.quit_item,
            }
            self.menu = [
                None if item_id is None else menu_items[item_id]
                for item_id in _MAIN_MENU_LAYOUT
            ]

            self._build_backend_menu()
            self._build_hotkey_menu()
            self._build_style_menu()
            self._update_detected_app()

            try:
                from .updater import check_for_updates

                check_for_updates(
                    config=self.config,
                    on_update_available=self._on_update_available,
                )
            except Exception:
                pass

        # ── Native status item ─────────────────────────────────────────────

        def _finish_status_bar_setup(self):
            """Apply accessibility metadata after rumps creates NSStatusItem."""
            _apply_status_bar_state(self, self._status_bar_state)
            if not self.context_timer.is_alive():
                self.context_timer.start()
            _call_on_main_thread_later(
                _LISTENER_START_DELAY_SECONDS,
                self._start_listening_safely,
            )

        # ── Menu builders ──────────────────────────────────────────────────

        def _build_backend_menu(self):
            """Rebuild the AI cleanup submenu with a native selected state."""
            _clear_submenu(self.backend_menu)
            current_backend = self.config.get("llm_backend", "openrouter")
            for name in VALID_BACKENDS:
                item = rumps.MenuItem(
                    _backend_label(name),
                    callback=lambda sender, n=name: self.set_backend(sender, n),
                )
                _set_checked(item, name == current_backend)
                self.backend_menu.add(item)

        def _build_hotkey_menu(self):
            """Rebuild the shortcut submenu with every supported hotkey."""
            _clear_submenu(self.hotkey_menu)
            current_hotkey = self.config.get("hotkey", "right_cmd")
            for hotkey, label, checked in _hotkey_choices(current_hotkey):
                item = rumps.MenuItem(
                    label,
                    callback=lambda sender, h=hotkey: self.set_hotkey(sender, h),
                )
                _set_checked(item, checked)
                self.hotkey_menu.add(item)

        def _build_style_menu(self):
            """Rebuild the writing-style submenu with native checkmarks."""
            _clear_submenu(self.style_menu)
            current_style = self.config.get("style", "default")
            for style_id in VALID_STYLES:
                item = rumps.MenuItem(
                    _style_label(style_id),
                    callback=lambda sender, s=style_id: self.set_style(sender, s),
                )
                _set_checked(item, style_id == current_style)
                self.style_menu.add(item)

        def _autostart_enabled(self) -> bool:
            try:
                from .autostart import get_autostart_status

                return get_autostart_status()
            except Exception:
                return self.config.get("launch_at_login", False)

        def _update_detected_app(self):
            """Refresh the current-app status item after starting listening."""
            if _frontmost_app_is_current_process():
                return
            try:
                from .context import get_frontmost_app, get_style_for_app

                app = get_frontmost_app()
                if app:
                    style = get_style_for_app(app, self.config)
                    self.detected_app_item.title = (
                        f"Current App: {app} · {_style_label(style)}"
                    )
                else:
                    self.detected_app_item.title = "Current App: —"
            except Exception:
                self.detected_app_item.title = "Current App: —"

        def _refresh_detected_app(self, _timer):
            """Keep the displayed app/style current as the user switches apps."""
            self._update_detected_app()

        # ── Listener lifecycle ─────────────────────────────────────────────

        def _start_listening_safely(self):
            """Start the listener without leaving the menu stuck on Starting."""
            if self._running:
                return
            try:
                self.start_listening()
            except Exception as exc:
                import sys

                try:
                    if self.listener:
                        self.listener.stop()
                except Exception:
                    pass
                self.listener = None
                self._abort_active_dictation()
                self._running = False
                _set_checked(self.listening_item, False)
                _apply_status_bar_state(self, "error")
                self.status_item.title = "Unable to Start"
                sys.stderr.write(f"OpenVoiceFlow menu startup failed: {exc}\n")
                _show_alert(
                    title="OpenVoiceFlow Could Not Start",
                    message=(
                        "The listening service could not start. Open the "
                        f"Advanced menu to review settings and logs.\n\n{exc}"
                    ),
                    ok="OK",
                )

        def _present_setup_errors(self):
            """Surface validation failures front-and-center.

            Notifications need a permission of their own and the status
            item can hide behind a MacBook notch, so a failed setup uses a
            modal alert — the one channel that is always visible.
            """
            errors = list(getattr(self.vf, "setup_errors", None) or [])
            details = "\n".join(f"• {e}" for e in errors) or (
                "Run `openvoiceflow --doctor` in Terminal for a full report."
            )
            pane = _settings_pane_for_errors(errors)
            if pane is None:
                _show_alert(
                    title="OpenVoiceFlow — Setup Required",
                    message=f"Dictation can't start yet:\n\n{details}",
                    ok="OK",
                )
                return
            pane_label, pane_url = pane
            result = _show_alert(
                title="OpenVoiceFlow — Setup Required",
                message=f"Dictation can't start yet:\n\n{details}",
                ok=pane_label,
                cancel="Later",
            )
            if _alert_confirmed(result):
                _open_url(pane_url)

        def _present_dead_hotkey_alert(self, message):
            """Modal alert from the dead-listener watchdog (daemon thread)."""
            def _show():
                _apply_status_bar_state(self, "error")
                self.status_item.title = "Check Input Monitoring"
                result = _show_alert(
                    title="OpenVoiceFlow — Hotkey Not Working",
                    message=message,
                    ok="Open Input Monitoring Settings",
                    cancel="Later",
                )
                if _alert_confirmed(result):
                    _open_url(
                        "x-apple.systempreferences:com.apple.preference."
                        "security?Privacy_ListenEvent"
                    )

            _call_on_main_thread(_show)

        def start_listening(self):
            self.vf = OpenVoiceFlow()
            if not self.vf.validate_setup():
                self._running = False
                _set_checked(self.listening_item, False)
                _apply_status_bar_state(self, "error")
                self.status_item.title = "Setup Required"
                self._present_setup_errors()
                return

            try:
                from pynput.keyboard import Listener
            except Exception as exc:
                self._running = False
                _set_checked(self.listening_item, False)
                _apply_status_bar_state(self, "error")
                self.status_item.title = "Keyboard Listener Unavailable"
                _show_notification(
                    "OpenVoiceFlow",
                    "Keyboard Listener Error",
                    f"Could not start the shortcut listener ({exc}). Reinstall pynput.",
                )
                return

            self.listener = Listener(
                on_press=self.vf.on_key_press,
                on_release=self.vf.on_key_release,
            )
            self.listener.start()
            self.vf.start_hotkey_runtime_checks(
                on_dead_hotkey=self._present_dead_hotkey_alert,
            )
            self._running = True
            _set_checked(self.listening_item, True)
            _apply_status_bar_state(self, "ready")
            if self.config.get("sound_feedback", True):
                play_sound("done")
            hotkey = self.config.get("hotkey", "right_cmd")
            self.status_item.title = _status_line(True, hotkey)
            _show_ready_tip(hotkey)
            self._update_detected_app()

        def _abort_active_dictation(self):
            """Stop any in-flight recording so mic/whisper-stream aren't orphaned."""
            vf = self.vf
            if not vf:
                return
            try:
                vf.is_recording = False
                if vf._streamer:
                    vf._streamer.stop()
                    vf._streamer = None
                    vf._streaming_active = False
                elif vf.recorder and vf.recorder.is_recording:
                    vf.recorder.stop()
                watcher = getattr(vf, "_watcher", None)
                if watcher:
                    watcher.stop()
                    vf._watcher = None
            except Exception:
                pass

        def stop_listening(self):
            if self.listener:
                self.listener.stop()
                self.listener = None
            self._abort_active_dictation()
            self._running = False
            _set_checked(self.listening_item, False)
            _apply_status_bar_state(self, "paused")
            hotkey = self.config.get("hotkey", "right_cmd")
            self.status_item.title = _status_line(False, hotkey)

        def toggle(self, _):
            if self._running:
                self.stop_listening()
            else:
                self._start_listening_safely()

        # ── Settings handlers ──────────────────────────────────────────────

        def set_backend(self, _sender, name):
            self.config["llm_backend"] = name
            save_config(self.config)
            self._build_backend_menu()
            if self._running:
                self.stop_listening()
                self._start_listening_safely()
            _show_notification(
                "OpenVoiceFlow",
                "AI Cleanup Changed",
                f"Now using {_backend_label(name)}.",
            )

        def set_hotkey(self, _sender, hotkey):
            self.config["hotkey"] = hotkey
            save_config(self.config)
            self._build_hotkey_menu()
            if self._running:
                self.stop_listening()
                self._start_listening_safely()
            _show_notification(
                "OpenVoiceFlow",
                "Dictation Shortcut Changed",
                f"Now using {_hotkey_label(hotkey)}.",
            )

        def set_style(self, _sender, style_id):
            self.config["style"] = style_id
            save_config(self.config)
            self._build_style_menu()
            if self._running:
                self.stop_listening()
                self._start_listening_safely()
            _show_notification(
                "OpenVoiceFlow",
                "Writing Style Changed",
                f"Now using {_style_label(style_id)}.",
            )

        def _set_config_flag(self, key: str, value: bool):
            """Persist a config flag and propagate it to the live instance."""
            self.config[key] = value
            save_config(self.config)
            if self.vf:
                self.vf.config[key] = value

        def toggle_streaming(self, _):
            current = self.config.get("streaming", False)
            enabled = not current
            self._set_config_flag("streaming", enabled)
            _set_checked(self.streaming_item, enabled)
            state = "enabled" if enabled else "disabled"
            _show_notification(
                "OpenVoiceFlow",
                "Streaming Transcription",
                f"Streaming transcription {state}.",
            )

        def toggle_auto_style(self, _):
            current = self.config.get("auto_style", True)
            enabled = not current
            self._set_config_flag("auto_style", enabled)
            _set_checked(self.auto_style_item, enabled)
            state = "enabled" if enabled else "disabled"
            _show_notification(
                "OpenVoiceFlow",
                "Automatic App Style",
                f"Automatic per-app style {state}.",
            )

        def toggle_auto_learn(self, _):
            current = self.config.get("auto_learn", False)
            enabled = not current
            self._set_config_flag("auto_learn", enabled)
            _set_checked(self.auto_learn_item, enabled)
            state = "enabled" if enabled else "disabled"
            _show_notification(
                "OpenVoiceFlow",
                "Learn Corrections",
                f"Correction learning {state}.",
            )

        # ── User-facing panels ─────────────────────────────────────────────

        def open_app(self, _):
            """Open a native status summary for the otherwise windowless app."""
            from . import __version__

            hotkey = self.config.get("hotkey", "right_cmd")
            backend = self.config.get("llm_backend", "openrouter")
            style = self.config.get("style", "default")
            message = (
                f"{self.status_item.title}\n\n"
                f"Dictation Shortcut: {_hotkey_label(hotkey)}\n"
                f"AI Cleanup: {_backend_label(backend)}\n"
                f"Writing Style: {_style_label(style)}\n\n"
                f"{_usage_instructions(hotkey)}"
            )
            _show_alert(
                title=f"OpenVoiceFlow {__version__}",
                message=message,
                ok="Done",
            )

        def show_usage(self, _):
            hotkey = self.config.get("hotkey", "right_cmd")
            _show_alert(
                title="How to Use OpenVoiceFlow",
                message=_usage_instructions(hotkey),
            )

        def show_stats(self, _):
            stats = load_stats()
            total = stats["total_dictations"]
            words = stats["total_words"]
            seconds = stats["total_seconds_recorded"]
            typing_min_saved = words / 40.0 if words else 0
            message = (
                f"Dictations: {total}\n"
                f"Words: {words:,}\n"
                f"Recorded: {seconds / 60:.1f} min\n"
                f"Time saved: about {typing_min_saved:.0f} min"
            )
            _show_alert(title="OpenVoiceFlow Statistics", message=message)

        def open_dictionary(self, _):
            try:
                from .dictionary import list_words

                words = list_words()
            except Exception:
                words = []

            if words:
                message = "\n".join(f"• {word}" for word in words)
                message += "\n\nAdd words with: openvoiceflow --add-word MyWord"
            else:
                message = "No words yet.\n\nAdd with: openvoiceflow --add-word MyWord"
            _show_alert(title="Personal Dictionary", message=message)

        def open_snippets(self, _):
            try:
                from .snippets import list_snippets

                snippets = list_snippets()
            except Exception:
                snippets = {}

            if snippets:
                lines = [
                    f"\"{trigger}\" → \"{expansion[:40]}"
                    f"{'...' if len(expansion) > 40 else ''}\""
                    for trigger, expansion in snippets.items()
                ]
                message = "\n".join(lines)
                message += (
                    "\n\nAdd with: openvoiceflow --add-snippet "
                    "\"trigger\" \"expansion\""
                )
            else:
                message = (
                    "No snippets yet.\n\nAdd with: openvoiceflow --add-snippet "
                    "\"insert signature\" \"Best regards\""
                )
            _show_alert(title="Voice Snippets", message=message)

        def open_profile(self, _):
            try:
                import subprocess

                subprocess.Popen(_profile_interview_command())
            except Exception as exc:
                _show_alert(title="Profile Error", message=str(exc))

        def toggle_dock_icon(self, _):
            enabled = not bool(self.config.get("show_dock_icon", True))
            self.config["show_dock_icon"] = enabled
            save_config(self.config)
            _set_checked(self.dock_icon_item, enabled)
            _apply_activation_policy(enabled)
            if enabled:
                _install_dock_activation_handler(self)

        def toggle_autostart(self, _):
            try:
                from .autostart import get_autostart_status, set_autostart

                current = get_autostart_status()
                success, message = set_autostart(not current)
                if success:
                    enabled = not current
                    self.config["launch_at_login"] = enabled
                    save_config(self.config)
                    _set_checked(self.autostart_item, enabled)
                    state = "enabled" if enabled else "disabled"
                    _show_notification(
                        "OpenVoiceFlow",
                        "Launch at Login",
                        f"Launch at Login {state}.",
                    )
                else:
                    _show_alert(title="Launch at Login Error", message=message)
            except Exception as exc:
                _show_alert(title="Launch at Login Error", message=str(exc))

        # ── File and settings openers ──────────────────────────────────────

        def open_microphone_settings(self, _):
            _open_url(
                "x-apple.systempreferences:com.apple.preference.security?"
                "Privacy_Microphone"
            )

        def open_accessibility_settings(self, _):
            _open_url(
                "x-apple.systempreferences:com.apple.preference.security?"
                "Privacy_Accessibility"
            )

        def open_config(self, _):
            _open_url(str(CONFIG_PATH))

        def open_logs(self, _):
            from .config import LOG_DIR

            LOG_DIR.mkdir(parents=True, exist_ok=True)
            _open_url(str(LOG_DIR))

        # ── Update handlers ────────────────────────────────────────────────

        def _on_update_available(self, latest_version: str, release_url: str):
            _call_on_main_thread(
                self._show_update_notification,
                latest_version,
                release_url,
            )

        def _show_update_notification(self, latest_version: str, release_url: str):
            from . import __version__

            _show_notification(
                "OpenVoiceFlow Update Available",
                f"Version {latest_version} is available; you have {__version__}.",
                release_url,
            )

        def check_for_updates(self, _):
            if self._checking_for_updates:
                return
            self._checking_for_updates = True
            self.check_updates_item.title = "Checking for Updates…"
            try:
                from .updater import check_for_updates_now

                check_for_updates_now(self._on_manual_update_result)
            except Exception:
                self._show_manual_update_result("error", "", "")

        def _on_manual_update_result(
            self,
            status: str,
            latest_version: str,
            release_url: str,
        ):
            _call_on_main_thread(
                self._show_manual_update_result,
                status,
                latest_version,
                release_url,
            )

        def _show_manual_update_result(
            self,
            status: str,
            latest_version: str,
            release_url: str,
        ):
            from . import __version__

            self._checking_for_updates = False
            self.check_updates_item.title = _MENU_ITEM_SPECS["updates"][0]
            if status == "available":
                result = _show_alert(
                    title="OpenVoiceFlow Update Available",
                    message=(
                        f"Version {latest_version} is available. "
                        f"You currently have version {__version__}."
                    ),
                    ok="Download",
                    cancel="Later",
                )
                if _alert_confirmed(result):
                    _open_url(release_url)
            elif status == "current":
                _show_alert(
                    title="OpenVoiceFlow Is Up to Date",
                    message=f"You have the latest version ({__version__}).",
                    ok="OK",
                )
            else:
                _show_alert(
                    title="Unable to Check for Updates",
                    message=(
                        "OpenVoiceFlow could not reach the update service. "
                        "Please check your internet connection and try again."
                    ),
                    ok="OK",
                )

        def quit_app(self, _):
            if self.context_timer.is_alive():
                self.context_timer.stop()
            self.stop_listening()
            rumps.quit_application()

    app = OpenVoiceFlowMenuBar()
    if bool(app.config.get("show_dock_icon", True)):
        _install_dock_activation_handler(app)
    app.run()
