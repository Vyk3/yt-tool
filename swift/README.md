# YTTool Swift Rewrite

这部分承载 Swift macOS 重写的 M0/M1 落地代码。

当前状态：
- 已建立 `swift/` 目录骨架
- 已建立 SwiftUI app 入口、基础状态模型、`BundledToolLocator`、`ProcessRunner`
- 已补 M0 约束记录、bundle fixture 与基础测试文件
- 已通过 `xcodebuild` 成功构建出 Debug `.app`
- 已通过 `swift test --disable-sandbox --package-path swift`，覆盖 `ProcessRunner` 的成功、失败、取消用例

当前阻塞：
- `ProcessRunner` 当前只统一了直接子进程取消入口，尚未完成 `yt-dlp -> ffmpeg` 子孙进程树清理验证

因此本目录的定位是：
- 先把结构与抽象稳定落仓
- 继续补完 M0 的真实 bundle 执行 spike，再进入 M1 probe flow

建议后续验证顺序：
1. 运行 `xcodebuild -project swift/YTTool.xcodeproj -scheme YTTool -configuration Debug -derivedDataPath "$PWD/tmp/xcode-derived-data" build`
2. 运行 `swift test --disable-sandbox --package-path swift`
3. 按 `swift/docs/m0-spike.md` 用 `probe-fixture` 和真实 `yt-dlp` 完成 stdout / stderr / exit code / cancel spike
4. 在确认取消策略后接入 `YtDlpProbeService` 与 parser
