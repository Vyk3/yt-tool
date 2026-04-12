# yt-tool

一个基于 `yt-dlp` 的终端交互式下载工具，支持：

- 视频下载
- 音频下载
- 普通字幕 / 自动字幕下载
- 视频 + 字幕一起下载
- 播放列表整列表下载
- 交互式选择格式与保存目录
- Mac / Windows 启动器

---

## 功能特性

- 启动时自动做环境自检
- 自动探测视频流、音频流、字幕轨道
- 按配置偏好排序视频 / 音频 / 字幕，并标记推荐项
- 支持 `video only` 流自动补选音频合并
- 支持高优先级候选格式预检，减少选中后才发现失效
- 支持 `live_chat` 轨道标记与下载前提示
- 支持可选浏览器 Cookie
- 支持下载归档，默认跳过已下载内容
- 支持片段下载（`--download-sections`）
- 支持 SponsorBlock 标记 / 移除
- 支持音频转码（MP3 / AAC / OPUS / M4A）
- 支持将普通字幕直接嵌入视频
- 支持交互式修改下载目录
- 下载成功后显示最终保存路径
- 下载失败时返回结构化错误，不直接抛业务异常
- 支持 `python -m app` 启动
- 默认下载目录自动按平台选择可用位置

---

## 项目结构

```text
app/
  __init__.py
  __main__.py
  core/
  services/
  cli/
  gui/

launcher/
  mac/
  windows/

tests/
  test_ui.py
  test_path_utils.py
  test_env_check.py
  test_downloader.py
  test_format_detector.py
  test_main_flow.py

requirements.txt
README.md
KNOWN_LIMITATIONS.md
TEST_REPORT.md
RELEASE_CHECKLIST.md
```

---

## 运行依赖

Python 依赖通过单一文件 `requirements.txt` 管理。

运行时外部依赖：

* Python 3.10+
* `ffmpeg`（部分视频合并功能需要）

`requirements.txt` 会安装：

* `yt-dlp`
* `pywebview`（GUI 模式，基于系统原生 WebView 运行）

---

## End-user Quick Start

面向普通用户，推荐直接下载发布页里的打包产物（`macOS .app` / `Windows .exe`）。

若你是源码运行用户，请看下一节 Developer Setup。

最小使用步骤：

1. 从 Release 页面下载对应平台产物：macOS `.dmg` / Windows `.zip`
2. macOS：挂载 `.dmg`，将 `yt-tool.app` 拖入 Applications，双击启动
3. Windows：解压 `.zip`，双击 `yt-tool.exe` 启动
4. 首次运行如提示缺少 `ffmpeg`，请先安装 `ffmpeg` 后重试

### macOS 首次运行提示"无法验证开发者"

由于应用未经 Apple 付费公证，macOS Gatekeeper 会在首次打开时提示：

> "yt-tool" cannot be opened because the developer cannot be verified.

解决方法（任选一）：

- **右键菜单**：在 Finder 中右键点击 `yt-tool.app` → **打开** → 弹窗中点击 **打开**
- **系统设置**：若双击后被拒绝，打开 **系统设置 → 隐私与安全性 → 安全性**，找到拦截提示，点击 **仍要打开**

首次确认后，后续双击可正常启动，无需重复操作。

---

## Developer Setup

### macOS

```bash
brew install python yt-dlp ffmpeg
python3 -m venv .venv
source .venv/bin/activate
python3 -m pip install -U pip
python3 -m pip install -r requirements.txt
```

### Windows

```powershell
winget install Python.Python.3
winget install yt-dlp
winget install Gyan.FFmpeg
py -m venv .venv
.venv\Scripts\Activate.ps1
py -m pip install -U pip
py -m pip install -r requirements.txt
```

---

## 启动方式（源码运行）

默认入口策略（`python3 -m app` 与 launcher 脚本一致）：

* 默认先尝试 GUI（`app.gui`）
* GUI 依赖缺失或启动失败时自动回退 CLI（`app.cli`）
* 可强制 CLI：传 `--cli` 或设置环境变量 `YT_TOOL_MODE=cli`
* 兼容旧行为：传入 `http/https` URL 参数时直接走 CLI（`python3 -m app "<url>"`）

