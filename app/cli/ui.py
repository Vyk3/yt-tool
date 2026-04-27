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

import os
import platform
import stat
import sys

from wcwidth import wcswidth, wcwidth

from ..core import config
from ..core.format_detector import AudioFormat, SubtitleTrack, VideoFormat

# ---- ANSI 颜色常量 ----

_BOLD   = "\033[1m"
_DIM    = "\033[2m"
_GREEN  = "\033[32m"
_YELLOW = "\033[33m"
_BLUE   = "\033[34m"
_CYAN   = "\033[36m"
_RESET  = "\033[0m"
_INVERT = "\033[7m"   # 反色，用于方向键选中高亮
_RECOMMENDED_PREFIX = "★ "
_COL_HINT_INDENT = " " * 4  # 补偿 "   N) " (6列) 与 "  " (2列) 之间的 4 列差值


def _c(code: str, text: str) -> str:
    """包裹 ANSI 颜色，仅在 TTY 下生效（非 TTY 返回纯文本）。"""
    if not sys.stdout.isatty():
        return text
    return f"{code}{text}{_RESET}"


def _char_width(ch: str) -> int:
    """按终端显示宽度估算单字符列数。"""
    width = wcwidth(ch) if ch else 0
    return width if width > 0 else 0


def _display_width(text: str) -> int:
    """计算字符串在终端中的显示宽度。"""
    width = wcswidth(text)
    if width >= 0:
        return width
    return sum(_char_width(ch) for ch in text)


def _pad_display(text: str, width: int, *, align: str = "left") -> str:
    """按显示宽度补空格。"""
    pad = max(width - _display_width(text), 0)
    if align == "right":
        return (" " * pad) + text
    return text + (" " * pad)


def _truncate_display(text: str, width: int) -> str:
    """按显示宽度截断字符串，并在必要时补省略号。"""
    if width <= 0:
        return ""
    if _display_width(text) <= width:
        return text
    if width == 1:
        return "…"

    out: list[str] = []
    current = 0
    limit = width - 1
    for ch in text:
        ch_w = _char_width(ch)
        if current + ch_w > limit:
            break
        out.append(ch)
        current += ch_w
    return "".join(out) + "…"


def _wrap_display(text: str, width: int) -> list[str]:
    """按显示宽度手动折行，避免依赖终端自动换行。"""
    if width <= 0:
        return [text]

    lines: list[str] = []
    current: list[str] = []
    current_width = 0

    for ch in text:
        if ch == "\n":
            lines.append("".join(current))
            current = []
            current_width = 0
            continue

        ch_w = _char_width(ch)
        if current and current_width + ch_w > width:
            lines.append("".join(current))
            current = [ch]
            current_width = ch_w
        else:
            current.append(ch)
            current_width += ch_w

    lines.append("".join(current))
    return lines


def _short_size(size_bytes: int) -> str:
    """把字节数缩写成人类可读形式。"""
    if size_bytes <= 0:
        return "─"

    units = ("B", "K", "M", "G", "T")
    size = float(size_bytes)
    unit_idx = 0
    while size >= 1024 and unit_idx < len(units) - 1:
        size /= 1024
        unit_idx += 1

    if unit_idx == 0:
        return f"{int(size)}{units[unit_idx]}"
    return f"{size:.1f}{units[unit_idx]}"


def _split_recommended(label: str) -> tuple[bool, str]:
    """拆分推荐标记，避免把宽字符混进列内容。"""
    if label.startswith(_RECOMMENDED_PREFIX):
        return True, label[len(_RECOMMENDED_PREFIX):]
    return False, label


def _positive_int_env(*names: str) -> int | None:
    """读取第一个有效的正整数环境变量。"""
    for name in names:
        raw = os.environ.get(name, "").strip()
        if not raw:
            continue
        try:
            value = int(raw)
        except ValueError:
            continue
        if value > 0:
            return value
    return None


def _tty_path_env(*names: str) -> str | None:
    """读取第一个有效的终端设备路径环境变量。"""
    for name in names:
        path = os.environ.get(name, "").strip()
        if path.startswith("/dev/"):
            return path
    return None


def _load_darwin_proc_libs():
    """按需加载 Darwin 进程探测依赖。"""
    import ctypes
    import ctypes.util

    libproc_path = ctypes.util.find_library("proc")
    libc_path = ctypes.util.find_library("c")
    if not libproc_path or not libc_path:
        return None

    try:
        libproc = ctypes.CDLL(libproc_path, use_errno=True)
        libc = ctypes.CDLL(libc_path, use_errno=True)
    except OSError:
        return None

    return ctypes, libproc, libc


