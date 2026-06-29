[English](README.en.md) | 简体中文

# yt-tool

`yt-tool` 是一个基于 `yt-dlp` 的 macOS 原生下载工具，提供 SwiftUI GUI，支持视频、音频、字幕和播放列表下载。

## 功能亮点

- **下载队列**：多 URL 批量入队，顺序下载，支持拖拽重排序、取消、重试
- **批量导入**：从文件或剪贴板一次性导入多条 URL
- **订阅监控**：订阅 YouTube / Bilibili 频道，定期检查新视频并通知
- **额外参数安全校验**：用户输入的额外 yt-dlp 参数经 allowlist 校验，仅允许审核过的选项
- **aria2c 加速**：检测到系统 aria2c 时自动启用多连接下载，不可用时回退内置下载器
- **下载历史**：持久化记录所有下载，可搜索和回溯
- **格式预估**：选择格式后显示视频 + 音频合并预估大小
- **协议感知格式选择**：显示 DASH / HLS / HTTP 协议标签，自动选择最佳 DASH 组合，并对 HLS 下载使用更合适的内置片段下载器
- **yt-dlp 自更新**：应用内检查并安装 yt-dlp 新版本（Stable / Nightly）
- **应用自更新**：集成 Sparkle 2.x，Ed25519 签名，自动检测新版本

## License

- 项目代码采用 `MIT` 许可证，见 [LICENSE](LICENSE)。
- 发布产物中捆绑的 `ffmpeg` / `ffprobe` 为自建 minimal LGPL 静态构建（FFmpeg 8.1.1 + LAME 3.100），第三方许可证见 [LICENSE_FFMPEG.txt](LICENSE_FFMPEG.txt)。

## 系统要求

- **Apple Silicon（M1 或更新）**：官方打包发布版（YTTool.dmg / YTTool.zip）为 arm64-only，不支持 Intel Mac。
- **macOS 14 Sonoma 或更新版本**。

## 给普通用户

从 Release 页面下载 `YTTool.dmg`，打开后将 `YTTool.app` 拖到 Applications 文件夹即可完成安装。

也可以下载 `YTTool.zip`，解压后手动将 `YTTool.app` 拖到 Applications。

### 首次打开提示"无法验证开发者"

当前发布包使用 ad-hoc 签名，不是 Apple Developer ID 签名，也未经过 Apple 公证。这类分发首次打开时出现 Gatekeeper 提示是预期行为，不代表下载包损坏。可通过以下任一方式放行：

- Finder 右键 `YTTool.app` → 打开 → 再次确认打开
- 系统设置 → 隐私与安全性 → 仍要打开

## 给开发者

详细说明见 [`swift/DEVLOG.md`](swift/DEVLOG.md)。

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

- Swift 端开发日志：[`swift/DEVLOG.md`](swift/DEVLOG.md)
- 变更记录：[CHANGELOG.md](CHANGELOG.md)
- 已知限制：[KNOWN_LIMITATIONS.md](docs/KNOWN_LIMITATIONS.md)
