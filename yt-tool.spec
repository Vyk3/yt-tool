# -*- mode: python ; coding: utf-8 -*-
import os

# Bundle the yt-dlp and ffmpeg binaries so the app works without system installs.
# Optional bundled helper binaries:
# - yt-dlp is expected by default.
# - ffmpeg/ffprobe are optional and included when present in vendor/bin.
_ext = '.exe' if os.name == 'nt' else ''
_optional_bins = [
    f'vendor/bin/yt-dlp{_ext}',
    f'vendor/bin/ffmpeg{_ext}',
    f'vendor/bin/ffprobe{_ext}',
]
_extra_binaries = [(path, '.') for path in _optional_bins if os.path.isfile(path)]

a = Analysis(
    ['run.py'],
    pathex=['.', 'vendor'],
    binaries=_extra_binaries,
    datas=[],
    hiddenimports=[],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    [],
    exclude_binaries=True,
    name='yt-tool',
    debug=False,
    bootloader_ignore_signals=False,
    strip=True,
    upx=True,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
coll = COLLECT(
    exe,
    a.binaries,
    a.datas,
    strip=True,
    upx=True,
    upx_exclude=[],
    name='yt-tool',
)
app = BUNDLE(
    coll,
    name='yt-tool.app',
    icon=None,
    bundle_identifier=None,
)
