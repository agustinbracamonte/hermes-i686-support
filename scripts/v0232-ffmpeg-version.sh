#!/usr/bin/env bash
# Version banner checks shared by the FFmpeg runtime verifier and its fixtures.

v0232_validate_ffmpeg_release_pair() {
  local source_commit=$1 ffmpeg_banner=$2 ffprobe_banner=$3
  local ffmpeg_release ffprobe_release
  ffmpeg_release=$(awk '{print $3}' <<<"$ffmpeg_banner")
  ffprobe_release=$(awk '{print $3}' <<<"$ffprobe_banner")
  [[ -n "$ffmpeg_release" && "$ffmpeg_release" == "$ffprobe_release" ]] || return 1
  case "$source_commit:$ffmpeg_release" in
    e47273f4d9227152dcbf543cebaf9e2430ddbcc4:n9.0.1-11-ge47273f4d9) ;;
    bf1b838f2ab88b4f8fd83443325c782ea0e0f7fa:n9.0.1) ;;
    *) return 1 ;;
  esac
  printf '%s' "$ffmpeg_release"
}
