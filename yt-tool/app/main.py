"""入口主流程 — 对应原 yt-interactive.sh 的 main() 函数。

串联各模块：环境自检 → URL 输入 → 格式探测 → 交互选择 → 下载执行。
本模块只做流程编排，不做具体业务逻辑。
"""
from __future__ import annotations

import sys

from .core import config
from .core.env_check import check_env
from .core.format_detector import DetectResult, detect, validate_detected_formats
from .core.path_utils import resolve_download_dir
from .core.downloader import download_audio, download_auto_subs, download_playlist, download_subs, download_video
from .ui import (
    ask_audio_transcode,
    ask_cookie_browser,
    ask_download_sections,
    ask_download_type,
    ask_embed_subs,
    ask_location,
    ask_playlist_mode,
    ask_sponsorblock_categories,
    ask_sponsorblock_mode,
    build_audio_header,
    build_audio_labels,
    build_sub_labels,
    build_video_header,
    build_video_labels,
    is_video_only,
    menu_select,
    show_detect_result,
    show_download_fail,
    show_download_ok,
    show_download_start,
)


def _build_media_extra_args(
    *,
    download_sections: str | None = None,
    sponsorblock_mode: str | None = None,
    sponsorblock_categories: str | None = None,
) -> list[str]:
    """构造媒体下载附加参数。"""
    args: list[str] = []
    if download_sections:
        args += ["--download-sections", download_sections]
    if sponsorblock_mode:
        cats = sponsorblock_categories or ",".join(config.YT_SPONSORBLOCK_DEFAULT_CATEGORIES)
        flag = "--sponsorblock-mark" if sponsorblock_mode == "mark" else "--sponsorblock-remove"
        args += [flag, cats]
    return args


def _is_format_unavailable_error(error: str) -> bool:
    """判断是否属于格式已失效、可尝试重探测的错误。"""
    err = error.lower()
    return "format is not available" in err or "requested format is not available" in err


def _refresh_detect_info(
    url: str,
    *,
    cookies_from: str | None = None,
    extra_dl_args: list[str] | None = None,
) -> DetectResult | None:
    """重新探测并预检格式，失败时返回 None。"""
    print("检测到格式可能已失效，正在重新探测...")
    # 若原始下载参数包含 --no-playlist，重新探测时也须保持，
    # 确保 watch?v=X&list=Y 形式的 URL 仍取目标视频而非播放列表首条
    no_playlist = "--no-playlist" in (extra_dl_args or [])
    try:
        info = detect(url, cookies_from=cookies_from, no_playlist=no_playlist)
    except (RuntimeError, ValueError) as e:
        print(f"重新探测失败: {e}")
        return None

    if config.YT_VALIDATE_FORMATS_BEFORE_MENU:
        info = validate_detected_formats(
            url,
            info,
            cookies_from=cookies_from,
            extra_args=extra_dl_args or [],
        )
    return info


