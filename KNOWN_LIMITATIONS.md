# Known Limitations

本文档记录当前 Swift 版本仍然存在的限制。

---

## 1. ffmpeg / ffprobe 来源仅覆盖 Intel（evermeet.cx）

### 现状
`scripts/build/swift/pinned_versions.sh` 中固定的 ffmpeg / ffprobe 来源为 evermeet.cx 的 Intel 静态构建。
Apple Silicon（arm64）原生静态构建尚未纳入 pinned 版本。

### 影响
- dev 模式通过 `dev_install_binaries.sh` 从本机 Homebrew 复制二进制，Apple Silicon 下可正常运行
- release 模式打包的 ffmpeg / ffprobe 是 Intel 构建，在 Apple Silicon 上通过 Rosetta 2 运行，功能正常但有轻微性能差异

### 后续建议
将 ffmpeg / ffprobe 来源切换至 BtbN/FFmpeg-Builds 的 macOS arm64 构建，或改用 universal binary 来源，并更新 `pinned_versions.sh` 中的 URL 和 SHA256。

---

## 2. 整列表模式逐条格式选择仍为文本语法

### 现状
整列表下载时的逐条格式映射（`Per-item mapping`）使用文本输入语法：`itemIndex=formatSelector;itemIndex=formatSelector`（例如 `1=137+140;2=136+140`）。

### 影响
- 需要用户手动查询并填写格式 ID，交互成本较高
- 语法错误时在下载阶段才会报错

### 后续建议
为整列表逐条格式选择提供可视化交互入口（先 probe 每条，再提供下拉选择）。

---

## 3. macOS Gatekeeper / 分发签名

### 现状
`scripts/build/swift/build.sh` 使用 ad-hoc 签名（`codesign --sign -`）。

### 影响
用户首次启动会看到"未经验证的开发者"弹窗；需右键点击 → 打开 绕过。
App 可正常运行，不会被系统实际阻断。

### 后续建议
申请 Apple Developer Program 证书（$99/年），将 `build.sh` 中 `--sign -` 替换为开发者 ID（Developer ID Application: ...）并通过 `notarytool` 公证。

---

## 4. 磁盘空间预检是 best-effort

### 现状
下载前对可估大小的候选格式做磁盘空间预检。仅对能从 probe 数据中读取到预估大小的格式生效；无法预估大小的格式（如部分直播回放）不做预检。

### 影响
空间不足时大多数情况下能提前失败并给出明确提示，但少数无法预估大小的场景仍可能在下载到一半时才报错。

---

## 5. `live_chat` 轨道不是常规字幕

### 现状
对于直播回放等内容，`yt-dlp` 返回的某些"字幕"轨道其实是 `live_chat`。当前版本在字幕列表中会标记该轨道类型。

### 影响
下载结果可能是 `.live_chat.json`，而非 `.srt` / `.vtt` 字幕文件。这是源数据本身的格式，不是程序错误。
