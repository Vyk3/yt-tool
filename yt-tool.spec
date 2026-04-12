# -*- mode: python ; coding: utf-8 -*-
import os

# Bundle optional helper binaries into the app.
# ffmpeg/ffprobe are included when present in vendor/bin.
_ext = '.exe' if os.name == 'nt' else ''
_optional_bins = [
    f'vendor/bin/ffmpeg{_ext}',
    f'vendor/bin/ffprobe{_ext}',
]
_extra_binaries = [(path, '.') for path in _optional_bins if os.path.isfile(path)]
_extra_datas = []
if os.path.isfile('LICENSE_FFMPEG.txt'):
    _extra_datas.append(('LICENSE_FFMPEG.txt', '.'))

a = Analysis(
    ['run.py'],
    pathex=['.', 'vendor'],
    binaries=_extra_binaries,
    datas=_extra_datas,
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
    strip=False,
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
    strip=False,
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
