"""动态格式探测 — 使用 yt-dlp Python API。

通过 yt_dlp.YoutubeDL.extract_info() 获取视频元数据，解析出可用的视频流、音频流、字幕列表。
不做交互，不做输出，只返回结构化数据。

播放列表：detect() 检测到 playlist 时设置 is_playlist=True，格式信息取自第一个条目
（供用户预览）；实际全列表下载由 downloader.download_playlist() 处理。
"""
from __future__ import annotations

from dataclasses import dataclass, replace
from typing import Any

import yt_dlp

from . import config


@dataclass(frozen=True)
class VideoFormat:
    id: str
    height: int
    codec: str
    fps: int
    tbr: float
    ext: str
    filesize_approx: int
    dynamic_range: str
    note: str


@dataclass(frozen=True)
class AudioFormat:
    id: str
    codec: str
    abr: float
    ext: str
    filesize_approx: int
    audio_channels: int
    note: str


@dataclass(frozen=True)
class SubtitleTrack:
    lang: str
    label: str
    is_live_chat: bool = False


def _is_live_chat_track(lang: str, entries: Any) -> bool:
    """粗略识别 live_chat 轨道，便于 UI 做提示。"""
    if "live_chat" in lang.lower():
        return True

    if not isinstance(entries, list):
        return False

    for entry in entries:
        if not isinstance(entry, dict):
            continue

        haystack = " ".join(
            str(entry.get(key, "") or "").lower()
            for key in ("name", "format", "protocol", "url")
        )
        if "live_chat" in haystack:
            return True

    return False


@dataclass(frozen=True)
class DetectResult:
    title: str
    raw_json: dict[str, Any]
    video_formats: tuple[VideoFormat, ...]
    audio_formats: tuple[AudioFormat, ...]
    subtitles: tuple[SubtitleTrack, ...]
    auto_subtitles: tuple[SubtitleTrack, ...]
    is_playlist: bool = False
    playlist_title: str = ""
    playlist_count: int = 0


def _parse_subtitle_tracks(
    mapping: dict[str, Any],
) -> tuple[SubtitleTrack, ...]:
    """从 yt-dlp 的 subtitles / automatic_captions 字典构建字幕轨道列表。"""
    tracks: list[SubtitleTrack] = []
    for lang, entries in mapping.items():
        lang_str = str(lang)
        label = (
            entries[0].get("name", lang_str)
            if entries and isinstance(entries[0], dict)
            else lang_str
        )
        tracks.append(
            SubtitleTrack(
                lang=lang_str,
                label=str(label),
                is_live_chat=_is_live_chat_track(lang_str, entries),
            )
        )
    return tuple(tracks)