def _darwin_proc_bsdinfo(pid: int) -> tuple[int, int] | None:
    """返回 Darwin 进程的 (ppid, controlling_tty_dev)。"""
    libs = _load_darwin_proc_libs()
    if libs is None:
        return None

    ctypes, libproc, _ = libs
    maxcomlen = 16
    proc_pidtbdsinfo = 3

    class ProcBsdInfo(ctypes.Structure):
        _fields_ = [
            ("pbi_flags", ctypes.c_uint32),
            ("pbi_status", ctypes.c_uint32),
            ("pbi_xstatus", ctypes.c_uint32),
            ("pbi_pid", ctypes.c_uint32),
            ("pbi_ppid", ctypes.c_uint32),
            ("pbi_uid", ctypes.c_uint32),
            ("pbi_gid", ctypes.c_uint32),
            ("pbi_ruid", ctypes.c_uint32),
            ("pbi_rgid", ctypes.c_uint32),
            ("pbi_svuid", ctypes.c_uint32),
            ("pbi_svgid", ctypes.c_uint32),
            ("rfu_1", ctypes.c_uint32),
            ("pbi_comm", ctypes.c_char * maxcomlen),
            ("pbi_name", ctypes.c_char * (2 * maxcomlen)),
            ("pbi_nfiles", ctypes.c_uint32),
            ("pbi_pgid", ctypes.c_uint32),
            ("pbi_pjobc", ctypes.c_uint32),
            ("e_tdev", ctypes.c_uint32),
            ("e_tpgid", ctypes.c_uint32),
            ("pbi_nice", ctypes.c_int32),
            ("pbi_start_tvsec", ctypes.c_uint64),
            ("pbi_start_tvusec", ctypes.c_uint64),
        ]

    libproc.proc_pidinfo.argtypes = [
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_uint64,
        ctypes.c_void_p,
        ctypes.c_int,
    ]
    libproc.proc_pidinfo.restype = ctypes.c_int

    info = ProcBsdInfo()
    result = libproc.proc_pidinfo(
        pid,
        proc_pidtbdsinfo,
        0,
        ctypes.byref(info),
        ctypes.sizeof(info),
    )
    if result != ctypes.sizeof(info):
        return None

    return int(info.pbi_ppid), int(info.e_tdev)


def _darwin_tty_path_for_device(device_id: int) -> str | None:
    """把 Darwin 的 tty 设备号映射到 `/dev/...` 路径。"""
    if device_id <= 0 or device_id == 0xFFFFFFFF:
        return None

    libs = _load_darwin_proc_libs()
    if libs is None:
        return None

    ctypes, _, libc = libs
    libc.devname_r.argtypes = [ctypes.c_uint32, ctypes.c_ushort, ctypes.c_char_p, ctypes.c_int]
    libc.devname_r.restype = ctypes.c_char_p

    buf = ctypes.create_string_buffer(1024)
    result = libc.devname_r(device_id, stat.S_IFCHR, buf, ctypes.sizeof(buf))
    if not result:
        return None

    name = buf.value.decode(errors="ignore").strip()
    if not name:
        return None

    return name if name.startswith("/dev/") else f"/dev/{name}"


def _darwin_parent_tty_paths() -> list[str]:
    """沿父进程链收集可能对应真实终端的 tty 设备路径。"""
    candidates: list[str] = []
    seen_pids: set[int] = set()
    seen_paths: set[str] = set()
    pid = os.getppid()

    while pid > 1 and pid not in seen_pids:
        seen_pids.add(pid)
        info = _darwin_proc_bsdinfo(pid)
        if info is None:
            break

        ppid, tty_device = info
        tty_path = _darwin_tty_path_for_device(tty_device)
        if tty_path and tty_path not in seen_paths:
            seen_paths.add(tty_path)
            candidates.append(tty_path)
        pid = ppid

    return candidates


