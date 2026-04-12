"""format_detector.py 单元测试。"""
from __future__ import annotations

from unittest.mock import MagicMock, patch

import pytest

from app.core.format_detector import (
    _parse_subtitle_tracks,
    detect,
    validate_detected_formats,
)

SAMPLE_YTDLP_JSON = {
    "title": "Test Video",
    "formats": [
        {
            "format_id": "137",
            "vcodec": "avc1",
            "acodec": "mp4a",
            "height": 1080,
            "fps": 30,
            "tbr": 4000,
            "filesize_approx": 120000000,
            "dynamic_range": "SDR",
            "format_note": "1080p",
            "ext": "mp4",
        },
        {
            "format_id": "248",
            "vcodec": "vp9",
            "acodec": "none",
            "height": 1080,
            "fps": 30,
            "tbr": 3500,
            "filesize_approx": 90000000,
            "dynamic_range": "HDR",
            "format_note": "1080p",
            "ext": "webm",
        },
        {
            "format_id": "140",
            "vcodec": "none",
            "acodec": "mp4a",
            "height": None,
            "fps": None,
            "tbr": 128,
            "abr": 128,
            "filesize_approx": 9000000,
            "audio_channels": 2,
            "format_note": "medium",
            "ext": "m4a",
        },
    ],
    "subtitles": {
        "en": [{"name": "English", "ext": "vtt"}],
    },
    "automatic_captions": {
        "en-auto": [{"name": "English (auto)", "ext": "vtt"}],
    },
}


def _patch_extract_info(return_value=None, side_effect=None):
    """Helper: patch yt_dlp.YoutubeDL to return a mock with controlled extract_info."""
    mock_ydl_instance = MagicMock()
    if side_effect:
        mock_ydl_instance.extract_info.side_effect = side_effect
    else:
        mock_ydl_instance.extract_info.return_value = return_value

    mock_ydl_cls = MagicMock()
    mock_ydl_cls.return_value.__enter__ = MagicMock(return_value=mock_ydl_instance)
    mock_ydl_cls.return_value.__exit__ = MagicMock(return_value=False)

    return patch("app.core.format_detector.yt_dlp.YoutubeDL", mock_ydl_cls)


class TestDetect:
    def test_empty_url_raises(self):
        with pytest.raises(ValueError, match="URL required"):
            detect("")

    def test_ytdlp_error_raises(self):
        import yt_dlp
        error = yt_dlp.utils.DownloadError("ERROR: not a video")
        with _patch_extract_info(side_effect=error), \
             pytest.raises(RuntimeError, match="format detect failed"):
            detect("http://example.com")

    def test_success_parses_formats(self):
        with _patch_extract_info(return_value=SAMPLE_YTDLP_JSON):
            result = detect("http://example.com")
            assert result.title == "Test Video"
            assert len(result.video_formats) == 2
            assert len(result.audio_formats) == 1
            assert len(result.subtitles) == 1
            assert len(result.auto_subtitles) == 1
            assert result.video_formats[0].filesize_approx == 120000000
            assert result.audio_formats[0].audio_channels == 2

    def test_video_only_tagged(self):
        with _patch_extract_info(return_value=SAMPLE_YTDLP_JSON):
            result = detect("http://example.com")
            fmt_248 = next(f for f in result.video_formats if f.id == "248")
            assert "video only" in fmt_248.note
            fmt_137 = next(f for f in result.video_formats if f.id == "137")
            assert "v+a" in fmt_137.note

    def test_playlist_takes_first_entry(self):
        playlist_json = {
            "title": "My Playlist",
            "entries": [SAMPLE_YTDLP_JSON, SAMPLE_YTDLP_JSON],
        }
        with _patch_extract_info(return_value=playlist_json):
            result = detect("http://example.com/playlist")
            assert result.title == "Test Video"
            assert result.is_playlist is True
            assert result.playlist_title == "My Playlist"
            assert result.playlist_count == 2

    def test_live_chat_track_marked(self):
        data = {
            "title": "Live Replay",
            "formats": [],
            "subtitles": {
                "live_chat": [{"name": "live_chat", "ext": "json"}],
            },
        }
        with _patch_extract_info(return_value=data):
            result = detect("http://example.com/live")
            assert result.subtitles[0].is_live_chat is True

    def test_subtitles_sorted_by_preference(self):
        data = {
            "title": "Test Video",
            "formats": [],
            "subtitles": {
                "en": [{"name": "English", "ext": "vtt"}],
                "zh-Hans": [{"name": "Chinese", "ext": "vtt"}],
            },
        }
        with _patch_extract_info(return_value=data):
            result = detect("http://example.com")
            assert [track.lang for track in result.subtitles] == ["zh-Hans", "en"]

    def test_validate_detected_formats_filters_unavailable_items(self):
        with _patch_extract_info(return_value=SAMPLE_YTDLP_JSON):
            result = detect("http://example.com")

        def is_available(url, format_id, **kwargs):
            return format_id != "248"

        with patch("app.core.format_detector._probe_format_available", side_effect=is_available):
            validated = validate_detected_formats("http://example.com", result)

        assert [fmt.id for fmt in validated.video_formats] == ["137"]
        assert [fmt.id for fmt in validated.audio_formats] == ["140"]

    def test_validate_detected_formats_only_checks_top_candidates(self):
        extended = {
            **SAMPLE_YTDLP_JSON,
            "formats": [
                *SAMPLE_YTDLP_JSON["formats"],
                {
                    "format_id": "399",
                    "vcodec": "av01",
                    "acodec": "none",
                    "height": 1440,
                    "fps": 30,
                    "tbr": 5000,
                    "filesize_approx": 150000000,
                    "dynamic_range": "HDR",
                    "format_note": "1440p",
                    "ext": "mp4",
                },
            ],
        }
        with _patch_extract_info(return_value=extended):
            result = detect("http://example.com")

        checked: list[str] = []

        def is_available(url, format_id, **kwargs):
            checked.append(format_id)
            return True

        with patch("app.core.format_detector.config.YT_VALIDATE_VIDEO_CANDIDATES", 1), \
             patch("app.core.format_detector._probe_format_available", side_effect=is_available):
            validated = validate_detected_formats("http://example.com", result)

        # 只有 top-1 视频候选和音频被探测
        assert checked == [validated.video_formats[0].id, "140"]
        # 未探测的低优先级视频格式应保留在菜单末尾，不被截断
        assert len(validated.video_formats) > 1

    def test_none_data_raises(self):
        with _patch_extract_info(return_value=None), \
             pytest.raises(RuntimeError, match="no data returned"):
            detect("http://example.com")


class TestParseSubtitleTracks:
    def test_normal_subtitles(self):
        mapping = {"en": [{"name": "English"}], "zh": [{"name": "Chinese"}]}
        tracks = _parse_subtitle_tracks(mapping)
        assert len(tracks) == 2
        langs = {t.lang for t in tracks}
        assert "en" in langs
        assert "zh" in langs

    def test_empty_mapping(self):
        assert _parse_subtitle_tracks({}) == ()
