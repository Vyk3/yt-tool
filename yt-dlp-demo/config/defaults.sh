#!/bin/zsh
# ================================================================
# defaults.sh — 默认配置（纯声明，无副作用）
#
# 本文件由各模块通过 source 加载。
# YT_PREFER_* 为排序偏好，非强制——交互层始终展示全部候选。
# YT_DIR_* 为路径默认值，用户可在交互时覆盖。
# ================================================================

# --- 输出目录（默认值，非偏好）---
YT_DIR_VIDEO="${HOME}/Downloads/Videos"
YT_DIR_AUDIO="${HOME}/Downloads/Music"
YT_DIR_SUBTITLE="${HOME}/Downloads/Subtitles"
# 默认与视频目录一致，下载时按 %(playlist_title)s 建子目录隔离
YT_DIR_PLAYLIST="${HOME}/Downloads/Videos"

# --- 视频排序偏好 ---
# height: 首选分辨率高度（像素）。排序规则：
#   1. 不超过此值的流按高度降序排列
#   2. 若所有流均超过此值，按与此值距离升序排列
#   3. 交互层始终展示全部候选，仅调整默认高亮项
YT_PREFER_VIDEO_HEIGHT=1080
# codec: 同分辨率时优先展示（h264 / vp9 / av01）
YT_PREFER_VIDEO_CODEC="h264"
# container: 视频合并输出容器格式
YT_PREFER_VIDEO_CONTAINER="mp4"

# --- 音频排序偏好 ---
# codec: 同码率时优先展示（m4a / opus / vorbis）
YT_PREFER_AUDIO_CODEC="m4a"
# min_bitrate: 低于此码率（kbps）的流排序靠后，但不隐藏
YT_PREFER_AUDIO_MIN_BITRATE=96

# --- 字幕 ---
# 逗号分隔的语言代码，探测后高亮这些语言，不隐藏其余
# 为空时不做高亮偏好，全部语言平等展示
YT_PREFER_SUBTITLE_LANGS="zh-Hans,en"

# --- 行为开关（值域：true / false）---
# 下载时是否显示进度信息；执行层应据此决定是否拼接相关参数
YT_SHOW_PROGRESS=true
# 仅影响播放列表：单项失败时是否继续下载后续项
YT_PLAYLIST_CONTINUE_ON_ERROR=true
