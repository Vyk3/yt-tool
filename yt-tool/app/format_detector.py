"""动态格式探测 — 对应原 format-detector.sh。

调用 yt-dlp -J 获取视频元数据，解析出可用的视频流、音频流、字幕列表。
不做交互，不做输出，只返回结构化数据。

注意: 当输入为 playlist URL 时，当前实现只探测第一个条目。
完整 playlist 支持需后续扩展。
"""
from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class VideoFormat:
    id: str
    height: int
    codec: str
    fps: int
    tbr: float
    note: str


@dataclass(frozen=True)
class AudioFormat:
    id: str
    codec: str
    abr: float
    ext: str
    note: str


@dataclass(frozen=True)
class SubtitleTrack:
    lang: str
    label: str


@dataclass(frozen=True)
class DetectResult:
    title: str
    raw_json: dict[str, Any]
    video_formats: tuple[VideoFormat, ...]
    audio_formats: tuple[AudioFormat, ...]
    subtitles: tuple[SubtitleTrack, ...]
    auto_subtitles: tuple[SubtitleTrack, ...]


def _parse_subtitle_tracks(
    mapping: dict[str, Any],
) -> tuple[SubtitleTrack, ...]:
    """从 yt-dlp 的 subtitles / automatic_captions 字典构建字幕轨道列表。"""
    tracks: list[SubtitleTrack] = []
    for lang, entries in mapping.items():
        label = (
            entries[0].get("name", lang)
            if entries and isinstance(entries[0], dict)
            else lang
        )
        tracks.append(SubtitleTrack(lang=str(lang), label=label))
    return tuple(tracks)


def detect(url: str) -> DetectResult:
    """调用 yt-dlp -J 获取视频信息并解析格式。"""
    if not url:
        raise ValueError("URL required")

    proc = subprocess.run(
        ["yt-dlp", "-J", "--no-warnings", url],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )

    if proc.returncode != 0:
        err = proc.stderr.strip()[:300]
        raise RuntimeError(
            f"format detect failed: yt-dlp exited {proc.returncode}: {err}"
        )

    data: dict[str, Any] = json.loads(proc.stdout)

    # 若为 playlist，先取第一个条目；后续可扩展成完整 playlist 支持
    if "entries" in data and isinstance(data["entries"], list) and data["entries"]:
        first = data["entries"][0]
        if isinstance(first, dict):
            data = first

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
            note = str(f.get("format_note", "") or "")
            video_formats.append(
                VideoFormat(
                    id=fid,
                    height=int(f.get("height") or 0),
                    codec=vc,
                    fps=int(f.get("fps") or 0),
                    tbr=float(f.get("tbr") or 0),
                    note=f"{note} [{tag}]" if note else f"[{tag}]",
                )
            )
        elif has_a:
            audio_formats.append(
                AudioFormat(
                    id=fid,
                    codec=ac,
                    abr=float(f.get("abr") or 0),
                    ext=str(f.get("ext", "") or ""),
                    note=str(f.get("format_note", "") or ""),
                )
            )

    return DetectResult(
        title=title,
        raw_json=data,
        video_formats=tuple(video_formats),
        audio_formats=tuple(audio_formats),
        subtitles=_parse_subtitle_tracks(data.get("subtitles", {})),
        auto_subtitles=_parse_subtitle_tracks(data.get("automatic_captions", {})),
    )
