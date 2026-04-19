from __future__ import annotations

import importlib.util
import stat
from pathlib import Path

import pytest


def _load_prepare_module():
    repo_root = Path(__file__).resolve().parent.parent
    module_path = repo_root / "scripts" / "build" / "common" / "prepare_ffmpeg.py"
    spec = importlib.util.spec_from_file_location("prepare_ffmpeg", module_path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class TestPrepareFfmpeg:
    def test_macos_preflight_runs_even_when_cached(self, tmp_path):
        mod = _load_prepare_module()
        vendor = tmp_path / "vendor-bin"
        vendor.mkdir()
        ffmpeg = vendor / "ffmpeg"
        ffprobe = vendor / "ffprobe"
        ffmpeg.write_text("bin")
        ffprobe.write_text("bin")
        ffmpeg.chmod(ffmpeg.stat().st_mode | stat.S_IXUSR)
        ffprobe.chmod(ffprobe.stat().st_mode | stat.S_IXUSR)

        # Missing URL should fail before cache short-circuit.
        with pytest.raises(SystemExit) as exc:
            mod._prepare_macos(
                vendor_bin_dir=vendor,
                clean=False,
                ffmpeg_url="",
                ffmpeg_sha256="deadbeef",
                ffprobe_url="https://example.com/ffprobe.zip",
                ffprobe_sha256="deadbeef",
            )
        assert exc.value.code == 2

    def test_macos_non_executable_cache_does_not_short_circuit(self, tmp_path, monkeypatch):
        mod = _load_prepare_module()
        vendor = tmp_path / "vendor-bin"
        vendor.mkdir()
        ffmpeg = vendor / "ffmpeg"
        ffprobe = vendor / "ffprobe"
        ffmpeg.write_text("bin")
        ffprobe.write_text("bin")
        ffmpeg.chmod(0o644)
        ffprobe.chmod(0o644)

        called = {"download": 0}

        def fake_download(url: str, out_path: Path, *, retries: int = 5, delay_sec: int = 2):
            called["download"] += 1
            out_path.write_bytes(b"fake")

        def fake_verify(path: Path, expected: str, *, source_url: str, label: str):
            return None

        def fake_extract(archive: Path, candidates: list[str], out_path: Path):
            out_path.write_text("bin")
            return True

        monkeypatch.setattr(mod, "_download", fake_download)
        monkeypatch.setattr(mod, "_verify_sha256", fake_verify)
        monkeypatch.setattr(mod, "_extract_named_member", fake_extract)

        mod._prepare_macos(
            vendor_bin_dir=vendor,
            clean=False,
            ffmpeg_url="https://example.com/ffmpeg.zip",
            ffmpeg_sha256="deadbeef",
            ffprobe_url="https://example.com/ffprobe.zip",
            ffprobe_sha256="deadbeef",
        )

        # Non-executable cache should trigger download path.
        assert called["download"] >= 1
        assert ffmpeg.exists()
        assert ffprobe.exists()
        assert ffmpeg.stat().st_mode & stat.S_IXUSR
        assert ffprobe.stat().st_mode & stat.S_IXUSR

    def test_windows_preflight_rejects_mutable_url_even_when_cached(self, tmp_path):
        mod = _load_prepare_module()
        vendor = tmp_path / "vendor-bin"
        vendor.mkdir()
        (vendor / "ffmpeg.exe").write_text("bin")
        (vendor / "ffprobe.exe").write_text("bin")

        with pytest.raises(SystemExit) as exc:
            mod._prepare_windows(
                vendor_bin_dir=vendor,
                clean=False,
                ffmpeg_url="https://example.com/latest/ffmpeg-win.zip",
                ffmpeg_sha256="deadbeef",
            )
        assert exc.value.code == 2
