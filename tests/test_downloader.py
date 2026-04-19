"""downloader.py 单元测试。"""
from __future__ import annotations

from pathlib import Path
from unittest.mock import patch

from app.core.downloader import (
    DownloadResult,
    _common_args,
    _run_ytdlp,
    _RunState,
    _stream_process_output,
    download_audio,
    download_auto_subs,
    download_playlist,
    download_subs,
    download_video,
)


def _ok_result(saved_path: str = "") -> DownloadResult:
    return DownloadResult(ok=True, output="ok", error="", saved_path=saved_path)


_SNAPSHOT_SWITCHES = {
    "--abort-on-error",
    "--embed-subs",
    "--no-abort-on-error",
    "--no-progress",
    "--no-warnings",
    "--skip-download",
    "--write-auto-subs",
    "--write-subs",
    "--yes-playlist",
    "-x",
}
_SNAPSHOT_OPTIONS = {
    "--audio-format",
    "--convert-subs",
    "--cookies-from-browser",
    "--download-archive",
    "--extractor-args",
    "--merge-output-format",
    "--playlist-items",
    "--sponsorblock-mark",
    "--sub-format",
    "--sub-langs",
    "-f",
    "-o",
}


def _normalize_snapshot_value(flag: str, value: str) -> str | dict[str, str]:
    if flag != "--download-archive":
        return value

    archive_path = Path(value)
    name = archive_path.name
    for mode in ("video", "audio"):
        prefix = f".yt-dl-archive-{mode}-"
        if name.startswith(prefix) and name.endswith(".txt"):
            name = f"{prefix}<hash>.txt"
            break
    return {"dir": str(archive_path.parent), "name": name}


def _args_snapshot(args: list[str]) -> dict[str, object]:
    switches: list[str] = []
    options: list[tuple[str, str | dict[str, str]]] = []
    unknown: list[str] = []
    idx = 0
    tokens = args[:-1]
    while idx < len(tokens):
        token = tokens[idx]
        if token in _SNAPSHOT_SWITCHES:
            switches.append(token)
            idx += 1
        elif token in _SNAPSHOT_OPTIONS:
            if idx + 1 >= len(tokens):
                unknown.append(token)
                idx += 1
                continue
            options.append((token, _normalize_snapshot_value(token, tokens[idx + 1])))
            idx += 2
        else:
            unknown.append(token)
            idx += 1

    return {
        "switches": tuple(switches),
        "options": tuple(options),
        "url": args[-1],
        "unknown": tuple(unknown),
    }


def _assert_args_snapshot(args: list[str], expected: dict[str, object]) -> None:
    snapshot = _args_snapshot(args)
    assert snapshot["unknown"] == ()
    assert {k: v for k, v in snapshot.items() if k != "unknown"} == expected


class TestCommonArgs:
    def test_default_has_no_warnings(self):
        args = _common_args()
        assert "--no-warnings" in args

    def test_no_progress_when_disabled(self):
        with patch("app.core.downloader.config") as mock_cfg:
            mock_cfg.YT_SHOW_PROGRESS = False
            args = _common_args()
            assert "--no-progress" in args

    def test_no_no_progress_when_enabled(self):
        with patch("app.core.downloader.config") as mock_cfg:
            mock_cfg.YT_SHOW_PROGRESS = True
            args = _common_args()
            assert "--no-progress" not in args


