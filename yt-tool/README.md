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

Python 代码本身不要求用户额外安装第三方 Python 包。
项目内部 vendored 了 `wcwidth`，用于终端字符显示宽度计算。

运行时外部依赖：

* `yt-dlp`
* `ffmpeg`（部分视频合并功能需要）
* `PySide6`（仅 GUI 模式需要）

---

## 安装依赖

### macOS

使用 Homebrew：

```bash
brew install python yt-dlp ffmpeg
```

安装完成后可检查：

```bash
python3 --version
yt-dlp --version
ffmpeg -version
```

如需 GUI：

```bash
python3 -m pip install PySide6
```

### Windows

可使用 `winget`：

```powershell
winget install Python.Python.3
winget install yt-dlp
winget install Gyan.FFmpeg
```

安装完成后可检查：

```powershell
py --version
yt-dlp --version
ffmpeg -version
```

如需 GUI：

```powershell
py -m pip install PySide6
```

---

## 启动方式

### 方式 1：直接运行 Python 模块

```bash
python3 -m app
```

或传入 URL：

```bash
python3 -m app "https://www.youtube.com/watch?v=xxxx"
```

### 方式 1.5：GUI 模式（需要 PySide6）

```bash
python3 -m app.gui
```

### 方式 2：Mac 启动器

```bash
./launcher/mac/yt.command
```

### 方式 3：Windows CMD

```bat
launcher\windows\yt.cmd "https://www.youtube.com/watch?v=xxxx"
```

### 方式 4：Windows PowerShell

```powershell
.\launcher\windows\yt.ps1 "https://www.youtube.com/watch?v=xxxx"
```

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