def _darwin_parent_fd_tty_paths() -> list[str]:
    """从祖先进程打开的 vnode fd 中收集 tty 设备路径。"""
    libs = _load_darwin_proc_libs()
    if libs is None:
        return []

    ctypes, libproc, _ = libs
    proc_pidlistfds = 1
    proc_pidfdvnodepathinfo = 2
    prox_fdtype_vnode = 1
    maxpathlen = 1024

    class ProcFdInfo(ctypes.Structure):
        _fields_ = [
            ("proc_fd", ctypes.c_int32),
            ("proc_fdtype", ctypes.c_uint32),
        ]

    class VinfoStat(ctypes.Structure):
        _fields_ = [
            ("vst_dev", ctypes.c_uint32),
            ("vst_mode", ctypes.c_uint16),
            ("vst_nlink", ctypes.c_uint16),
            ("vst_ino", ctypes.c_uint64),
            ("vst_uid", ctypes.c_uint32),
            ("vst_gid", ctypes.c_uint32),
            ("vst_atime", ctypes.c_int64),
            ("vst_atimensec", ctypes.c_int64),
            ("vst_mtime", ctypes.c_int64),
            ("vst_mtimensec", ctypes.c_int64),
            ("vst_ctime", ctypes.c_int64),
            ("vst_ctimensec", ctypes.c_int64),
            ("vst_birthtime", ctypes.c_int64),
            ("vst_birthtimensec", ctypes.c_int64),
            ("vst_size", ctypes.c_int64),
            ("vst_blocks", ctypes.c_int64),
            ("vst_blksize", ctypes.c_int32),
            ("vst_flags", ctypes.c_uint32),
            ("vst_gen", ctypes.c_uint32),
            ("vst_rdev", ctypes.c_uint32),
            ("vst_qspare", ctypes.c_int64 * 2),
        ]

    class Fsid(ctypes.Structure):
        _fields_ = [("val", ctypes.c_int32 * 2)]

    class VnodeInfo(ctypes.Structure):
        _fields_ = [
            ("vi_stat", VinfoStat),
            ("vi_type", ctypes.c_int),
            ("vi_pad", ctypes.c_int),
            ("vi_fsid", Fsid),
        ]

    class VnodeInfoPath(ctypes.Structure):
        _fields_ = [
            ("vip_vi", VnodeInfo),
            ("vip_path", ctypes.c_char * maxpathlen),
        ]

    class ProcFileInfo(ctypes.Structure):
        _fields_ = [
            ("fi_openflags", ctypes.c_uint32),
            ("fi_status", ctypes.c_uint32),
            ("fi_offset", ctypes.c_int64),
            ("fi_type", ctypes.c_int32),
            ("fi_guardflags", ctypes.c_uint32),
        ]

    class VnodeFdInfoWithPath(ctypes.Structure):
        _fields_ = [
            ("pfi", ProcFileInfo),
            ("pvip", VnodeInfoPath),
        ]

    libproc.proc_pidinfo.argtypes = [
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_uint64,
        ctypes.c_void_p,
        ctypes.c_int,
    ]
    libproc.proc_pidinfo.restype = ctypes.c_int
    libproc.proc_pidfdinfo.argtypes = [
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_void_p,
        ctypes.c_int,
    ]
    libproc.proc_pidfdinfo.restype = ctypes.c_int

    candidates: list[str] = []
    seen_pids: set[int] = set()
    seen_paths: set[str] = set()
    pid = os.getppid()

    while pid > 1 and pid not in seen_pids:
        seen_pids.add(pid)
        info = _darwin_proc_bsdinfo(pid)
        if info is None:
            break

        ppid, _ = info
        fd_capacity = 256
        fd_buf = (ProcFdInfo * fd_capacity)()
        result = libproc.proc_pidinfo(
            pid,
            proc_pidlistfds,
            0,
            ctypes.byref(fd_buf),
            ctypes.sizeof(fd_buf),
        )
        if result > 0:
            fd_count = result // ctypes.sizeof(ProcFdInfo)
            for fd_info in fd_buf[:fd_count]:
                if fd_info.proc_fdtype != prox_fdtype_vnode:
                    continue

                vnode_info = VnodeFdInfoWithPath()
                vnode_result = libproc.proc_pidfdinfo(
                    pid,
                    fd_info.proc_fd,
                    proc_pidfdvnodepathinfo,
                    ctypes.byref(vnode_info),
                    ctypes.sizeof(vnode_info),
                )
                if vnode_result <= 0:
                    continue

                path = bytes(vnode_info.pvip.vip_path).split(b"\0")[0].decode(errors="ignore").strip()
                if not path.startswith("/dev/tty") and not path.startswith("/dev/ttys"):
                    continue
                if path in seen_paths:
                    continue

                seen_paths.add(path)
                candidates.append(path)

        pid = ppid

    return candidates


def _darwin_parent_terminal_size() -> tuple[int, int] | None:
    """Darwin: 从祖先进程关联的 tty 设备读取实时窗口尺寸。"""
    for path in dict.fromkeys(_darwin_parent_tty_paths() + _darwin_parent_fd_tty_paths()):
        size = _ioctl_terminal_size_for_path(path)
        if size is not None:
            return size

    return None


def _ioctl_terminal_size() -> tuple[int, int] | None:
    """直接向已绑定终端的标准流查询窗口尺寸。"""
    import fcntl
    import struct
    import termios

    for stream in (sys.__stdout__, sys.__stderr__, sys.__stdin__, sys.stdout, sys.stderr, sys.stdin):
        if stream is None:
            continue

        try:
            fd = stream.fileno()
        except (AttributeError, OSError, ValueError):
            continue

        try:
            rows, cols, _, _ = struct.unpack(
                "HHHH",
                fcntl.ioctl(fd, termios.TIOCGWINSZ, struct.pack("HHHH", 0, 0, 0, 0)),
            )
        except OSError:
            continue

        if cols > 0 and rows > 0:
            return cols, rows

    return None


def _ioctl_terminal_size_for_path(path: str) -> tuple[int, int] | None:
    """直接对指定终端设备路径做 TIOCGWINSZ。"""
    import fcntl
    import struct
    import termios

    try:
        fd = os.open(path, os.O_RDONLY)
    except OSError:
        return None

    try:
        rows, cols, _, _ = struct.unpack(
            "HHHH",
            fcntl.ioctl(fd, termios.TIOCGWINSZ, struct.pack("HHHH", 0, 0, 0, 0)),
        )
    except OSError:
        return None
    finally:
        os.close(fd)

    if cols > 0 and rows > 0:
        return cols, rows
    return None


