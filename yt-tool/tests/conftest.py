"""共享 fixture。"""
from __future__ import annotations

import pytest

from app.core.format_detector import (
    AudioFormat,
    DetectResult,
    SubtitleTrack,
    VideoFormat,
)


@pytest.fixture()
def sample_video_formats() -> tuple[VideoFormat, ...]:
    return (
        VideoFormat(id="137", height=1080, codec="avc1", fps=30, tbr=4000.0, ext="mp4",
                    filesize_approx=120_000_000, dynamic_range="SDR", note="[v+a]"),
        VideoFormat(id="248", height=1080, codec="vp9",  fps=30, tbr=3500.0, ext="webm",
                    filesize_approx=90_000_000, dynamic_range="HDR", note="[video only]"),
        VideoFormat(id="136", height=720,  codec="avc1", fps=30, tbr=2500.0, ext="mp4",
                    filesize_approx=60_000_000, dynamic_range="", note="[v+a]"),
    )


@pytest.fixture()
def sample_audio_formats() -> tuple[AudioFormat, ...]:
    return (
        AudioFormat(id="140", codec="mp4a", abr=128.0, ext="m4a",
                    filesize_approx=9_000_000, audio_channels=2, note="medium"),
        AudioFormat(id="251", codec="opus", abr=160.0, ext="webm",
                    filesize_approx=11_000_000, audio_channels=2, note="high"),
    )


@pytest.fixture()
def sample_subtitles() -> tuple[SubtitleTrack, ...]:
    return (
        SubtitleTrack(lang="en", label="English"),
        SubtitleTrack(lang="zh-Hans", label="Chinese (Simplified)"),
    )


@pytest.fixture()
def sample_detect_result(
    sample_video_formats, sample_audio_formats, sample_subtitles,
) -> DetectResult:
    return DetectResult(
        title="Test Video Title",
        raw_json={},
        video_formats=sample_video_formats,
        audio_formats=sample_audio_formats,
        subtitles=sample_subtitles,
        auto_subtitles=(SubtitleTrack(lang="en-auto", label="English (auto)"),),
    )
