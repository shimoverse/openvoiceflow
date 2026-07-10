from __future__ import annotations

import inspect
from pathlib import Path
from types import SimpleNamespace

import pytest


class FakeMenu:
    def __init__(self, initialized: bool) -> None:
        self._menu = object() if initialized else None
        self.clear_calls = 0

    def clear(self) -> None:
        self.clear_calls += 1


def test_clear_submenu_skips_uninitialized_rumps_menu() -> None:
    from voiceflow.menubar import _clear_submenu

    menu = FakeMenu(initialized=False)
    _clear_submenu(menu)

    assert menu.clear_calls == 0


def test_clear_submenu_clears_initialized_rumps_menu() -> None:
    from voiceflow.menubar import _clear_submenu

    menu = FakeMenu(initialized=True)
    _clear_submenu(menu)

    assert menu.clear_calls == 1


def test_ready_tip_teaches_menu_bar_hotkey(monkeypatch) -> None:
    import voiceflow.notify as notify
    from voiceflow.menubar import _show_ready_tip

    calls = []
    monkeypatch.setattr(
        notify,
        "tip",
        lambda message, **kwargs: calls.append((message, kwargs)),
    )

    _show_ready_tip("right_cmd")

    assert len(calls) == 1
    assert "menu bar" in calls[0][0]
    assert "Right Command" in calls[0][0]
    assert len(calls[0][0]) <= 72
    assert calls[0][1]["once_key"] == "menubar_ready_v034"


def test_usage_instructions_explain_menu_bar_and_hotkey() -> None:
    from voiceflow.menubar import _usage_instructions

    message = _usage_instructions("right_cmd")

    assert "menu bar" in message
    assert "Right Command (⌘)" in message
    assert "hold" in message.lower()
    assert "release" in message.lower()
    assert "waveform icon" in message
    assert "🎙️✅" not in message


def test_main_menu_is_branded_and_uses_standard_shortcuts() -> None:
    from voiceflow.menubar import _MAIN_MENU_LAYOUT, _MENU_ITEM_SPECS

    visible_ids = [item_id for item_id in _MAIN_MENU_LAYOUT if item_id is not None]

    assert visible_ids[0] == "open"
    assert _MENU_ITEM_SPECS["open"] == ("Open OpenVoiceFlow", None)
    assert visible_ids[-1] == "quit"
    assert _MENU_ITEM_SPECS["quit"] == ("Quit OpenVoiceFlow", "q")
    assert _MAIN_MENU_LAYOUT.count(None) >= 4


def test_informational_panels_do_not_use_input_ellipsis() -> None:
    from voiceflow.menubar import _MENU_ITEM_SPECS

    assert _MENU_ITEM_SPECS["stats"][0] == "Usage Statistics"
    assert _MENU_ITEM_SPECS["usage"][0] == "How to Use"


def test_menu_labels_are_native_text_without_emoji_or_manual_checkmarks() -> None:
    from voiceflow.menubar import _MENU_ITEM_SPECS

    labels = [title for title, _key in _MENU_ITEM_SPECS.values()]
    forbidden = ("✓", "🎙", "✅", "❌", "▶", "⏸", "📊", "📖", "📌", "👤", "❓")

    assert all(not any(marker in label for marker in forbidden) for label in labels)


def test_hotkey_menu_offers_every_supported_shortcut_with_human_labels() -> None:
    from voiceflow.config import VALID_HOTKEYS
    from voiceflow.menubar import _hotkey_choices

    choices = _hotkey_choices("right_cmd")

    assert [choice[0] for choice in choices] == VALID_HOTKEYS
    assert dict((hotkey, label) for hotkey, label, _checked in choices)["right_cmd"] == "Right Command (⌘)"
    assert dict((hotkey, label) for hotkey, label, _checked in choices)["f12"] == "F12"
    assert sum(checked for _hotkey, _label, checked in choices) == 1
    assert all(not label.startswith("✓") for _hotkey, label, _checked in choices)


def test_native_menu_state_is_used_for_checkmarks() -> None:
    from voiceflow.menubar import _set_checked

    class FakeItem:
        state = None

    item = FakeItem()
    _set_checked(item, True)
    assert item.state == 1

    _set_checked(item, False)
    assert item.state == 0