def _stty_terminal_size(path: str) -> tuple[int, int] | None:
    """在已知 tty 设备路径上尝试用 `stty size` 取窗口尺寸。"""
    import subprocess

    try:
        with open(path, "rb", buffering=0) as tty_stream:
            result = subprocess.run(
                ["stty", "size"],
                stdin=tty_stream,
                capture_output=True,
                text=True,
                check=False,
            )
    except (FileNotFoundError, OSError, PermissionError):
        return None

    if result.returncode != 0:
        return None

    parts = result.stdout.strip().split()
    if len(parts) != 2:
        return None

    try:
        rows, cols = (int(part) for part in parts)
    except ValueError:
        return None

    if cols > 0 and rows > 0:
        return cols, rows
    return None


def _tput_terminal_columns(path: str) -> int | None:
    """在已知 tty 设备路径上尝试用 `tput cols` 取列宽。"""
    import subprocess

    try:
        with open(path, "rb", buffering=0) as tty_stream:
            result = subprocess.run(
                ["tput", "cols"],
                stdin=tty_stream,
                capture_output=True,
                text=True,
                check=False,
                env=os.environ,
            )
    except (FileNotFoundError, OSError, PermissionError):
        return None

    if result.returncode != 0:
        return None

    try:
        cols = int(result.stdout.strip())
    except ValueError:
        return None

    return cols if cols > 0 else None


def _fallback_terminal_size() -> os.terminal_size:
    """最后回退到 Python 自带探测，不在仓库里硬编码宽高常量。"""
    import shutil

    fallback = shutil.get_terminal_size()
    cols = fallback.columns if fallback.columns > 0 else 1
    rows = fallback.lines if fallback.lines > 0 else 1
    return os.terminal_size((cols, rows))


def _terminal_size(default: tuple[int, int] | None = None) -> os.terminal_size:
    """尽量读取真实终端宽高，允许显式环境覆盖，并在 Darwin 上追溯祖先进程 tty。

    Claude Code 这类无控制 TTY 的子进程里，当前进程的 ioctl、`/dev/tty` 和裸 `tput`
    往往失效。这里按以下顺序取值：
    1. 显式环境覆盖 `YT_TOOL_TERM_*` / `COLUMNS` / `LINES`
    2. 外层 wrapper 导出的真实 tty 路径 `YT_TOOL_TERM_TTY` / `TTY`
    3. 当前进程已绑定标准流的 ioctl
    4. Darwin 父进程链上的真实 tty 设备 ioctl
    5. Darwin 已定位 tty 设备上的 `stty size`
    6. Darwin 已定位 tty 设备上的 `tput cols`
    7. Python 自带终端探测回退
    """
    env_cols = _positive_int_env("YT_TOOL_TERM_COLUMNS", "COLUMNS")
    env_rows = _positive_int_env("YT_TOOL_TERM_LINES", "LINES")
    if env_cols is not None and env_rows is not None:
        return os.terminal_size((env_cols, env_rows))

    env_tty_path = _tty_path_env("YT_TOOL_TERM_TTY", "TTY")
    if env_tty_path is not None:
        tty_size = _ioctl_terminal_size_for_path(env_tty_path)
        if tty_size is not None:
            cols, rows = tty_size
            return os.terminal_size((env_cols or cols, env_rows or rows))

    ioctl_size = _ioctl_terminal_size()
    if ioctl_size is not None:
        cols, rows = ioctl_size
        return os.terminal_size((env_cols or cols, env_rows or rows))

    darwin_paths: list[str] = []
    if platform.system() == "Darwin":
        darwin_paths = list(dict.fromkeys(_darwin_parent_tty_paths() + _darwin_parent_fd_tty_paths()))
        for path in darwin_paths:
            size = _ioctl_terminal_size_for_path(path)
            if size is not None:
                cols, rows = size
                return os.terminal_size((env_cols or cols, env_rows or rows))

        for path in darwin_paths:
            size = _stty_terminal_size(path)
            if size is not None:
                cols, rows = size
                return os.terminal_size((env_cols or cols, env_rows or rows))

        for path in darwin_paths:
            cols = _tput_terminal_columns(path)
            if cols is not None:
                fallback = _fallback_terminal_size()
                return os.terminal_size((env_cols or cols, env_rows or fallback.lines))

    fallback = _fallback_terminal_size()
    if default is not None:
        fallback = os.terminal_size((
            fallback.columns if fallback.columns > 0 else default[0],
            fallback.lines if fallback.lines > 0 else default[1],
        ))

    return os.terminal_size((env_cols or fallback.columns, env_rows or fallback.lines))


# ---- 方向键菜单（macOS / Linux，stdlib only）----

