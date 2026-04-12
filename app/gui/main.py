"""pywebview GUI 入口。"""
from __future__ import annotations

import sys
from collections.abc import Sequence


def main(argv: Sequence[str] | None = None) -> int:
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

    api = Api()
    window = webview.create_window(
        "yt-tool",
        html=get_html(),
        js_api=api,
        width=1020,
        height=860,
        min_size=(880, 700),
    )
    api.set_window(window)

    def on_loaded() -> None:
        """Auto-run environment check when window loads."""
        window.evaluate_js("checkEnvironment()")

    window.events.loaded += on_loaded
    webview.start()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
