"""format_detector.py 单元测试。"""
from __future__ import annotations

import json
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


class TestDetect:
    def test_empty_url_raises(self):
        with pytest.raises(ValueError, match="URL required"):
            detect("")

    def test_ytdlp_nonzero_raises(self):
        fake_proc = MagicMock()
        fake_proc.returncode = 1
        fake_proc.stderr = "ERROR: not a video"
        with patch("app.core.format_detector.subprocess.run", return_value=fake_proc), pytest.raises(RuntimeError, match="format detect failed"):
            detect("http://example.com")

    def test_success_parses_formats(self):
        fake_proc = MagicMock()
        fake_proc.returncode = 0
        fake_proc.stdout = json.dumps(SAMPLE_YTDLP_JSON)
        fake_proc.stderr = ""
        with patch("app.core.format_detector.subprocess.run", return_value=fake_proc):
            result = detect("http://example.com")
            assert result.title == "Test Video"
            assert len(result.video_formats) == 2
            assert len(result.audio_formats) == 1
            assert len(result.subtitles) == 1
            assert len(result.auto_subtitles) == 1
            assert result.video_formats[0].filesize_approx == 120000000
            assert result.audio_formats[0].audio_channels == 2

    def test_video_only_tagged(self):
        fake_proc = MagicMock()
        fake_proc.returncode = 0
        fake_proc.stdout = json.dumps(SAMPLE_YTDLP_JSON)
        fake_proc.stderr = ""
        with patch("app.core.format_detector.subprocess.run", return_value=fake_proc):
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
        fake_proc = MagicMock()
        fake_proc.returncode = 0
        fake_proc.stdout = json.dumps(playlist_json)
        fake_proc.stderr = ""
        with patch("app.core.format_detector.subprocess.run", return_value=fake_proc):
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
        fake_proc = MagicMock()
        fake_proc.returncode = 0
        fake_proc.stdout = json.dumps(data)
        fake_proc.stderr = ""
        with patch("app.core.format_detector.subprocess.run", return_value=fake_proc):
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
        fake_proc = MagicMock()
        fake_proc.returncode = 0
        fake_proc.stdout = json.dumps(data)
        fake_proc.stderr = ""
        with patch("app.core.format_detector.subprocess.run", return_value=fake_proc):
            result = detect("http://example.com")
            assert [track.lang for track in result.subtitles] == ["zh-Hans", "en"]

    def test_validate_detected_formats_filters_unavailable_items(self):
        fake_proc = MagicMock()
        fake_proc.returncode = 0
        fake_proc.stdout = json.dumps(SAMPLE_YTDLP_JSON)
        fake_proc.stderr = ""
        with patch("app.core.format_detector.subprocess.run", return_value=fake_proc):
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
        fake_proc = MagicMock(returncode=0, stdout=json.dumps(extended), stderr="")
        with patch("app.core.format_detector.subprocess.run", return_value=fake_proc):
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
