#!/usr/bin/env python3
"""Prepare vendored binaries for the Swift macOS build.

Downloads and verifies yt-dlp, ffmpeg, and ffprobe into the target directory.
All source URLs must be pinned (no /latest/ or mutable paths).
"""
from __future__ import annotations

import argparse
import hashlib
import shutil
import stat
import sys
import tempfile
import time
import urllib.request
import zipfile
from pathlib import Path


def _die(message: str, code: int = 2) -> None:
    print(message, file=sys.stderr)
    raise SystemExit(code)


def _is_mutable_url(url: str) -> bool:
    return "/latest/" in url


def _normalize_sha256(value: str) -> str:
    return value.strip().lower()


def _sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest().lower()


def _download(url: str, out_path: Path, *, retries: int = 5, delay_sec: int = 2) -> None:
    last_error: Exception | None = None
    for attempt in range(1, retries + 1):
        try:
            with urllib.request.urlopen(url) as resp, out_path.open("wb") as out:
                shutil.copyfileobj(resp, out)
            return
        except Exception as exc:
            last_error = exc
            if attempt >= retries:
                break
            time.sleep(delay_sec)
    _die(f"Failed to download after {retries} attempts: {url}\n{last_error}")


def _verify_sha256(path: Path, expected: str, *, source_url: str, label: str) -> None:
    actual = _sha256(path)
    expected_norm = _normalize_sha256(expected)
    if actual != expected_norm:
        _die(
            "\n".join([
                f"{label} SHA256 mismatch.",
                f"  expected: {expected_norm}",
                f"  actual  : {actual}",
                f"  source  : {source_url}",
            ])
        )


def _extract_named_member(archive: Path, candidates: list[str], out_path: Path) -> bool:
    with zipfile.ZipFile(archive) as zf:
        for name in zf.namelist():
            base = name.rsplit("/", 1)[-1]
            for candidate in candidates:
                if name == candidate or base == candidate:
                    with zf.open(name) as src, out_path.open("wb") as dst:
                        shutil.copyfileobj(src, dst)
                    return True
    return False


