"""ui.py 单元测试。"""
from __future__ import annotations

import pytest

from app.format_detector import VideoFormat
from app.ui import (
    ask_download_type,
    build_audio_labels,
    build_sub_labels,
    build_video_labels,
    is_video_only,
    menu_select,
)


class TestMenuSelect:
    def test_valid_selection(self, monkeypatch):
        monkeypatch.setattr("builtins.input", lambda _: "1")
        result = menu_select("test", ["A", "B"], ["a", "b"])
        assert result == "a"

    def test_select_last(self, monkeypatch):
        monkeypatch.setattr("builtins.input", lambda _: "2")
        result = menu_select("test", ["A", "B"], ["a", "b"])
        assert result == "b"

    def test_skip_returns_none(self, monkeypatch):
        monkeypatch.setattr("builtins.input", lambda _: "0")
        result = menu_select("test", ["A"], ["a"])
        assert result is None

    def test_empty_labels_returns_none(self):
        result = menu_select("test", [], [])
        assert result is None

    def test_invalid_then_valid(self, monkeypatch):
        inputs = iter(["x", "-1", "999", "1"])
        monkeypatch.setattr("builtins.input", lambda _: next(inputs))
        result = menu_select("test", ["A", "B"], ["a", "b"])
        assert result == "a"

    def test_labels_values_mismatch_raises(self):
        with pytest.raises(ValueError, match="mismatch"):
            menu_select("test", ["A"], ["a", "b"])


class TestAskDownloadType:
    @pytest.mark.parametrize("raw,expected", [
        ("1", "video"),
        ("2", "audio"),
        ("3", "subs"),
        ("4", "all"),
        ("0", None),
    ])
    def test_valid_choices(self, monkeypatch, raw, expected):
        monkeypatch.setattr("builtins.input", lambda _: raw)
        assert ask_download_type() == expected

    def test_invalid_then_valid(self, monkeypatch):
        inputs = iter(["a", "5", "1"])
        monkeypatch.setattr("builtins.input", lambda _: next(inputs))
        assert ask_download_type() == "video"


class TestIsVideoOnly:
    def test_video_only_true(self, sample_video_formats):
        assert is_video_only(sample_video_formats, "248") is True

    def test_video_with_audio_false(self, sample_video_formats):
        assert is_video_only(sample_video_formats, "137") is False

    def test_unknown_id_false(self, sample_video_formats):
        assert is_video_only(sample_video_formats, "999") is False


class TestBuildLabels:
    def test_video_labels_count(self, sample_video_formats):
        labels, values = build_video_labels(sample_video_formats)
        assert len(labels) == 3
        assert values == ["137", "248", "136"]

    def test_audio_labels_count(self, sample_audio_formats):
        labels, values = build_audio_labels(sample_audio_formats)
        assert len(labels) == 2
        assert values == ["140", "251"]

    def test_sub_labels_count(self, sample_subtitles):
        labels, values = build_sub_labels(sample_subtitles)
        assert len(labels) == 2
        assert values == ["en", "zh-Hans"]