def _build_ydl_opts(
    *,
    cookies_from: str | None = None,
    no_playlist: bool = False,
    extra_opts: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """构建 yt-dlp YoutubeDL 选项字典。"""
    opts: dict[str, Any] = {
        "quiet": True,
        "no_warnings": True,
    }
    if no_playlist:
        opts["noplaylist"] = True
    else:
        opts["playlist_items"] = "1"
    if cookies_from:
        opts["cookiesfrombrowser"] = (cookies_from,)
    if extra_opts:
        opts.update(extra_opts)
    return opts


def detect(url: str, *, cookies_from: str | None = None, no_playlist: bool = False) -> DetectResult:
    """使用 yt-dlp Python API 获取视频信息并解析格式。

    cookies_from: 浏览器名称（"chrome"/"firefox" 等），None 表示不使用 Cookie。
    no_playlist: True 时设置 noplaylist，用于下载 watch?v=X&list=Y 形式 URL 时
                 确保获取的是 URL 实际指向的视频，而非播放列表第一条。
    """
    if not url:
        raise ValueError("URL required")

    ydl_opts = _build_ydl_opts(cookies_from=cookies_from, no_playlist=no_playlist)

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            data: dict[str, Any] | None = ydl.extract_info(url, download=False)
    except yt_dlp.utils.DownloadError as e:
        raise RuntimeError(f"format detect failed: {e}") from e

    if data is None:
        raise RuntimeError("format detect failed: no data returned")

    # 检测播放列表
    is_playlist = False
    playlist_title = ""
    playlist_count = 0
    if "entries" in data and isinstance(data["entries"], list) and data["entries"]:
        is_playlist = True
        playlist_title = str(data.get("title", "") or "")
        # playlist_count / n_entries 是 yt-dlp 上报的总条数；
        # 加了 --playlist-items 1 后 entries 只有 1 项，不能再用 len(entries) 计数。
        playlist_count = int(
            data.get("playlist_count") or data.get("n_entries") or len(data["entries"])
        )
        first = data["entries"][0]
        if isinstance(first, dict):
            data = first  # 格式信息取自首条（供预览）

    title = (
        str(data.get("title", "unknown"))
        .replace("\t", " ")
        .replace("\n", " ")
        .replace("\r", "")
    )

    video_formats: list[VideoFormat] = []
    audio_formats: list[AudioFormat] = []

    for f in data.get("formats", []):
        if not isinstance(f, dict):
            continue

        fid = str(f.get("format_id", "") or "")
        if not fid:
            continue

        vc = str(f.get("vcodec", "none") or "none")
        ac = str(f.get("acodec", "none") or "none")
        has_v = vc != "none"
        has_a = ac != "none"

        if has_v:
            tag = "v+a" if has_a else "video only"
            video_formats.append(
                VideoFormat(
                    id=fid,
                    height=int(f.get("height") or 0),
                    codec=vc,
                    fps=int(f.get("fps") or 0),
                    tbr=float(f.get("tbr") or 0),
                    ext=str(f.get("ext", "") or ""),
                    filesize_approx=int(f.get("filesize_approx") or f.get("filesize") or 0),
                    dynamic_range=str(f.get("dynamic_range", "") or ""),
                    note=f"[{tag}]",
                )
            )
        elif has_a:
            audio_formats.append(
                AudioFormat(
                    id=fid,
                    codec=ac,
                    abr=float(f.get("abr") or 0),
                    ext=str(f.get("ext", "") or ""),
                    filesize_approx=int(f.get("filesize_approx") or f.get("filesize") or 0),
                    audio_channels=int(f.get("audio_channels") or 0),
                    note=str(f.get("format_note", "") or ""),
                )
            )

    return DetectResult(
        title=title,
        raw_json=data,
        video_formats=_sort_video_formats(video_formats),
        audio_formats=_sort_audio_formats(audio_formats),
        subtitles=_sort_subtitle_tracks(
            _parse_subtitle_tracks(data.get("subtitles", {}))
        ),
        auto_subtitles=_sort_subtitle_tracks(
            _parse_subtitle_tracks(data.get("automatic_captions", {}))
        ),
        is_playlist=is_playlist,
        playlist_title=playlist_title,
        playlist_count=playlist_count,
    )


def _probe_format_available(
    url: str,
    format_id: str,
    *,
    cookies_from: str | None = None,
    extra_args: list[str] | None = None,
) -> bool:
    """用 yt-dlp Python API 模拟一次格式选择，判断当前 format_id 是否仍可用。"""
    extra_opts: dict[str, Any] = {
        "format": format_id,
        "socket_timeout": config.YT_VALIDATE_FORMAT_TIMEOUT_SEC,
    }
    # 将已知的 CLI extra_args 映射为 library 选项
    no_playlist = bool(extra_args and "--no-playlist" in extra_args)

    ydl_opts = _build_ydl_opts(
        cookies_from=cookies_from,
        no_playlist=no_playlist,
        extra_opts=extra_opts,
    )

    try:
        with yt_dlp.YoutubeDL(ydl_opts) as ydl:
            ydl.extract_info(url, download=False)
        return True
    except yt_dlp.utils.DownloadError as e:
        # 仅在明确指出格式不可用时才删除候选；
        # 网络抖动、限速、认证失败等瞬时错误不应误删有效格式。
        err = str(e).lower()
        return not (
            "format is not available" in err
            or "requested format is not available" in err
        )
    except Exception:
        # 超时或其他异常：保守地视为可用
        return True


def validate_detected_formats(
    url: str,
    result: DetectResult,
    *,
    cookies_from: str | None = None,
    extra_args: list[str] | None = None,
) -> DetectResult:
    """预检高优先级候选格式是否仍可用，并过滤掉失效项。"""
    if not config.YT_VALIDATE_FORMATS_BEFORE_MENU:
        return result

    available_videos = _validate_top_candidates(
        url,
        result.video_formats,
        limit=config.YT_VALIDATE_VIDEO_CANDIDATES,
        cookies_from=cookies_from,
        extra_args=extra_args,
    )
    available_audios = _validate_top_candidates(
        url,
        result.audio_formats,
        limit=config.YT_VALIDATE_AUDIO_CANDIDATES,
        cookies_from=cookies_from,
        extra_args=extra_args,
    )

    return replace(
        result,
        video_formats=_sort_video_formats(list(available_videos)),
        audio_formats=_sort_audio_formats(list(available_audios)),
    )


def _validate_top_candidates(
    url: str,
    formats: tuple[VideoFormat, ...] | tuple[AudioFormat, ...],
    *,
    limit: int,
    cookies_from: str | None = None,
    extra_args: list[str] | None = None,
) -> tuple[VideoFormat, ...] | tuple[AudioFormat, ...]:
    """只预检排序靠前的候选；若一个都没通过，则继续向后探测直到找到可用项。"""
    if not formats:
        return formats

    checked = 0
    available: list[VideoFormat | AudioFormat] = []
    target = max(limit, 1)

    for fmt in formats:
        should_probe = checked < target or not available
        if not should_probe:
            break

        checked += 1
        if _probe_format_available(
            url,
            fmt.id,
            cookies_from=cookies_from,
            extra_args=extra_args,
        ):
            available.append(fmt)

    # 未探测的低优先级格式保留在列表末尾：
    # 预检只过滤已被确认失效的候选，不截断用户的完整选择范围。
    available.extend(formats[checked:])
    return tuple(available)


def _video_codec_matches(codec: str, pref: str) -> bool:
    """将配置中的编码偏好与 yt-dlp 实际 vcodec 字段做模糊匹配。

    yt-dlp 上报 H.264 为 "avc1.*"，配置通常写 "h264"；需要处理这类常见别名。
    """
    c, p = codec.lower(), pref.lower()
    if p in c:
        return True
    _ALIASES: dict[str, tuple[str, ...]] = {
        "h264": ("avc1",),
        "h265": ("hvc1", "hev1"),
        "vp9":  ("vp09",),
        "av1":  ("av01",),
    }
    return any(c.startswith(alias) for alias in _ALIASES.get(p, ()))


def _audio_codec_matches(fmt: AudioFormat, pref: str) -> bool:
    """将配置中的音频编码偏好与 yt-dlp 实际 acodec/ext 字段做模糊匹配。

    yt-dlp 上报 AAC/M4A 为 "mp4a.*"，配置通常写 "m4a"；同时检查 ext 字段兜底。
    """
    p = pref.lower()
    if p in fmt.codec.lower():
        return True
    if p in fmt.ext.lower():
        return True
    # m4a ↔ mp4a 家族
    return p == "m4a" and fmt.codec.lower().startswith("mp4a")


def _sort_video_formats(
    formats: list[VideoFormat],
) -> tuple[VideoFormat, ...]:
    """按 config 偏好排序视频流：分辨率接近度 → 编码匹配 → 码率。"""

    def _key(f: VideoFormat) -> tuple[int, int, float]:
        height_diff = abs(f.height - config.YT_PREFER_VIDEO_HEIGHT)
        codec_match = 0 if _video_codec_matches(f.codec, config.YT_PREFER_VIDEO_CODEC) else 1
        return (height_diff, codec_match, -f.tbr)

    return tuple(sorted(formats, key=_key))


def _sort_audio_formats(
    formats: list[AudioFormat],
) -> tuple[AudioFormat, ...]:
    """按 config 偏好排序音频流：编码匹配 → 比特率（不足最低值的排末尾）。"""

    def _key(f: AudioFormat) -> tuple[int, int, float]:
        codec_match = 0 if _audio_codec_matches(f, config.YT_PREFER_AUDIO_CODEC) else 1
        below_min = 0 if f.abr >= config.YT_PREFER_AUDIO_MIN_BITRATE else 1
        return (below_min, codec_match, -f.abr)

    return tuple(sorted(formats, key=_key))


def _sort_subtitle_tracks(
    tracks: tuple[SubtitleTrack, ...],
) -> tuple[SubtitleTrack, ...]:
    """按 YT_PREFER_SUBTITLE_LANGS 将首选语言排到前面。"""
    pref = config.YT_PREFER_SUBTITLE_LANGS

    def _key(t: SubtitleTrack) -> int:
        for i, lang in enumerate(pref):
            if t.lang.startswith(lang) or lang.startswith(t.lang):
                return i
        return len(pref)

    return tuple(sorted(tracks, key=_key))
