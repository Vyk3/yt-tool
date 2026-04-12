from __future__ import annotations

from app.gui import main as gui_main


class _FakeSignal:
    def connect(self, slot):
        pass


class _FakeApp:
    def __init__(self, argv):
        self.argv = argv
        self.aboutToQuit = _FakeSignal()

    def exec(self) -> int:
        return 7


class _FakeWindow:
    def __init__(self) -> None:
        self.shown = False

    def show(self) -> None:
        self.shown = True


class _FakeController:
    def __init__(self, window) -> None:
        self.window = window
        self.started = False

    def startup(self) -> None:
        self.started = True

    def cleanup(self) -> None:
        pass


def test_main_returns_error_when_pyside6_missing(monkeypatch, capsys):
    def _raise_missing():
        raise ModuleNotFoundError("No module named 'PySide6'", name="PySide6")

    monkeypatch.setattr(
        gui_main,
        "_load_gui_components",
        _raise_missing,
    )

    code = gui_main.main(["app.gui.main"])
    captured = capsys.readouterr()

    assert code == 2
    assert "PySide6" in captured.err


def test_main_starts_window_and_controller(monkeypatch):
    monkeypatch.setattr(
        gui_main,
        "_load_gui_components",
        lambda: (_FakeApp, _FakeController, _FakeWindow),
    )

    code = gui_main.main(["app.gui.main", "--x"])

    assert code == 7
