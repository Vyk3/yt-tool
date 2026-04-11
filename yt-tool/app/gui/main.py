"""PySide6 GUI 入口。"""
from __future__ import annotations

import sys
from collections.abc import Sequence


def _load_gui_components():
    from PySide6.QtWidgets import QApplication

    from .controllers import AppController
    from .main_window import MainWindow

    return QApplication, AppController, MainWindow


def main(argv: Sequence[str] | None = None) -> int:
    try:
        QApplication, AppController, MainWindow = _load_gui_components()
    except ModuleNotFoundError as exc:
        if exc.name and exc.name.startswith("PySide6"):
            print(
                "PySide6 is not installed. Install it first: pip install PySide6",
                file=sys.stderr,
            )
            return 2
        raise

    args = list(argv) if argv is not None else sys.argv
    app = QApplication(args)
    window = MainWindow()
    controller = AppController(window=window)
    controller.startup()
    window.show()
    window._controller = controller  # keep controller alive with window lifecycle
    return int(app.exec())


if __name__ == "__main__":
    raise SystemExit(main())
