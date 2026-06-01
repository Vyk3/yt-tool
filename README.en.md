English | [简体中文](README.md)

# yt-tool

`yt-tool` is a macOS native download tool based on `yt-dlp`, with a SwiftUI GUI. Supports video, audio, subtitle, and playlist downloads.

## Features

- **Download Queue**: Batch-enqueue multiple URLs, sequential downloads with drag-to-reorder, cancel, and retry
- **Batch Import**: Import multiple URLs from file or clipboard at once
- **aria2c Acceleration**: Automatically enables multi-connection download when aria2c is detected; falls back to built-in downloader otherwise
- **Download History**: Persistent download records with search
- **Size Estimation**: Shows estimated merged file size after format selection
- **yt-dlp Self-Update**: Check and install new yt-dlp versions (Stable / Nightly) from within the app
- **App Self-Update**: Sparkle 2.x integration with Ed25519 signing for automatic update detection

## License

- Project code is licensed under the `MIT` License. See [LICENSE](LICENSE).
- Third-party licenses for bundled `ffmpeg` / `ffprobe` binaries are in [LICENSE_FFMPEG.txt](LICENSE_FFMPEG.txt).

## System Requirements

- **Apple Silicon (M1 or later)**: The packaged release (YTTool.dmg / YTTool.zip) is arm64-only. Intel Mac is not supported.
- **macOS 14 Sonoma or later**.

## For Users

Download `YTTool.dmg` from the Releases page, then drag `YTTool.app` to the Applications folder.

Alternatively, download `YTTool.zip`, extract it, and drag `YTTool.app` to Applications manually.

### "Cannot verify developer" on first launch

This is a common Gatekeeper prompt for unsigned apps. To allow it:

- Right-click `YTTool.app` in Finder → Open → Confirm Open
- System Settings → Privacy & Security → Open Anyway

## For Developers

See [`swift/DEVLOG.md`](swift/DEVLOG.md) for full details.

### Quick Start

```bash
# Install dev binaries (yt-dlp, ffmpeg, ffprobe)
bash scripts/build/swift/dev_install_binaries.sh

# Open the Xcode project
open swift/YTTool.xcodeproj
```

### Running Tests

```bash
swift test --disable-sandbox --package-path swift
```

### Local Build

```bash
# dev mode (uses locally installed binaries)
bash scripts/build/swift/build.sh

# release mode (downloads and verifies pinned versions)
bash scripts/build/swift/build.sh --release
```

Output: `swift/dist/YTTool.app`, `swift/dist/YTTool.zip`, `swift/dist/YTTool.dmg`.

## Related Documentation

- Swift development log: [`swift/DEVLOG.md`](swift/DEVLOG.md)
- Changelog: [CHANGELOG.md](CHANGELOG.md)
- Known limitations: [KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md)
