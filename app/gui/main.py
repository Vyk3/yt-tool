"""pywebview GUI 入口。"""
from __future__ import annotations

import os
import sys
import time
from collections.abc import Sequence


def _startup_trace_enabled() -> bool:
    return os.environ.get("YT_TOOL_STARTUP_TRACE", "").strip().lower() in {"1", "true", "yes", "on"}


def main(argv: Sequence[str] | None = None) -> int:
    trace_enabled = _startup_trace_enabled()
    startup_t0 = time.perf_counter()

    def trace(event: str) -> None:
        if trace_enabled:
            elapsed = time.perf_counter() - startup_t0
            print(f"[startup +{elapsed:.3f}s] {event}", file=sys.stderr, flush=True)

    try:
        import webview
    except ModuleNotFoundError:
        print(
            "pywebview is not installed. Install it first: pip install pywebview",
            file=sys.stderr,
        )
        return 2

    from .bridge import Api
    from .frontend import get_html

    trace("gui import complete")
    api = Api()
    trace("api created")
    window = webview.create_window(
        "yt-tool",
        html=get_html(startup_trace=trace_enabled),
        js_api=api,
        width=1020,
        height=860,
        min_size=(880, 700),
    )
    trace("window created")
    api.set_window(window)

    def on_loaded() -> None:
        """Auto-run environment check when window loads."""
        trace("webview loaded event")
        window.evaluate_js("setTimeout(() => checkEnvironment({ background: true }), 0)")

    window.events.loaded += on_loaded
    trace("webview start called")
    webview.start()
    trace("webview.start returned")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
