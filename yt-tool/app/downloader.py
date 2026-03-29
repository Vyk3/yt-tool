"""下载执行 — 对应原 yt-download.sh。

封装 yt-dlp 的视频、音频、字幕下载调用。
每个函数只做一件事：拼参数 → 调 yt-dlp → 返回结构化结果。
不做交互，不做路径猜测；调用方应传入目标目录，本模块会做最后一道 ensure。
永不抛业务异常，所有失败统一通过 DownloadResult 返回。
"""
from __future__ import annotations

import subprocess
from dataclasses import dataclass
from pathlib import Path

from . import config
from .path_utils import ensure_dir, expand_path


@dataclass(frozen=True)
class DownloadResult:
    ok: bool
    output: str
    error: str


def _common_args() -> list[str]:
    """所有下载共用的 yt-dlp 参数。"""
    args = ["--no-warnings"]
    if not config.YT_SHOW_PROGRESS:
        args.append("--no-progress")
    return args


def _run_ytdlp(args: list[str]) -> DownloadResult:
    """执行 yt-dlp 并返回结构化结果。"""
    proc = subprocess.run(
        ["yt-dlp", *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if proc.returncode != 0:
        err = proc.stderr.strip()[:300]
        return DownloadResult(
            ok=False,
            output=proc.stdout,
            error=f"yt-dlp exited {proc.returncode}: {err}",
        )
    return DownloadResult(ok=True, output=proc.stdout, error="")


def _prepare_output_dir(output_dir: str | Path) -> Path | DownloadResult:
    """准备输出目录，失败时返回 DownloadResult 而非抛异常。"""
    try:
        return ensure_dir(expand_path(output_dir))
    except (ValueError, OSError) as e:
        return DownloadResult(ok=False, output="", error=str(e))


def download_video(url: str, format_id: str, output_dir: str | Path) -> DownloadResult:
    """下载用户选定的视频流（含合并音频）。"""
    if not url or not format_id:
        return DownloadResult(ok=False, output="", error="url and format_id required")

    dest = _prepare_output_dir(output_dir)
    if isinstance(dest, DownloadResult):
        return dest

    args = _common_args()
    args += ["-f", format_id]
    args += ["--merge-output-format", config.YT_PREFER_VIDEO_CONTAINER]
    args += ["-o", str(dest / "%(title)s.%(ext)s")]
    args.append(url)

    return _run_ytdlp(args)


def download_audio(url: str, format_id: str, output_dir: str | Path) -> DownloadResult:
    """下载用户选定的音频流（原始格式，不执行转码）。"""
    if not url or not format_id:
        return DownloadResult(ok=False, output="", error="url and format_id required")

    dest = _prepare_output_dir(output_dir)
    if isinstance(dest, DownloadResult):
        return dest

    args = _common_args()
    args += ["-f", format_id]
    args += ["-o", str(dest / "%(title)s.%(ext)s")]
    args.append(url)

    return _run_ytdlp(args)


def download_subs(url: str, lang: str, output_dir: str | Path) -> DownloadResult:
    """下载普通字幕（不含自动字幕）。

    仅处理 subtitles，不碰 automatic_captions。
    若后续需要下载自动字幕，应扩展为独立函数或增加参数。
    """
    if not url or not lang:
        return DownloadResult(ok=False, output="", error="url and lang required")

    dest = _prepare_output_dir(output_dir)
    if isinstance(dest, DownloadResult):
        return dest

    args = _common_args()
    args += ["--write-subs", "--sub-langs", lang]
    args += ["--skip-download"]
    args += ["--sub-format", "best"]
    # yt-dlp 会自动在文件名中插入语言码（如 title.zh-Hans.vtt）
    args += ["-o", str(dest / "%(title)s.%(ext)s")]
    args.append(url)

    return _run_ytdlp(args)
