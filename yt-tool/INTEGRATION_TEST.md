# 联调测试记录

## 测试环境

- macOS Darwin 25.3.0 (Apple Silicon)
- Python 3.14.3
- yt-dlp: /opt/homebrew/bin/yt-dlp
- ffmpeg: /opt/homebrew/bin/ffmpeg
- 测试日期: 2026-03-30
- 测试视频: AJR - World's Smallest Violin (https://www.youtube.com/watch?v=PEnJbjBuxnw)

## 冒烟联调

| ID | 场景 | 输入 | 预期 | 实际 | 结果 |
|----|------|------|------|------|------|
| IT-01 | 正常启动 | 有效 YouTube URL | 环境自检 → 格式探测 → 下载菜单 | 显示 25 视频流 / 4 音频流 / 1 字幕，进入菜单 | ✓ 通过 |
| IT-02 | 视频下载 | 选 1 → 选流 91 → /tmp 目录 | 视频落盘，打印"视频下载完成" | 3.0M .mp4 文件落盘，打印"视频下载完成" | ✓ 通过 |
| IT-03 | video only 合并 | 选 1 → 选流 160 (video only) | 提示选音频流合并，拼 160+139 下载 | 提示"该流为 video only，需选择音频流合并"→ 选 139 → format=160+139 → 2.9M 合并 .mp4 落盘 | ✓ 通过 |
| IT-04 | 仅音频 | 选 2 → 选 139 (mp4a 49k) | 音频落盘至目标目录 | 1.1M .m4a 文件落盘，打印"音频下载完成" | ✓ 通过 |
| IT-05 | 仅字幕 | 选 3 → 选 live_chat | 仅下字幕，不下视频 | 3.6M .live_chat.json 落盘（该视频仅有 live_chat 字幕） | ✓ 通过 |
| IT-06 | all 模式 | 选 4 → 视频流 91 → 字幕 live_chat | 视频后继续字幕，字幕默认复用视频目录 | 视频 3.0M .mp4 + 字幕 3.6M .json 同目录落盘，提示"字幕将默认保存到视频目录" | ✓ 通过 |
| IT-06b | all 跳过视频 | 选 4 → 视频选 0 → 字幕选 1 | 字幕步骤仍继续 | 视频跳过后字幕正常下载完成 | ✓ 通过 |

## 异常联调

| ID | 场景 | 输入 | 预期 | 实际 | 结果 |
|----|------|------|------|------|------|
| IT-07 | 缺 yt-dlp | PATH=/usr/bin:/bin | "✗ yt-dlp: 未找到 (必需)" + "缺少必要依赖"，exit 1 | "✗ yt-dlp: 未找到 (必需)" + 安装提示 + "缺少必要依赖，无法继续。" exit 1 | ✓ 通过 |
| IT-08 | 缺 ffmpeg | mock shutil.which 屏蔽 ffmpeg | "△ ffmpeg: 未找到 (可选)"，ok=True，程序继续 | ok=True, warning=True, "△ ffmpeg: 未找到 (可选)" | ✓ 通过 |
| IT-09 | 空 URL | 启动后直接回车 | "需要提供视频 URL"，退出码 1 | 打印"需要提供视频 URL"，exit 1 | ✓ 通过 |
| IT-10 | 非法 URL | `http://not-a-real-video-12345` | "格式探测失败:"，不爆 traceback | 打印"格式探测失败: format detect failed: yt-dlp exited 1: ERROR..."，无 traceback | ✓ 通过 |
| IT-11 | 目录是已有文件 | 输入已存在的 .m4a 文件路径 | 下载失败提示"不是目录"，不崩 | 打印"音频下载失败: 路径已存在但不是目录: ..." | ✓ 通过 |
| IT-11b | 不可写目录 | 只读目录 | 下载失败提示"不可写" | 单元测试验证: test_path_utils::test_unwritable_dir_raises ✓ | ✓ 单测覆盖 |
| IT-12 | 菜单乱输入 | `a` / `-1` / `999` / 空回车 | 循环提示"无效输入，请重试" | 4 次非法输入均提示"无效输入，请重试"，第 5 次输入合法值后正常继续 | ✓ 通过 |
| IT-13 | playlist URL | 播放列表链接 | 仅探测首条 | 由单元测试验证: test_format_detector::test_playlist_takes_first_entry ✓ | ✓ 单测覆盖 |
| IT-14 | 无字幕视频选字幕 | 选 3 且视频无字幕 | "该视频无可用字幕" | 代码逻辑明确 (main.py _handle_subs 检查 sub_labels 为空)，单测可覆盖 | ✓ 逻辑验证 |

## 自动化测试覆盖

| 模块 | 测试文件 | 用例数 | 状态 |
|------|----------|--------|------|
| ui.py | test_ui.py | 14 | ✓ 全部通过 |
| path_utils.py | test_path_utils.py | 8 | ✓ 全部通过 |
| env_check.py | test_env_check.py | 4 | ✓ 全部通过 |
| downloader.py | test_downloader.py | 12 | ✓ 全部通过 |
| format_detector.py | test_format_detector.py | 7 | ✓ 全部通过 |
| main.py (流程) | test_main_flow.py | 4 | ✓ 全部通过 |
| **合计** | **6 个文件** | **55** | **✓ 55/55** |

### 关键自动化用例清单

按优先级排序的 6 条核心用例：

| # | 用例 | 测试位置 | 状态 |
|---|------|----------|------|
| 1 | `ask_download_type()` 非法值后重试 | test_ui.py::TestAskDownloadType::test_invalid_then_valid | ✓ |
| 2 | `menu_select()` 输入 0 返回 None | test_ui.py::TestMenuSelect::test_skip_returns_none | ✓ |
| 3 | `ensure_dir()` 文件路径报错 | test_path_utils.py::TestEnsureDir::test_file_path_raises | ✓ |
| 4 | `download_video()` 空参数返回失败 | test_downloader.py::TestDownloadVideo::test_empty_url_fails | ✓ |
| 5 | `detect()` 非 0 返回码抛 RuntimeError | test_format_detector.py::TestDetect::test_ytdlp_nonzero_raises | ✓ |
| 6 | `main()` detect 失败时返回 1 | test_main_flow.py::TestMainFlow::test_detect_failure_returns_1 | ✓ |

## 验收标准

- **下载成功**: 文件落盘到预期目录，控制台打印"XX下载完成"
- **失败但可接受**: 打印"XX下载失败: 错误信息"，无 traceback，程序不崩溃
- **已知限制**: 见 KNOWN_LIMITATIONS.md

## 联调完成判定

- [x] 四个业务分支全部跑过: video ✓ / audio ✓ / subs ✓ / all ✓
- [x] 至少 5 条异常路径跑过: 缺依赖 ✓ / 空 URL ✓ / 非法 URL ✓ / 路径错误 ✓ / 菜单错误 ✓
- [x] 落盘结果检查过: video 3.0M .mp4 ✓ / audio 1.1M .m4a ✓ / subs 3.6M .json ✓ / all 模式双文件同目录 ✓
- [x] playlist 与自动字幕两个限制已记录: KNOWN_LIMITATIONS.md ✓
- [x] 自动化测试覆盖主流程和核心工具函数: 55/55 ✓

**联调状态: ✅ 全部完成**
