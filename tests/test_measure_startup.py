from __future__ import annotations

import importlib.util
from pathlib import Path


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
