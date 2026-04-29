# YTTool Swift Rewrite

这部分承载 Swift macOS 重写版的当前可运行实现。

相关文档：
- [URL Support Policy](docs/url-support-policy.md)

相关决策：
- `P0` 决策文档见 [swift/docs/p0-capability-ceiling.md](/Users/koa/.codex/worktrees/yt-tool-standalone-ytdlp-eval/swift/docs/p0-capability-ceiling.md)
- `P1` 设计文档见 [swift/docs/p1-canary-channel.md](/Users/koa/.codex/worktrees/yt-tool-standalone-ytdlp-eval/swift/docs/p1-canary-channel.md)
- `P2` 决策文档见 [swift/docs/p2-youtube-specialization.md](/Users/koa/.codex/worktrees/yt-tool-standalone-ytdlp-eval/swift/docs/p2-youtube-specialization.md)

当前状态：
- `M0` 可行性验证已完成：bundle 内二进制定位、进程执行、stdout/stderr、退出码、取消链路均已落地
- `M1` probe flow 已完成：真实 URL 可返回格式，错误映射与 parser 单测已补齐
- `M2` 下载 flow 已完成：格式选择、输出目录、进度、完成/失败/取消状态已接入
- `M3` 构建链路已完成：可通过脚本产出 `.app` / `.zip` 并通过 smoke test
- `M4` 体验补强已完成：URL 拖拽、最近目录记忆、下载完成通知、格式列表可读性优化已落地
- `Sprint 5` 已完成：会话级 `Session Log`、下载区阶段层级与进度排版、完成态快捷操作、失败态提示收口均已落地
- 最新补强已完成：缺失 `ffmpeg` / `ffprobe` 时显示 `FFmpeg unavailable` 警示；下载前会对可估大小的候选格式做磁盘空间预检，并在空间不足时给出明确失败提示
- 播放列表最小策略已完成：播放列表 URL 现支持 `Only first item`、`Whole playlist: best video`、`Whole playlist: best audio` 三种模式；整列表视频模式支持 `Best compatibility` / `Prefer higher quality` 两种质量策略；整列表音频模式同样支持 `More compatible` / `Higher quality` 两种音频质量策略；整列表模式仍跳过逐条格式选择并直接下载全部条目

当前验证结果：
- `scripts/test/swift_test.sh`：58 个测试通过
- `xcodebuild -project swift/YTTool.xcodeproj -scheme YTTool -configuration Debug -derivedDataPath "$PWD/tmp/xcode-derived-data" build`：通过
- 手工验收：真实 URL probe 成功；下载完成通知可在通知中心看到；`Sprint 4` 验收文档已同步到当前 UI 文案
- 运行时取消验证：已分别验证 `yt-dlp` 下载阶段取消，以及 `ffmpeg` 合并阶段取消，Cancel 对 `yt-dlp -> ffmpeg` 进程树生效
- 最新修复：`yt-dlp` 进度行现在可从 stdout/stderr 两侧识别；下载状态更新显式回到 `MainActor`
- 最新手工验收：fresh debug build 已确认下载可从 `Preparing` 正常走到 `Completed`，并正确显示完成路径与通知日志；`Downloading` 中间态也已由手工截图确认，百分比与 `Size / Speed / ETA` 可见
- 缺失工具手工验收：最新 Debug build 中临时移走 app bundle 的 `ffprobe` 后，下载区会显示 `FFmpeg unavailable`，点击可见缺失项说明
- 磁盘空间手工验收：在仅 `19.3 MB` 可用空间的临时卷上选择 `38.9 MB` 格式后，点击 `Download` 直接进入 `Insufficient disk space.` 失败态，并显示估算大小与可用空间
- 播放列表手工验收：播放列表 URL 会显示模式选择器，默认 `Only first item`；切换到 `Whole playlist` 模式后，`Probe first item` 收起，格式区改为自动下载说明，`Download` 入口按模式放开；`Whole playlist: best video` 下会出现 `Video quality`，可在 `Best compatibility` 和 `Prefer higher quality` 之间切换；`Whole playlist: best audio` 下会出现 `Audio quality`，可在 `More compatible` 和 `Higher quality` 之间切换
- 打包口径：dev / release 统一以官方 `yt-dlp_macos` standalone 为目标交付物；Homebrew `yt-dlp` 仅作为本机参考，不再作为 app 内 `yt-dlp` 来源
- URL 支持边界：standalone 二进制已确认提供可用的 impersonation targets，但站点是否可下载仍取决于 `yt-dlp` extractor/站点兼容性；这一步不承诺 `missav` 一类站点可用

当前剩余重点：
- 与 Python GUI 的功能缺口（按优先级）：字幕下载（手动 + 自动字幕）
- 已补齐：音频转码格式选择（`mp3 / m4a / wav`，含 `Keep original`）
- 已补齐：Cookies 文件路径（probe/download 均支持 `--cookies <path>`，含存在性与可读性校验）
- 已补齐：额外 yt-dlp 参数透传（probe/download 均支持，含引号参数解析）
- 播放列表模式目前仍是最小版：不支持逐条格式选择、整列表字幕或整列表片段策略
- 持久化输出目录现在会在启动和下载前校验是否仍然存在且可用；如目录已失效，UI 不再把它当成可下载状态

建议后续顺序：
1. 运行 `xcodebuild -project swift/YTTool.xcodeproj -scheme YTTool -configuration Debug -derivedDataPath "$PWD/tmp/xcode-derived-data" build`
2. 运行 `scripts/test/swift_test.sh`
3. 如需继续做手工验收，始终先退出旧实例，再只打开 `tmp/xcode-derived-data/Build/Products/Debug/YTTool.app`
4. 下一个功能切片：整列表字幕与整列表片段策略