def _run_env_check() -> tuple[bool, bool]:
    """环境自检，返回 (是否可继续, ffmpeg 是否可用)。"""
    print("── 环境自检 ──")
    result = check_env()

    has_ffmpeg = any(item.name == "ffmpeg" and item.found for item in result.items)

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
        return False, has_ffmpeg

    if result.warning_missing:
        print("\n部分可选依赖缺失，某些功能可能受限。")

    return True, has_ffmpeg


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
    sub_labels: list[str],
    sub_values: list[str],
    cookies_from: str | None = None,
    extra_dl_args: list[str] | None = None,
    has_ffmpeg: bool = True,
) -> tuple[str | None, str | None]:
    """处理视频下载流程，返回 (输出目录, 已嵌入的字幕语言)。

    embed_lang 非 None 时表示用户已选择嵌入字幕，调用方应跳过额外的字幕下载。
    """
    current_info = info

    for attempt in range(2):
        current_vid_labels, current_vid_values = build_video_labels(current_info.video_formats)
        current_aud_labels, current_aud_values = build_audio_labels(current_info.audio_formats)
        current_sub_labels, current_sub_values = build_sub_labels(current_info.subtitles, current_info.auto_subtitles)

        vid_fmt = menu_select(
            "选择视频流", current_vid_labels, current_vid_values,
            column_hint=build_video_header(),
        )
        if not vid_fmt:
            return None, None

        final_fmt = vid_fmt

        if is_video_only(current_info.video_formats, vid_fmt):
            print("该流为 video only，需选择音频流合并")
            aud_fmt = menu_select(
                "选择音频流", current_aud_labels, current_aud_values,
                column_hint=build_audio_header(),
            )
            if not aud_fmt:
                print("未选择音频流，已取消视频下载")
                return None, None
            final_fmt = f"{vid_fmt}+{aud_fmt}"

        embed_sub_tracks = tuple(t for t in current_info.subtitles if not t.is_live_chat)
        plain_sub_labels, plain_sub_values = build_sub_labels(embed_sub_tracks)
        # ffmpeg 不可用时跳过嵌入字幕询问，避免 --embed-subs 失败阻断正常视频下载
        embed_lang = ask_embed_subs(plain_sub_labels, plain_sub_values) if has_ffmpeg else None

        default_dir = str(resolve_download_dir(config.YT_DIR_VIDEO, "Videos"))
        dest = ask_location(default_dir)

        show_download_start(final_fmt, dest)
        result = download_video(url, final_fmt, dest, cookies_from=cookies_from,
                                embed_subs_lang=embed_lang, extra_args=extra_dl_args or [])
        if result.ok:
            show_download_ok("视频", result.output, result.saved_path)
            return dest, embed_lang

        show_download_fail("视频", result.error)
        if attempt == 0 and _is_format_unavailable_error(result.error):
            refreshed = _refresh_detect_info(
                url,
                cookies_from=cookies_from,
                extra_dl_args=extra_dl_args,
            )
            if refreshed and (refreshed.video_formats or refreshed.audio_formats):
                current_info = refreshed
                continue
        # 下载失败：embed_lang 未实际生效，返回 None 让调用方仍可单独下载字幕
        return dest, None

    return None, None


def _handle_subs(
    url: str,
    sub_labels: list[str],
    sub_values: list[str],
    default_dir: str | None = None,
    live_chat_values: set[str] | None = None,
    cookies_from: str | None = None,
    extra_dl_args: list[str] | None = None,
) -> None:
    """处理字幕下载流程（普通字幕 + 自动字幕合并菜单）。"""
    if not sub_labels:
        print("该视频无可用字幕（含自动字幕）")
        return

    sub_lang = menu_select("选择字幕语言", sub_labels, sub_values)
    if not sub_lang:
        return

    if live_chat_values and sub_lang in live_chat_values:
        print("该轨道是 live_chat，下载结果通常为 JSON，不是常规 .srt/.vtt 字幕")

    if default_dir:
        print(f"\n字幕将默认保存到视频目录: {default_dir}")
        dest = ask_location(default_dir)
    else:
        dest = ask_location(
            str(resolve_download_dir(config.YT_DIR_SUBTITLE, "Subtitles"))
        )

    # 按值前缀区分普通字幕与自动字幕
    if sub_lang.startswith("auto:"):
        actual_lang = sub_lang[len("auto:"):]
        result = download_auto_subs(url, actual_lang, dest, cookies_from=cookies_from,
                                    extra_args=extra_dl_args or [])
    else:
        result = download_subs(url, sub_lang, dest, cookies_from=cookies_from,
                               extra_args=extra_dl_args or [])

    if result.ok:
        show_download_ok("字幕", result.output, result.saved_path)
    else:
        show_download_fail("字幕", result.error)


