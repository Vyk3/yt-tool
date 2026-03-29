#!/bin/zsh
# ================================================================
# path-validator.sh — 路径校验与展开（无 eval，无直接输出）
#
# 错误通过返回值传递，诊断信息写入 YT_PATH_ERROR
# ================================================================

typeset -g YT_PATH_ERROR=""

# 展开路径：仅处理 ~ 前缀，不 eval 任意 shell 语法
# 规则:
#   ~/...  → ${HOME}/...
#   ~      → ${HOME}
#   其余   → 原样返回（~user 不展开）
yt_expand_path() {
  local p="$1"
  if [[ "$p" == "~/"* ]]; then
    echo "${HOME}${p#\~}"
  elif [[ "$p" == "~" ]]; then
    echo "${HOME}"
  else
    echo "$p"
  fi
}

# 确保目录存在且可写
# 返回: 0=可用 1=失败（原因见 YT_PATH_ERROR）
yt_ensure_dir() {
  local dir="$1"
  YT_PATH_ERROR=""

  if [[ -z "$dir" ]]; then
    YT_PATH_ERROR="empty path"
    return 1
  fi

  if [[ -e "$dir" && ! -d "$dir" ]]; then
    YT_PATH_ERROR="path exists but is not a directory: $dir"
    return 1
  fi

  if [[ -d "$dir" ]]; then
    if [[ ! -w "$dir" ]]; then
      YT_PATH_ERROR="directory not writable: $dir"
      return 1
    fi
    return 0
  fi

  if ! mkdir -p -- "$dir" 2>/dev/null; then
    YT_PATH_ERROR="cannot create directory: $dir"
    return 1
  fi

  if [[ ! -w "$dir" ]]; then
    YT_PATH_ERROR="created directory not writable: $dir"
    return 1
  fi

  return 0
}