def _menu_arrow(
    prompt: str,
    labels: list[str],
    values: list[str],
    column_hint: str | None = None,
) -> str | None:
    """用 ↑/↓/Enter 选择的交互菜单（仅 Unix TTY）。返回选中 value 或 None（跳过）。"""
    import termios
    import tty

    term_size = _terminal_size()
    term_cols, term_rows = term_size.columns, term_size.lines

    items = ["跳过"] + labels
    idx = 1  # 默认选第一个真实选项（跳过排在 0）
    title_lines = [_c(_BOLD + _BLUE, f"── {prompt} ──")]
    hint_lines = (
        [_c(_DIM, line) for line in _wrap_display(f"  {column_hint}", term_cols)]
        if column_hint else []
    )
    tip_lines = [_c(_DIM, line) for line in _wrap_display("  ↑↓ 移动  Enter 确认  0/q 跳过", term_cols)]

    label_width = max(term_cols - 9, 12)
    rendered_items: list[tuple[bool, str]] = []
    for item in items:
        if item == "跳过":
            rendered_items.append((False, item))
            continue
        recommended, text = _split_recommended(item)
        rendered_items.append((recommended, _truncate_display(text, label_width)))

    total_lines = len(title_lines) + len(hint_lines) + len(rendered_items) + len(tip_lines)
    if total_lines + 1 > term_rows:
        return _menu_numeric(prompt, labels, values, column_hint=column_hint)

    def _prefix(recommended: bool) -> str:
        return _c(_GREEN, "★ ") if recommended else "   "

    def _render(current: int, *, rewind: bool) -> None:
        if rewind:
            sys.stdout.write(f"\033[{total_lines}A\033[J")
        for line in title_lines:
            sys.stdout.write(line + "\n")
        for line in hint_lines:
            sys.stdout.write(line + "\n")
        for i, (recommended, item_text) in enumerate(rendered_items):
            prefix = _prefix(recommended)
            if i == current:
                sys.stdout.write(f"{prefix}{_INVERT} {i}) {item_text} {_RESET}\n")
            elif i == 0:
                sys.stdout.write(_c(_DIM, f"   0) {item_text}") + "\n")
            else:
                sys.stdout.write(f"{prefix}{_c(_BOLD, str(i))}) {item_text}\n")
        for line in tip_lines:
            sys.stdout.write(line + "\n")
        sys.stdout.flush()

    sys.stdout.write("\n")
    _render(idx, rewind=False)
    sys.stdout.flush()

    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    try:
        tty.setraw(fd)
        while True:
            ch = sys.stdin.read(1)
            if ch == "\r" or ch == "\n":
                break
            if ch == "0" or ch in ("q", "Q"):
                idx = 0
                break
            if ch == "\x1b":
                seq = sys.stdin.read(2)
                if seq == "[A" and idx > 0:      # 上
                    idx -= 1
                elif seq == "[B" and idx < len(items) - 1:  # 下
                    idx += 1
            elif ch == "\x03":  # Ctrl-C
                raise KeyboardInterrupt
            _render(idx, rewind=True)
    finally:
        termios.tcsetattr(fd, termios.TCSADRAIN, old)

    sys.stdout.write("\n")
    return None if idx == 0 else values[idx - 1]


def _should_use_arrow_menu(
    labels: list[str],
    column_hint: str | None,
) -> bool:
    """仅在布局足够简单时启用方向键菜单。

    终端软换行、宽字符和复杂列头会让重绘高度难以稳定计算。
    对带列头的表格菜单，直接降级为数字菜单更稳。
    """
    if column_hint:
        return False

    term_cols = _terminal_size().columns
    safe_width = max(term_cols - 12, 20)

    for label in labels:
        _, text = _split_recommended(label)
        if _display_width(text) > safe_width:
            return False

    return True


# ---- 通用菜单（数字输入，带 ANSI 颜色）----

def _menu_numeric(
    prompt: str,
    labels: list[str],
    values: list[str],
    column_hint: str | None = None,
) -> str | None:
    """数字输入菜单，支持 ANSI 颜色。"""
    print(_c(_BOLD + _BLUE, f"\n── {prompt} ──"))
    if column_hint:
        term_cols = _terminal_size().columns
        for line in _wrap_display(f"  {column_hint}", term_cols):
            print(_c(_DIM, line))

    for i, label in enumerate(labels, 1):
        recommended, text = _split_recommended(label)
        if recommended:
            print(f"{_c(_GREEN, '★ ')}{_c(_BOLD, str(i))}) {_c(_GREEN, text)}")
        else:
            print(f"   {_c(_BOLD, str(i))}) {text}")
    print(_c(_DIM, "  0) 跳过"))
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
        print(_c(_YELLOW, "  无效输入，请重试"))


# ---- 通用菜单（对外接口）----

