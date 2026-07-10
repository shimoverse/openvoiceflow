from __future__ import annotations


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
    assert calls[0][1]["once_key"] == "menubar_ready_v033"


def test_usage_instructions_explain_menu_bar_and_hotkey() -> None:
    from voiceflow.menubar import _usage_instructions

    message = _usage_instructions("right_cmd")

    assert "menu bar" in message
    assert "Right Command (⌘)" in message
    assert "hold" in message.lower()
    assert "release" in message.lower()
