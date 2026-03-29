"""终端交互 UI — 对应原 yt-interactive.sh 中的交互逻辑。

职责:
  - 纯终端 stdin/stdout 交互：菜单选择、路径确认、状态展示
  - 不调用 yt-dlp，不做下载，不做格式探测
  - 所有展示走 print()，所有用户输入走 input()
  - 返回用户的选择结果，由调用方（main.py）串联业务流程

设计约束:
  - 函数只做"问 → 答 → 返回"，不持有状态
  - 返回 None 表示用户选择跳过或退出该步骤，由调用方决定后续行为
"""
from __future__ import annotations

from .format_detector import AudioFormat, SubtitleTrack, VideoFormat


# ---- 通用菜单 ----

def menu_select(prompt: str, labels: list[str], values: list[str]) -> str | None:
    """展示编号菜单，返回用户选中的 value；跳过返回 None。"""
    if len(labels) != len(values):
        raise ValueError("labels and values length mismatch")

    print(f"\n── {prompt} ──")

    if not labels:
        print("  没有可选项，跳过")
        return None

    for i, label in enumerate(labels, 1):
        print(f"  {i}) {label}")
    print("  0) 跳过")
    print()

    count = len(labels)
    while True:
        raw = input(f"选择 [0-{count}]: ").strip()
        if raw == "0":
            return None
        if raw.isdigit():
            idx = int(raw)
            if 1 <= idx <= count:
                return values[idx - 1]
        print("  无效输入，请重试")


# ---- 菜单数据构造 ----

def build_video_labels(formats: tuple[VideoFormat, ...]) -> tuple[list[str], list[str]]:
    """从 VideoFormat 列表构造菜单 (labels, values)。"""
    labels: list[str] = []
    values: list[str] = []
    for f in formats:
        if f.height:
            label = f"{f.id}  {f.height}p  {f.codec}  {f.fps}fps  {f.note}"
        else:
            label = f"{f.id}  {f.codec}  {f.fps}fps  {f.note}"
        labels.append(label)
        values.append(f.id)
    return labels, values


def build_audio_labels(formats: tuple[AudioFormat, ...]) -> tuple[list[str], list[str]]:
    """从 AudioFormat 列表构造菜单 (labels, values)。"""
    labels: list[str] = []
    values: list[str] = []
    for f in formats:
        if f.abr:
            label = f"{f.id}  {f.codec}  {f.abr:.0f}k  {f.ext}  {f.note}"
        else:
            label = f"{f.id}  {f.codec}  {f.ext}  {f.note}"
        labels.append(label)
        values.append(f.id)
    return labels, values


def build_sub_labels(tracks: tuple[SubtitleTrack, ...]) -> tuple[list[str], list[str]]:
    """从 SubtitleTrack 列表构造菜单 (labels, values)。"""
    labels: list[str] = []
    values: list[str] = []
    for t in tracks:
        labels.append(f"{t.lang}  {t.label}")
        values.append(t.lang)
    return labels, values


# ---- 下载类型选择 ----

def ask_download_type() -> str | None:
    """让用户选择下载类型，循环直到合法输入。

    返回 "video" / "audio" / "subs" / "all"；输入 0 退出返回 None。
    """
    print("\n── 下载什么? ──")
    print("  1) 视频 (视频+音频合并)")
    print("  2) 仅音频")
    print("  3) 仅字幕")
    print("  4) 全部 (视频+字幕)")
    print("  0) 退出")
    print()

    mapping = {"1": "video", "2": "audio", "3": "subs", "4": "all"}
    while True:
        raw = input("选择 [0-4]: ").strip()
        if raw == "0":
            return None
        if raw in mapping:
            return mapping[raw]
        print("  无效输入，请重试")


# ---- 路径确认 ----

def ask_location(default_dir: str) -> str:
    """让用户确认或修改下载目录，返回最终路径字符串。"""
    print("\n── 下载位置 ──")
    print(f"  当前: {default_dir}")
    change = input("修改位置? [直接回车保持/输入新路径]: ").strip()
    return change if change else default_dir


# ---- 辅助查询 ----

def is_video_only(formats: tuple[VideoFormat, ...], format_id: str) -> bool:
    """判断指定 format_id 是否为 video only 流。"""
    for f in formats:
        if f.id == format_id:
            return "video only" in f.note
    return False


# ---- 状态展示 ----

def show_detect_result(
    title: str,
    video_count: int,
    audio_count: int,
    sub_count: int,
    auto_sub_count: int,
) -> None:
    """展示格式探测结果摘要。"""
    print(f"\n标题: {title}")
    sub_info = f"{sub_count} 个字幕"
    if auto_sub_count:
        sub_info += f" (另有 {auto_sub_count} 个自动字幕)"
    print(f"发现 {video_count} 个视频流, {audio_count} 个音频流, {sub_info}")


def show_download_start(format_spec: str, dest: str) -> None:
    """展示下载开始信息。"""
    print(f"\n开始下载: format={format_spec} → {dest}")


def show_download_ok(kind: str, output: str) -> None:
    """展示下载成功信息。"""
    print(f"{kind}下载完成")
    if output.strip():
        print(output.strip())


def show_download_fail(kind: str, error: str) -> None:
    """展示下载失败信息。"""
    print(f"{kind}下载失败: {error}")
