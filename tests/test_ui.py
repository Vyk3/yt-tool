"""ui.py 单元测试。"""
from __future__ import annotations

import pytest

import app.cli.ui as ui
from app.cli.ui import (
    _terminal_size,
    ask_download_sections,
    ask_download_type,
    ask_sponsorblock_categories,
    ask_sponsorblock_mode,
    build_audio_labels,
    build_sub_labels,
    build_video_labels,
    is_video_only,
    menu_select,
)
from app.core.format_detector import SubtitleTrack


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
        monkeypatch.setattr("app.cli.ui.sys.stdin.isatty", lambda: True)
        monkeypatch.setattr("app.cli.ui.sys.stdout.isatty", lambda: True)
        monkeypatch.setattr("builtins.input", lambda _: "1")
        result = menu_select("test", ["A", "B"], ["a", "b"], column_hint="ID  编码  码率")
        assert result == "a"


class TestTerminalSize:
    def test_ignores_zero_columns_env_and_uses_explicit_override(self, monkeypatch):
        monkeypatch.setenv("COLUMNS", "0")
        monkeypatch.setenv("YT_TOOL_TERM_COLUMNS", "132")
        monkeypatch.delenv("LINES", raising=False)
        monkeypatch.delenv("YT_TOOL_TERM_LINES", raising=False)
        monkeypatch.setattr("app.cli.ui._ioctl_terminal_size", lambda: None)
        monkeypatch.setattr("app.cli.ui._fallback_terminal_size", lambda: ui.os.terminal_size((91, 33)))

        size = _terminal_size()

        assert size.columns == 132
        assert size.lines == 33

    def test_uses_ioctl_when_env_is_missing(self, monkeypatch):
        monkeypatch.delenv("COLUMNS", raising=False)
        monkeypatch.delenv("LINES", raising=False)
        monkeypatch.delenv("YT_TOOL_TERM_COLUMNS", raising=False)
        monkeypatch.delenv("YT_TOOL_TERM_LINES", raising=False)
        monkeypatch.delenv("YT_TOOL_TERM_TTY", raising=False)
        monkeypatch.setattr("app.cli.ui._ioctl_terminal_size", lambda: (111, 29))

        size = _terminal_size()

        assert size.columns == 111
        assert size.lines == 29

    def test_uses_exported_tty_path_before_other_fallbacks(self, monkeypatch):
        monkeypatch.delenv("COLUMNS", raising=False)
        monkeypatch.delenv("LINES", raising=False)
        monkeypatch.delenv("YT_TOOL_TERM_COLUMNS", raising=False)
        monkeypatch.delenv("YT_TOOL_TERM_LINES", raising=False)
        monkeypatch.setenv("YT_TOOL_TERM_TTY", "/dev/ttys555")
        monkeypatch.setattr(
            "app.cli.ui._ioctl_terminal_size_for_path",
            lambda path: (156, 48) if path == "/dev/ttys555" else None,
        )
        monkeypatch.setattr("app.cli.ui._ioctl_terminal_size", lambda: (80, 24))

        size = _terminal_size()

        assert size.columns == 156
        assert size.lines == 48

    def test_uses_darwin_parent_tty_when_local_streams_have_no_tty(self, monkeypatch):
        monkeypatch.delenv("COLUMNS", raising=False)
        monkeypatch.delenv("LINES", raising=False)
        monkeypatch.delenv("YT_TOOL_TERM_COLUMNS", raising=False)
        monkeypatch.delenv("YT_TOOL_TERM_LINES", raising=False)
        monkeypatch.setattr("app.cli.ui.platform.system", lambda: "Darwin")
        monkeypatch.setattr("app.cli.ui._ioctl_terminal_size", lambda: None)
        monkeypatch.setattr("app.cli.ui._darwin_parent_tty_paths", lambda: ["/dev/ttys999"])
        monkeypatch.setattr(
            "app.cli.ui._ioctl_terminal_size_for_path",
            lambda path: (143, 41) if path == "/dev/ttys999" else None,
        )

        size = _terminal_size()

        assert size.columns == 143
        assert size.lines == 41

    def test_uses_darwin_parent_fd_tty_when_controlling_tty_is_missing(self, monkeypatch):
        monkeypatch.delenv("COLUMNS", raising=False)
        monkeypatch.delenv("LINES", raising=False)
        monkeypatch.delenv("YT_TOOL_TERM_COLUMNS", raising=False)
        monkeypatch.delenv("YT_TOOL_TERM_LINES", raising=False)
        monkeypatch.setattr("app.cli.ui.platform.system", lambda: "Darwin")
        monkeypatch.setattr("app.cli.ui._ioctl_terminal_size", lambda: None)
        monkeypatch.setattr("app.cli.ui._darwin_parent_tty_paths", lambda: [])
        monkeypatch.setattr("app.cli.ui._darwin_parent_fd_tty_paths", lambda: ["/dev/ttys123"])
        monkeypatch.setattr(
            "app.cli.ui._ioctl_terminal_size_for_path",
            lambda path: (101, 27) if path == "/dev/ttys123" else None,
        )

        size = _terminal_size()

        assert size.columns == 101
        assert size.lines == 27

    def test_rechecks_width_on_every_call_instead_of_caching(self, monkeypatch):
        monkeypatch.delenv("COLUMNS", raising=False)
        monkeypatch.delenv("LINES", raising=False)
        monkeypatch.delenv("YT_TOOL_TERM_COLUMNS", raising=False)
        monkeypatch.delenv("YT_TOOL_TERM_LINES", raising=False)
        monkeypatch.setattr("app.cli.ui.platform.system", lambda: "Darwin")
        monkeypatch.setattr("app.cli.ui._ioctl_terminal_size", lambda: None)
        monkeypatch.setattr("app.cli.ui._darwin_parent_tty_paths", lambda: ["/dev/ttys999"])
        sizes = iter([(120, 33), (88, 33)])
        monkeypatch.setattr("app.cli.ui._ioctl_terminal_size_for_path", lambda path: next(sizes))

        first = _terminal_size()
        second = _terminal_size()

        assert first.columns == 120
        assert second.columns == 88


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
