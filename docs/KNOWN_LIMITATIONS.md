# Known Limitations

本文档记录当前 Swift 版本仍然存在的限制。

---

## 1. 官方打包发布版仅支持 Apple Silicon

### 现状
官方打包发布版（`YTTool.dmg` / `YTTool.zip`）为 arm64-only 构建。`build.sh` 在 release 模式下强制要求 arm64 运行环境（`uname -m == arm64`），所有捆绑二进制（ffmpeg / ffprobe / Python 运行时）均为 arm64 原生构建。

### 影响
Intel Mac 不在当前打包发布版的支持范围内。从源码构建不受此限制。

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

## 3. macOS Gatekeeper / 分发签名（Apple 公证未完成）

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
