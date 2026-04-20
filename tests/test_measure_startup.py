from __future__ import annotations

import importlib.util
from pathlib import Path
from types import SimpleNamespace


def _load_module():
    repo_root = Path(__file__).resolve().parent.parent
    module_path = repo_root / "scripts" / "measure" / "macos" / "measure_startup.py"
    spec = importlib.util.spec_from_file_location("measure_startup", module_path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_parse_trace_output_extracts_startup_events() -> None:
    mod = _load_module()
    output = "\n".join(
        [
            "[startup +0.008s] gui import complete",
            "noise",
            "[startup +0.405s] webview loaded event",
        ]
    )
    assert mod.parse_trace_output(output) == [
        ("gui import complete", 0.008),
        ("webview loaded event", 0.405),
    ]


def test_summarize_trace_samples_groups_by_event() -> None:
    mod = _load_module()
    summary = mod.summarize_trace_samples(
        [
            {"trace_events": [("window created", 0.01), ("webview loaded event", 0.40)]},
            {"trace_events": [("window created", 0.02), ("webview loaded event", 0.50)]},
        ]
    )
    assert summary["window created"]["median"] == 0.015
    assert summary["webview loaded event"]["max"] == 0.50


def test_compare_launchers_keeps_trace_disabled_for_symmetric_timing(monkeypatch, tmp_path, capsys) -> None:
    mod = _load_module()
    calls: list[SimpleNamespace] = []

    def fake_run_measurements(**kwargs):
        calls.append(SimpleNamespace(**kwargs))
        summary = {
            "window_visible_s": {"min": 0.3, "median": 0.3, "mean": 0.3, "max": 0.3},
            "ready_s": {"min": 0.3, "median": 0.3, "mean": 0.3, "max": 0.3},
            "ready_after_window_s": {"min": 0.0, "median": 0.0, "mean": 0.0, "max": 0.0},
        }
        return [], summary, {}

    monkeypatch.setattr(mod, "run_measurements", fake_run_measurements)
    monkeypatch.setattr(mod.Path, "resolve", lambda self: self)

    app_path = tmp_path / "yt-tool.app"
    app_path.write_text("fake")
    monkeypatch.setattr(
        mod.argparse.ArgumentParser,
        "parse_args",
        lambda self: SimpleNamespace(
            app=str(app_path),
            process_name="yt-tool",
            iterations=2,
            timeout=30.0,
            interval=0.1,
            launcher="open",
            capture_trace=True,
            compare_launchers=True,
        ),
    )

    assert mod.main() == 0
    assert [call.launcher for call in calls] == ["open", "binary"]
    assert [call.capture_trace for call in calls] == [False, False]
    captured = capsys.readouterr()
    assert "ignores --capture-trace" in captured.err
