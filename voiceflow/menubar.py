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
    from .config import load_config, save_config, CONFIG_PATH
    from .llm import BACKENDS

    class OpenVoiceFlowMenuBar(rumps.App):
        def __init__(self):
            super().__init__("🎙️", quit_button=None)
            self.vf = None
            self.listener = None
            self.config = load_config()
            self._running = False

            # Build menu
            self.start_stop_item = rumps.MenuItem("▶ Start Listening", callback=self.toggle)
            self.status_item = rumps.MenuItem("Status: Stopped")
            self.status_item.set_callback(None)

            # Backend submenu
            self.backend_menu = rumps.MenuItem("LLM Backend")
            self._build_backend_menu()

            # Hotkey submenu
            self.hotkey_menu = rumps.MenuItem("Hotkey")
            self._build_hotkey_menu()

            self.menu = [
                self.start_stop_item,
                self.status_item,
                None,  # separator
                self.backend_menu,
                self.hotkey_menu,
                None,
                rumps.MenuItem("Open Config", callback=self.open_config),
                rumps.MenuItem("View Logs", callback=self.open_logs),
                None,
                rumps.MenuItem("Quit", callback=self.quit_app),
            ]

            # Auto-start
            self.start_listening()

        def _build_backend_menu(self):
            """(Re)build backend submenu with current checkmarks."""
            # Clear existing items
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

        def start_listening(self):
            self.vf = OpenVoiceFlow()
            if not self.vf.validate_setup():
                self.title = "🎙️❌"
                self.status_item.title = "Status: Setup error"
                rumps.notification("OpenVoiceFlow", "Setup Error", "Check config. Click menu bar icon for details.")
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

        def set_backend(self, sender, name):
            self.config["llm_backend"] = name
            save_config(self.config)
            # BUG-016 fix: rebuild backend menu to update checkmarks
            self._build_backend_menu()
            # Restart if running
            if self._running:
                self.stop_listening()
                self.start_listening()
            rumps.notification("OpenVoiceFlow", "Backend Changed", f"Now using: {name}")

        def set_hotkey(self, sender, hotkey):
            self.config["hotkey"] = hotkey
            save_config(self.config)
            # BUG-016 fix: rebuild hotkey menu to update checkmarks
            self._build_hotkey_menu()
            if self._running:
                self.stop_listening()
                self.start_listening()
            rumps.notification("OpenVoiceFlow", "Hotkey Changed", f"Now using: {hotkey}")

        def open_config(self, _):
            import subprocess
            subprocess.Popen(["open", str(CONFIG_PATH)])

        def open_logs(self, _):
            import subprocess
            from .config import LOG_DIR
            LOG_DIR.mkdir(parents=True, exist_ok=True)
            subprocess.Popen(["open", str(LOG_DIR)])

        def quit_app(self, _):
            self.stop_listening()
            rumps.quit_application()

    OpenVoiceFlowMenuBar().run()
