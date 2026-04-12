# -*- mode: python ; coding: utf-8 -*-
import os
from PyInstaller.utils.hooks import collect_all

pyside6_d, pyside6_b, pyside6_h = collect_all('PySide6')
shiboken6_d, shiboken6_b, shiboken6_h = collect_all('shiboken6')
ytdlp_d, ytdlp_b, ytdlp_h = collect_all('yt_dlp')

# Bundle the yt-dlp standalone binary so the app works without a system yt-dlp install.
# macOS uses 'yt-dlp' (no extension); Windows uses 'yt-dlp.exe'.
_ytdlp_bin = 'vendor/bin/yt-dlp.exe' if os.name == 'nt' else 'vendor/bin/yt-dlp'
_extra_binaries = [(_ytdlp_bin, '.')] if os.path.isfile(_ytdlp_bin) else []

a = Analysis(
    ['run.py'],
    pathex=['.', 'vendor'],
    binaries=[*pyside6_b, *shiboken6_b, *ytdlp_b, *_extra_binaries],
    datas=[*pyside6_d, *shiboken6_d, *ytdlp_d],
    hiddenimports=[*pyside6_h, *shiboken6_h, *ytdlp_h],
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
