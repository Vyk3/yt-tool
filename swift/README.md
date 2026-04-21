# YTTool Swift Rewrite

这部分承载 Swift macOS 重写版的当前可运行实现。

当前状态：
- `M0` 可行性验证已完成：bundle 内二进制定位、进程执行、stdout/stderr、退出码、取消链路均已落地
- `M1` probe flow 已完成：真实 URL 可返回格式，错误映射与 parser 单测已补齐
- `M2` 下载 flow 已完成：格式选择、输出目录、进度、完成/失败/取消状态已接入
- `M3` 构建链路已完成：可通过脚本产出 `.app` / `.zip` 并通过 smoke test
- `M4` 体验补强已完成：URL 拖拽、最近目录记忆、下载完成通知、格式列表可读性优化已落地
- `Sprint 5` 正在收尾：新增会话级 `Session Log` 面板，用于查看 probe/download/cancel 的关键事件与 stderr/stdout 片段，默认折叠、按需展开；下载区阶段层级与进度排版已补强

当前验证结果：
- `swift test --disable-sandbox --package-path swift`：15 个测试通过
- `xcodebuild -project swift/YTTool.xcodeproj -scheme YTTool -configuration Debug -derivedDataPath "$PWD/tmp/xcode-derived-data" build`：通过
- 手工验收：真实 URL probe 成功；下载完成通知可在通知中心看到；`Sprint 4` 验收文档已同步到当前 UI 文案
- 运行时取消验证：已分别验证 `yt-dlp` 下载阶段取消，以及 `ffmpeg` 合并阶段取消，Cancel 对 `yt-dlp -> ffmpeg` 进程树生效
- 最新修复：`yt-dlp` 进度行现在可从 stdout/stderr 两侧识别；下载状态更新显式回到 `MainActor`
- 最新手工验收：fresh debug build 已确认下载可从 `Preparing` 正常走到 `Completed`，并正确显示完成路径与通知日志；`Downloading` 中间态也已由手工截图确认，百分比与 `Size / Speed / ETA` 可见

当前剩余重点：
- 如需继续增强 UX，优先评估是否还要进一步优化下载中信息排版，而不是继续加动画
- 继续用日志面板支撑后续排障与收尾验证

建议后续顺序：
1. 运行 `xcodebuild -project swift/YTTool.xcodeproj -scheme YTTool -configuration Debug -derivedDataPath "$PWD/tmp/xcode-derived-data" build`
2. 运行 `swift test --disable-sandbox --package-path swift`
3. 如需继续做 UX 收口，优先基于已确认的 `Downloading` 面板决定是否还要微调信息密度
4. 在日志面板基础上扩展后续能力
