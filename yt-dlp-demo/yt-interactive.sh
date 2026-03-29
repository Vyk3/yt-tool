#!/bin/zsh
# ================================================================
# yt-interactive.sh — 交互式入口
# 用法: zsh /tmp/yt-dlp-demo/yt-interactive.sh [URL]
#
# 职责: 用户交互（菜单、输入、展示）
# 原则: 工具函数展示走 stderr / 返回值走 stdout
#        入口层面向用户的状态信息走 stdout
# ================================================================

SCRIPT_DIR="${0:a:h}"
source "$SCRIPT_DIR/config/defaults.sh"
source "$SCRIPT_DIR/lib/path-validator.sh"
source "$SCRIPT_DIR/lib/format-detector.sh"
source "$SCRIPT_DIR/yt-download.sh"

# ---- 交互工具（展示走 stderr，返回值走 stdout）----

_yt_menu_select() {
  local prompt="$1"
  local -a labels=("${(@P)2}")
  local -a values=("${(@P)3}")
  local count=${#labels[@]}

  echo "" >&2
  echo "── $prompt ──" >&2

  if (( count == 0 )); then
    echo "  没有可选项，跳过" >&2
    return 1
  fi

  local i=1
  while (( i <= count )); do
    echo "  $i) ${labels[$i]}" >&2
    ((i++))
  done
  echo "  0) 跳过" >&2
  echo "" >&2

  local choice
  while true; do
    read -r "choice?选择 [0-$count]: "
    if [[ "$choice" == "0" ]]; then
      return 1
    elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= count )); then
      echo "${values[$choice]}"
      return 0
    fi
    echo "  无效输入，请重试" >&2
  done
}

_yt_ask_location() {
  local default_dir="$1"
  echo "" >&2
  echo "── 下载位置 ──" >&2
  echo "  当前: $default_dir" >&2
  read -r "change?修改位置? [直接回车保持/输入新路径]: "

  if [[ -n "$change" ]]; then
    local expanded
    expanded=$(yt_expand_path "$change")
    if yt_ensure_dir "$expanded"; then
      echo "$expanded"
    else
      echo "  路径无效 ($YT_PATH_ERROR)，使用默认位置" >&2
      echo "$default_dir"
    fi
  else
    echo "$default_dir"
  fi
}

# ---- 批量字段提取（字段名通过 argv 传递，无注入风险）----

# 用法: _yt_fields "json" "field1" "field2" ...
# stdout: 每个字段一行
_yt_fields() {
  local json="$1"
  shift
  python3 -c '
import json, sys
d = json.loads(sys.stdin.read())
for k in sys.argv[1:]:
    print(d.get(k, ""))
' "$@" <<< "$json"
}

# ---- 菜单数据构造（每条记录一次 python3）----

# 菜单构造函数通过约定的全局数组返回结果
# （zsh 不支持 local -n / nameref）
typeset -ga _YT_MENU_LABELS _YT_MENU_VALUES

_yt_build_video_menu() {
  _YT_MENU_LABELS=() _YT_MENU_VALUES=()

  local entry
  for entry in "${YT_FORMATS_VIDEO[@]}"; do
    local id height codec fps note label

    id=$(print -r -- "$entry" | _yt_field id)
    height=$(print -r -- "$entry" | _yt_field height)
    codec=$(print -r -- "$entry" | _yt_field codec)
    fps=$(print -r -- "$entry" | _yt_field fps)
    note=$(print -r -- "$entry" | _yt_field note)

    [[ -z "$id" ]] && continue

    if [[ -n "$height" && "$height" != "0" ]]; then
      label="${id}  ${height}p  ${codec}  ${fps}fps  ${note}"
    else
      label="${id}  ${codec}  ${fps}fps  ${note}"
    fi

    _YT_MENU_LABELS+=("$label")
    _YT_MENU_VALUES+=("$id")
  done
}

_yt_build_audio_menu() {
  _YT_MENU_LABELS=() _YT_MENU_VALUES=()

  local entry
  for entry in "${YT_FORMATS_AUDIO[@]}"; do
    local id codec abr ext note label

    id=$(print -r -- "$entry" | _yt_field id)
    codec=$(print -r -- "$entry" | _yt_field codec)
    abr=$(print -r -- "$entry" | _yt_field abr)
    ext=$(print -r -- "$entry" | _yt_field ext)
    note=$(print -r -- "$entry" | _yt_field note)

    [[ -z "$id" ]] && continue

    if [[ -n "$abr" && "$abr" != "0" ]]; then
      label="${id}  ${codec}  ${abr}k  ${ext}  ${note}"
    else
      label="${id}  ${codec}  ${ext}  ${note}"
    fi

    _YT_MENU_LABELS+=("$label")
    _YT_MENU_VALUES+=("$id")
  done
}

_yt_build_sub_menu() {
  local array_name="$1"
  local -a source_array=("${(@P)array_name}")
  _YT_MENU_LABELS=() _YT_MENU_VALUES=()

  local entry
  for entry in "${source_array[@]}"; do
    local lang label

    lang=$(print -r -- "$entry" | _yt_field lang)
    label=$(print -r -- "$entry" | _yt_field label)

    [[ -z "$lang" ]] && continue

    _YT_MENU_LABELS+=("${lang}  ${label}")
    _YT_MENU_VALUES+=("$lang")
  done
}