def test_native_alert_download_button_is_recognized() -> None:
    from voiceflow.menubar import _alert_confirmed

    assert _alert_confirmed(1000) is True
    assert _alert_confirmed(1) is True
    assert _alert_confirmed(1001) is False
    assert _alert_confirmed(0) is False


def test_profile_interview_runs_in_an_isolated_python_process() -> None:
    from voiceflow.menubar import _profile_interview_command

    command = _profile_interview_command("/test/python")

    assert command[:2] == ["/test/python", "-c"]
    assert "from voiceflow.interview import run_interview" in command[2]
    assert "run_interview()" in command[2]


def test_packaged_app_icon_is_discovered_from_launcher_environment(
    monkeypatch,
    tmp_path,
) -> None:
    from voiceflow.menubar import _app_icon_path

    icon = tmp_path / "OpenVoiceFlow.icns"
    icon.write_bytes(b"icon")
    monkeypatch.setenv("OPENVOICEFLOW_APP_RESOURCES", str(tmp_path))

    assert _app_icon_path() == str(icon)


def test_alerts_and_notifications_use_the_branded_app_icon(monkeypatch) -> None:
    import voiceflow.menubar as menubar

    alerts = []
    notifications = []
    fake_rumps = SimpleNamespace(
        alert=lambda **kwargs: alerts.append(kwargs) or 1000,
        notification=lambda *args, **kwargs: notifications.append((args, kwargs)),
    )
    monkeypatch.setattr(menubar, "rumps", fake_rumps)
    monkeypatch.setattr(
        menubar,
        "_app_icon_path",
        lambda: "/Applications/OpenVoiceFlow.app/Contents/Resources/OpenVoiceFlow.icns",
    )

    assert menubar._show_alert(title="OpenVoiceFlow", message="Ready") == 1000
    menubar._show_notification("OpenVoiceFlow", "Ready", "Listening")

    assert alerts[0]["icon_path"].endswith("OpenVoiceFlow.icns")
    assert notifications[0][1]["icon"].endswith("OpenVoiceFlow.icns")


def test_current_app_status_has_a_lightweight_refresh_interval() -> None:
    from voiceflow.menubar import (
        _CONTEXT_REFRESH_SECONDS,
        _LISTENER_START_DELAY_SECONDS,
        _is_current_process,
        _is_openvoiceflow_host,
    )

    assert 1 <= _CONTEXT_REFRESH_SECONDS <= 5
    assert 0 < _LISTENER_START_DELAY_SECONDS <= 0.5
    assert _is_current_process(420, current_process_id=420) is True
    assert _is_current_process(421, current_process_id=420) is False
    assert _is_openvoiceflow_host(421, "Python", "com.apple.python3", 420) is True
    assert _is_openvoiceflow_host(421, "OpenVoiceFlow", "com.openvoiceflow.dictation", 420) is True
    assert _is_openvoiceflow_host(421, "TextEdit", "com.apple.TextEdit", 420) is False


def test_status_line_uses_the_human_shortcut_name() -> None:
    from voiceflow.menubar import _status_line

    assert _status_line(True, "right_cmd") == "Ready — Hold Right Command (⌘)"
    assert _status_line(False, "right_cmd") == "Listening Paused"


def test_status_bar_states_have_accessible_native_symbol_presentations() -> None:
    from voiceflow.menubar import _STATUS_PRESENTATIONS

    assert _STATUS_PRESENTATIONS["ready"] == ("waveform", "Ready")
    assert _STATUS_PRESENTATIONS["paused"][0] == "pause.circle"
    assert _STATUS_PRESENTATIONS["error"][0] == "exclamationmark.triangle"
    assert all(label and label.isascii() for _symbol, label in _STATUS_PRESENTATIONS.values())


def test_status_bar_uses_native_image_without_duplicate_text(monkeypatch) -> None:
    import voiceflow.menubar as menubar

    image = object()
    monkeypatch.setattr(menubar, "_system_symbol_image", lambda *_args: image)

    class FakeApp:
        pass

    app = FakeApp()
    menubar._apply_status_bar_state(app, "ready")

    assert app._icon_nsimage is image
    assert app._title is None
    assert app._status_bar_state == "ready"


