from __future__ import annotations

import importlib
import sys
from types import ModuleType


def _load_entry_module():
    entry = importlib.import_module("app.__main__")
    return importlib.reload(entry)


def test_force_cli_via_flag(monkeypatch):
    entry = _load_entry_module()
    called = {}

    def fake_cli(argv):
        called["argv"] = list(argv)
        return 0

    monkeypatch.setattr(entry, "cli_main", fake_cli)

    rc = entry.main(["--cli", "http://x"])

    assert rc == 0
    assert called["argv"] == ["http://x"]


def test_force_cli_via_env(monkeypatch):
    entry = _load_entry_module()
    called = {}
    monkeypatch.setenv("YT_TOOL_MODE", "cli")

    def fake_cli(argv):
        called["argv"] = list(argv)
        return 0

    monkeypatch.setattr(entry, "cli_main", fake_cli)

    rc = entry.main(["http://x"])

    assert rc == 0
    assert called["argv"] == ["http://x"]


def test_default_uses_gui_then_fallback_to_cli_on_nonzero(monkeypatch):
    entry = _load_entry_module()
    gui_mod = ModuleType("app.gui.main")
    gui_mod.main = lambda argv: 2
    monkeypatch.setitem(sys.modules, "app.gui.main", gui_mod)

    called = {}

    def fake_cli(argv):
        called["argv"] = list(argv)
        return 0

    monkeypatch.setattr(entry, "cli_main", fake_cli)

    rc = entry.main(["http://x"])

    assert rc == 0
    assert called["argv"] == ["http://x"]


def test_default_uses_gui_when_ok(monkeypatch):
    entry = _load_entry_module()
    gui_mod = ModuleType("app.gui.main")
    gui_mod.main = lambda argv: 0
    monkeypatch.setitem(sys.modules, "app.gui.main", gui_mod)

    called = {}
    monkeypatch.setattr(entry, "cli_main", lambda argv: called.setdefault("argv", list(argv)) or 0)

    rc = entry.main(["http://x"])

    assert rc == 0
    assert called == {}
