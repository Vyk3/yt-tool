"""入口主流程 — 对应原 yt-interactive.sh 的 main() 函数。

串联各模块：环境自检 → URL 输入 → 格式探测 → 交互选择 → 下载执行。
本模块只做流程编排，不做具体业务逻辑。
"""
from __future__ import annotations

import sys

from . import config
from .downloader import download_audio, download_subs, download_video
from .env_check import check_env
from .format_detector import DetectResult, detect
from .path_utils import resolve_download_dir
from .ui import (
    ask_download_type,
    ask_location,
    build_audio_labels,
    build_sub_labels,
    build_video_labels,
    is_video_only,
    menu_select,
    show_detect_result,
    show_download_fail,
    show_download_ok,
    show_download_start,
)


def _run_env_check() -> bool:
    """环境自检，返回是否可继续。"""
    print("── 环境自检 ──")
    result = check_env()

    for item in result.items:
        if item.found:
            print(f"  ✓ {item.name}: {item.path}")
        elif item.required:
            print(f"  ✗ {item.name}: 未找到 (必需)")
            print(f"    安装: {item.hint}")
        else:
            print(f"  △ {item.name}: 未找到 (可选)")
            print(f"    安装: {item.hint}")

    if not result.ok:
        print("\n缺少必要依赖，无法继续。")
        return False

    if result.warning_missing:
        print("\n部分可选依赖缺失，某些功能可能受限。")

    return True


def _get_url(argv: list[str]) -> str | None:
    """从命令行参数或交互输入获取 URL。"""
    if argv:
        return argv[0]

    try:
        url = input("输入视频 URL: ").strip()
    except (EOFError, KeyboardInterrupt):
        return None

    return url if url else None


def _handle_video(
    url: str,
    info: DetectResult,
    vid_labels: list[str],
    vid_values: list[str],
    aud_labels: list[str],
    aud_values: list[str],
) -> str | None:
    """处理视频下载流程，返回实际使用的输出目录（供后续字幕复用）。"""
    vid_fmt = menu_select("选择视频流", vid_labels, vid_values)
    if not vid_fmt:
        return None

    final_fmt = vid_fmt

    # video only 流需要用户额外选择音频流合并
    if is_video_only(info.video_formats, vid_fmt):
        print("该流为 video only，需选择音频流合并")
        aud_fmt = menu_select("选择音频流", aud_labels, aud_values)
        if not aud_fmt:
            print("未选择音频流，已取消视频下载")
            return None
        final_fmt = f"{vid_fmt}+{aud_fmt}"

    default_dir = str(resolve_download_dir(config.YT_DIR_VIDEO, "Videos"))
    dest = ask_location(default_dir)

    show_download_start(final_fmt, dest)
    result = download_video(url, final_fmt, dest)
    if result.ok:
        show_download_ok("视频", result.output)
    else:
        show_download_fail("视频", result.error)

    return dest


def _handle_subs(
    url: str,
    sub_labels: list[str],
    sub_values: list[str],
    default_dir: str | None = None,
) -> None:
    """处理字幕下载流程。"""
    if not sub_labels:
        print("该视频无可用字幕")
        return

    sub_lang = menu_select("选择字幕语言", sub_labels, sub_values)
    if not sub_lang:
        return

    if default_dir:
        print(f"\n字幕将默认保存到视频目录: {default_dir}")
        dest = ask_location(default_dir)
    else:
        dest = ask_location(
            str(resolve_download_dir(config.YT_DIR_SUBTITLE, "Subtitles"))
        )

    result = download_subs(url, sub_lang, dest)
    if result.ok:
        show_download_ok("字幕", result.output)
    else:
        show_download_fail("字幕", result.error)


def main(argv: list[str] | None = None) -> int:
    """主入口，返回退出码。"""
    if argv is None:
        argv = sys.argv[1:]

    # 1. 环境自检
    if not _run_env_check():
        return 1

    # 2. 获取 URL
    url = _get_url(argv)
    if not url:
        print("需要提供视频 URL")
        return 1

    # 3. 格式探测
    print("\n正在探测格式...")
    try:
        info = detect(url)
    except (RuntimeError, ValueError) as e:
        print(f"格式探测失败: {e}")
        return 1

    # 4. 展示探测结果
    show_detect_result(
        title=info.title,
        video_count=len(info.video_formats),
        audio_count=len(info.audio_formats),
        sub_count=len(info.subtitles),
        auto_sub_count=len(info.auto_subtitles),
    )

    # 5. 构造菜单数据
    vid_labels, vid_values = build_video_labels(info.video_formats)
    aud_labels, aud_values = build_audio_labels(info.audio_formats)
    sub_labels, sub_values = build_sub_labels(info.subtitles)

    # 6. 下载类型选择
    dtype = ask_download_type()
    if dtype is None:
        return 0

    # 7. 按类型执行下载
    if dtype in ("video", "all"):
        video_dir = _handle_video(
            url, info, vid_labels, vid_values, aud_labels, aud_values,
        )

        # "all" 模式：即使视频被跳过，仍允许单独下载字幕
        if dtype == "all":
            _handle_subs(url, sub_labels, sub_values, default_dir=video_dir)

    elif dtype == "audio":
        aud_fmt = menu_select("选择音频流", aud_labels, aud_values)
        if aud_fmt:
            default_dir = str(resolve_download_dir(config.YT_DIR_AUDIO, "Music"))
            dest = ask_location(default_dir)
            show_download_start(aud_fmt, dest)
            result = download_audio(url, aud_fmt, dest)
            if result.ok:
                show_download_ok("音频", result.output)
            else:
                show_download_fail("音频", result.error)

    elif dtype == "subs":
        _handle_subs(url, sub_labels, sub_values)

    return 0


if __name__ == "__main__":
    sys.exit(main())
