"""OpenVoiceFlow macOS menu bar app using rumps."""
import sys
import threading

try:
    import rumps
except ImportError:
    rumps = None


def run_menubar():
    """Launch OpenVoiceFlow as a menu bar app."""
    if rumps is None:
        print("❌ rumps not installed. Install with: pip install rumps")
        print("   Falling back to CLI mode...")
        from .app import OpenVoiceFlow
        OpenVoiceFlow().run()
        return

    from .app import OpenVoiceFlow
    from .config import load_config, save_config, CONFIG_PATH, VALID_STYLES
    from .llm import BACKENDS
    from .stats import load_stats
    from .styles import get_style_label

    class OpenVoiceFlowMenuBar(rumps.App):
        def __init__(self):
            super().__init__("🎙️", quit_button=None)
            self.vf = None
            self.listener = None
            self.config = load_config()
            self._running = False

            # Build menu items
            self.start_stop_item = rumps.MenuItem("▶ Start Listening", callback=self.toggle)
            self.status_item = rumps.MenuItem("Status: Stopped")
            self.status_item.set_callback(None)

            # Backend submenu
            self.backend_menu = rumps.MenuItem("LLM Backend")
            self._build_backend_menu()

            # Hotkey submenu
            self.hotkey_menu = rumps.MenuItem("Hotkey")
            self._build_hotkey_menu()

            # Style submenu
            self.style_menu = rumps.MenuItem("Style/Tone")
            self._build_style_menu()

            # Stats item
            self.stats_item = rumps.MenuItem("📊 Statistics", callback=self.show_stats)

            # Dictionary item
            self.dictionary_item = rumps.MenuItem("📖 Dictionary", callback=self.open_dictionary)

            # Snippets item
            self.snippets_item = rumps.MenuItem("📌 Snippets", callback=self.open_snippets)

            # Autostart item
            self.autostart_item = rumps.MenuItem(
                self._autostart_label(),
                callback=self.toggle_autostart,
            )

            self.menu = [
                self.start_stop_item,
                self.status_item,
                None,  # separator
                self.backend_menu,
                self.hotkey_menu,
                self.style_menu,
                None,
                self.stats_item,
                self.dictionary_item,
                self.snippets_item,
                None,
                self.autostart_item,
                rumps.MenuItem("Open Config", callback=self.open_config),
                rumps.MenuItem("View Logs", callback=self.open_logs),
                None,
                rumps.MenuItem("Quit", callback=self.quit_app),
            ]

            # Kick off update check in background
            try:
                from .updater import check_for_updates
                check_for_updates(on_update_available=self._on_update_available)
            except Exception:
                pass

            # Auto-start
            self.start_listening()

        # ── Menu builders ──────────────────────────────────────────────────

        def _build_backend_menu(self):
            """(Re)build backend submenu with current checkmarks."""
            self.backend_menu.clear()
            current_backend = self.config.get("llm_backend", "gemini")
            for name in list(BACKENDS.keys()) + ["none"]:
                item = rumps.MenuItem(
                    f"{'✓ ' if name == current_backend else '  '}{name}",
                    callback=lambda sender, n=name: self.set_backend(sender, n),
                )
                self.backend_menu.add(item)

        def _build_hotkey_menu(self):
            """(Re)build hotkey submenu with current checkmarks."""
            self.hotkey_menu.clear()
            current_hotkey = self.config.get("hotkey", "right_cmd")
            for hk in ["right_cmd", "right_alt", "left_alt", "f5", "f6", "f7", "f8"]:
                item = rumps.MenuItem(
                    f"{'✓ ' if hk == current_hotkey else '  '}{hk}",
                    callback=lambda sender, h=hk: self.set_hotkey(sender, h),
                )
                self.hotkey_menu.add(item)

        def _build_style_menu(self):
            """(Re)build style submenu with current checkmarks."""
            self.style_menu.clear()
            current_style = self.config.get("style", "default")
            for style_id in VALID_STYLES:
                label = get_style_label(style_id)
                item = rumps.MenuItem(
                    f"{'✓ ' if style_id == current_style else '  '}{label}",
                    callback=lambda sender, s=style_id: self.set_style(sender, s),
                )
                self.style_menu.add(item)

        def _autostart_label(self) -> str:
            try:
                from .autostart import get_autostart_status
                enabled = get_autostart_status()
            except Exception:
                enabled = self.config.get("launch_at_login", False)
            return "✓ Launch at Login" if enabled else "  Launch at Login"

        # ── Listeners ──────────────────────────────────────────────────────

        def start_listening(self):
            self.vf = OpenVoiceFlow()
            if not self.vf.validate_setup():
                self.title = "🎙️❌"
                self.status_item.title = "Status: Setup error"
                rumps.notification(
                    "OpenVoiceFlow", "Setup Error",
                    "Check config. Click menu bar icon for details.",
                )
                return

            from pynput.keyboard import Listener
            self.listener = Listener(
                on_press=self.vf.on_key_press,
                on_release=self.vf.on_key_release,
            )
            self.listener.start()
            self._running = True
            self.title = "🎙️"
            hotkey = self.config.get("hotkey", "right_cmd")
            self.start_stop_item.title = "⏸ Stop Listening"
            self.status_item.title = f"Status: Ready — hold [{hotkey}]"

        def stop_listening(self):
            if self.listener:
                self.listener.stop()
                self.listener = None
            self._running = False
            self.title = "🎙️💤"
            self.start_stop_item.title = "▶ Start Listening"
            self.status_item.title = "Status: Paused"

        def toggle(self, _):
            if self._running:
                self.stop_listening()
            else:
                self.start_listening()

        # ── Settings handlers ──────────────────────────────────────────────

        def set_backend(self, sender, name):
            self.config["llm_backend"] = name
            save_config(self.config)
            self._build_backend_menu()
            if self._running:
                self.stop_listening()
                self.start_listening()
            rumps.notification("OpenVoiceFlow", "Backend Changed", f"Now using: {name}")

        def set_hotkey(self, sender, hotkey):
            self.config["hotkey"] = hotkey
            save_config(self.config)
            self._build_hotkey_menu()
            if self._running:
                self.stop_listening()
                self.start_listening()
            rumps.notification("OpenVoiceFlow", "Hotkey Changed", f"Now using: {hotkey}")

        def set_style(self, sender, style_id):
            self.config["style"] = style_id
            save_config(self.config)
            self._build_style_menu()
            # Rebuild VoiceFlow instance so LLM backend picks up new style prompt
            if self._running:
                self.stop_listening()
                self.start_listening()
            label = get_style_label(style_id)
            rumps.notification("OpenVoiceFlow", "Style Changed", f"Now using: {label}")

        # ── Feature handlers ───────────────────────────────────────────────

        def show_stats(self, _):
            """Show statistics in a rumps alert dialog."""
            stats = load_stats()
            total = stats["total_dictations"]
            words = stats["total_words"]
            seconds = stats["total_seconds_recorded"]
            typing_min_saved = words / 40.0 if words else 0

            msg = (
                f"Dictations: {total}\n"
                f"Words:       {words:,}\n"
                f"Recorded:    {seconds / 60:.1f} min\n"
                f"Time saved:  ~{typing_min_saved:.0f} min"
            )
            rumps.alert(title="📊 OpenVoiceFlow Stats", message=msg)

        def open_dictionary(self, _):
            """Open a window to view dictionary words, or open config dir."""
            try:
                from .dictionary import list_words
                words = list_words()
            except Exception:
                words = []

            if words:
                msg = "\n".join(f"  • {w}" for w in words)
                msg += "\n\nAdd words: openvoiceflow --add-word \"MyWord\""
            else:
                msg = "No words yet.\n\nAdd with:\nopenvoiceflow --add-word \"MyWord\""
            rumps.alert(title="📖 Personal Dictionary", message=msg)

        def open_snippets(self, _):
            """Show snippet list in a rumps alert dialog."""
            try:
                from .snippets import list_snippets
                snips = list_snippets()
            except Exception:
                snips = {}

            if snips:
                lines = [f"  \"{t}\" → \"{e[:40]}{'...' if len(e)>40 else ''}\"" for t, e in snips.items()]
                msg = "\n".join(lines)
                msg += "\n\nAdd: openvoiceflow --add-snippet \"trigger\" \"expansion\""
            else:
                msg = "No snippets yet.\n\nAdd with:\nopenvoiceflow --add-snippet \"insert sig\" \"Best regards, Name\""
            rumps.alert(title="📌 Voice Snippets", message=msg)

        def toggle_autostart(self, _):
            """Toggle launch at login."""
            try:
                from .autostart import get_autostart_status, set_autostart
                current = get_autostart_status()
                success, msg = set_autostart(not current)
                if success:
                    new_state = not current
                    self.config["launch_at_login"] = new_state
                    save_config(self.config)
                    self.autostart_item.title = self._autostart_label()
                    state_str = "enabled" if new_state else "disabled"
                    rumps.notification("OpenVoiceFlow", "Launch at Login", f"Autostart {state_str}")
                else:
                    rumps.alert(title="Autostart Error", message=msg)
            except Exception as e:
                rumps.alert(title="Autostart Error", message=str(e))

        # ── File openers ───────────────────────────────────────────────────

        def open_config(self, _):
            import subprocess
            subprocess.Popen(["open", str(CONFIG_PATH)])

        def open_logs(self, _):
            import subprocess
            from .config import LOG_DIR
            LOG_DIR.mkdir(parents=True, exist_ok=True)
            subprocess.Popen(["open", str(LOG_DIR)])

        # ── Update handler ─────────────────────────────────────────────────

        def _on_update_available(self, latest_version: str, release_url: str):
            """Called from updater thread when a new version is found."""
            from . import __version__
            rumps.notification(
                "OpenVoiceFlow Update Available",
                f"v{latest_version} is available (you have v{__version__})",
                f"Visit: {release_url}",
            )

        def quit_app(self, _):
            self.stop_listening()
            rumps.quit_application()

    OpenVoiceFlowMenuBar().run()
