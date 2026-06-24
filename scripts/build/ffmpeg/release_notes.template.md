Minimal LGPL ffmpeg/ffprobe ${FFMPEG_VERSION} for yt-tool.

- FFmpeg ${FFMPEG_VERSION} (LGPL 2.1+)
- LAME ${LAME_VERSION} (LGPL 2.0)
- arch: arm64, macOS deployment target: 14.0
- Source tarballs included for LGPL compliance

Corresponding source:
- FFmpeg: https://ffmpeg.org/releases/ffmpeg-${FFMPEG_VERSION}.tar.xz
- LAME: https://sourceforge.net/projects/lame/files/lame/${LAME_VERSION}/lame-${LAME_VERSION}.tar.gz

LGPL notice: ffmpeg and ffprobe statically link libmp3lame (LGPL 2.0).
You may rebuild and replace these binaries using the included source
tarballs and scripts/build/ffmpeg/build_minimal.sh in the yt-tool repo.
