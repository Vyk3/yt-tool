"""CLI 主流程 — 通过 AppWorkflow 驱动的终端入口。

串联各模块：环境自检 → URL 输入 → 格式探测 → 交互选择 → 下载执行。
本模块只做流程编排，不做具体业务逻辑。
"""
from __future__ import annotations

import contextlib
import sys
from collections.abc import Callable

from ..core import config
from ..core.path_utils import resolve_download_dir
from ..services.models import DetectRequest, DetectResponse
from ..services.workflow import AppWorkflow, _is_format_unavailable_error
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


def _run_env_check(workflow: AppWorkflow) -> tuple[bool, bool]:
    """环境自检，返回 (是否可继续, ffmpeg 是否可用)。"""
    print("── 环境自检 ──")
    result = workflow.check_environment()

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


def _refresh_detect_info(
    workflow: AppWorkflow,
    url: str,
    *,
    cookies_from: str | None = None,
    extra_dl_args: list[str] | None = None,
) -> DetectResponse | None:
    """重新探测并预检格式，失败时返回 None。"""
    print("检测到格式可能已失效，正在重新探测...")
    try:
        return workflow.detect_formats(
            DetectRequest(
                url=url,
                cookies_from=cookies_from,
                extra_args=tuple(extra_dl_args or []),
            )
        )
    except (RuntimeError, ValueError) as e:
        print(f"重新探测失败: {e}")
        return None


def _retryable_refresh(
    *,
    attempt: int,
    error: str,
    workflow: AppWorkflow,
    url: str,
    cookies_from: str | None = None,
    extra_dl_args: list[str] | None = None,
    has_formats: Callable[[DetectResponse], bool],
) -> DetectResponse | None:
    """首次因格式失效失败时，按需重新探测并返回可继续使用的新结果。"""
    if attempt != 0 or not _is_format_unavailable_error(error):
        return None

    refreshed = _refresh_detect_info(
        workflow,
        url,
        cookies_from=cookies_from,
        extra_dl_args=extra_dl_args,
    )
    if refreshed and has_formats(refreshed):
        return refreshed
    return None


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
    workflow: AppWorkflow,
    url: str,
    info: DetectResponse,
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

        vid_fmt = menu_select(
            "选择视频流", current_vid_labels, current_vid_values,
            column_hint=build_video_header(),
        )
        if not vid_fmt:
            return None, None

        aud_fmt_for_merge = ""
        if is_video_only(current_info.video_formats, vid_fmt):
            print("该流为 video only，需选择音频流合并")
            aud_fmt = menu_select(
                "选择音频流", current_aud_labels, current_aud_values,
                column_hint=build_audio_header(),
            )
            if not aud_fmt:
                print("未选择音频流，已取消视频下载")
                return None, None
            aud_fmt_for_merge = aud_fmt

        embed_sub_tracks = tuple(t for t in current_info.subtitles if not t.is_live_chat)
        plain_sub_labels, plain_sub_values = build_sub_labels(embed_sub_tracks)
        embed_lang = ask_embed_subs(plain_sub_labels, plain_sub_values) if has_ffmpeg else None

        default_dir = str(resolve_download_dir(config.YT_DIR_VIDEO, "Videos"))
        dest = ask_location(default_dir)

        req = workflow.build_download_request(
            "video", url, dest,
            format_id=vid_fmt,
            audio_format_id=aud_fmt_for_merge,
            embed_subs_lang=embed_lang or "",
            cookies_from=cookies_from,
            extra_args=tuple(extra_dl_args or []),
        )
        show_download_start(
            f"{vid_fmt}+{aud_fmt_for_merge}" if aud_fmt_for_merge else vid_fmt,
            dest,
        )
        result = workflow.run_download(req)

        if result.ok:
            show_download_ok("视频", result.output, result.saved_path)
            return dest, embed_lang

        show_download_fail("视频", result.error)
        refreshed = _retryable_refresh(
            attempt=attempt,
            error=result.error,
            workflow=workflow,
            url=url,
            cookies_from=cookies_from,
            extra_dl_args=extra_dl_args,
            has_formats=lambda info: bool(info.video_formats or info.audio_formats),
        )
        if refreshed:
            current_info = refreshed
            continue
        return dest, None

    return None, None