def menu_select(
    prompt: str,
    labels: list[str],
    values: list[str],
    column_hint: str | None = None,
) -> str | None:
    """展示菜单，返回用户选中的 value；跳过返回 None。

    在支持 tty 的 Unix 终端中使用方向键交互，否则降级为数字输入。
    column_hint: 在选项列表前显示的列头说明（可选）。
    """
    if len(labels) != len(values):
        raise ValueError("labels and values length mismatch")

    if not labels:
        print(_c(_DIM, f"\n── {prompt} ──"))
        print(_c(_DIM, "  没有可选项，跳过"))
        return None

    # 尝试方向键模式（仅 Unix TTY，且菜单足够简单）
    if sys.stdin.isatty() and sys.stdout.isatty() and _should_use_arrow_menu(labels, column_hint):
        try:
            import termios  # noqa: F401
            import tty  # noqa: F401
            return _menu_arrow(prompt, labels, values, column_hint=column_hint)
        except (ImportError, Exception):
            pass

    return _menu_numeric(prompt, labels, values, column_hint=column_hint)


# ---- 菜单数据构造 ----

def _short_vcodec(codec: str) -> str:
    """将 yt-dlp 原始 vcodec 字符串缩写为可读名称。"""
    c = codec.lower()
    if c.startswith("avc1") or c.startswith("h264"):
        return "H.264"
    if c.startswith("vp09") or c == "vp9":
        return "VP9"
    if c.startswith("av01"):
        return "AV1"
    if c.startswith("hvc1") or c.startswith("hev1") or c.startswith("h265"):
        return "H.265"
    if c.startswith("mp4v"):
        return "MPEG4"
    return codec[:6]


def _short_acodec(codec: str) -> str:
    """将 yt-dlp 原始 acodec 字符串缩写为可读名称。"""
    c = codec.lower()
    if c.startswith("mp4a"):
        return "AAC"
    if c == "opus":
        return "Opus"
    if c.startswith("mp3") or c == "mp3":
        return "MP3"
    if c.startswith("vorbis"):
        return "Vorbis"
    if c.startswith("flac"):
        return "FLAC"
    return codec[:6]


def build_video_labels(formats: tuple[VideoFormat, ...]) -> tuple[list[str], list[str]]:
    """从 VideoFormat 列表构造菜单 (labels, values)，第一项标记为推荐。

    固定列宽格式：ID  容器  分辨率  帧率  码率  体积  HDR  编码  类型
    """
    labels: list[str] = []
    values: list[str] = []
    for i, f in enumerate(formats):
        codec = _short_vcodec(f.codec)
        height = f"{f.height}p" if f.height else "─"
        fps = f"{f.fps}fps" if f.fps else "─"
        tbr = f"{f.tbr:.0f}k" if f.tbr else "─"
        size = _short_size(f.filesize_approx)
        hdr = f.dynamic_range or "─"
        parts = (
            _pad_display(f.id, 11, align="right"),
            _pad_display(f.ext, 5),
            _pad_display(height, 7, align="right"),
            _pad_display(fps, 6, align="right"),
            _pad_display(tbr, 7, align="right"),
            _pad_display(size, 7, align="right"),
            _pad_display(hdr, 5),
            _pad_display(codec, 6),
            f.note,
        )
        label = "  ".join(parts)
        if i == 0:
            label = f"{_RECOMMENDED_PREFIX}{label}"
        labels.append(label)
        values.append(f.id)
    return labels, values


def build_audio_labels(formats: tuple[AudioFormat, ...]) -> tuple[list[str], list[str]]:
    """从 AudioFormat 列表构造菜单 (labels, values)，第一项标记为推荐。

    固定列宽格式：ID  编码  码率  声道  体积  格式
    """
    labels: list[str] = []
    values: list[str] = []
    for i, f in enumerate(formats):
        codec = _short_acodec(f.codec)
        abr = f"{f.abr:.0f}k" if f.abr else "─"
        channels = f"{f.audio_channels}ch" if f.audio_channels else "─"
        size = _short_size(f.filesize_approx)
        label = "  ".join((
            _pad_display(f.id, 11, align="right"),
            _pad_display(codec, 6),
            _pad_display(abr, 6, align="right"),
            _pad_display(channels, 5, align="right"),
            _pad_display(size, 7, align="right"),
            _pad_display(f.ext, 5),
        ))
        if f.note:
            label += f"  {f.note}"
        if i == 0:
            label = f"{_RECOMMENDED_PREFIX}{label}"
        labels.append(label)
        values.append(f.id)
    return labels, values


def build_video_header() -> str:
    """生成与 build_video_labels 完全对齐的列头字符串，用作 column_hint。"""
    parts = (
        _pad_display("ID",    11, align="right"),
        _pad_display("容器",   5),
        _pad_display("分辨率", 7, align="right"),
        _pad_display("帧率",   6, align="right"),
        _pad_display("码率",   7, align="right"),
        _pad_display("体积",   7, align="right"),
        _pad_display("HDR",    5),
        _pad_display("编码",   6),
        "类型",
    )
    return _COL_HINT_INDENT + "  ".join(parts)


def build_audio_header() -> str:
    """生成与 build_audio_labels 完全对齐的列头字符串，用作 column_hint。"""
    parts = (
        _pad_display("ID",   11, align="right"),
        _pad_display("编码",  6),
        _pad_display("码率",  6, align="right"),
        _pad_display("声道",  5, align="right"),
        _pad_display("体积",  7, align="right"),
        _pad_display("格式",  5),
    )
    return _COL_HINT_INDENT + "  ".join(parts)


