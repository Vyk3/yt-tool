"""服务层数据模型。

GUI 和 CLI 共享的统一数据结构，屏蔽 core 层的实现细节。
"""
from __future__ import annotations

from contextlib import suppress
from dataclasses import dataclass
from enum import Enum

from ..core.format_detector import AudioFormat, SubtitleTrack, VideoFormat


class DownloadKind(str, Enum):
    VIDEO = "video"
    AUDIO = "audio"
    SUBTITLE = "subtitle"
    PLAYLIST = "playlist"


class TaskState(str, Enum):
    IDLE = "idle"
    CHECKING_ENV = "checking_env"
    DETECTING = "detecting"
    DOWNLOADING = "downloading"
    SUCCESS = "success"
    ERROR = "error"
    CANCELLED = "cancelled"


@dataclass(frozen=True)
class AppSettings:
    download_dir_video: str
    download_dir_audio: str
    download_dir_subtitle: str
    cookies_from: str | None = None


@dataclass(frozen=True)
class DetectRequest:
    url: str
    cookies_from: str | None = None
    extra_args: tuple[str, ...] = ()
    validate_formats: bool = True  # AppWorkflow.detect_formats() 读取此标记决定是否执行预检

    def has_extra_arg(self, flag: str) -> bool:
        return flag in self.extra_args


@dataclass(frozen=True)
class DetectResponse:
    title: str
    video_formats: tuple[VideoFormat, ...]
    audio_formats: tuple[AudioFormat, ...]
    subtitles: tuple[SubtitleTrack, ...]
    auto_subtitles: tuple[SubtitleTrack, ...]
    is_playlist: bool = False
    playlist_title: str = ""
    playlist_count: int = 0


@dataclass(frozen=True)
class DownloadRequest:
    kind: DownloadKind | str
    url: str
    dest_dir: str
    format_id: str = ""
    audio_format_id: str = ""   # video-only 流需要合并时填入音频流 ID
    subtitle_lang: str = ""      # "auto:<lang>" 前缀表示自动字幕
    embed_subs_lang: str = ""
    transcode_to: str = ""
    cookies_from: str | None = None
    extra_args: tuple[str, ...] = ()

    def __post_init__(self) -> None:
        # Backward compatibility: accept legacy string kind from old call-sites.
        if not isinstance(self.kind, DownloadKind):
            with suppress(ValueError):
                object.__setattr__(self, "kind", DownloadKind(self.kind))

    def has_extra_arg(self, flag: str) -> bool:
        return flag in self.extra_args


@dataclass(frozen=True)
class ProgressEvent:
    stage: str
    message: str
    percent: float | None = None


@dataclass(frozen=True)
class TaskResult:
    ok: bool
    state: TaskState
    output: str = ""
    error: str = ""
    saved_path: str = ""
