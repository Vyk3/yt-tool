# M0 Spike Notes

## 当前结论

### Bundle 二进制布局

- 工具统一放在 app bundle 的 `Contents/Resources/Binaries/`
- 业务层只依赖 `BundledToolLocator`
- 开发态允许从源码目录的 `YTTool/Resources/Binaries/` 回退读取
- 生产环境通过 `scripts/build/swift/prepare_binaries.py` 下载固定版本 + SHA256 校验
- 开发/内测通过 `scripts/build/swift/dev_install_binaries.sh` 复制本地 Homebrew 二进制
- 二进制不纳入 git（.gitignore 已配置排除 yt-dlp / ffmpeg / ffprobe）

### Process 约束（已定结论）

- 所有子进程通过 `ProcessRunner` 启动
- 子进程 launch 后立即调用 `setpgid(pid, pid)`，将子进程移到独立进程组
- 取消策略：`killpg(pgid, SIGTERM)` + `process.terminate()` → 等待 grace period → `killpg(pgid, SIGKILL)` + `kill(pid, SIGKILL)` 兜底
- `killpg` 覆盖范围：yt-dlp 本身以及它 fork 出的 ffmpeg 子孙进程（均继承同一进程组）
- 已知竞争窗口：`setpgid` 在 `process.run()` 之后调用，如果 yt-dlp 在极短时间内已经 fork ffmpeg，该子孙可能仍在原进程组。实践中这个窗口极小（yt-dlp 在解析参数后才启动 ffmpeg），接受此风险。

### yt-dlp 进度输出通道

- yt-dlp `--progress --newline` 的进度行在不同运行环境下可能出现在 **stderr 或 stdout**
- stdout 仍可能包含 `--dump-single-json`、`--print after_move:filepath` 等业务输出
- `ProgressParser` 需要同时容忍 stdout/stderr 两侧的 progress line，并保留非 progress 行给日志与结果解析

---

## 验证历史

| 日期 | 结论 |
|------|------|
| 2026-04-20 | Xcode build 成功（Debug） |
| 2026-04-20 | bundle 内 probe-fixture 可执行并正确复制 |
| 2026-04-20 | `swift test` 8 个测试全绿 |
| 2026-04-20 | ProcessRunner 覆盖：成功执行、非零退出码、取消长任务 |
| 2026-04-20 | killpg 进程组取消实现完成（代码层），运行时 yt-dlp→ffmpeg 链路验证待完成 |
| 2026-04-20 | dev_install_binaries.sh 将 yt-dlp/ffmpeg/ffprobe 复制到 Resources/Binaries/ |
| 2026-04-21 | xcodebuild Debug 成功（修复 YtDlpProbeService.swift 未加入 xcodeproj） |
| 2026-04-21 | **运行时 probe 验证 ✅**：App 启动后对 `jNQXAC9IVRw`（Me at the zoo）执行 Probe，状态栏显示 "Ready: Me at the zoo"，Formats 区域渲染 5 video + 4 audio 格式，链路全通 |
| 2026-04-22 | `Session Log` 面板接入，probe/download/cancel 关键事件与 stderr/stdout 片段可在 UI 内查看 |
| 2026-04-22 | **ffmpeg 阶段取消验证 ✅**：对 `P5yHEKqx86U` 选择 `136+140`（视频专流 + 音频专流），确认进入 `ffmpeg` 合并阶段后点击 Cancel，随后 `ffmpeg` 与 `yt-dlp` 进程列表均清空，UI 状态变为 `Cancelled` |
| 2026-04-22 | **下载状态刷新修复 ✅**：修复了 progress line 落在 stdout 时 UI 卡在 `Preparing` 的问题；fresh debug build 已确认下载可正常进入并完成，Completed 状态与输出路径显示正确 |
| 2026-04-22 | **Downloading 中间态验收 ✅**：用户手工截图确认下载中面板可见 `Downloading`、百分比以及 `Size / Speed / ETA`，说明下载区进度展示已在真实运行中落地 |
| 2026-04-22 | **FFmpeg 缺失提示验收 ✅**：最新 Debug build 中临时移走 app bundle 的 `ffprobe` 后，下载区标题旁显示 `FFmpeg unavailable`，点击可见缺失项说明；运行时不再错误回退到源码目录二进制 |
| 2026-04-22 | **磁盘空间预检验收 ✅**：在仅 `19.3 MB` 可用空间的临时卷上选择 `38.9 MB` 格式，点击 `Download` 后直接进入 `Insufficient disk space.` 失败态，并显示估算大小与可用空间 |
| 2026-04-27 | **播放列表最小策略验收 ✅**：播放列表 URL 会显示三种模式（`Only first item` / `Whole playlist: best video` / `Whole playlist: best audio`）；整列表模式会收起 `Probe first item`，并在格式区显示自动下载说明 |
| 2026-04-27 | **输出目录失效兜底 ✅**：上次记住的输出目录如果后来被删除或卸载，启动时不会再恢复为有效目录；下载前也会再次校验，避免 stale 路径误导 UI 进入可下载状态 |
| 2026-04-27 | **整列表视频质量策略验收 ✅**：`Whole playlist: best video` 下会出现 `Video quality`，默认 `Best compatibility`，可切换到 `Prefer higher quality`；切换到 `Whole playlist: best audio` 后该行会消失 |

---

## 待完成验证（T1 剩余项）

**已完成**：
- ✅ 代码实现（ProcessRunner killpg 策略）
- ✅ 运行时 yt-dlp probe 验证（2026-04-21 通过）

**待完成**：
- 无

---

## 已消除的风险

- 工程能否构建：已消除
- bundle 内二进制是否可执行：已消除
- JSON 解析链路是否稳定：已消除（ProbeParser + 单测）
- Swift 6 并发模型兼容性：已消除（BundledToolLocator @unchecked Sendable，YtDlpProbeService Sendable）
- 端到端 probe 链路正确性：已消除（运行时验证，格式列表成功渲染）
- `yt-dlp -> ffmpeg` 进程树取消正确性：已消除（运行时验证，ffmpeg 阶段取消后进程清空）
- 下载状态流是否会卡在 `Preparing`：已消除（stdout/stderr 双通道 progress 解析 + MainActor 状态更新）
- 下载中信息是否真实可见：已消除（手工截图确认 `Downloading` + 百分比 + `Size / Speed / ETA`）
- 缺失 `ffmpeg` / `ffprobe` 时用户是否能得到明确提示：已消除（运行时 UI 验证）
- 已知候选格式大小明显超过可用空间时是否能提前阻断：已消除（磁盘空间预检运行时验证）
- 播放列表整列表模式是否有最小可用入口：已消除（三模式入口 + 运行时 UI 验证）
- 持久化输出目录失效后是否会错误放开下载：已消除（启动恢复与下载前双重校验）
- 播放列表整列表视频模式是否有最小整体质量策略入口：已消除（双策略入口 + 运行时 UI 验证）