class TestRunYtdlp:
    def test_tty_progress_uses_streaming_mode(self, monkeypatch):
        monkeypatch.setattr("app.core.downloader.config.YT_SHOW_PROGRESS", True)
        monkeypatch.setattr("app.core.downloader.sys.stdout.isatty", lambda: True)
        state = _RunState(
            returncode=0,
            output='[download] Destination: "/tmp/x.mp4"\n',
            saved_path="/tmp/x.mp4",
            error_line="",
        )
        with patch("app.core.downloader._run_with_yt_dlp_api", return_value=state) as mock_run:
            result = _run_ytdlp(["http://example.com"])
            assert result.ok is True
            assert result.saved_path == "/tmp/x.mp4"
            mock_run.assert_called_once_with(
                ["yt-dlp", "http://example.com"],
                on_chunk=None,
                emit_stdout=True,
            )

    def test_on_chunk_forces_streaming_in_non_tty(self, monkeypatch):
        monkeypatch.setattr("app.core.downloader.config.YT_SHOW_PROGRESS", False)
        monkeypatch.setattr("app.core.downloader.sys.stdout.isatty", lambda: False)
        chunks: list[str] = []
        state = _RunState(returncode=0, output="ok\n", saved_path="", error_line="")
        with patch("app.core.downloader._run_with_yt_dlp_api", return_value=state) as mock_run:
            result = _run_ytdlp(["http://example.com"], on_chunk=chunks.append)
            assert result.ok is True
            mock_run.assert_called_once_with(
                ["yt-dlp", "http://example.com"],
                on_chunk=chunks.append,
                emit_stdout=False,
            )

    def test_failure_uses_error_line(self, monkeypatch):
        monkeypatch.setattr("app.core.downloader.config.YT_SHOW_PROGRESS", False)
        monkeypatch.setattr("app.core.downloader.sys.stdout.isatty", lambda: False)
        state = _RunState(
            returncode=1,
            output="line1\nERROR: bad\n",
            saved_path="",
            error_line="ERROR: bad",
        )
        with patch("app.core.downloader._run_with_yt_dlp_api", return_value=state):
            result = _run_ytdlp(["http://example.com"])
            assert result.ok is False
            assert "yt-dlp exited 1" in result.error
            assert "ERROR: bad" in result.error


class TestDownloadVideo:
    def test_empty_url_fails(self):
        result = download_video("", "137", "/tmp")
        assert result.ok is False
        assert "required" in result.error

    def test_empty_format_fails(self):
        result = download_video("http://example.com", "", "/tmp")
        assert result.ok is False

    def test_success_forwards_args(self, tmp_path):
        with patch("app.core.downloader._run_ytdlp", return_value=_ok_result("/tmp/out.mp4")) as mock_run:
            result = download_video("http://example.com/v", "137", str(tmp_path))
            assert result.ok is True
            assert result.saved_path == "/tmp/out.mp4"
            args = mock_run.call_args.args[0]
            assert "-f" in args
            assert "137" in args
            assert "--merge-output-format" in args
            assert str(tmp_path / "%(title)s.%(ext)s") in args

    def test_embed_subs_adds_required_args(self, tmp_path):
        with patch("app.core.downloader._run_ytdlp", return_value=_ok_result()) as mock_run:
            result = download_video(
                "http://example.com/v",
                "137",
                str(tmp_path),
                embed_subs_lang="en",
            )
            assert result.ok is True
            args = mock_run.call_args.args[0]
            assert "--write-subs" in args
            assert "--embed-subs" in args
            assert "--sub-langs" in args
            assert "en" in args
            assert "--sub-format" in args

    def test_no_download_archive_for_single_video(self, tmp_path):
        with patch("app.core.downloader._run_ytdlp", return_value=_ok_result()) as mock_run:
            result = download_video("http://example.com/v", "137", str(tmp_path))
            assert result.ok is True
            args = mock_run.call_args.args[0]
            assert "--download-archive" not in args

    def test_bad_dir_fails(self, tmp_path):
        file_path = tmp_path / "afile"
        file_path.write_text("x")
        result = download_video("http://example.com/v", "137", str(file_path))
        assert result.ok is False
        assert "不是目录" in result.error


