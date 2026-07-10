"""Layout regressions for the floating HUD."""

from __future__ import annotations

from types import SimpleNamespace


class _Window:
    def __init__(self) -> None:
        self.frame = None

    def setFrame_display_(self, frame, display) -> None:
        self.frame = (frame, display)


class _Label:
    def __init__(self) -> None:
        self.frame = None

    def setFrame_(self, frame) -> None:
        self.frame = frame


def test_resize_updates_window_and_label(monkeypatch) -> None:
    import voiceflow.overlay as overlay_module

    screen = SimpleNamespace(
        frame=lambda: SimpleNamespace(size=SimpleNamespace(width=1000)),
    )
    monkeypatch.setattr(
        overlay_module,
        "NSScreen",
        SimpleNamespace(mainScreen=lambda: screen),
        raising=False,
    )
    monkeypatch.setattr(
        overlay_module,
        "NSMakeRect",
        lambda x, y, width, height: (x, y, width, height),
        raising=False,
    )

    hud = object.__new__(overlay_module.FloatingOverlay)
    hud._window = _Window()
    hud._label = _Label()

    hud._resize(650)

    assert hud._window.frame == ((175, 80, 650, 40), True)
    assert hud._label.frame == (10, 5, 630, 30)