```bash
python3 -m app
python3 -m app.gui
python3 -m app --cli
YT_TOOL_MODE=cli python3 -m app
```

Launcher：

```bash
./launcher/mac/yt.command
```

```bat
launcher\windows\yt.cmd "https://www.youtube.com/watch?v=xxxx"
```

```powershell
.\launcher\windows\yt.ps1 "https://www.youtube.com/watch?v=xxxx"
```

自动化环境可设置 `YT_TOOL_NO_PAUSE=1` 跳过 Windows launcher 末尾的“按回车退出”暂停。

---

## 打包（M5）

打包统一基于 `app/__main__.py`，保持与源码运行一致的入口策略（GUI 优先 + CLI 回退）。

### macOS 生成 `.app`（可本机实测）

先安装打包依赖：

```bash
python3 -m pip install pyinstaller
```

执行打包：

```bash
scripts/build/macos/build_app.sh --clean
```

可选参数：

* `--name <APP_NAME>`：设置应用名（默认 `yt-tool`）
* `--clean`：清理后打包
* `--with-ffmpeg`：下载并捆绑 `ffmpeg` + `ffprobe`（默认不启用）
* `--codesign-identity <IDENTITY>`：签名身份（默认 `-`，即 ad-hoc）
* `--ffmpeg-url <URL>`：覆盖 ffmpeg 下载地址（也可通过 `YT_TOOL_FFMPEG_MACOS_URL` 环境变量）
* `--ffmpeg-sha256 <HEX>`：校验 ffmpeg 压缩包 SHA256（或用 `YT_TOOL_FFMPEG_MACOS_SHA256`）

产物路径：

* `dist/yt-tool.app`

### Windows 打包脚本（在 Windows 上执行）

PowerShell：

```powershell
.\scripts\build\windows\build_exe.ps1 -Clean -Name yt-tool
```

Batch/CMD：

```bat
scripts\build\windows\build_exe.bat yt-tool clean
```

参数说明：

* PowerShell: `-Name <name>`、`-Clean`、`-WithFfmpeg`、`-FfmpegUrl <url>`、`-FfmpegSha256 <hex>`
* Batch: 第一个参数是 name，第二个参数填 `clean` 启用清理

默认产物路径（PyInstaller onedir）：

* `dist\yt-tool\yt-tool.exe`

注意：

* 默认只捆绑 `yt-dlp`；`ffmpeg` 需在打包时显式开启（`--with-ffmpeg` / `-WithFfmpeg`）
* 启用 `with_ffmpeg` 时，必须提供**固定版本 URL + SHA256**；脚本会拒绝 `/latest/` 可变地址并在校验失败时中止
* 若未启用 ffmpeg 捆绑，目标机器仍需自行安装 `ffmpeg`

CI（Release workflow）读取以下 Repository Variables：
* `YT_TOOL_FFMPEG_MACOS_URL`
* `YT_TOOL_FFMPEG_MACOS_SHA256`
* `YT_TOOL_FFMPEG_WINDOWS_URL`
* `YT_TOOL_FFMPEG_WINDOWS_SHA256`

---

## 使用说明

程序启动后主流程如下：

1. 环境自检
2. 输入视频 URL（或读取命令行传入 URL）
3. 可选选择浏览器 Cookie
4. 探测视频格式
5. 若检测到播放列表，选择只处理首条或下载整个播放列表
6. 选择下载类型
7. 选择视频流 / 音频流 / 字幕语言
8. 确认或修改保存目录
9. 执行下载

下载类型：

* `1` 视频（视频 + 音频合并）
* `2` 仅音频
* `3` 仅字幕
* `4` 全部（视频 + 字幕）
* `0` 退出

---

## 默认下载目录

默认配置位于 `app/config.py`：

* 视频：`~/Downloads/Videos`
* 音频：`~/Downloads/Music`
* 字幕：`~/Downloads/Subtitles`