class TestDownloadArgSnapshots:
    def test_video_args_snapshot(self, tmp_path):
        with patch("app.core.downloader._run_ytdlp", return_value=_ok_result()) as mock_run:
            result = download_video(
                "http://example.com/v",
                "137",
                str(tmp_path),
                cookies_from="chrome",
                embed_subs_lang="en",
                extra_args=["--playlist-items", "1"],
            )

        assert result.ok is True
        _assert_args_snapshot(mock_run.call_args.args[0], {
            "switches": (
                "--no-warnings",
                "--write-subs",
                "--embed-subs",
            ),
            "options": (
                ("--cookies-from-browser", "chrome"),
                ("-f", "137"),
                ("--merge-output-format", "mp4"),
                ("--sub-langs", "en"),
                ("--sub-format", "best"),
                ("--playlist-items", "1"),
                ("-o", str(tmp_path / "%(title)s.%(ext)s")),
            ),
            "url": "http://example.com/v",
        })

    def test_audio_args_snapshot(self, tmp_path):
        with patch("app.core.downloader._run_ytdlp", return_value=_ok_result()) as mock_run:
            result = download_audio(
                "http://example.com/a",
                "140",
                str(tmp_path),
                cookies_from="firefox",
                transcode_to="mp3",
                extra_args=["--extractor-args", "youtube:player_client=web"],
            )

        assert result.ok is True
        _assert_args_snapshot(mock_run.call_args.args[0], {
            "switches": (
                "--no-warnings",
                "-x",
            ),
            "options": (
                ("--cookies-from-browser", "firefox"),
                ("-f", "140"),
                ("--audio-format", "mp3"),
                ("--extractor-args", "youtube:player_client=web"),
                ("-o", str(tmp_path / "%(title)s.%(ext)s")),
            ),
            "url": "http://example.com/a",
        })

    def test_subs_args_snapshot(self, tmp_path):
        with patch("app.core.downloader._run_ytdlp", return_value=_ok_result()) as mock_run:
            result = download_subs(
                "http://example.com/subs",
                "zh-Hans",
                str(tmp_path),
                cookies_from="chrome",
                extra_args=["--convert-subs", "srt"],
            )

        assert result.ok is True
        _assert_args_snapshot(mock_run.call_args.args[0], {
            "switches": (
                "--no-warnings",
                "--write-subs",
                "--skip-download",
            ),
            "options": (
                ("--cookies-from-browser", "chrome"),
                ("--sub-langs", "zh-Hans"),
                ("--sub-format", "best"),
                ("--convert-subs", "srt"),
                ("-o", str(tmp_path / "%(title)s.%(ext)s")),
            ),
            "url": "http://example.com/subs",
        })

    def test_auto_subs_args_snapshot(self, tmp_path):
        with patch("app.core.downloader._run_ytdlp", return_value=_ok_result()) as mock_run:
            result = download_auto_subs(
                "http://example.com/auto",
                "en",
                str(tmp_path),
                cookies_from="firefox",
                extra_args=["--convert-subs", "vtt"],
            )

        assert result.ok is True
        _assert_args_snapshot(mock_run.call_args.args[0], {
            "switches": (
                "--no-warnings",
                "--write-auto-subs",
                "--skip-download",
            ),
            "options": (
                ("--cookies-from-browser", "firefox"),
                ("--sub-langs", "en"),
                ("--sub-format", "best"),
                ("--convert-subs", "vtt"),
                ("-o", str(tmp_path / "%(title)s.%(ext)s")),
            ),
            "url": "http://example.com/auto",
        })

    def test_playlist_video_args_snapshot(self, tmp_path):
        with patch("app.core.downloader.config.YT_USE_DOWNLOAD_ARCHIVE", True), \
             patch("app.core.downloader.config.YT_PLAYLIST_CONTINUE_ON_ERROR", True), \
             patch("app.core.downloader.shutil.which", return_value="/usr/bin/ffmpeg"), \
             patch("app.core.downloader._run_ytdlp", return_value=_ok_result()) as mock_run:
            result = download_playlist(
                "http://example.com/list",
                "video",
                str(tmp_path),
                cookies_from="chrome",
                extra_args=["--sponsorblock-mark", "sponsor,intro"],
            )

        assert result.ok is True
        _assert_args_snapshot(mock_run.call_args.args[0], {
            "switches": (
                "--no-warnings",
                "--no-abort-on-error",
                "--yes-playlist",
            ),
            "options": (
                ("--cookies-from-browser", "chrome"),
                (
                    "--download-archive",
                    {
                        "dir": str(tmp_path),
                        "name": ".yt-dl-archive-video-<hash>.txt",
                    },
                ),
                ("-f", "bestvideo+bestaudio/best"),
                ("--merge-output-format", "mp4"),
                ("--sponsorblock-mark", "sponsor,intro"),
                (
                    "-o",
                    str(tmp_path / "%(playlist_title)s" / "%(playlist_index)s - %(title)s.%(ext)s"),
                ),
            ),
            "url": "http://example.com/list",
        })

    def test_playlist_audio_args_snapshot(self, tmp_path):
        with patch("app.core.downloader.config.YT_USE_DOWNLOAD_ARCHIVE", True), \
             patch("app.core.downloader.config.YT_PLAYLIST_CONTINUE_ON_ERROR", False), \
             patch("app.core.downloader._run_ytdlp", return_value=_ok_result()) as mock_run:
            result = download_playlist(
                "http://example.com/list-audio",
                "audio",
                str(tmp_path),
                cookies_from="firefox",
            )

        assert result.ok is True
        _assert_args_snapshot(mock_run.call_args.args[0], {
            "switches": (
                "--no-warnings",
                "--abort-on-error",
                "--yes-playlist",
            ),
            "options": (
                ("--cookies-from-browser", "firefox"),
                (
                    "--download-archive",
                    {
                        "dir": str(tmp_path),
                        "name": ".yt-dl-archive-audio-<hash>.txt",
                    },
                ),
                ("-f", "bestaudio"),
                (
                    "-o",
                    str(tmp_path / "%(playlist_title)s" / "%(playlist_index)s - %(title)s.%(ext)s"),
                ),
            ),
            "url": "http://example.com/list-audio",
        })


