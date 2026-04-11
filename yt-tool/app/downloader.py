"""下载执行 — 对应原 yt-download.sh。

封装 yt-dlp 的视频、音频、字幕下载调用。
每个函数只做一件事：拼参数 → 调 yt-dlp → 返回结构化结果。
不做交互，不做路径猜测；调用方应传入目标目录，本模块会做最后一道 ensure。
永不抛业务异常，所有失败统一通过 DownloadResult 返回。
"""
from __future__ import annotations

import hashlib
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

from . import config
from .path_utils import ensure_dir, expand_path


@dataclass(frozen=True)
class DownloadResult:
    ok: bool
    output: str
    error: str
    saved_path: str = ""


# 匹配 yt-dlp 输出中的落盘路径
# 同时覆盖媒体（[download]/[Merger]/[ExtractAudio]）与字幕/缩略图（[info] Writing ... to:）两类格式
_DEST_RE = re.compile(
    r"^\[(?:download|Merger|ExtractAudio)\] (?:Destination:|Merging formats into |Destination )\"?(.+?)\"?$"
    r"|^\[info\] Writing (?:video subtitles|video thumbnail) to: (.+)$",
    re.MULTILINE,
)


def _common_args() -> list[str]:
    """所有下载共用的 yt-dlp 参数。"""
    args = ["--no-warnings"]
    if not config.YT_SHOW_PROGRESS:
        args.append("--no-progress")
    return args


def _extract_saved_path(output: str) -> str:
    """从 yt-dlp 输出中提取最终保存路径。"""
    # findall 返回元组列表（每个捕获组一个元素），取最后一个非空捕获组的值
    matches = _DEST_RE.findall(output)
    if not matches:
        return ""
    last = matches[-1]
    path = next((g for g in reversed(last) if g), "") if isinstance(last, tuple) else last
    return path.strip().strip("\"'")


def _stream_process_output(cmd: list[str]) -> tuple[int, str]:
    """流式转发 yt-dlp 输出，保留进度条，同时捕获完整文本。"""
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=0,
    )

    chunks: list[str] = []
    assert proc.stdout is not None

    while True:
        chunk = proc.stdout.read(1)
        if chunk == "":
            break
        chunks.append(chunk)
        sys.stdout.write(chunk)
        sys.stdout.flush()

    returncode = proc.wait()
    return returncode, "".join(chunks)


