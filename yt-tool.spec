# -*- mode: python ; coding: utf-8 -*-
import os

# Bundle optional helper binaries into the app.
# ffmpeg/ffprobe are included when present in vendor/bin.
_app_name = os.environ.get('YT_TOOL_BUILD_NAME', 'yt-tool')
_ext = '.exe' if os.name == 'nt' else ''
_optional_bins = [
    f'vendor/bin/ffmpeg{_ext}',
    f'vendor/bin/ffprobe{_ext}',
]
_extra_binaries = [(path, '.') for path in _optional_bins if os.path.isfile(path)]
_bundles_ffmpeg = bool(_extra_binaries)
_extra_datas = []
if _bundles_ffmpeg and os.path.isfile('LICENSE_FFMPEG.txt'):
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
    name=_app_name,
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
    name=_app_name,
)
app = BUNDLE(
    coll,
    name=f'{_app_name}.app',
    icon=None,
    bundle_identifier=None,
)
