"""路径校验、展开与下载目录自动选择 — 对应原 path-validator.sh。

职责:
  - expand_path: 展开 ~ 前缀，返回绝对路径（不做 resolve）
  - ensure_dir: 确保目录存在且可写
  - resolve_download_dir: 按优先级自动选择可用下载目录
"""
from __future__ import annotations

import os
import platform
from pathlib import Path

_SYSTEM: str = platform.system()


def expand_path(p: str | Path) -> Path:
    """展开 ~ 前缀。只做 expanduser，不做 resolve。"""
    return Path(p).expanduser()


def ensure_dir(p: str | Path) -> Path:
    """确保目录存在且可写，返回 Path。不可用时抛 ValueError。"""
    path = Path(p).expanduser()

    if path.exists() and not path.is_dir():
        raise ValueError(f"路径已存在但不是目录: {path}")

    try:
        path.mkdir(parents=True, exist_ok=True)
    except OSError as e:
        raise ValueError(f"无法创建目录: {path} ({e})") from e

    if not os.access(path, os.W_OK):
        raise ValueError(f"目录不可写: {path}")

    return path


def resolve_download_dir(configured: str | Path, subdir: str) -> Path:
    """按优先级自动选择可用下载目录。

    策略:
      1. 优先用 configured（用户显式配置）
      2. 按平台猜测常见下载目录
      3. 找到第一个"可创建且可写"的目录就用
      4. 全部失败时返回 configured 兜底，由调用方让用户手输
    """
    # 策略1: 用户显式配置
    try:
        return ensure_dir(configured)
    except (ValueError, OSError):
        pass

    # 策略2: 按平台猜测候选目录
    for candidate in _platform_candidates(subdir):
        try:
            return ensure_dir(candidate)
        except (ValueError, OSError):
            continue

    # 策略3: 兜底，统一 expanduser 后返回
    return Path(configured).expanduser()


def _platform_candidates(subdir: str) -> tuple[Path, ...]:
    """按平台返回候选下载目录列表。

    注意: Linux 下 XDG_DOWNLOAD_DIR 环境变量命中率不高，
    这里仅作辅助参考，主要依赖 ~/Downloads 兜底。
    """
    home = Path.home()

    if _SYSTEM == "Darwin":
        return (
            home / "Downloads" / subdir,
            home / "Downloads",
            home / "Desktop" / subdir,
            home / "Movies",
        )

    if _SYSTEM == "Windows":
        win_home = Path(os.environ.get("USERPROFILE", str(home)))
        return (
            win_home / "Downloads" / subdir,
            win_home / "Downloads",
            win_home / "Desktop" / subdir,
            win_home / "Videos",
        )

    # Linux / 其他 — XDG_DOWNLOAD_DIR 仅作辅助，不保证精确
    xdg_dl_str = os.environ.get("XDG_DOWNLOAD_DIR")
    candidates: list[Path] = []
    if xdg_dl_str:
        xdg_dl = Path(xdg_dl_str)
        candidates.append(xdg_dl / subdir)
        candidates.append(xdg_dl)
    candidates.append(home / "Downloads" / subdir)
    candidates.append(home / "Downloads")
    return tuple(candidates)