def _run_ytdlp(args: list[str]) -> DownloadResult:
    """执行 yt-dlp 并返回结构化结果。"""
    cmd = ["yt-dlp", *args]

    if config.YT_SHOW_PROGRESS and sys.stdout.isatty():
        returncode, output = _stream_process_output(cmd)
        if returncode != 0:
            err = output.strip().splitlines()[-1][:300] if output.strip() else ""
            return DownloadResult(
                ok=False,
                output=output,
                error=f"yt-dlp exited {returncode}: {err}",
            )
        return DownloadResult(
            ok=True,
            output=output,
            error="",
            saved_path=_extract_saved_path(output),
        )

    proc = subprocess.run(
        cmd,
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
    return DownloadResult(
        ok=True,
        output=proc.stdout,
        error="",
        saved_path=_extract_saved_path(proc.stdout + proc.stderr),
    )


def _prepare_output_dir(output_dir: str | Path) -> Path | DownloadResult:
    """准备输出目录，失败时返回 DownloadResult 而非抛异常。"""
    try:
        return ensure_dir(expand_path(output_dir))
    except (ValueError, OSError) as e:
        return DownloadResult(ok=False, output="", error=str(e))


def _cookie_args(cookies_from: str | None) -> list[str]:
    """生成 Cookie 参数（若指定）。"""
    return ["--cookies-from-browser", cookies_from] if cookies_from else []


def _playlist_error_args() -> list[str]:
    """按配置控制播放列表遇错时是否继续。"""
    if config.YT_PLAYLIST_CONTINUE_ON_ERROR:
        return ["--no-abort-on-error"]
    return ["--abort-on-error"]


def _archive_args(
    mode: str = "",
    output_dir: Path | None = None,
    url: str = "",
    extra_key: str = "",
) -> list[str]:
    """媒体下载归档，避免重复下载。

    mode: 非空时在归档文件名中插入后缀（如 "video"/"audio"）。
    output_dir: 指定时将归档文件放在输出目录内，使归档与目标路径绑定。
    url: 指定时将 URL 的短哈希加入文件名，避免同目录多个播放列表共享同一归档。
    extra_key: 附加内容（如 SponsorBlock 参数），与 url 合并计算哈希，
               使不同下载选项产生不同的归档文件。
    """
    if not config.YT_USE_DOWNLOAD_ARCHIVE:
        return []
    if output_dir is not None:
        key_material = f"{url}{extra_key}"
        url_tag = f"-{hashlib.md5(key_material.encode()).hexdigest()[:8]}" if key_material else ""
        archive_name = f".yt-dl-archive-{mode}{url_tag}.txt" if mode else f".yt-dl-archive{url_tag}.txt"
        archive_path = output_dir / archive_name
    else:
        base = expand_path(config.YT_DOWNLOAD_ARCHIVE)
        archive_path = base.parent / f"{base.stem}-{mode}{base.suffix}" if mode else base
    try:
        ensure_dir(archive_path.parent)
    except (ValueError, OSError):
        return []  # 目录不可用时静默跳过归档，不阻断下载
    return ["--download-archive", str(archive_path)]


def download_video(
    url: str,
    format_id: str,
    output_dir: str | Path,
    *,
    cookies_from: str | None = None,
    embed_subs_lang: str | None = None,
    extra_args: list[str] | None = None,
) -> DownloadResult:
    """下载用户选定的视频流（含合并音频）。

    cookies_from: 浏览器名称（"chrome"/"firefox" 等），None 表示不使用 Cookie。
    embed_subs_lang: 嵌入字幕的语言代码，None 表示不嵌入。
    extra_args: 追加到 yt-dlp 调用的额外参数（如 ["--playlist-items", "1"]）。
    """
    if not url or not format_id:
        return DownloadResult(ok=False, output="", error="url and format_id required")

    dest = _prepare_output_dir(output_dir)
    if isinstance(dest, DownloadResult):
        return dest

    args = _common_args()
    args += _cookie_args(cookies_from)
    args += ["-f", format_id]
    args += ["--merge-output-format", config.YT_PREFER_VIDEO_CONTAINER]
    if embed_subs_lang:
        args += ["--write-subs", "--embed-subs", "--sub-langs", embed_subs_lang]
        args += ["--sub-format", "best"]
    if extra_args:
        args += extra_args
    args += ["-o", str(dest / "%(title)s.%(ext)s")]
    args.append(url)

    return _run_ytdlp(args)


def download_audio(
    url: str,
    format_id: str,
    output_dir: str | Path,
    *,
    cookies_from: str | None = None,
    transcode_to: str | None = None,
    extra_args: list[str] | None = None,
) -> DownloadResult:
    """下载用户选定的音频流。

    cookies_from: 浏览器名称，None 表示不使用 Cookie。
    transcode_to: 转码目标格式（"mp3"/"aac" 等），None 表示保持原始格式。
    extra_args: 追加到 yt-dlp 调用的额外参数。
    """
    if not url or not format_id:
        return DownloadResult(ok=False, output="", error="url and format_id required")

    dest = _prepare_output_dir(output_dir)
    if isinstance(dest, DownloadResult):
        return dest

    args = _common_args()
    args += _cookie_args(cookies_from)
    args += ["-f", format_id]
    if transcode_to:
        args += ["-x", "--audio-format", transcode_to]
    if extra_args:
        args += extra_args
    args += ["-o", str(dest / "%(title)s.%(ext)s")]
    args.append(url)

    return _run_ytdlp(args)


def download_subs(
    url: str,
    lang: str,
    output_dir: str | Path,
    *,
    cookies_from: str | None = None,
    extra_args: list[str] | None = None,
) -> DownloadResult:
    """下载普通字幕（不含自动字幕）。"""
    if not url or not lang:
        return DownloadResult(ok=False, output="", error="url and lang required")

    dest = _prepare_output_dir(output_dir)
    if isinstance(dest, DownloadResult):
        return dest

    args = _common_args()
    args += _cookie_args(cookies_from)
    args += ["--write-subs", "--sub-langs", lang]
    args += ["--skip-download"]
    args += ["--sub-format", "best"]
    if extra_args:
        args += extra_args
    # yt-dlp 会自动在文件名中插入语言码（如 title.zh-Hans.vtt）
    args += ["-o", str(dest / "%(title)s.%(ext)s")]
    args.append(url)

    return _run_ytdlp(args)


def download_auto_subs(
    url: str,
    lang: str,
    output_dir: str | Path,
    *,
    cookies_from: str | None = None,
    extra_args: list[str] | None = None,
) -> DownloadResult:
    """下载自动字幕（automatic_captions）。"""
    if not url or not lang:
        return DownloadResult(ok=False, output="", error="url and lang required")

    dest = _prepare_output_dir(output_dir)
    if isinstance(dest, DownloadResult):
        return dest

    args = _common_args()
    args += _cookie_args(cookies_from)
    args += ["--write-auto-subs", "--sub-langs", lang]
    args += ["--skip-download"]
    args += ["--sub-format", "best"]
    if extra_args:
        args += extra_args
    args += ["-o", str(dest / "%(title)s.%(ext)s")]
    args.append(url)

    return _run_ytdlp(args)


def download_playlist(
    url: str,
    mode: str,
    output_dir: str | Path,
    *,
    cookies_from: str | None = None,
    extra_args: list[str] | None = None,
) -> DownloadResult:
    """下载整个播放列表（自动选取最佳格式）。

    mode: "video" 下载视频+音频合并；"audio" 仅下载音频流。
    输出目录结构：{output_dir}/{playlist_title}/{index} - {title}.{ext}
    """
    if not url or mode not in ("video", "audio"):
        return DownloadResult(ok=False, output="", error="url and valid mode required")

    dest = _prepare_output_dir(output_dir)
    if isinstance(dest, DownloadResult):
        return dest

    out_tmpl = str(dest / "%(playlist_title)s" / "%(playlist_index)s - %(title)s.%(ext)s")

    args = _common_args()
    args += _cookie_args(cookies_from)
    extra_key = " ".join(extra_args) if extra_args else ""
    args += _archive_args(mode, output_dir=dest, url=url, extra_key=extra_key)
    args += _playlist_error_args()
    if mode == "video":
        if shutil.which("ffmpeg"):
            args += ["-f", "bestvideo+bestaudio/best"]
            args += ["--merge-output-format", config.YT_PREFER_VIDEO_CONTAINER]
        else:
            # ffmpeg 不可用时回退到渐进式格式，避免选出无法合并的分离流
            args += ["-f", "best"]
    else:
        # bestaudio（不带 /best 回退）：若无纯音频流则报错，
        # 避免静默下载完整视频文件违背"仅音频"的用户预期
        args += ["-f", "bestaudio"]

    if extra_args:
        args += extra_args
    args += ["-o", out_tmpl]
    args += ["--yes-playlist"]
    args.append(url)

    return _run_ytdlp(args)
