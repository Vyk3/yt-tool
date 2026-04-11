"""应用工作流 — GUI 和 CLI 共享的业务编排层。

不包含任何终端 I/O（print / input）或 Qt 导入。
"""
from __future__ import annotations

from collections.abc import Callable

from ..core import config
from ..core.downloader import (
    download_audio,
    download_auto_subs,
    download_playlist,
    download_subs,
    download_video,
)
from ..core.env_check import CheckResult, check_env
from ..core.format_detector import detect, validate_detected_formats
from .models import (
    AppSettings,
    DetectRequest,
    DetectResponse,
    DownloadKind,
    DownloadRequest,
    ProgressEvent,
    TaskResult,
)


def _is_format_unavailable_error(error: str) -> bool:
    """判断是否属于格式已失效、可尝试重探测的错误。"""
    err = error.lower()
    return "format is not available" in err or "requested format is not available" in err


class AppWorkflow:
    def __init__(self, settings: AppSettings | None = None) -> None:
        self._settings = settings or AppSettings(
            download_dir_video=str(config.YT_DIR_VIDEO),
            download_dir_audio=str(config.YT_DIR_AUDIO),
            download_dir_subtitle=str(config.YT_DIR_SUBTITLE),
        )

    def check_environment(self) -> CheckResult:
        """检查运行环境，返回 CheckResult。"""
        return check_env()

    def _effective_cookies(self, req_cookies: str | None) -> str | None:
        """per-request cookies 优先，不存在时回退到 AppSettings.cookies_from。"""
        return req_cookies if req_cookies is not None else self._settings.cookies_from

    def detect_formats(self, request: DetectRequest) -> DetectResponse:
        """探测格式，按配置可选执行预检，返回 DetectResponse。"""
        no_playlist = "--no-playlist" in request.extra_args
        cookies = self._effective_cookies(request.cookies_from)
        info = detect(request.url, cookies_from=cookies, no_playlist=no_playlist)
        if config.YT_VALIDATE_FORMATS_BEFORE_MENU:
            info = validate_detected_formats(
                request.url,
                info,
                cookies_from=cookies,
                extra_args=list(request.extra_args),
            )
        return DetectResponse(
            title=info.title,
            video_formats=info.video_formats,
            audio_formats=info.audio_formats,
            subtitles=info.subtitles,
            auto_subtitles=info.auto_subtitles,
            is_playlist=info.is_playlist,
            playlist_title=info.playlist_title,
            playlist_count=info.playlist_count,
        )

    def build_download_request(
        self,
        kind: DownloadKind,
        url: str,
        dest_dir: str,
        *,
        format_id: str = "",
        audio_format_id: str = "",
        subtitle_lang: str = "",
        embed_subs_lang: str = "",
        transcode_to: str = "",
        cookies_from: str | None = None,
        extra_args: tuple[str, ...] = (),
    ) -> DownloadRequest:
        """构造 DownloadRequest，供 CLI 和 GUI 统一使用。"""
        return DownloadRequest(
            kind=kind,
            url=url,
            dest_dir=dest_dir,
            format_id=format_id,
            audio_format_id=audio_format_id,
            subtitle_lang=subtitle_lang,
            embed_subs_lang=embed_subs_lang,
            transcode_to=transcode_to,
            cookies_from=cookies_from,
            extra_args=extra_args,
        )

    def run_download(
        self,
        request: DownloadRequest,
        on_progress: Callable[[ProgressEvent], None] | None = None,
    ) -> TaskResult:
        """执行一次下载，on_progress 收到每个输出块对应的 ProgressEvent。"""
        on_chunk: Callable[[str], None] | None = None
        if on_progress is not None:
            _cb = on_progress  # avoid late-binding in closure

            def on_chunk(chunk: str) -> None:
                _cb(ProgressEvent(stage="download", message=chunk, percent=None))

        dl_result = self._dispatch(request, on_chunk)
        state = "success" if dl_result.ok else "error"
        return TaskResult(
            ok=dl_result.ok,
            state=state,
            output=dl_result.output,
            error=dl_result.error,
            saved_path=dl_result.saved_path,
        )

    def retry_with_redetect(
        self,
        request: DownloadRequest,
        on_progress: Callable[[ProgressEvent], None] | None = None,
    ) -> TaskResult:
        """首次下载失败且为格式失效错误时，重新探测并在目标格式仍可用时重试一次。

        若重新探测后所请求的 format_id 已不在新结果中，则直接返回首次失败结果，
        让上层（GUI/CLI）重新选择格式，而不是做一次必然失败的重试。
        """
        first = self.run_download(request, on_progress)
        if not first.ok and _is_format_unavailable_error(first.error):
            no_playlist = "--no-playlist" in request.extra_args
            try:
                info = detect(
                    request.url,
                    cookies_from=self._effective_cookies(request.cookies_from),
                    no_playlist=no_playlist,
                )
            except (RuntimeError, ValueError):
                return first
            if not (info.audio_formats or info.video_formats):
                return first
            # playlist 的 format_id 是模式字符串（"video"/"audio"），不是真实格式 ID，
            # 跳过可用性检查；video/audio kind 才需要验证
            if request.kind in ("video", "audio"):
                available_ids = {f.id for f in (*info.video_formats, *info.audio_formats)}
                if request.format_id and request.format_id not in available_ids:
                    return first
                if request.audio_format_id and request.audio_format_id not in available_ids:
                    return first
            return self.run_download(request, on_progress)
        return first

    # ------------------------------------------------------------------
    # Internal helpers
    # ------------------------------------------------------------------

    def _dispatch(
        self,
        request: DownloadRequest,
        on_chunk: Callable[[str], None] | None,
    ):  # -> DownloadResult (core type, not re-exported from services)
        """根据 kind 分派到对应的 core downloader 函数。"""
        kind = request.kind
        cookies = self._effective_cookies(request.cookies_from)

        if kind == "video":
            combined_fmt = (
                f"{request.format_id}+{request.audio_format_id}"
                if request.audio_format_id
                else request.format_id
            )
            return download_video(
                request.url,
                combined_fmt,
                request.dest_dir,
                cookies_from=cookies,
                embed_subs_lang=request.embed_subs_lang or None,
                extra_args=list(request.extra_args),
                on_chunk=on_chunk,
            )

        if kind == "audio":
            return download_audio(
                request.url,
                request.format_id,
                request.dest_dir,
                cookies_from=cookies,
                transcode_to=request.transcode_to or None,
                extra_args=list(request.extra_args),
                on_chunk=on_chunk,
            )

        if kind == "subtitle":
            if request.subtitle_lang.startswith("auto:"):
                actual_lang = request.subtitle_lang[len("auto:"):]
                return download_auto_subs(
                    request.url,
                    actual_lang,
                    request.dest_dir,
                    cookies_from=cookies,
                    extra_args=list(request.extra_args),
                    on_chunk=on_chunk,
                )
            return download_subs(
                request.url,
                request.subtitle_lang,
                request.dest_dir,
                cookies_from=cookies,
                extra_args=list(request.extra_args),
                on_chunk=on_chunk,
            )

        if kind == "playlist":
            # format_id 复用为 playlist mode: "video" 或 "audio"
            return download_playlist(
                request.url,
                request.format_id,
                request.dest_dir,
                cookies_from=cookies,
                extra_args=list(request.extra_args),
                on_chunk=on_chunk,
            )

        from ..core.downloader import DownloadResult
        return DownloadResult(ok=False, output="", error=f"Unknown kind: {kind}")