def test_status_bar_has_visible_text_fallback_when_symbols_fail(monkeypatch) -> None:
    import voiceflow.menubar as menubar

    monkeypatch.setattr(menubar, "_system_symbol_image", lambda *_args: None)

    class FakeApp:
        pass

    app = FakeApp()
    menubar._apply_status_bar_state(app, "error")

    assert app._icon_nsimage is None
    assert app._title == "OpenVoiceFlow"
    assert app._status_bar_state == "error"


def test_runtime_no_longer_replaces_the_app_identity_with_status_emoji() -> None:
    from voiceflow.menubar import run_menubar

    source = inspect.getsource(run_menubar)

    assert "self.title =" not in source
    assert "🎙️✅" not in source
    assert "before_start.unregister" not in source
    assert "_call_on_main_thread_later(" in source
    assert "self._start_listening_safely" in source


def test_readme_explains_the_branded_menu_bar_experience() -> None:
    readme = (Path(__file__).resolve().parent.parent / "README.md").read_text()

    assert "waveform icon" in readme
    assert "Open OpenVoiceFlow" in readme
    assert "Check for Updates" in readme
    assert "🎙️✅" not in readme


def test_real_rumps_constructor_builds_the_branded_menu(
    monkeypatch,
    tmp_path,
) -> None:
    import voiceflow.app as app_module
    import voiceflow.autostart as autostart
    import voiceflow.config as config
    import voiceflow.context as context
    import voiceflow.menubar as menubar
    import voiceflow.updater as updater

    if menubar.rumps is None:
        pytest.skip("rumps is an optional macOS dependency")

    captured = {}
    alerts = []

    class FakeVoiceFlow:
        def __init__(self) -> None:
            self.config = {}

    monkeypatch.setattr(app_module, "OpenVoiceFlow", FakeVoiceFlow)
    monkeypatch.setattr(config, "load_config", lambda: dict(config.DEFAULTS))
    monkeypatch.setattr(config, "save_config", lambda _config: None)
    monkeypatch.setattr(autostart, "get_autostart_status", lambda: False)
    monkeypatch.setattr(context, "get_frontmost_app", lambda: "TextEdit")
    monkeypatch.setattr(context, "get_style_for_app", lambda *_args: "default")
    monkeypatch.setattr(updater, "check_for_updates", lambda **_kwargs: None)
    monkeypatch.setattr(menubar, "_configure_macos_application", lambda: None)
    monkeypatch.setattr(menubar, "_frontmost_app_is_current_process", lambda: False)
    monkeypatch.setattr(
        menubar.rumps,
        "alert",
        lambda **kwargs: alerts.append(kwargs),
    )
    monkeypatch.setattr(menubar.rumps.rumps, "application_support", lambda _name: str(tmp_path))
    monkeypatch.setattr(
        menubar.rumps.App,
        "run",
        lambda app, **_kwargs: captured.setdefault("app", app),
    )

    menubar.run_menubar()
    app = captured["app"]
    visible_titles = [
        item.title
        for item in app.menu.values()
        if hasattr(item, "title")
    ]

    assert visible_titles[0] == "Open OpenVoiceFlow"
    assert visible_titles[-1] == "Quit OpenVoiceFlow"
    assert app.quit_item.key == "q"
    assert app.open_item.callback.__self__ is app
    assert app.quit_item.callback.__self__ is app
    assert sum(item.state == 1 for item in app.hotkey_menu.values()) == 1
    assert sum(item.state == 1 for item in app.backend_menu.values()) == 1
    assert sum(item.state == 1 for item in app.style_menu.values()) == 1
    assert app.detected_app_item.title == "Current App: TextEdit · Default"

    app._start_listening_safely()

    assert app._status_bar_state == "error"
    assert app.status_item.title == "Unable to Start"
    assert app.listening_item.state == 0
    assert alerts[-1]["title"] == "OpenVoiceFlow Could Not Start"
    assert alerts[-1]["icon_path"].endswith("OpenVoiceFlow.icns")

    menubar.rumps.events.before_start.unregister(app._finish_status_bar_setup)