def build_sub_labels(
    tracks: tuple[SubtitleTrack, ...],
    auto_tracks: tuple[SubtitleTrack, ...] = (),
) -> tuple[list[str], list[str]]:
    """从 SubtitleTrack 列表构造菜单 (labels, values)。

    auto_tracks 中的条目标记 [自动]，值加 auto: 前缀以便调用方区分。
    """
    labels: list[str] = []
    values: list[str] = []
    for t in tracks:
        label = f"{t.lang}  {t.label}"
        if t.is_live_chat:
            label += "  [live_chat/JSON]"
        labels.append(label)
        values.append(t.lang)
    for t in auto_tracks:
        label = f"{t.lang}  {t.label}  [自动]"
        if t.is_live_chat:
            label += "  [live_chat/JSON]"
        labels.append(label)
        values.append(f"auto:{t.lang}")
    return labels, values


# ---- Playlist 询问 ----

def ask_playlist_mode(playlist_title: str, count: int) -> str | None:
    """检测到播放列表时，询问下载范围。

    返回 "first"（仅首条）/ "all_video"（全部视频）/ "all_audio"（全部音频）/ None（退出）。
    """
    print(_c(_BOLD + _BLUE, "\n── 检测到播放列表 ──"))
    print(f"  列表名: {_c(_CYAN, playlist_title)}")
    print(f"  共 {_c(_GREEN, str(count))} 条")
    print()
    print(f"  {_c(_BOLD, '1')}) 仅下载首条（手动选格式）")
    print(f"  {_c(_BOLD, '2')}) 下载全部 — 视频（自动最佳画质）")
    print(f"  {_c(_BOLD, '3')}) 下载全部 — 仅音频（自动最佳音质）")
    print(_c(_DIM, "  0) 退出"))
    print()

    mapping = {"1": "first", "2": "all_video", "3": "all_audio"}
    while True:
        raw = input("选择 [0-3]: ").strip()
        if raw == "0":
            return None
        if raw in mapping:
            return mapping[raw]
        print(_c(_YELLOW, "  无效输入，请重试"))


# ---- 下载类型选择 ----

def ask_download_type() -> str | None:
    """让用户选择下载类型，循环直到合法输入。

    返回 "video" / "audio" / "subs" / "all"；输入 0 退出返回 None。
    """
    print(_c(_BOLD + _BLUE, "\n── 下载什么? ──"))
    print(f"  {_c(_BOLD, '1')}) 视频 (视频+音频合并)")
    print(f"  {_c(_BOLD, '2')}) 仅音频")
    print(f"  {_c(_BOLD, '3')}) 仅字幕")
    print(f"  {_c(_BOLD, '4')}) 全部 (视频+字幕)")
    print(_c(_DIM, "  0) 退出"))
    print()

    mapping = {"1": "video", "2": "audio", "3": "subs", "4": "all"}
    while True:
        raw = input("选择 [0-4]: ").strip()
        if raw == "0":
            return None
        if raw in mapping:
            return mapping[raw]
        print(_c(_YELLOW, "  无效输入，请重试"))


# ---- 高级参数询问 ----

def ask_cookie_browser() -> str | None:
    """询问是否使用浏览器 Cookie，返回浏览器名或 None（不使用）。"""
    print(_c(_BOLD + _BLUE, "\n── Cookie 登录（可选）──"))
    print(_c(_DIM, "  用于下载需要登录的内容（YouTube Premium、私人视频等）"))
    print(f"  {_c(_BOLD, '1')}) Chrome")
    print(f"  {_c(_BOLD, '2')}) Firefox")
    is_macos = config.IS_MAC
    if is_macos:
        print(f"  {_c(_BOLD, '3')}) Safari")
    print(f"  {_c(_BOLD, '4')}) Edge")
    print(_c(_DIM, "  0) 不使用 Cookie"))
    print()

    mapping: dict[str, str] = {"1": "chrome", "2": "firefox", "4": "edge"}
    if is_macos:
        mapping["3"] = "safari"
    valid_range = "0-4" if is_macos else "0-2, 4"
    while True:
        raw = input(f"选择 [{valid_range}]: ").strip()
        if raw == "0":
            return None
        if raw in mapping:
            return mapping[raw]
        print(_c(_YELLOW, "  无效输入，请重试"))


