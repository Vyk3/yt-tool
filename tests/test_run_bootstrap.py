from __future__ import annotations

import importlib
import os
import stat


def _load_run_module():
    module = importlib.import_module("run")
    return importlib.reload(module)


def test_patch_frozen_path_noop_when_not_frozen(monkeypatch):
    run_mod = _load_run_module()
    monkeypatch.setenv("PATH", "/usr/bin")
    monkeypatch.delattr(run_mod.sys, "_MEIPASS", raising=False)
    monkeypatch.setattr(run_mod.sys, "frozen", False, raising=False)

    run_mod._patch_frozen_path()

    assert os.environ["PATH"] == "/usr/bin"


def test_patch_frozen_path_adds_bundle_and_exec_bits(monkeypatch, tmp_path):
    run_mod = _load_run_module()
    ext = ".exe" if os.name == "nt" else ""

    helper_paths = [tmp_path / f"{name}{ext}" for name in ("yt-dlp", "ffmpeg", "ffprobe")]
    for helper_path in helper_paths:
        helper_path.write_text("x", encoding="utf-8")
        if os.name != "nt":
            helper_path.chmod(0o644)

    monkeypatch.setenv("PATH", "/usr/bin")
    monkeypatch.setattr(run_mod.sys, "frozen", True, raising=False)
    monkeypatch.setattr(run_mod.sys, "_MEIPASS", str(tmp_path), raising=False)

    run_mod._patch_frozen_path()

    assert os.environ["PATH"].startswith(f"{tmp_path}{os.pathsep}")
    if os.name != "nt":
        for helper_path in helper_paths:
            mode = helper_path.stat().st_mode
            assert mode & stat.S_IXUSR
            assert mode & stat.S_IXGRP
            assert mode & stat.S_IXOTH
