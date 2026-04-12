# Windows Acceptance Template

用于真实 Windows 环境（非 CI runner）验收 `yt.cmd` / `yt.ps1` 与打包产物行为。

## 1. 基本信息

- 执行日期：
- 执行人：
- Windows 版本：
- Python 安装方式（Store / 官方安装包 / 其他）：
- PowerShell 版本：
- 验收对象版本（tag）：

## 2. 验收矩阵

| 场景 | 构建模式 | 预期 | 结果(Pass/Fail) | 备注 |
|---|---|---|---|---|
| 双击 `launcher\\windows\\yt.cmd`（无参数） | without ffmpeg | 进入交互并可输入 URL |  |  |
| `yt.cmd "https://..."` | without ffmpeg | 可启动并进入下载流程 |  |  |
| 双击 `launcher\\windows\\yt.ps1`（无参数） | without ffmpeg | 进入交互并可输入 URL |  |  |
| `yt.ps1 "https://..."` | without ffmpeg | 可启动并进入下载流程 |  |  |
| 双击 `yt-tool.exe` | without ffmpeg | 可启动，缺 ffmpeg 功能有明确提示 |  |  |
| 双击 `yt-tool.exe` | with ffmpeg | 可启动，视频音频合并链路可用 |  |  |

## 3. 入口策略专项

- `python -m app`：默认 GUI，失败回退 CLI
- `--cli`：可强制 CLI
- `YT_TOOL_MODE=cli`：可强制 CLI

记录：
- [ ] `yt.cmd` 与 `python -m app` 策略一致
- [ ] `yt.ps1` 与 `python -m app` 策略一致
- [ ] `--cli` 生效
- [ ] `YT_TOOL_MODE=cli` 生效

## 4. 依赖组合专项

- [ ] Python 在 PATH 中
- [ ] Python 不在 PATH 中（能给出可操作提示）
- [ ] `yt-dlp` 缺失提示可理解
- [ ] `ffmpeg` 缺失提示可理解（without ffmpeg 场景）

## 5. 结论

- 总结：
- 是否解除 Windows 阻塞：`是 / 否`
- 若否，阻塞项：
- 建议修复：