def main(argv: list[str] | None = None) -> int:
    """主入口，返回退出码。"""
    if argv is None:
        argv = sys.argv[1:]

    # 1. 环境自检
    env_ok, has_ffmpeg = _run_env_check()
    if not env_ok:
        return 1

    # 2. 获取 URL
    url = _get_url(argv)
    if not url:
        print("需要提供视频 URL")
        return 1

    # 2b. 询问 Cookie（可选）
    cookies_from = ask_cookie_browser()

    # 3. 格式探测
    print("\n正在探测格式...")
    try:
        info = detect(url, cookies_from=cookies_from)
    except (RuntimeError, ValueError) as e:
        print(f"格式探测失败: {e}")
        return 1

    # 4. 若为播放列表，先询问下载范围
    if info.is_playlist:
        pmode = ask_playlist_mode(info.playlist_title, info.playlist_count)
        if pmode is None:
            return 0
        if pmode in ("all_video", "all_audio"):
            mode = "video" if pmode == "all_video" else "audio"
            sponsorblock_mode = ask_sponsorblock_mode(has_ffmpeg=has_ffmpeg) if mode in ("video", "audio") else None
            sponsorblock_categories = (
                ask_sponsorblock_categories(config.YT_SPONSORBLOCK_DEFAULT_CATEGORIES)
                if sponsorblock_mode else None
            )
            default_dir = str(resolve_download_dir(
                config.YT_DIR_PLAYLIST,
                "Playlists",
            ))
            dest = ask_location(default_dir)
            show_download_start(f"playlist:{mode}", dest)
            result = download_playlist(
                url,
                mode,
                dest,
                cookies_from=cookies_from,
                extra_args=_build_media_extra_args(
                    sponsorblock_mode=sponsorblock_mode,
                    sponsorblock_categories=sponsorblock_categories,
                ),
            )
            if result.ok:
                show_download_ok("播放列表", result.output, result.saved_path)
            else:
                show_download_fail("播放列表", result.error)
            return 0
        # pmode == "first"：继续走下方单条流程，只下载 URL 指向的那条视频
        # 优先尝试 --no-playlist（适用于 watch?v=X&list=Y，确保取到 URL 指定视频）；
        # 若失败则说明是纯播放列表 URL（无具体视频 ID），回退到 --playlist-items 1
        print("正在重新探测目标视频格式...")
        try:
            info = detect(url, cookies_from=cookies_from, no_playlist=True)
            extra_dl_args: list[str] = ["--no-playlist"]
        except (RuntimeError, ValueError):
            # 纯播放列表 URL（如 playlist?list=...）：--no-playlist 不适用，
            # 保留初次探测得到的首条格式信息，下载时限定为首条
            extra_dl_args = ["--playlist-items", "1"]
    else:
        extra_dl_args = []

    # 4b. 下载前预检格式可用性，过滤掉当前已失效的 format_id
    if config.YT_VALIDATE_FORMATS_BEFORE_MENU:
        print("正在验证高优先级候选格式...")
        original_video_count = len(info.video_formats)
        original_audio_count = len(info.audio_formats)
        info = validate_detected_formats(
            url,
            info,
            cookies_from=cookies_from,
            extra_args=extra_dl_args,
        )
        if original_video_count or original_audio_count:
            print(
                "候选预检结果: "
                f"视频 {len(info.video_formats)}/{original_video_count}, "
                f"音频 {len(info.audio_formats)}/{original_audio_count}"
            )

    # 5. 展示探测结果（单条或首条预览）
    show_detect_result(
        title=info.title,
        video_count=len(info.video_formats),
        audio_count=len(info.audio_formats),
        sub_count=len(info.subtitles),
        auto_sub_count=len(info.auto_subtitles),
    )

    # 6. 构造菜单数据
    vid_labels, vid_values = build_video_labels(info.video_formats)
    aud_labels, aud_values = build_audio_labels(info.audio_formats)
    sub_labels, sub_values = build_sub_labels(info.subtitles, info.auto_subtitles)
    live_chat_values = {
        t.lang for t in info.subtitles if t.is_live_chat
    } | {
        f"auto:{t.lang}" for t in info.auto_subtitles if t.is_live_chat
    }

    # 7. 下载类型选择
    dtype = ask_download_type()
    if dtype is None:
        return 0

    # 8. 按类型执行下载
    if dtype in ("video", "all"):
        download_sections = ask_download_sections() if (dtype == "video" and has_ffmpeg) else None
        sponsorblock_mode = ask_sponsorblock_mode(has_ffmpeg=has_ffmpeg)
        sponsorblock_categories = (
            ask_sponsorblock_categories(config.YT_SPONSORBLOCK_DEFAULT_CATEGORIES)
            if sponsorblock_mode else None
        )
        media_extra_args = [*extra_dl_args, *_build_media_extra_args(
            download_sections=download_sections,
            sponsorblock_mode=sponsorblock_mode,
            sponsorblock_categories=sponsorblock_categories,
        )]
        video_dir, embed_lang_used = _handle_video(
            url, info, vid_labels, vid_values, aud_labels, aud_values,
            sub_labels, sub_values, cookies_from=cookies_from,
            extra_dl_args=media_extra_args, has_ffmpeg=has_ffmpeg,
        )

        # "all" 模式：字幕已嵌入视频时跳过单独下载，避免重复保存
        # 字幕下载不传入 --sponsorblock-remove/mark（需要媒体文件，与 --skip-download 冲突）；
        # 保留 --download-sections 以确保字幕时间轴与视频片段一致
        if dtype == "all" and not embed_lang_used:
            subs_extra_args = [*extra_dl_args, *_build_media_extra_args(
                download_sections=download_sections,
            )]
            _handle_subs(url, sub_labels, sub_values, default_dir=video_dir,
                         live_chat_values=live_chat_values,
                         cookies_from=cookies_from, extra_dl_args=subs_extra_args)

    elif dtype == "audio":
        current_info = info
        for attempt in range(2):
            current_aud_labels, current_aud_values = build_audio_labels(current_info.audio_formats)
            aud_fmt = menu_select(
                "选择音频流", current_aud_labels, current_aud_values,
                column_hint=build_audio_header(),
            )
            if not aud_fmt:
                break
            download_sections = ask_download_sections() if has_ffmpeg else None
            sponsorblock_mode = ask_sponsorblock_mode(has_ffmpeg=has_ffmpeg)
            sponsorblock_categories = (
                ask_sponsorblock_categories(config.YT_SPONSORBLOCK_DEFAULT_CATEGORIES)
                if sponsorblock_mode else None
            )
            media_extra_args = [*extra_dl_args, *_build_media_extra_args(
                download_sections=download_sections,
                sponsorblock_mode=sponsorblock_mode,
                sponsorblock_categories=sponsorblock_categories,
            )]
            transcode_to = ask_audio_transcode(has_ffmpeg=has_ffmpeg)
            default_dir = str(resolve_download_dir(config.YT_DIR_AUDIO, "Music"))
            dest = ask_location(default_dir)
            show_download_start(aud_fmt, dest)
            result = download_audio(url, aud_fmt, dest,
                                    cookies_from=cookies_from, transcode_to=transcode_to,
                                    extra_args=media_extra_args)
            if result.ok:
                show_download_ok("音频", result.output, result.saved_path)
                break

            show_download_fail("音频", result.error)
            if attempt == 0 and _is_format_unavailable_error(result.error):
                refreshed = _refresh_detect_info(
                    url,
                    cookies_from=cookies_from,
                    extra_dl_args=extra_dl_args,
                )
                if refreshed and refreshed.audio_formats:
                    current_info = refreshed
                    continue
            break

    elif dtype == "subs":
        _handle_subs(url, sub_labels, sub_values, live_chat_values=live_chat_values,
                     cookies_from=cookies_from,
                     extra_dl_args=extra_dl_args)

    return 0


if __name__ == "__main__":
    sys.exit(main())