_yt_is_video_only() {
  local fmt_id="$1"
  local entry

  for entry in "${YT_FORMATS_VIDEO[@]}"; do
    local id note
    id=$(print -r -- "$entry" | _yt_field id)
    note=$(print -r -- "$entry" | _yt_field note)

    if [[ "$id" == "$fmt_id" ]]; then
      [[ "$note" == *"video only"* ]] && return 0
      return 1
    fi
  done

  return 1
}

# ---- 主流程 ----

main() {
  local url="$1"

  if [[ -z "$url" ]]; then
    read -r "url?输入视频 URL: "
    [[ -z "$url" ]] && { echo "URL required"; return 1; }
  fi

  echo ""
  echo "正在探测格式..."
  if ! yt_detect "$url"; then
    echo "格式探测失败: $YT_DETECT_ERROR"
    return 1
  fi

  echo "标题: $YT_DETECT_TITLE"
  echo "发现 ${#YT_FORMATS_VIDEO} 个视频流, ${#YT_FORMATS_AUDIO} 个音频流, ${#YT_FORMATS_SUBS} 个字幕"

  _yt_build_video_menu
  local -a vid_labels=("${_YT_MENU_LABELS[@]}") vid_values=("${_YT_MENU_VALUES[@]}")

  _yt_build_audio_menu
  local -a aud_labels=("${_YT_MENU_LABELS[@]}") aud_values=("${_YT_MENU_VALUES[@]}")

  _yt_build_sub_menu YT_FORMATS_SUBS
  local -a sub_labels=("${_YT_MENU_LABELS[@]}") sub_values=("${_YT_MENU_VALUES[@]}")

  echo ""
  echo "── 下载什么? ──"
  echo "  1) 视频 (视频+音频合并)"
  echo "  2) 仅音频"
  echo "  3) 仅字幕"
  echo "  4) 全部 (视频+字幕)"
  echo ""
  local dtype
  read -r "dtype?选择 [1-4]: "

  local video_dir=""

  case "$dtype" in
    1|4)
      local vid_fmt
      vid_fmt=$(_yt_menu_select "选择视频流" vid_labels vid_values)
      if [[ $? -eq 0 && -n "$vid_fmt" ]]; then
        local final_fmt="$vid_fmt"

        if _yt_is_video_only "$vid_fmt"; then
          echo "该流为 video only，需选择音频流合并"
          local aud_fmt
          aud_fmt=$(_yt_menu_select "选择音频流" aud_labels aud_values)
          [[ $? -eq 0 && -n "$aud_fmt" ]] && final_fmt="${vid_fmt}+${aud_fmt}"
        fi

        video_dir=$(_yt_ask_location "$YT_DIR_VIDEO")

        echo ""
        echo "开始下载: format=$final_fmt → $video_dir"
        if yt_dl_video "$url" "$final_fmt" "$video_dir"; then
          echo "视频下载完成"
          [[ -n "$YT_DL_OUTPUT" ]] && echo "$YT_DL_OUTPUT"
        else
          echo "视频下载失败: $YT_DL_ERROR"
        fi
      fi

      if [[ "$dtype" == "4" ]] && (( ${#sub_values} > 0 )); then
        local sub_dir="${video_dir:-$YT_DIR_SUBTITLE}"
        if [[ -n "$video_dir" ]]; then
          echo ""
          echo "字幕将默认保存到视频目录: $video_dir"
        fi
        local sub_lang
        sub_lang=$(_yt_menu_select "选择字幕语言" sub_labels sub_values)
        if [[ $? -eq 0 && -n "$sub_lang" ]]; then
          if yt_dl_subs "$url" "$sub_lang" "$sub_dir"; then
            echo "字幕下载完成"
          else
            echo "字幕下载失败: $YT_DL_ERROR"
          fi
        fi
      fi
      ;;
    2)
      local aud_fmt
      aud_fmt=$(_yt_menu_select "选择音频流" aud_labels aud_values)
      if [[ $? -eq 0 && -n "$aud_fmt" ]]; then
        local dir
        dir=$(_yt_ask_location "$YT_DIR_AUDIO")
        echo ""
        echo "开始下载: format=$aud_fmt → $dir"
        if yt_dl_audio "$url" "$aud_fmt" "$dir"; then
          echo "音频下载完成"
        else
          echo "音频下载失败: $YT_DL_ERROR"
        fi
      fi
      ;;
    3)
      if (( ${#sub_values} > 0 )); then
        local sub_lang
        sub_lang=$(_yt_menu_select "选择字幕语言" sub_labels sub_values)
        if [[ $? -eq 0 && -n "$sub_lang" ]]; then
          local dir
          dir=$(_yt_ask_location "$YT_DIR_SUBTITLE")
          if yt_dl_subs "$url" "$sub_lang" "$dir"; then
            echo "字幕下载完成"
          else
            echo "字幕下载失败: $YT_DL_ERROR"
          fi
        fi
      else
        echo "该视频无可用字幕"
      fi
      ;;
    *)
      echo "无效选择"
      return 1
      ;;
  esac
}

main "$@"
