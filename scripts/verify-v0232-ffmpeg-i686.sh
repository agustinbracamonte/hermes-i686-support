#!/usr/bin/env bash
# Verify FFmpeg artifacts without treating static ELF inspection as runtime proof.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/v0232-i686-build-common.sh
source "$SCRIPT_DIR/v0232-i686-build-common.sh"
# shellcheck source=scripts/v0232-ffmpeg-version.sh
source "$SCRIPT_DIR/v0232-ffmpeg-version.sh"

MODE=static
usage() {
  cat <<'HELP'
Usage: verify-v0232-ffmpeg-i686.sh [--static-only|--runtime] FFmpeg FFprobe OUTPUT_DIR

Always checks both binaries are little-endian ELF32/EM_386 and records their
SHA-256, dynamic dependencies and GLIBC requirements. --static-only never runs
the supplied binaries. --runtime requires a native Debian 11 i386 userspace,
then checks library resolution, expected codecs, synthetic encode/decode, and
X11 capture using Xvfb. It measures peak RSS for the video smoke test.

FFMPEG_SOURCE_COMMIT may be set to the exact source commit recorded by the
builder. It is reported as UNKNOWN when unavailable; this tool does not infer
source provenance from the executable version string.

The runtime checks generate only synthetic media under a temporary directory.
The report is written to OUTPUT_DIR/ffmpeg-i686-verification.txt, which must
not already exist. Static inspection is not evidence of runtime compatibility.
HELP
}

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  usage
  exit 0
fi
if [[ "${1:-}" == --static-only ]]; then
  shift
elif [[ "${1:-}" == --runtime ]]; then
  MODE=runtime
  shift
fi
[[ $# -eq 3 ]] || { usage >&2; v0232_die 'expected FFmpeg, FFprobe, and output directory'; }

FFMPEG_BIN=$1
FFPROBE_BIN=$2
OUTPUT_DIR=$3
REPORT="$OUTPUT_DIR/ffmpeg-i686-verification.txt"
SOURCE_COMMIT=${FFMPEG_SOURCE_COMMIT:-UNKNOWN}
[[ "$SOURCE_COMMIT" == UNKNOWN || "$SOURCE_COMMIT" =~ ^[0-9a-f]{40}$ ]] || \
  v0232_die 'FFMPEG_SOURCE_COMMIT must be a full 40-character lowercase Git commit'
[[ -x "$FFMPEG_BIN" ]] || v0232_die "FFmpeg executable is missing or not executable: $FFMPEG_BIN"
[[ -x "$FFPROBE_BIN" ]] || v0232_die "FFprobe executable is missing or not executable: $FFPROBE_BIN"
[[ ! -e "$REPORT" && ! -L "$REPORT" ]] || v0232_die "report already exists; use a new output directory: $REPORT"
mkdir -p -- "$OUTPUT_DIR"
[[ -d "$OUTPUT_DIR" && ! -L "$OUTPUT_DIR" ]] || v0232_die "output path must be a regular directory: $OUTPUT_DIR"
v0232_need awk grep paste readelf sha256sum sed sort tail

TEMP=
TEMP_REPORT="$REPORT.tmp.$$"
XVFB_PID=
FFMPEG_PID=
FFPROBE_PID=
cleanup() {
  if [[ -n "${XVFB_PID:-}" ]]; then
    kill "$XVFB_PID" 2>/dev/null || true
    wait "$XVFB_PID" 2>/dev/null || true
  fi
  if [[ -n "${FFMPEG_PID:-}" ]]; then
    kill "$FFMPEG_PID" 2>/dev/null || true
    wait "$FFMPEG_PID" 2>/dev/null || true
  fi
  if [[ -n "${FFPROBE_PID:-}" ]]; then
    kill "$FFPROBE_PID" 2>/dev/null || true
    wait "$FFPROBE_PID" 2>/dev/null || true
  fi
  if [[ -n "${TEMP:-}" ]]; then
    rm -rf -- "$TEMP"
  fi
  rm -f -- "$TEMP_REPORT"
}
trap cleanup EXIT

FFMPEG_ID=$(v0232_elf_identity "$FFMPEG_BIN") || v0232_die 'FFmpeg must be ELF32 little-endian EM_386'
FFPROBE_ID=$(v0232_elf_identity "$FFPROBE_BIN") || v0232_die 'FFprobe must be ELF32 little-endian EM_386'
assert_executable_elf_image() {
  local binary=$1 elf_type
  elf_type=$(readelf -h "$binary" | awk '/Type:/ { print $2; exit }')
  case "$elf_type" in
    EXEC) return 0 ;;
    DYN)
      # Older binutils labels PIE as "Shared object file". Require its
      # interpreter segment and a nonzero entry point to distinguish it from a DSO.
      readelf -h "$binary" | awk '
        /Entry point address:/ {
          address=$4
          sub(/^0x0*/, "", address)
          if (address ~ /^[1-9a-fA-F][0-9a-fA-F]*$/) valid=1
        }
        END { exit !valid }
      ' || return 1
      readelf -l "$binary" 2>/dev/null | grep -Eq '^[[:space:]]*INTERP([[:space:]]|$)'
      ;;
    *) return 1 ;;
  esac
}
for binary in "$FFMPEG_BIN" "$FFPROBE_BIN"; do
  assert_executable_elf_image "$binary" || \
    v0232_die "$binary is not an executable ELF image"
