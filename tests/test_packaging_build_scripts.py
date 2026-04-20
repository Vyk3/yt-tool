from __future__ import annotations

import os
import runpy
import subprocess
import textwrap
from contextlib import contextmanager
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
SPEC_PATH = REPO_ROOT / "yt-tool.spec"
MAC_BUILD_SCRIPT = REPO_ROOT / "scripts" / "build" / "macos" / "build_app.sh"
WINDOWS_BUILD_SCRIPT = REPO_ROOT / "scripts" / "build" / "windows" / "build_exe.ps1"
WINDOWS_BUILD_BAT = REPO_ROOT / "scripts" / "build" / "windows" / "build_exe.bat"


@contextmanager
def _pushd(path: Path):
    prev = Path.cwd()
    os.chdir(path)
    try:
        yield
    finally:
        os.chdir(prev)


class _FakeAnalysis:
    def __init__(self, *args, **kwargs):
        self.pure = []
        self.scripts = []
        self.binaries = kwargs["binaries"]
        self.datas = kwargs["datas"]


def _fake_pyz(*args, **kwargs):
    return {"args": args, "kwargs": kwargs}


def _fake_exe(*args, **kwargs):
    return {"args": args, "kwargs": kwargs}


def _fake_collect(*args, **kwargs):
    return {"args": args, "kwargs": kwargs}


def _fake_bundle(*args, **kwargs):
    return {"args": args, "kwargs": kwargs}


def _load_spec_globals(project_dir: Path) -> dict[str, object]:
    init_globals = {
        "Analysis": _FakeAnalysis,
        "PYZ": _fake_pyz,
        "EXE": _fake_exe,
        "COLLECT": _fake_collect,
        "BUNDLE": _fake_bundle,
    }
    with _pushd(project_dir):
        return runpy.run_path(str(project_dir / "yt-tool.spec"), init_globals=init_globals)


def test_spec_only_bundles_ffmpeg_license_when_helper_binaries_exist(tmp_path):
    project_dir = tmp_path / "project"
    project_dir.mkdir()
    (project_dir / "yt-tool.spec").write_text(SPEC_PATH.read_text())
    (project_dir / "LICENSE_FFMPEG.txt").write_text("license")

    globals_no_bins = _load_spec_globals(project_dir)
    assert globals_no_bins["_extra_binaries"] == []
    assert globals_no_bins["_extra_datas"] == []

    vendor_bin = project_dir / "vendor" / "bin"
    vendor_bin.mkdir(parents=True)
    (vendor_bin / "ffmpeg").write_text("bin")

    globals_with_bin = _load_spec_globals(project_dir)
    assert globals_with_bin["_extra_binaries"] == [("vendor/bin/ffmpeg", ".")]
    assert globals_with_bin["_extra_datas"] == [("LICENSE_FFMPEG.txt", ".")]


def test_spec_uses_env_override_for_bundle_name(tmp_path, monkeypatch):
    project_dir = tmp_path / "project"
    project_dir.mkdir()
    (project_dir / "yt-tool.spec").write_text(SPEC_PATH.read_text())

    monkeypatch.setenv("YT_TOOL_BUILD_NAME", "custom-tool")
    spec_globals = _load_spec_globals(project_dir)

    assert spec_globals["_app_name"] == "custom-tool"
    assert spec_globals["exe"]["kwargs"]["name"] == "custom-tool"
    assert spec_globals["coll"]["kwargs"]["name"] == "custom-tool"
    assert spec_globals["app"]["kwargs"]["name"] == "custom-tool.app"


def test_macos_clean_build_without_ffmpeg_removes_stale_vendor_binaries(tmp_path):
    project_dir = tmp_path / "project"
    script_dir = project_dir / "scripts" / "build" / "macos"
    script_dir.mkdir(parents=True)
    build_script = script_dir / "build_app.sh"
    build_script.write_text(MAC_BUILD_SCRIPT.read_text())
    build_script.chmod(0o755)

    (project_dir / "yt-tool.spec").write_text("# test spec\n")
    vendor_bin = project_dir / "vendor" / "bin"
    vendor_bin.mkdir(parents=True)
    stale_ffmpeg = vendor_bin / "ffmpeg"
    stale_ffprobe = vendor_bin / "ffprobe"
    stale_ffmpeg.write_text("old")
    stale_ffprobe.write_text("old")

    fake_python = project_dir / ".venv" / "bin" / "python3"
    fake_python.parent.mkdir(parents=True)
    fake_python.write_text(
        textwrap.dedent(
            f"""\
            #!/bin/zsh
            set -euo pipefail
            if [[ "$1" == "-c" ]]; then
              exit 0
            fi
            if [[ "$1" == "-m" && "$2" == "PyInstaller" ]]; then
              mkdir -p "{project_dir}/dist/yt-tool.app"
              exit 0
            fi
            echo "unexpected python args: $@" >&2
            exit 1
            """
        )
    )
    fake_python.chmod(0o755)

    fake_bin = tmp_path / "fake-bin"
    fake_bin.mkdir()
    codesign = fake_bin / "codesign"
    codesign.write_text("#!/bin/zsh\nexit 0\n")
    codesign.chmod(0o755)
    hdiutil = fake_bin / "hdiutil"
    hdiutil.write_text(
        textwrap.dedent(
            """\
            #!/bin/zsh
            set -euo pipefail
            touch "${@: -1}"
            """
        )
    )
    hdiutil.chmod(0o755)

    env = os.environ.copy()
    env["PATH"] = f"{fake_bin}:{env['PATH']}"
    subprocess.run(
        ["zsh", str(build_script), "--clean"],
        check=True,
        cwd=project_dir,
        env=env,
    )

    assert not stale_ffmpeg.exists()
    assert not stale_ffprobe.exists()
    assert (project_dir / "dist" / "yt-tool.app").exists()
    assert (project_dir / "dist" / "yt-tool-macOS.dmg").exists()


def test_windows_script_cleans_stale_vendor_binaries_for_clean_baseline_build():
    text = WINDOWS_BUILD_SCRIPT.read_text()
    assert "if ($Clean -and -not $WithFfmpeg)" in text
    assert "@('ffmpeg.exe', 'ffprobe.exe')" in text
    assert "Remove-Item -Force $stalePath" in text


def test_windows_script_passes_requested_name_through_env():
    text = WINDOWS_BUILD_SCRIPT.read_text()
    assert '$env:YT_TOOL_BUILD_NAME = $Name' in text
    assert 'Remove-Item Env:\\YT_TOOL_BUILD_NAME' in text


def test_windows_bat_wrapper_delegates_to_powershell_spec_entrypoint():
    text = WINDOWS_BUILD_BAT.read_text()
    assert "build_exe.ps1" in text
    assert "-ExecutionPolicy Bypass -File" in text
    assert "-WithFfmpeg" in text
    assert "app\\__main__.py" not in text
