"""统一入口：默认 GUI，失败自动回退 CLI。"""
from __future__ import annotations

import os
import sys
from collections.abc import Sequence

from .cli.main import main as cli_main


def _should_force_cli(argv: Sequence[str]) -> bool:
    mode = os.environ.get("YT_TOOL_MODE", "").strip().lower()
    if mode == "cli":
        return True
    return "--cli" in argv


def _argv_without_cli_flag(argv: Sequence[str]) -> list[str]:
    return [arg for arg in argv if arg != "--cli"]


def main(argv: Sequence[str] | None = None) -> int:
    args = list(argv) if argv is not None else sys.argv[1:]
    if _should_force_cli(args):
        return cli_main(_argv_without_cli_flag(args))

    try:
        from .gui.main import main as gui_main
        rc = int(gui_main(["app.gui", *_argv_without_cli_flag(args)]))
        if rc == 0:
            return 0
        # GUI 返回非 0（例如缺依赖/初始化失败）时回退 CLI。
        print(f"GUI exited with code {rc}, fallback to CLI.", file=sys.stderr)
    except Exception as exc:
        print(f"GUI startup failed ({exc}), fallback to CLI.", file=sys.stderr)

    return cli_main(_argv_without_cli_flag(args))


if __name__ == "__main__":
    sys.exit(main())
