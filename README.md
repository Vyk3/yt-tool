# yt-tool

`yt-tool` 是一个基于 `yt-dlp` 的 macOS 原生下载工具，提供 SwiftUI GUI，支持视频、音频、字幕和播放列表下载。

## License

- 项目代码采用 `MIT` 许可证，见 [LICENSE](LICENSE)。
- 发布产物中捆绑的 `ffmpeg` / `ffprobe` 第三方许可证见 [LICENSE_FFMPEG.txt](LICENSE_FFMPEG.txt)。

## 给普通用户

从 Release 页面下载 `YTTool.dmg`，打开后将 `YTTool.app` 拖到 Applications 文件夹即可完成安装。

也可以下载 `YTTool.zip`，解压后手动将 `YTTool.app` 拖到 Applications。

### 首次打开提示"无法验证开发者"

这是未公证应用的常见 Gatekeeper 提示。可通过以下任一方式放行：

- Finder 右键 `YTTool.app` → 打开 → 再次确认打开
- 系统设置 → 隐私与安全性 → 仍要打开

## 给开发者

详细说明见 [`swift/README.md`](swift/README.md)。

### 快速上手

```bash
# 安装开发用二进制（yt-dlp, ffmpeg, ffprobe）
bash scripts/build/swift/dev_install_binaries.sh

# 打开 Xcode 项目
open swift/YTTool.xcodeproj
```

### 运行测试

```bash
swift test --disable-sandbox --package-path swift
```

### 本地打包

```bash
# dev 模式（使用本地已安装的二进制）
bash scripts/build/swift/build.sh

# release 模式（下载并校验 pinned 版本）
bash scripts/build/swift/build.sh --release
```

产出：`swift/dist/YTTool.app`、`swift/dist/YTTool.zip`、`swift/dist/YTTool.dmg`。

## 相关文档

- Swift 端完整说明：[`swift/README.md`](swift/README.md)
- 变更记录：[CHANGELOG.md](CHANGELOG.md)
- 已知限制：[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md)
