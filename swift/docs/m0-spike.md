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

- yt-dlp `--progress --newline` 的进度行输出到 **stderr**（不是 stdout）
- stdout 用于 `--dump-single-json` 等 JSON 输出
- `ProgressParser` 应订阅 `ProcessEvent.stderr` 行，而非 stdout

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

---

## 待完成验证（T1 剩余项）

**已完成**：
- ✅ 代码实现（ProcessRunner killpg 策略）
- ✅ 运行时 yt-dlp probe 验证（2026-04-21 通过）

**待完成**：
- ⏳ 运行时 ffmpeg 子进程取消验证（需要 M2 下载 UI）
  - 验证步骤：在 Download 期间点击 Cancel，用 `ps aux | grep -E 'yt-dlp|ffmpeg'` 确认两者均已退出

---

## 已消除的风险

- 工程能否构建：已消除
- bundle 内二进制是否可执行：已消除
- JSON 解析链路是否稳定：已消除（ProbeParser + 单测）
- Swift 6 并发模型兼容性：已消除（BundledToolLocator @unchecked Sendable，YtDlpProbeService Sendable）
- 端到端 probe 链路正确性：已消除（运行时验证，格式列表成功渲染）