def ask_audio_transcode(has_ffmpeg: bool = True) -> str | None:
    """询问音频转码目标格式，返回格式名或 None（保持原始）。

    has_ffmpeg: ffmpeg 是否可用；为 False 时转码不可用，直接返回 None。
    """
    print(_c(_BOLD + _BLUE, "\n── 音频转码（可选）──"))
    if not has_ffmpeg:
        print(_c(_DIM, "  ffmpeg 未安装，转码不可用，将保持原始格式"))
        return None

    print(f"  {_c(_BOLD, '1')}) 保持原始格式")
    print(f"  {_c(_BOLD, '2')}) MP3")
    print(f"  {_c(_BOLD, '3')}) AAC")
    print(f"  {_c(_BOLD, '4')}) OPUS")
    print(f"  {_c(_BOLD, '5')}) M4A")
    print()

    mapping: dict[str, str | None] = {"1": None, "2": "mp3", "3": "aac", "4": "opus", "5": "m4a"}
    while True:
        raw = input("选择 [1-5]: ").strip()
        if raw in mapping:
            return mapping[raw]
        print(_c(_YELLOW, "  无效输入，请重试"))


def ask_download_sections() -> str | None:
    """询问是否仅下载片段，返回 yt-dlp --download-sections 表达式或 None。"""
    print(_c(_BOLD + _BLUE, "\n── 片段下载（可选）──"))
    print(_c(_DIM, "  回车跳过；可输入时间段或章节名/正则"))
    print(_c(_DIM, "  例1: *10:15-20:30"))
    print(_c(_DIM, "  例2: intro"))
    print(_c(_DIM, "  例3: *from-url"))
    raw = input("片段表达式: ").strip()
    return raw or None


def ask_sponsorblock_mode(has_ffmpeg: bool = True) -> str | None:
    """询问 SponsorBlock 模式，返回 None / mark / remove。

    has_ffmpeg: ffmpeg 是否可用；为 False 时隐藏"移除片段"选项（需要 ffmpeg）。
    """
    print(_c(_BOLD + _BLUE, "\n── SponsorBlock（可选）──"))
    print(_c(_DIM, "  适用于支持 SponsorBlock 的站点，如 YouTube"))
    print(f"  {_c(_BOLD, '1')}) 不使用")
    print(f"  {_c(_BOLD, '2')}) 标记章节")
    if has_ffmpeg:
        print(f"  {_c(_BOLD, '3')}) 直接移除片段")
    else:
        print(_c(_DIM, "  3) 直接移除片段（需要 ffmpeg，当前不可用）"))
    print()

    mapping: dict[str, str | None] = {"1": None, "2": "mark"}
    valid_range = "1-3"
    if has_ffmpeg:
        mapping["3"] = "remove"
    while True:
        raw = input(f"选择 [{valid_range}]: ").strip()
        if raw in mapping:
            return mapping[raw]
        print(_c(_YELLOW, "  无效输入，请重试"))


def ask_sponsorblock_categories(default_categories: tuple[str, ...]) -> str | None:
    """询问 SponsorBlock 类别，返回逗号分隔字符串；回车使用默认值。"""
    print(_c(_BOLD + _BLUE, "\n── SponsorBlock 类别（可选）──"))
    print(_c(_DIM, f"  直接回车使用默认: {','.join(default_categories)}"))
    print(_c(_DIM, "  也可手动输入逗号分隔类别，如 sponsor,intro,outro"))
    raw = input("类别: ").strip()
    if not raw:
        return ",".join(default_categories)
    return raw


def ask_embed_subs(sub_labels: list[str], sub_values: list[str]) -> str | None:
    """询问是否将字幕嵌入视频，返回选中的语言代码或 None（不嵌入）。"""
    if not sub_labels:
        return None
    print(_c(_BOLD + _BLUE, "\n── 嵌入字幕（可选，需 ffmpeg）──"))
    print(_c(_DIM, "  字幕将直接嵌入视频文件，不单独保存"))
    return menu_select("选择要嵌入的字幕语言（0 跳过）", sub_labels, sub_values)


# ---- 路径确认 ----

def ask_location(default_dir: str) -> str:
    """让用户确认或修改下载目录，返回最终路径字符串。"""
    print(_c(_BOLD + _BLUE, "\n── 下载位置 ──"))
    print(f"  当前: {_c(_CYAN, default_dir)}")
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
    print(f"\n{_c(_BOLD, '标题')}: {title}")
    sub_info = f"{sub_count} 个字幕"
    if auto_sub_count:
        sub_info += f" (另有 {auto_sub_count} 个自动字幕)"
    print(f"发现 {_c(_GREEN, str(video_count))} 个视频流, "
          f"{_c(_GREEN, str(audio_count))} 个音频流, {sub_info}")


def show_download_start(format_spec: str, dest: str) -> None:
    """展示下载开始信息。"""
    print(f"\n{_c(_BOLD, '开始下载')}: format={_c(_CYAN, format_spec)} → {_c(_CYAN, dest)}")


def show_download_ok(kind: str, output: str, saved_path: str = "") -> None:
    """展示下载成功信息。"""
    print(_c(_GREEN + _BOLD, f"✓ {kind}下载完成"))
    if saved_path:
        print(f"  已保存: {_c(_CYAN, saved_path)}")
    elif output.strip():
        print(output.strip())


def show_download_fail(kind: str, error: str) -> None:
    """展示下载失败信息。"""
    print(_c(_YELLOW + _BOLD, f"✗ {kind}下载失败") + f": {error}")
