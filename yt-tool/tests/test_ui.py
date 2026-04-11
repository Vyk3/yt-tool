"""ui.py 单元测试。"""
from __future__ import annotations

import pytest

from app.format_detector import SubtitleTrack, VideoFormat
from app.ui import (
    ask_download_type,
    ask_download_sections,
    ask_sponsorblock_categories,
    ask_sponsorblock_mode,
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

    def test_column_hint_forces_numeric_menu(self, monkeypatch):
        monkeypatch.setattr("app.ui.sys.stdin.isatty", lambda: True)
        monkeypatch.setattr("app.ui.sys.stdout.isatty", lambda: True)
        monkeypatch.setattr("builtins.input", lambda _: "1")
        result = menu_select("test", ["A", "B"], ["a", "b"], column_hint="ID  编码  码率")
        assert result == "a"


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


class TestAdvancedPrompts:
    def test_download_sections_empty_returns_none(self, monkeypatch):
        monkeypatch.setattr("builtins.input", lambda _: "")
        assert ask_download_sections() is None

    def test_download_sections_returns_raw_expr(self, monkeypatch):
        monkeypatch.setattr("builtins.input", lambda _: "*10:15-20:30")
        assert ask_download_sections() == "*10:15-20:30"

    @pytest.mark.parametrize("raw,expected", [
        ("1", None),
        ("2", "mark"),
        ("3", "remove"),
    ])
    def test_sponsorblock_choices(self, monkeypatch, raw, expected):
        monkeypatch.setattr("builtins.input", lambda _: raw)
        assert ask_sponsorblock_mode() == expected

    def test_sponsorblock_categories_uses_default_on_empty(self, monkeypatch):
        monkeypatch.setattr("builtins.input", lambda _: "")
        assert ask_sponsorblock_categories(("sponsor", "intro")) == "sponsor,intro"


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
        assert "HDR" in labels[1]
        assert "114.4M" in labels[0]

    def test_audio_labels_count(self, sample_audio_formats):
        labels, values = build_audio_labels(sample_audio_formats)
        assert len(labels) == 2
        assert values == ["140", "251"]
        assert "2ch" in labels[0]

    def test_sub_labels_count(self, sample_subtitles):
        labels, values = build_sub_labels(sample_subtitles)
        assert len(labels) == 2
        assert values == ["en", "zh-Hans"]

    def test_sub_labels_mark_live_chat_and_auto(self):
        labels, values = build_sub_labels(
            (SubtitleTrack(lang="live_chat", label="live_chat", is_live_chat=True),),
            (SubtitleTrack(lang="en", label="English (auto)"),),
        )
        assert "[live_chat/JSON]" in labels[0]
        assert values == ["live_chat", "auto:en"]