程序会：

1. 优先使用配置目录
2. 若配置目录不可用，则按平台尝试常见候选目录
3. 若仍不可用，则允许用户手动输入路径

---

## 行为说明

### 视频下载

* 用户先选择视频流
* 菜单前会先预检高优先级候选格式
* 如果所选流是 `video only`
* 程序会要求继续选择一个音频流
* 可选下载指定片段
* 可选使用 SponsorBlock 标记或移除片段
* 可选嵌入普通字幕到视频文件
* 最终用 `视频ID+音频ID` 方式交给 `yt-dlp` 下载并合并

### 音频下载

* 下载用户选中的音频流
* 可选下载指定片段
* 可选使用 SponsorBlock 标记或移除片段
* 可选转码为 `mp3` / `aac` / `opus` / `m4a`
* 不转码时，文件格式取决于所选流本身

### 字幕下载

* 菜单会同时展示普通字幕与自动字幕
* 某些视频显示的"字幕"可能实际是 `live_chat`
* 这类轨道会被标记，下载结果通常是 `.json`，而不是 `.srt` / `.vtt`

### 全部下载

* 先执行视频下载
* 再执行字幕下载
* 即使视频步骤被跳过，字幕步骤仍可继续

### 播放列表下载

* 可选择只预览并处理首条视频
* 也可直接下载整个播放列表的视频或音频
* 整列表下载会按 `%(playlist_title)s/%(playlist_index)s - %(title)s.%(ext)s` 组织输出
* 默认启用下载归档，避免重复下载

---

## 已验证行为

当前版本已经完成以下验证：

* 视频 / 音频 / 字幕 / 全部 四个业务分支联调
* `video only` 补选音频合并联调
* 自动字幕、播放列表、音频转码、Cookie、候选预检、片段下载、SponsorBlock、下载归档等分支测试
* 缺 `yt-dlp` / 缺 `ffmpeg` / 空 URL / 非法 URL / 路径错误 / 菜单非法输入等异常联调
* 自动化测试覆盖核心模块，可通过 `pytest -q` 复验

---

## 已知限制

详见 `KNOWN_LIMITATIONS.md`。

当前已知限制包括：

1. 播放列表整列表下载目前只支持自动最佳视频 / 音频，不支持逐条交互选格式
2. `live_chat` 轨道虽然会被标记并允许下载，但结果仍是 JSON，不会自动转换成常规字幕
3. 播放列表模式当前不提供整列表字幕下载，片段下载也只在单条视频 / 音频流程中提供
4. 候选格式预检是 best-effort，只检查高优先级候选，不保证下载时 100% 不失效
5. Windows 启动器仍建议在真实 Windows 环境做最终验收

---

## 测试

运行测试：

```bash
pytest -q
```

查看详细输出：

```bash
pytest -vv
```

---

## 测试覆盖

当前自动化测试覆盖以下模块：

* `ui.py`
* `path_utils.py`
* `env_check.py`
* `downloader.py`
* `format_detector.py`
* `main.py`

共 6 个测试文件，55 条用例，全部通过。

---

## 常见问题

### 1. 提示 `yt-dlp: 未找到`

请先安装 `yt-dlp`，并确认它已加入 PATH：

```bash
yt-dlp --version
```

### 2. 提示 `ffmpeg: 未找到`

程序仍可运行，但部分视频合并功能可能受限。建议安装：

```bash
brew install ffmpeg
```

或在 Windows 上：

```powershell
winget install Gyan.FFmpeg
```

### 3. 下载字幕后得到的是 `.json`

这通常表示该视频只有 `live_chat` 轨道，而不是常规字幕文件。这是当前下载结果的真实格式，不是程序异常。

### 4. 为什么播放列表只处理了一个视频

当前版本对 playlist URL 只探测首条内容，完整播放列表支持尚未实现。

### 5. 为什么输入一个文件路径会报"不是目录"

下载位置需要是目录。如果你输入了一个已存在文件的路径，程序会提示该路径不是目录。