def _handle_subs(
    workflow: AppWorkflow,
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

    req = workflow.build_download_request(
        "subtitle", url, dest,
        subtitle_lang=sub_lang,
        cookies_from=cookies_from,
        extra_args=tuple(extra_dl_args or []),
    )
    result = workflow.run_download(req)

    if result.ok:
        show_download_ok("字幕", result.output, result.saved_path)
    else:
        show_download_fail("字幕", result.error)


def main(argv: list[str] | None = None) -> int:
    """主入口，返回退出码。"""
    if argv is None:
        argv = sys.argv[1:]

    workflow = AppWorkflow()

    # 1. 环境自检
    env_ok, has_ffmpeg = _run_env_check(workflow)
    if not env_ok:
        return 1

    # 2. 获取 URL
    url = _get_url(argv)
    if not url:
        print("需要提供视频 URL")
        return 1

    # 2b. 询问 Cookie（可选）
    cookies_from = ask_cookie_browser()

    # 3. 格式探测（含按配置预检）
    print("\n正在探测格式...")
    try:
        resp = workflow.detect_formats(DetectRequest(url, cookies_from=cookies_from))
    except (RuntimeError, ValueError) as e:
        print(f"格式探测失败: {e}")
        return 1

    # 4. 若为播放列表，先询问下载范围
    extra_dl_args: list[str] = []
    if resp.is_playlist:
        pmode = ask_playlist_mode(resp.playlist_title, resp.playlist_count)
        if pmode is None:
            return 0
        if pmode in ("all_video", "all_audio"):
            mode = "video" if pmode == "all_video" else "audio"
            sponsorblock_mode = ask_sponsorblock_mode(has_ffmpeg=has_ffmpeg) if mode in ("video", "audio") else None
            sponsorblock_categories = (
                ask_sponsorblock_categories(config.YT_SPONSORBLOCK_DEFAULT_CATEGORIES)
                if sponsorblock_mode else None
            )
            default_dir = str(resolve_download_dir(config.YT_DIR_PLAYLIST, "Playlists"))
            dest = ask_location(default_dir)
            show_download_start(f"playlist:{mode}", dest)
            req = workflow.build_download_request(
                "playlist", url, dest,
                format_id=mode,
                cookies_from=cookies_from,
                extra_args=tuple(_build_media_extra_args(
                    sponsorblock_mode=sponsorblock_mode,
                    sponsorblock_categories=sponsorblock_categories,
                )),
            )
            result = workflow.run_download(req)
            if result.ok:
                show_download_ok("播放列表", result.output, result.saved_path)
            else:
                show_download_fail("播放列表", result.error)
            return 0
        # pmode == "first"：重探测目标视频
        print("正在重新探测目标视频格式...")
        try:
            resp = workflow.detect_formats(
                DetectRequest(url, cookies_from=cookies_from, extra_args=("--no-playlist",))
            )
            extra_dl_args = ["--no-playlist"]
        except (RuntimeError, ValueError):
            # 纯播放列表 URL（无具体视频 ID）：改用 --playlist-items 1 并重新预检，
            # 确保格式可用性检查与下载时的参数一致（修复原代码在 extra_dl_args 确定后才 validate 的行为）
            extra_dl_args = ["--playlist-items", "1"]
            with contextlib.suppress(RuntimeError, ValueError):
                resp = workflow.detect_formats(
                    DetectRequest(url, cookies_from=cookies_from, extra_args=("--playlist-items", "1"))
                )  # 回退到初次探测结果，不阻断流程

    # 5. 展示探测结果
    show_detect_result(
        title=resp.title,
        video_count=len(resp.video_formats),
        audio_count=len(resp.audio_formats),
        sub_count=len(resp.subtitles),
        auto_sub_count=len(resp.auto_subtitles),
    )

    # 6. 构造菜单数据
    vid_labels, vid_values = build_video_labels(resp.video_formats)
    aud_labels, aud_values = build_audio_labels(resp.audio_formats)
    sub_labels, sub_values = build_sub_labels(resp.subtitles, resp.auto_subtitles)
    live_chat_values = {
        t.lang for t in resp.subtitles if t.is_live_chat
    } | {
        f"auto:{t.lang}" for t in resp.auto_subtitles if t.is_live_chat
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
            workflow, url, resp,
            cookies_from=cookies_from,
            extra_dl_args=media_extra_args,
            has_ffmpeg=has_ffmpeg,
        )

        if dtype == "all" and not embed_lang_used:
            subs_extra_args = [*extra_dl_args, *_build_media_extra_args(
                download_sections=download_sections,
            )]
            _handle_subs(
                workflow, url, sub_labels, sub_values,
                default_dir=video_dir,
                live_chat_values=live_chat_values,
                cookies_from=cookies_from,
                extra_dl_args=subs_extra_args,
            )

    elif dtype == "audio":
        current_info = resp
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
            req = workflow.build_download_request(
                "audio", url, dest,
                format_id=aud_fmt,
                transcode_to=transcode_to or "",
                cookies_from=cookies_from,
                extra_args=tuple(media_extra_args),
            )
            result = workflow.run_download(req)
            if result.ok:
                show_download_ok("音频", result.output, result.saved_path)
                break

            show_download_fail("音频", result.error)
            refreshed = _retryable_refresh(
                attempt=attempt,
                error=result.error,
                workflow=workflow,
                url=url,
                cookies_from=cookies_from,
                extra_dl_args=extra_dl_args,
                has_formats=lambda info: bool(info.audio_formats),
            )
            if refreshed:
                current_info = refreshed
                continue
            break

    elif dtype == "subs":
        _handle_subs(
            workflow, url, sub_labels, sub_values,
            live_chat_values=live_chat_values,
            cookies_from=cookies_from,
            extra_dl_args=extra_dl_args,
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
