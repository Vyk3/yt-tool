# yt-tool

`yt-tool` 是一个基于 `yt-dlp` 的下载工具，提供 GUI + CLI 双入口，支持视频、音频、字幕和播放列表下载。

## License

- 项目代码采用 `MIT` 许可证，见 [LICENSE](LICENSE)。
- 发布产物中如捆绑 `ffmpeg` / `ffprobe`，其第三方许可证见 [LICENSE_FFMPEG.txt](LICENSE_FFMPEG.txt)。

## 给普通用户

推荐直接使用 Release 产物：

- macOS：`yt-tool-macOS.dmg`
- Windows：`yt-tool-Windows.zip`

基本步骤：

1. 从 Release 页面下载对应平台产物。
2. macOS 挂载 DMG 后将 `yt-tool.app` 拖到 Applications；Windows 解压后运行 `yt-tool.exe`。
3. 正式发布产物默认已捆绑 `ffmpeg`/`ffprobe`。

### macOS 首次打开提示“无法验证开发者”

这是未公证应用的常见 Gatekeeper 提示。可通过以下任一方式放行：

- Finder 右键 `yt-tool.app` -> 打开 -> 再次确认打开
- 系统设置 -> 隐私与安全性 -> 仍要打开

## 给开发者（源码运行）

### 依赖

- Python 3.10+
- `ffmpeg`（部分合并/转码路径需要）

安装 Python 依赖：

```bash
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -U pip
python3 -m pip install -r requirements-cli.txt
python3 -m pip install ".[gui]"
```

Windows PowerShell：

```powershell
py -m venv .venv
.venv\Scripts\Activate.ps1
py -m pip install -U pip
py -m pip install -r requirements-cli.txt
py -m pip install ".[gui]"
```

### 启动

```bash
python3 -m app
python3 -m app --cli
YT_TOOL_MODE=cli python3 -m app
```

说明：

- 默认优先 GUI，失败自动回退 CLI
- 传入 URL 时可直接走 CLI：`python3 -m app "https://..."`

### Launcher

```bash
./launcher/mac/yt.command
```

```bat
launcher\windows\yt.cmd "https://www.youtube.com/watch?v=xxxx"
```

```powershell
.\launcher\windows\yt.ps1 "https://www.youtube.com/watch?v=xxxx"
```

自动化环境可设置 `YT_TOOL_NO_PAUSE=1` 跳过 Windows launcher 末尾暂停。

## 测试与质量

```bash
ruff check app/ tests/
python -m pytest tests/ -q
```

当前分支最近一次本地回归：`159 passed, 1 skipped`。

## 打包（维护者）

### macOS

```bash
python3 -m pip install -r requirements-cli.txt ".[gui]" pyinstaller
bash scripts/build/macos/build_app.sh --clean
```

可选：`--with-ffmpeg`（需传固定 URL + SHA256，拒绝 `/latest/`）。

### Windows

```powershell
python -m pip install -r requirements-cli.txt ".[gui]" pyinstaller
.\scripts\build\windows\build_exe.ps1 -Clean -Name yt-tool
```

可选：`-WithFfmpeg -FfmpegUrl <url> -FfmpegSha256 <hex>`。

### 统一说明

- `ffmpeg`/`ffprobe` 准备逻辑已统一到 `scripts/build/common/prepare_ffmpeg.py`
- macOS/Windows 入口脚本只负责参数解析与转发
- Release workflow 默认读取以下变量：
  - `YT_TOOL_FFMPEG_MACOS_URL`
  - `YT_TOOL_FFMPEG_MACOS_SHA256`
  - `YT_TOOL_FFPROBE_MACOS_URL`
  - `YT_TOOL_FFPROBE_MACOS_SHA256`
  - `YT_TOOL_FFMPEG_WINDOWS_URL`
  - `YT_TOOL_FFMPEG_WINDOWS_SHA256`

## 当前状态（2026-04-19）

- CI 矩阵处于阶段一收敛：
  - 主门禁：Linux 3.12 + macOS 3.12
  - 影子检查：Linux 3.13（non-gating）
- macOS 本地 `--clean` 打包已验证通过（`.app` + `.dmg`）
- Windows 真机打包/验收暂缓

## 相关文档

- 变更记录：[CHANGELOG.md](CHANGELOG.md)
- 已知限制：[KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md)
