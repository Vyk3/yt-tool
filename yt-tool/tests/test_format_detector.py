"""format_detector.py 单元测试。"""
from __future__ import annotations

import json
from unittest.mock import MagicMock, patch

import pytest

from app.format_detector import DetectResult, _parse_subtitle_tracks, detect


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
        with patch("app.format_detector.subprocess.run", return_value=fake_proc):
            with pytest.raises(RuntimeError, match="format detect failed"):
                detect("http://example.com")

    def test_success_parses_formats(self):
        fake_proc = MagicMock()
        fake_proc.returncode = 0
        fake_proc.stdout = json.dumps(SAMPLE_YTDLP_JSON)
        fake_proc.stderr = ""
        with patch("app.format_detector.subprocess.run", return_value=fake_proc):
            result = detect("http://example.com")
            assert result.title == "Test Video"
            assert len(result.video_formats) == 2
            assert len(result.audio_formats) == 1
            assert len(result.subtitles) == 1
            assert len(result.auto_subtitles) == 1

    def test_video_only_tagged(self):
        fake_proc = MagicMock()
        fake_proc.returncode = 0
        fake_proc.stdout = json.dumps(SAMPLE_YTDLP_JSON)
        fake_proc.stderr = ""
        with patch("app.format_detector.subprocess.run", return_value=fake_proc):
            result = detect("http://example.com")
            fmt_248 = next(f for f in result.video_formats if f.id == "248")
            assert "video only" in fmt_248.note
            fmt_137 = next(f for f in result.video_formats if f.id == "137")
            assert "v+a" in fmt_137.note

    def test_playlist_takes_first_entry(self):
        playlist_json = {
            "entries": [SAMPLE_YTDLP_JSON],
        }
        fake_proc = MagicMock()
        fake_proc.returncode = 0
        fake_proc.stdout = json.dumps(playlist_json)
        fake_proc.stderr = ""
        with patch("app.format_detector.subprocess.run", return_value=fake_proc):
            result = detect("http://example.com/playlist")
            assert result.title == "Test Video"


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
