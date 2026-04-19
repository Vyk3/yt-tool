"""环境自检 — 检查后续子进程调用所需命令是否在 PATH 中可用，缺失时提示安装命令。

对应原 format-detector.sh 中的依赖检查，扩展为独立模块。
"""
from __future__ import annotations

import importlib.util
import shutil
import sys
from dataclasses import dataclass

from . import config

# (逻辑名, 是否必需, 候选命令名, 可选 Python 模块名)
TARGETS: tuple[tuple[str, bool, tuple[str, ...], str | None], ...] = (
    ("python", True, ("python3", "python", "py"), None),
    ("yt-dlp", True, (), "yt_dlp"),
    ("ffmpeg", False, ("ffmpeg",), None),
)


@dataclass(frozen=True)
class CheckItem:
    name: str
    required: bool
    found: bool
    path: str | None
    hint: str


@dataclass(frozen=True)
class CheckResult:
    ok: bool
    fatal_missing: bool
    warning_missing: bool
    items: tuple[CheckItem, ...]


def _install_hint(dep: str) -> str:
    hints_map: dict[str, dict[str, str]] = {
        "Darwin": {
            "python": "brew install python",
            "yt-dlp": "python3 -m pip install -U yt-dlp",
            "ffmpeg": "brew install ffmpeg",
        },
        "Windows": {
            "python": "winget install Python.Python.3",
            "yt-dlp": "python -m pip install -U yt-dlp",
            "ffmpeg": "winget install Gyan.FFmpeg",
        },
    }

    default_hints: dict[str, str] = {
        "python": "sudo apt install python3  或使用发行版对应包管理器安装",
        "yt-dlp": "python3 -m pip install -U yt-dlp",
        "ffmpeg": "sudo apt install ffmpeg  或使用发行版对应包管理器安装",
    }

    hints = hints_map.get(config.SYSTEM, default_hints)
    return hints.get(dep, f"请参考 {dep} 官方文档安装")


def check_env() -> CheckResult:
    """检查后续调用依赖是否可用。"""
    items: list[CheckItem] = []
    fatal_missing = False
    warning_missing = False

    for logical_name, required, cmds, module_name in TARGETS:
        found_path: str | None = None

        # In a PyInstaller bundle Python is obviously present — skip the which() check.
        if logical_name == "python" and getattr(sys, "frozen", False):
            found_path = sys.executable
        elif module_name:
            spec = importlib.util.find_spec(module_name)
            if spec is not None:
                found_path = spec.origin or module_name
        else:
            for cmd in cmds:
                found_path = shutil.which(cmd)
                if found_path:
                    break

        found = found_path is not None
        items.append(
            CheckItem(
                name=logical_name,
                required=required,
                found=found,
                path=found_path,
                hint=_install_hint(logical_name),
            )
        )

        if not found and required:
            fatal_missing = True
        elif not found:
            warning_missing = True

    return CheckResult(
        ok=not fatal_missing,
        fatal_missing=fatal_missing,
        warning_missing=warning_missing,
        items=tuple(items),
    )
