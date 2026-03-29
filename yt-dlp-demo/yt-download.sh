#!/bin/zsh
# ================================================================
# yt-download.sh — 非交互下载核心（库函数风格）
#
# 设计:
#   - yt-dlp 输出捕获到 YT_DL_OUTPUT，调用方决定是否展示
#   - 参数通过数组传递，保留空格等边界
#   - 配置驱动，不硬编码 yt-dlp 参数
#   - 通过 source 加载，调用方负责先加载 config + lib
#
# 函数职责说明:
#   yt_dl_video — 下载用户选定的视频流（含合并音频）
#   yt_dl_audio — 下载用户选定的音频流（原始格式，不执行转码）
#   yt_dl_subs  — 下载用户选定语言的字幕
# ================================================================

typeset -g YT_DL_ERROR=""
typeset -g YT_DL_OUTPUT=""

# zsh 不支持 local -n，通过全局数组返回
typeset -ga _YT_COMMON_ARGS
_yt_build_common_args() {
  _YT_COMMON_ARGS=(--no-warnings)
  if [[ "$YT_SHOW_PROGRESS" != "true" ]]; then
    _YT_COMMON_ARGS+=(--no-progress)
  fi
}

_yt_exec() {
  local stderr_file
  stderr_file=$(mktemp) || { YT_DL_ERROR="mktemp failed"; return 1; }

  YT_DL_OUTPUT=$(yt-dlp "$@" 2>"$stderr_file")
  local rc=$?
  local stderr_out=$(<"$stderr_file")
  rm -f "$stderr_file"

  if (( rc != 0 )); then
    YT_DL_ERROR="yt-dlp failed (exit $rc): ${stderr_out:0:300}"
    return $rc
  fi
  return 0
}

# $1=URL $2=format_id $3=output_dir
# 返回: 0=成功 1=参数错误 2=路径错误 3=下载错误
yt_dl_video() {
  local url="$1" fmt="$2" dir="$3"
  YT_DL_ERROR="" YT_DL_OUTPUT=""

  if [[ -z "$url" || -z "$fmt" || -z "$dir" ]]; then
    YT_DL_ERROR="yt_dl_video requires: URL FORMAT_ID DIR"
    return 1
  fi

  dir=$(yt_expand_path "$dir")
  if ! yt_ensure_dir "$dir"; then
    YT_DL_ERROR="$YT_PATH_ERROR"
    return 2
  fi

  local -a args=()
  _yt_build_common_args; args+=("${_YT_COMMON_ARGS[@]}")
  args+=(-f "$fmt")
  args+=(--merge-output-format "${YT_PREFER_VIDEO_CONTAINER:-mp4}")
  args+=(-o "$dir/%(title)s.%(ext)s")
  args+=("$url")

  _yt_exec "${args[@]}" || { YT_DL_ERROR="video download: $YT_DL_ERROR"; return 3; }
  return 0
}

yt_dl_audio() {
  local url="$1" fmt="$2" dir="$3"
  YT_DL_ERROR="" YT_DL_OUTPUT=""

  if [[ -z "$url" || -z "$fmt" || -z "$dir" ]]; then
    YT_DL_ERROR="yt_dl_audio requires: URL FORMAT_ID DIR"
    return 1
  fi

  dir=$(yt_expand_path "$dir")
  if ! yt_ensure_dir "$dir"; then
    YT_DL_ERROR="$YT_PATH_ERROR"
    return 2
  fi

  local -a args=()
  _yt_build_common_args; args+=("${_YT_COMMON_ARGS[@]}")
  args+=(-f "$fmt")
  args+=(-o "$dir/%(title)s.%(ext)s")
  args+=("$url")

  _yt_exec "${args[@]}" || { YT_DL_ERROR="audio download: $YT_DL_ERROR"; return 3; }
  return 0
}

yt_dl_subs() {
  local url="$1" lang="$2" dir="$3"
  YT_DL_ERROR="" YT_DL_OUTPUT=""

  if [[ -z "$url" || -z "$lang" || -z "$dir" ]]; then
    YT_DL_ERROR="yt_dl_subs requires: URL LANG DIR"
    return 1
  fi

  dir=$(yt_expand_path "$dir")
  if ! yt_ensure_dir "$dir"; then
    YT_DL_ERROR="$YT_PATH_ERROR"
    return 2
  fi

  local -a args=()
  _yt_build_common_args; args+=("${_YT_COMMON_ARGS[@]}")
  args+=(--write-subs --sub-langs "$lang")
  args+=(--skip-download)
  args+=(--sub-format "best")
  # yt-dlp 会自动在文件名中插入语言码（如 title.zh-Hans.vtt）
  args+=(-o "$dir/%(title)s.%(ext)s")
  args+=("$url")

  _yt_exec "${args[@]}" || { YT_DL_ERROR="subtitle download: $YT_DL_ERROR"; return 3; }
  return 0
}