class TestDownloadAudio:
    def test_empty_params_fail(self):
        assert download_audio("", "140", "/tmp").ok is False
        assert download_audio("http://x", "", "/tmp").ok is False

    def test_success(self, tmp_path):
        with patch("app.core.downloader._run_ytdlp", return_value=_ok_result()) as mock_run:
            result = download_audio("http://x", "140", str(tmp_path))
            assert result.ok is True
            args = mock_run.call_args.args[0]
            assert "-f" in args
            assert "140" in args

    def test_transcode_adds_args(self, tmp_path):
        with patch("app.core.downloader._run_ytdlp", return_value=_ok_result()) as mock_run:
            result = download_audio("http://x", "140", str(tmp_path), transcode_to="mp3")
            assert result.ok is True
            args = mock_run.call_args.args[0]
            assert "-x" in args
            assert "--audio-format" in args
            assert "mp3" in args


class TestDownloadSubs:
    def test_empty_params_fail(self):
        assert download_subs("", "en", "/tmp").ok is False
        assert download_subs("http://x", "", "/tmp").ok is False

    def test_success(self, tmp_path):
        with patch("app.core.downloader._run_ytdlp", return_value=_ok_result()) as mock_run:
            result = download_subs("http://x", "en", str(tmp_path))
            assert result.ok is True
            args = mock_run.call_args.args[0]
            assert "--write-subs" in args
            assert "--skip-download" in args

    def test_auto_subs_uses_auto_flag(self, tmp_path):
        with patch("app.core.downloader._run_ytdlp", return_value=_ok_result()) as mock_run:
            result = download_auto_subs("http://x", "en", str(tmp_path))
            assert result.ok is True
            args = mock_run.call_args.args[0]
            assert "--write-auto-subs" in args
            assert "--write-subs" not in args


class TestDownloadPlaylist:
    def test_continue_on_error_config_is_applied(self, tmp_path):
        with patch("app.core.downloader.config.YT_PLAYLIST_CONTINUE_ON_ERROR", False), \
             patch("app.core.downloader._run_ytdlp", return_value=_ok_result()) as mock_run:
            result = download_playlist("http://example.com/list", "video", str(tmp_path))
            assert result.ok is True
            args = mock_run.call_args.args[0]
            assert "--abort-on-error" in args
            assert "--no-abort-on-error" not in args

    def test_extra_args_are_forwarded(self, tmp_path):
        with patch("app.core.downloader._run_ytdlp", return_value=_ok_result()) as mock_run:
            result = download_playlist(
                "http://example.com/list",
                "video",
                str(tmp_path),
                extra_args=["--sponsorblock-mark", "sponsor,intro"],
            )
            assert result.ok is True
            args = mock_run.call_args.args[0]
            assert "--sponsorblock-mark" in args


class TestStreamProcessOutput:
    def test_on_chunk_mode(self):
        chunks: list[str] = []
        state = _RunState(returncode=0, output="h\ni\n", saved_path="", error_line="")
        with patch("app.core.downloader._run_with_yt_dlp_api", return_value=state) as mock_run:
            rc, output = _stream_process_output(["yt-dlp", "http://example.com"], on_chunk=chunks.append)
            assert rc == 0
            assert output == "h\ni\n"
            mock_run.assert_called_once_with(
                ["yt-dlp", "http://example.com"],
                on_chunk=chunks.append,
                emit_stdout=False,
            )

    def test_stdout_mode(self):
        state = _RunState(returncode=0, output="x\n", saved_path="", error_line="")
        with patch("app.core.downloader._run_with_yt_dlp_api", return_value=state) as mock_run:
            rc, output = _stream_process_output(["yt-dlp", "http://example.com"])
            assert rc == 0
            assert output == "x\n"
            mock_run.assert_called_once_with(
                ["yt-dlp", "http://example.com"],
                on_chunk=None,
                emit_stdout=True,
            )
