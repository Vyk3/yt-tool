#!/bin/zsh
# ================================================================
# format-detector.sh — 动态格式探测（纯数据，无交互，无直接输出）
#
# 依赖: yt-dlp, python3
# Shell ↔ Python 协议: 每行 "TYPE<TAB>value"
#   TITLE 行: TITLE<TAB>原始标题文本（制表符和换行已替换为空格）
#   其余行: TYPE<TAB>JSON_object
# 错误: python3 失败 → exit code 1 + stderr
# ================================================================

typeset -ga YT_FORMATS_VIDEO
typeset -ga YT_FORMATS_AUDIO
typeset -ga YT_FORMATS_SUBS
typeset -ga YT_FORMATS_AUTO_SUBS
typeset -g YT_DETECT_TITLE=""
typeset -g YT_DETECT_ERROR=""
typeset -g YT_DETECT_RAW_JSON=""

_yt_reset_detect() {
  YT_FORMATS_VIDEO=()
  YT_FORMATS_AUDIO=()
  YT_FORMATS_SUBS=()
  YT_FORMATS_AUTO_SUBS=()
  YT_DETECT_TITLE=""
  YT_DETECT_ERROR=""
  YT_DETECT_RAW_JSON=""
}

# 返回: 0=成功 1=参数/依赖错误 2=yt-dlp错误 3=解析错误 4=环境错误
yt_detect() {
  local url="$1"
  _yt_reset_detect

  if [[ -z "$url" ]]; then
    YT_DETECT_ERROR="URL required"
    return 1
  fi

  local dep
  for dep in yt-dlp python3; do
    if ! command -v "$dep" &>/dev/null; then
      YT_DETECT_ERROR="$dep not found in PATH"
      return 1
    fi
  done

  local stderr_file
  stderr_file=$(mktemp) || { YT_DETECT_ERROR="mktemp failed"; return 4; }

  local raw
  raw=$(yt-dlp -j --no-warnings "$url" 2>"$stderr_file")
  local rc=$?
  local stderr_out=$(<"$stderr_file")
  rm -f "$stderr_file"

  if (( rc != 0 )); then
    YT_DETECT_ERROR="yt-dlp failed (exit $rc): ${stderr_out:0:200}"
    return 2
  fi

  YT_DETECT_RAW_JSON="$raw"

  local py_err_file
  py_err_file=$(mktemp) || { YT_DETECT_ERROR="mktemp failed"; return 4; }

  local parsed
  parsed=$(python3 -c '
import json, sys

d = json.loads(sys.stdin.read())

# 标题：替换制表符和换行，确保单行传输
title = d.get("title", "unknown")
title = title.replace("\t", " ").replace("\n", " ").replace("\r", "")
print(f"TITLE\t{title}")

for f in d.get("formats", []):
    fid = f.get("format_id", "")
    vc = f.get("vcodec", "none") or "none"
    ac = f.get("acodec", "none") or "none"
    has_v = vc != "none"
    has_a = ac != "none"

    if has_v:
        tag = "v+a" if has_a else "video only"
        note = f.get("format_note", "")
        obj = {
            "id": fid, "height": f.get("height") or 0,
            "codec": vc, "fps": f.get("fps") or 0,
            "tbr": f.get("tbr") or 0,
            "note": f"{note} [{tag}]" if note else f"[{tag}]"
        }
        print("V\t" + json.dumps(obj))
    elif has_a:
        obj = {
            "id": fid, "codec": ac,
            "abr": f.get("abr") or 0,
            "ext": f.get("ext", ""),
            "note": f.get("format_note", "")
        }
        print("A\t" + json.dumps(obj))

for lang, entries in d.get("subtitles", {}).items():
    label = entries[0].get("name", lang) if entries else lang
    print("S\t" + json.dumps({"lang": lang, "label": label}))

for lang, entries in d.get("automatic_captions", {}).items():
    label = entries[0].get("name", lang) if entries else lang
    print("AS\t" + json.dumps({"lang": lang, "label": label}))
' <<< "$raw" 2>"$py_err_file")

  rc=$?
  local py_err=$(<"$py_err_file")
  rm -f "$py_err_file"

  if (( rc != 0 )); then
    YT_DETECT_ERROR="python3 parse failed: ${py_err:0:200}"
    return 3
  fi

  if [[ -z "$parsed" ]]; then
    YT_DETECT_ERROR="python3 produced no output"
    return 3
  fi

  while IFS=$'\t' read -r type payload; do
    case "$type" in
      TITLE) YT_DETECT_TITLE="$payload" ;;
      V)     YT_FORMATS_VIDEO+=("$payload") ;;
      A)     YT_FORMATS_AUDIO+=("$payload") ;;
      S)     YT_FORMATS_SUBS+=("$payload") ;;
      AS)    YT_FORMATS_AUTO_SUBS+=("$payload") ;;
    esac
  done <<< "$parsed"

  return 0
}

# 从 JSON 字符串提取字段（字段名通过 argv 传递，无注入风险）
# 用法: echo "$json_line" | _yt_field "field_name"
_yt_field() {
  python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get(sys.argv[1],""))' "$1"
}
