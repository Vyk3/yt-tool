from __future__ import annotations

import importlib
import sys
from types import ModuleType

from app.core.env_check import CheckItem, CheckResult


def _make_fake_pyside6_for_main_window():
    class _Stub:
        def __init__(self, *args, **kwargs):
            pass

    class _QFileDialog(_Stub):
        class Option:
            ShowDirsOnly = 0

    class _QMessageBox(_Stub):
        @staticmethod
        def critical(*args, **kwargs):
            return None

    class _Qt:
        class ItemDataRole:
            UserRole = 0

        class AlignmentFlag:
            AlignRight = 0

    qtcore = ModuleType("PySide6.QtCore")
    qtcore.Qt = _Qt

    qtwidgets = ModuleType("PySide6.QtWidgets")
    qtwidgets.QComboBox = _Stub
    qtwidgets.QFileDialog = _QFileDialog
    qtwidgets.QFormLayout = _Stub
    qtwidgets.QGroupBox = _Stub
    qtwidgets.QHBoxLayout = _Stub
    qtwidgets.QHeaderView = _Stub
    qtwidgets.QLabel = _Stub
    qtwidgets.QLineEdit = _Stub
    qtwidgets.QListWidget = _Stub
    qtwidgets.QListWidgetItem = _Stub
    qtwidgets.QMainWindow = _Stub
    qtwidgets.QMessageBox = _QMessageBox
    qtwidgets.QPlainTextEdit = _Stub
    qtwidgets.QPushButton = _Stub
    qtwidgets.QSizePolicy = _Stub
    qtwidgets.QTreeWidget = _Stub
    qtwidgets.QTreeWidgetItem = _Stub
    qtwidgets.QVBoxLayout = _Stub
    qtwidgets.QWidget = _Stub

    pyside6 = ModuleType("PySide6")
    pyside6.QtCore = qtcore
    pyside6.QtWidgets = qtwidgets
    return pyside6, qtcore, qtwidgets


def _load_main_window_module(monkeypatch):
    pyside6, qtcore, qtwidgets = _make_fake_pyside6_for_main_window()
    monkeypatch.setitem(sys.modules, "PySide6", pyside6)
    monkeypatch.setitem(sys.modules, "PySide6.QtCore", qtcore)
    monkeypatch.setitem(sys.modules, "PySide6.QtWidgets", qtwidgets)
    module = importlib.import_module("app.gui.main_window")
    importlib.reload(module)
    return module


class _FakeLabel:
    def __init__(self):
        self.text = ""

    def setText(self, text: str) -> None:
        self.text = text


class _FakeWindow:
    def __init__(self):
        self.env_label = _FakeLabel()
        self.logs: list[str] = []

    def append_log(self, message: str) -> None:
        self.logs.append(message)


def test_set_env_check_result_appends_ffmpeg_hint_when_optional_missing(monkeypatch):
    main_window = _load_main_window_module(monkeypatch)
    window = _FakeWindow()
    result = CheckResult(
        ok=True,
        fatal_missing=False,
        warning_missing=True,
        items=(
            CheckItem("python", True, True, "/usr/bin/python3", "brew install python"),
            CheckItem("yt-dlp", True, True, "/usr/local/bin/yt-dlp", "brew install yt-dlp"),
            CheckItem("ffmpeg", False, False, None, "brew install ffmpeg"),
        ),
    )

    main_window.MainWindow.set_env_check_result(window, result)

    assert window.env_label.text == "环境检查通过"
    assert window.logs[0] == "环境检查通过"
    assert any("ffmpeg 未安装（可选）" in msg for msg in window.logs)
    assert any("brew install ffmpeg" in msg for msg in window.logs)


def test_set_env_check_result_skips_optional_warning_when_ffmpeg_present(monkeypatch):
    main_window = _load_main_window_module(monkeypatch)
    window = _FakeWindow()
    result = CheckResult(
        ok=True,
        fatal_missing=False,
        warning_missing=False,
        items=(
            CheckItem("python", True, True, "/usr/bin/python3", "brew install python"),
            CheckItem("yt-dlp", True, True, "/usr/local/bin/yt-dlp", "brew install yt-dlp"),
            CheckItem("ffmpeg", False, True, "/usr/local/bin/ffmpeg", "brew install ffmpeg"),
        ),
    )

    main_window.MainWindow.set_env_check_result(window, result)

    assert window.env_label.text == "环境检查通过"
    assert window.logs == ["环境检查通过"]


def test_set_env_check_result_skips_optional_warning_on_fatal_failure(monkeypatch):
    main_window = _load_main_window_module(monkeypatch)
    window = _FakeWindow()
    result = CheckResult(
        ok=False,
        fatal_missing=True,
        warning_missing=True,
        items=(
            CheckItem("python", True, False, None, "brew install python"),
            CheckItem("yt-dlp", True, True, "/usr/local/bin/yt-dlp", "brew install yt-dlp"),
            CheckItem("ffmpeg", False, False, None, "brew install ffmpeg"),
        ),
    )

    main_window.MainWindow.set_env_check_result(window, result)

    assert window.env_label.text == "环境检查失败: 缺少 python"
    assert window.logs[0] == "环境检查失败: 缺少 python"
    assert all("ffmpeg 未安装（可选）" not in msg for msg in window.logs)