done
FFMPEG_SHA=$(v0232_sha256 "$FFMPEG_BIN")
FFPROBE_SHA=$(v0232_sha256 "$FFPROBE_BIN")

needed_libraries() {
  readelf -d "$1" 2>/dev/null | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p' | sort -u | paste -sd, -
}

max_glibc_requirement() {
  local version
  version=$(readelf --version-info "$1" 2>/dev/null | grep -oE 'GLIBC_[0-9]+(\.[0-9]+)*' | sort -Vu | tail -n 1 || true)
  printf '%s' "${version:-NONE}"
}

assert_bullseye_glibc_requirement() {
  local binary=$1 requirement=${2#GLIBC_} highest
  [[ "$requirement" == NONE ]] && return 0
  highest=$(printf '%s\n' 2.31 "$requirement" | sort -V | tail -n 1)
  [[ "$highest" == 2.31 ]] || \
    v0232_die "$binary requires GLIBC_$requirement, newer than Debian 11's GLIBC_2.31"
}

FFMPEG_NEEDED=$(needed_libraries "$FFMPEG_BIN")
FFPROBE_NEEDED=$(needed_libraries "$FFPROBE_BIN")
FFMPEG_GLIBC=$(max_glibc_requirement "$FFMPEG_BIN")
FFPROBE_GLIBC=$(max_glibc_requirement "$FFPROBE_BIN")
assert_bullseye_glibc_requirement "$FFMPEG_BIN" "$FFMPEG_GLIBC"
assert_bullseye_glibc_requirement "$FFPROBE_BIN" "$FFPROBE_GLIBC"

RUNTIME_RESULT=NOT_RUN
RUNTIME_OS=UNKNOWN
RUNTIME_ARCH=UNKNOWN
LDD_RESULT=NOT_RUN
FFMPEG_LDD_LIBRARIES=NOT_RUN
FFPROBE_LDD_LIBRARIES=NOT_RUN
CODECS_RESULT=NOT_RUN
MEDIA_RESULT=NOT_RUN
X11_RESULT=NOT_RUN
RSS_KB=NOT_MEASURED
FFMPEG_VERSION=NOT_RUN
FFPROBE_VERSION=NOT_RUN
BUILD_CONFIG_SHA=NOT_RUN
NATIVE_CHILD_RESULT=NOT_RUN

if [[ "$MODE" == runtime ]]; then
  v0232_assert_i686_process
  v0232_need dpkg getconf ldd mkfifo mktemp paste readlink seq sleep Xvfb
  [[ -x /usr/bin/time ]] || v0232_die 'missing GNU time at /usr/bin/time'
  [[ "$(getconf LONG_BIT)" == 32 ]] || v0232_die 'runtime process reports pointer width other than 32 bits'
  RUNTIME_ARCH=$(dpkg --print-architecture)
  [[ "$RUNTIME_ARCH" == i386 ]] || v0232_die "runtime dpkg architecture is '$RUNTIME_ARCH', not i386"
  RUNTIME_OS=$(< /etc/debian_version)
  [[ "$RUNTIME_OS" == 11* ]] || v0232_die "runtime Debian version is '$RUNTIME_OS', not Bullseye 11"

  for qemu_env in QEMU_LD_PREFIX QEMU_CPU QEMU_SET_ENV QEMU_UNSET_ENV; do
    [[ -z "${!qemu_env:-}" ]] || v0232_die "refusing emulator-marked runtime environment ($qemu_env is set)"
  done
  ! grep -qi qemu "/proc/$$/maps" || v0232_die 'refusing a runtime shell with QEMU mapped into its process image'

  resolve_runtime_libraries() {
    local binary=$1 output path
    output=$(ldd "$binary" 2>&1) || v0232_die "ldd failed for $binary: $output"
    [[ "$output" != *'not found'* ]] || v0232_die "unresolved runtime library for $binary: $output"
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      v0232_elf_identity "$path" >/dev/null || v0232_die "runtime dependency is not ELF32/EM_386: $path"
    done < <(printf '%s\n' "$output" | awk '$2 == "=>" && $3 ~ /^\// {print $3} $1 ~ /^\// {print $1}' | sort -u)
    printf '%s\n' "$output" | awk '$2 == "=>" && $3 ~ /^\// {print $1 "=" $3} $1 ~ /^\// {print $1}' | sort -u | paste -sd, -
  }
  FFMPEG_LDD_LIBRARIES=$(resolve_runtime_libraries "$FFMPEG_BIN")
  FFPROBE_LDD_LIBRARIES=$(resolve_runtime_libraries "$FFPROBE_BIN")
  LDD_RESULT=PASS

  FFMPEG_VERSION=$("$FFMPEG_BIN" -hide_banner -version 2>&1 | sed -n '1p')
  FFPROBE_VERSION=$("$FFPROBE_BIN" -hide_banner -version 2>&1 | sed -n '1p')
  FFMPEG_RELEASE=$(v0232_validate_ffmpeg_release_pair \
    "$SOURCE_COMMIT" "$FFMPEG_VERSION" "$FFPROBE_VERSION") || \
    v0232_die 'FFmpeg/FFprobe versions do not match either recorded FFmpeg 9.0.1 source pin'
  BUILD_CONFIG=$("$FFMPEG_BIN" -hide_banner -buildconf 2>&1)
  BUILD_CONFIG_SHA=$(printf '%s\n' "$BUILD_CONFIG" | sha256sum | awk '{print $1}')
  ENCODERS=$("$FFMPEG_BIN" -hide_banner -encoders 2>&1)
  for encoder in aac libx264 libopus libmp3lame; do
    [[ "$ENCODERS" == *"$encoder"* ]] || v0232_die "required smoke-test encoder is unavailable: $encoder"
  done
  for option in --enable-gpl --enable-libx264 --enable-libopus --enable-libmp3lame --enable-libxcb; do
    [[ "$BUILD_CONFIG" == *"$option"* ]] || v0232_die "build configuration omits expected feature: $option"
  done
  [[ "$BUILD_CONFIG" != *'--enable-nonfree'* ]] || v0232_die 'nonfree FFmpeg configuration is not accepted by this profile'
  CODECS_RESULT=PASS

  TEMP=$(mktemp -d "${TMPDIR:-/tmp}/v0232-ffmpeg-i686.XXXXXX")
  verify_native_child() {
    local pid=$1 binary=$2 child_exe= expected_exe
    expected_exe=$(readlink -f "$binary")
    for _ in $(seq 1 20); do
      [[ -e "/proc/$pid/exe" ]] || break
      child_exe=$(readlink -f "/proc/$pid/exe" || true)
      [[ "$child_exe" == "$expected_exe" ]] && break
      kill -0 "$pid" 2>/dev/null || break
      sleep 0.1
    done
    [[ "$child_exe" == "$expected_exe" ]] || \
      v0232_die "process $pid did not resolve to the supplied executable (observed '$child_exe')"
    v0232_assert_i686_elf "$child_exe"
    ! grep -qi qemu "/proc/$pid/maps" || \
      v0232_die "refusing process $pid with QEMU mapped into its process image"
  }

  "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -re \
    -f lavfi -i 'sine=frequency=440:sample_rate=48000' -t 30 -f null - \
    >"$TEMP/native-process.log" 2>&1 &
  FFMPEG_PID=$!
  for _ in $(seq 1 20); do
    [[ -e "/proc/$FFMPEG_PID/exe" ]] && break
    kill -0 "$FFMPEG_PID" 2>/dev/null || break
    sleep 0.1
  done
  [[ -e "/proc/$FFMPEG_PID/exe" ]] || \
    v0232_die 'could not inspect a live FFmpeg process for native ELF identity'
  verify_native_child "$FFMPEG_PID" "$FFMPEG_BIN"
  kill "$FFMPEG_PID" 2>/dev/null || true
  wait "$FFMPEG_PID" 2>/dev/null || true
  FFMPEG_PID=

  mkfifo "$TEMP/probe-input.mkv"
  "$FFPROBE_BIN" -v error -show_entries format=format_name -of default=noprint_wrappers=1 \
    "$TEMP/probe-input.mkv" >"$TEMP/probe-process.log" 2>&1 &
  FFPROBE_PID=$!
  for _ in $(seq 1 20); do
    [[ -e "/proc/$FFPROBE_PID/exe" ]] && break
    kill -0 "$FFPROBE_PID" 2>/dev/null || break
    sleep 0.1
  done
  [[ -e "/proc/$FFPROBE_PID/exe" ]] || \
    v0232_die 'could not inspect a live FFprobe process for native ELF identity'
  verify_native_child "$FFPROBE_PID" "$FFPROBE_BIN"
  kill "$FFPROBE_PID" 2>/dev/null || true
  wait "$FFPROBE_PID" 2>/dev/null || true
  FFPROBE_PID=
  NATIVE_CHILD_RESULT=PASS

  timed_encode() {
    local name=$1; shift
    /usr/bin/time -f '%M' -o "$TEMP/$name.rss-kb" "$FFMPEG_BIN" \
      -nostdin -hide_banner -loglevel error -y -threads 1 "$@"
  }
  codec_name() {
    "$FFPROBE_BIN" -v error -select_streams "$1" -show_entries stream=codec_name \
      -of default=noprint_wrappers=1:nokey=1 "$2"
  }

  timed_encode h264 -f lavfi -i 'testsrc2=size=64x64:rate=5' -frames:v 5 -an \
    -c:v libx264 -threads:v 1 -pix_fmt yuv420p "$TEMP/h264.mkv"
  [[ "$(codec_name v:0 "$TEMP/h264.mkv")" == h264 ]] || v0232_die 'H.264 encode/ffprobe check failed'
  "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -threads 1 -i "$TEMP/h264.mkv" \
    -frames:v 1 -f null -
  RSS_KB=$(<"$TEMP/h264.rss-kb")

  timed_encode aac -f lavfi -i 'sine=frequency=880:sample_rate=44100' -t 0.5 \
    -c:a aac -b:a 64k "$TEMP/aac.m4a"
  [[ "$(codec_name a:0 "$TEMP/aac.m4a")" == aac ]] || v0232_die 'AAC encode/ffprobe check failed'
  "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -threads 1 -i "$TEMP/aac.m4a" -f null -

  timed_encode opus -f lavfi -i 'sine=frequency=1000:sample_rate=48000' -t 0.5 \
    -c:a libopus "$TEMP/opus.ogg"
  [[ "$(codec_name a:0 "$TEMP/opus.ogg")" == opus ]] || v0232_die 'Opus encode/ffprobe check failed'
  "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -threads 1 -i "$TEMP/opus.ogg" -f null -

  timed_encode mp3 -f lavfi -i 'sine=frequency=440:sample_rate=44100' -t 0.5 \
    -c:a libmp3lame "$TEMP/mp3.mp3"
  [[ "$(codec_name a:0 "$TEMP/mp3.mp3")" == mp3 ]] || v0232_die 'MP3 encode/ffprobe check failed'
  "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error -threads 1 -i "$TEMP/mp3.mp3" -f null -

  MEDIA_RESULT=PASS

  XVFB_PID=
  for display_number in $(seq 90 199); do
    [[ ! -e "/tmp/.X11-unix/X$display_number" && ! -e "/tmp/.X$display_number-lock" ]] || continue
    Xvfb ":$display_number" -screen 0 320x240x24 -nolisten tcp -noreset \
      >"$TEMP/xvfb.log" 2>&1 &
    XVFB_PID=$!
    for _ in $(seq 1 30); do
      [[ -S "/tmp/.X11-unix/X$display_number" ]] && break
      kill -0 "$XVFB_PID" 2>/dev/null || break
      sleep 0.1
    done
    if [[ -S "/tmp/.X11-unix/X$display_number" ]]; then
      DISPLAY=":$display_number.0" "$FFMPEG_BIN" -nostdin -hide_banner -loglevel error \
        -f x11grab -video_size 320x240 -framerate 5 -i ":$display_number.0+0,0" \
        -frames:v 1 -f null -
      break
    fi
    kill "$XVFB_PID" 2>/dev/null || true
    wait "$XVFB_PID" 2>/dev/null || true
    XVFB_PID=
  done
  [[ -n "$XVFB_PID" && -S "/tmp/.X11-unix/X$display_number" ]] || \
    v0232_die 'could not start an isolated Xvfb display for the x11grab test'
  X11_RESULT=PASS
  RUNTIME_RESULT=PASS
fi

{
  printf 'schema=hermes-ffmpeg-i686-check-v1\n'
  printf 'validation_mode=%s\n' "$MODE"
  printf 'native_i686_execution=%s\n' "$RUNTIME_RESULT"
  printf 'ffmpeg_process_elf_identity=%s\n' "$NATIVE_CHILD_RESULT"
  printf 'debian_version=%s\n' "$RUNTIME_OS"
  printf 'dpkg_architecture=%s\n' "$RUNTIME_ARCH"
  printf 'source_commit_claimed=%s\n' "$SOURCE_COMMIT"
  printf 'ffmpeg_elf=%s\n' "$FFMPEG_ID"
  printf 'ffmpeg_sha256=%s\n' "$FFMPEG_SHA"
  printf 'ffmpeg_needed=%s\n' "${FFMPEG_NEEDED:-NONE}"
  printf 'ffmpeg_resolved_libraries=%s\n' "$FFMPEG_LDD_LIBRARIES"
  printf 'ffmpeg_max_glibc=%s\n' "$FFMPEG_GLIBC"
  printf 'ffprobe_elf=%s\n' "$FFPROBE_ID"
  printf 'ffprobe_sha256=%s\n' "$FFPROBE_SHA"
  printf 'ffprobe_needed=%s\n' "${FFPROBE_NEEDED:-NONE}"
  printf 'ffprobe_resolved_libraries=%s\n' "$FFPROBE_LDD_LIBRARIES"
  printf 'ffprobe_max_glibc=%s\n' "$FFPROBE_GLIBC"
  printf 'ffmpeg_version=%s\n' "$FFMPEG_VERSION"
  printf 'ffprobe_version=%s\n' "$FFPROBE_VERSION"
  printf 'build_config_sha256=%s\n' "$BUILD_CONFIG_SHA"
  printf 'runtime_library_resolution=%s\n' "$LDD_RESULT"
  printf 'codec_availability=%s\n' "$CODECS_RESULT"
  printf 'synthetic_codec_smoke=%s\n' "$MEDIA_RESULT"
  printf 'x11grab_xvfb_smoke=%s\n' "$X11_RESULT"
  printf 'h264_encode_peak_rss_kb=%s\n' "$RSS_KB"
} >"$TEMP_REPORT"
mv -- "$TEMP_REPORT" "$REPORT"
v0232_log "verification report: $REPORT"