def _ensure_executable(path: Path) -> None:
    if not path.exists():
        return
    mode = path.stat().st_mode
    path.chmod(mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def _is_executable_file(path: Path) -> bool:
    return path.is_file() and (path.stat().st_mode & stat.S_IXUSR) != 0


def _prepare_ytdlp(
    *,
    vendor_bin_dir: Path,
    clean: bool,
    url: str,
    sha256: str,
) -> None:
    if not url:
        _die("Missing yt-dlp URL. Set --ytdlp-url.")
    if not sha256:
        _die("Missing yt-dlp SHA256. Set --ytdlp-sha256.")
    if _is_mutable_url(url):
        _die(f"Refuse mutable yt-dlp URL: {url}")

    out = vendor_bin_dir / "yt-dlp"
    if not clean and _is_executable_file(out):
        print(f"yt-dlp already present: {out}")
        return

    with tempfile.TemporaryDirectory(prefix="yt-tool-ytdlp-") as tmp:
        tmp_file = Path(tmp) / "yt-dlp"
        print("Downloading yt-dlp...")
        _download(url, tmp_file)
        _verify_sha256(tmp_file, sha256, source_url=url, label="yt-dlp")
        shutil.copy2(tmp_file, out)

    _ensure_executable(out)
    print(f"yt-dlp binary: {out}")


def _prepare_ffmpeg(
    *,
    vendor_bin_dir: Path,
    clean: bool,
    ffmpeg_url: str,
    ffmpeg_sha256: str,
    ffprobe_url: str,
    ffprobe_sha256: str,
) -> None:
    if not ffmpeg_url:
        _die("Missing ffmpeg URL. Set --ffmpeg-url.")
    if not ffmpeg_sha256:
        _die("Missing ffmpeg SHA256. Set --ffmpeg-sha256.")
    if not ffprobe_url:
        _die("Missing ffprobe URL. Set --ffprobe-url.")
    if not ffprobe_sha256:
        _die("Missing ffprobe SHA256. Set --ffprobe-sha256.")
    if _is_mutable_url(ffmpeg_url):
        _die(f"Refuse mutable ffmpeg URL: {ffmpeg_url}")
    if _is_mutable_url(ffprobe_url):
        _die(f"Refuse mutable ffprobe URL: {ffprobe_url}")

    ffmpeg_bin = vendor_bin_dir / "ffmpeg"
    ffprobe_bin = vendor_bin_dir / "ffprobe"

    if not clean and _is_executable_file(ffmpeg_bin) and _is_executable_file(ffprobe_bin):
        print(f"ffmpeg binaries already present: {ffmpeg_bin} / {ffprobe_bin}")
        return

    with tempfile.TemporaryDirectory(prefix="yt-tool-ffmpeg-") as tmp:
        tmp_dir = Path(tmp)

        print("Downloading ffmpeg archive...")
        ffmpeg_archive = tmp_dir / "ffmpeg.zip"
        _download(ffmpeg_url, ffmpeg_archive)
        _verify_sha256(ffmpeg_archive, ffmpeg_sha256, source_url=ffmpeg_url, label="ffmpeg")

        _extract_named_member(ffmpeg_archive, ["ffmpeg"], ffmpeg_bin)
        _extract_named_member(ffmpeg_archive, ["ffprobe"], ffprobe_bin)

        if not ffprobe_bin.exists():
            print("Downloading ffprobe archive...")
            ffprobe_archive = tmp_dir / "ffprobe.zip"
            _download(ffprobe_url, ffprobe_archive)
            _verify_sha256(ffprobe_archive, ffprobe_sha256, source_url=ffprobe_url, label="ffprobe")
            _extract_named_member(ffprobe_archive, ["ffprobe"], ffprobe_bin)

    if not ffmpeg_bin.exists():
        _die(f"ffmpeg archive does not contain ffmpeg: {ffmpeg_url}")
    if not ffprobe_bin.exists():
        _die(f"ffprobe archive does not contain ffprobe: {ffprobe_url}")
    _ensure_executable(ffmpeg_bin)
    _ensure_executable(ffprobe_bin)
    print(f"ffmpeg binary: {ffmpeg_bin}")
    print(f"ffprobe binary: {ffprobe_bin}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare binaries for the Swift macOS build.")
    parser.add_argument("--vendor-bin-dir", required=True, help="Output directory for binaries.")
    parser.add_argument("--clean", action="store_true", help="Re-download even if already present.")
    parser.add_argument("--ytdlp-url", default="", help="Pinned yt-dlp download URL.")
    parser.add_argument("--ytdlp-sha256", default="", help="Expected SHA256 of the yt-dlp binary.")
    parser.add_argument("--ffmpeg-url", default="", help="Pinned ffmpeg archive URL.")
    parser.add_argument("--ffmpeg-sha256", default="", help="Expected SHA256 of ffmpeg archive.")
    parser.add_argument("--ffprobe-url", default="", help="Pinned ffprobe archive URL.")
    parser.add_argument("--ffprobe-sha256", default="", help="Expected SHA256 of ffprobe archive.")
    parser.add_argument(
        "--skip",
        choices=["ytdlp", "ffmpeg"],
        nargs="*",
        default=[],
        help="Skip downloading specific tools.",
    )
    args = parser.parse_args()

    vendor_bin_dir = Path(args.vendor_bin_dir)
    vendor_bin_dir.mkdir(parents=True, exist_ok=True)

    skip = set(args.skip or [])

    if "ytdlp" not in skip:
        _prepare_ytdlp(
            vendor_bin_dir=vendor_bin_dir,
            clean=args.clean,
            url=args.ytdlp_url,
            sha256=args.ytdlp_sha256,
        )

    if "ffmpeg" not in skip:
        _prepare_ffmpeg(
            vendor_bin_dir=vendor_bin_dir,
            clean=args.clean,
            ffmpeg_url=args.ffmpeg_url,
            ffmpeg_sha256=args.ffmpeg_sha256,
            ffprobe_url=args.ffprobe_url,
            ffprobe_sha256=args.ffprobe_sha256,
        )

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
