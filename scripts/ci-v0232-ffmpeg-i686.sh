#!/usr/bin/env bash
# Build and execute a disposable FFmpeg 9.0.1 ELF32 in hosted i686 userspace.
# The output is hashed and then deleted; this script never uploads binaries.
set -Eeuo pipefail

readonly DEBIAN_SNAPSHOT=20260912T092708Z

die() {
  printf 'v0.23.2 FFmpeg hosted CI: ERROR: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'HELP'
Usage: ci-v0232-ffmpeg-i686.sh SOURCE_ROOT BUILD_ROOT

Build FFmpeg 9.0.1 serially in a disposable Debian 11 i386 chroot on a
GitHub-hosted x86_64 runner. The build runs without QEMU, produces and checks
ELF32/EM_386 binaries, exercises synthetic codec/X11 paths, prints hashes,
and deletes all binaries and the chroot on exit. It never uploads artifacts.

BUILD_ROOT must be a new directory under RUNNER_TEMP. This helper refuses
local, self-hosted, non-x86_64, or out-of-scope build environments.
HELP
}

if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
  usage
  exit 0
fi

[[ "$(printenv GITHUB_ACTIONS 2>/dev/null || true)" == true ]] || die 'only GitHub Actions is allowed'
[[ "$(printenv RUNNER_ENVIRONMENT 2>/dev/null || true)" == github-hosted ]] || die 'self-hosted runners are not allowed'
[[ "$(printenv RUNNER_ARCH 2>/dev/null || true)" == X64 ]] || die 'requires an ephemeral GitHub-hosted X64 runner'
[[ "$(uname -m)" == x86_64 ]] || die 'expected an x86_64 Linux kernel with native IA32 compatibility'
[[ $# == 2 ]] || die 'usage: ci-v0232-ffmpeg-i686.sh SOURCE_ROOT BUILD_ROOT'

readonly RUNNER_TEMP_ROOT=$(realpath -e -- "${RUNNER_TEMP:-}") || die 'RUNNER_TEMP is missing'
readonly SOURCE_ROOT=$(realpath -e -- "$1") || die 'source root does not exist'
[[ -f "$SOURCE_ROOT/scripts/build-v0232-ffmpeg-i686.sh" ]] || die 'FFmpeg source recipe is missing'
[[ -f "$SOURCE_ROOT/scripts/verify-v0232-ffmpeg-i686.sh" ]] || die 'FFmpeg verifier is missing'

[[ "$2" == /* ]] || die 'build root must be an absolute path'
readonly BUILD_ROOT=$(realpath -m -- "$2") || die 'cannot resolve build root'
case "$BUILD_ROOT/" in
  "$RUNNER_TEMP_ROOT/"*) ;;
  *) die "build root must remain under RUNNER_TEMP: $BUILD_ROOT" ;;
esac
case "$SOURCE_ROOT/" in
  "$BUILD_ROOT/"*) die 'source root must not be inside the disposable build root' ;;
esac
case "$BUILD_ROOT/" in
  "$SOURCE_ROOT/"*) die 'disposable build root must not contain the source root' ;;
esac
[[ ! -e "$BUILD_ROOT" && ! -L "$BUILD_ROOT" ]] || die "refusing to reuse existing build root: $BUILD_ROOT"

readonly ROOTFS="$BUILD_ROOT/rootfs"
readonly WORK="$BUILD_ROOT/work"
readonly BUILD_AREA="$WORK/build"
readonly LOG="$BUILD_ROOT/ffmpeg-build.log"
readonly RESULT_ROOT="$BUILD_AREA/ffmpeg-build-root/results/ffmpeg-9.0.1"
readonly SUMMARY_PATH=$(printenv GITHUB_STEP_SUMMARY 2>/dev/null || true)

cleanup() {
  local status=$?
  local can_remove_root=true
  trap - EXIT
  if [[ -d "$ROOTFS" ]]; then
    sudo umount -R "$ROOTFS/sys" 2>/dev/null || true
    sudo umount -R "$ROOTFS/dev" 2>/dev/null || true
    sudo umount "$ROOTFS/proc" 2>/dev/null || true
    sudo umount "$ROOTFS/work/build" 2>/dev/null || true
    sudo umount "$ROOTFS/work/source" 2>/dev/null || true
    if awk -v root="$ROOTFS" '$2 == root || index($2, root "/") == 1 { mounted=1 } END { exit !mounted }' /proc/self/mounts; then
      printf 'v0.23.2 FFmpeg hosted CI: ERROR: refusing to delete a rootfs with active mounts: %s\n' "$ROOTFS" >&2
      can_remove_root=false
      status=1
      if [[ -n "$SUMMARY_PATH" ]]; then
        printf '\nCleanup result: **FAIL**; active mounts remain under `%s`, so the runner workspace was left for hosted-runner teardown.\n' "$ROOTFS" >>"$SUMMARY_PATH"
      fi
    else
      sudo rm -rf -- "$ROOTFS" || { can_remove_root=false; status=1; }
    fi
  elif [[ -e "$ROOTFS" || -L "$ROOTFS" ]]; then
    can_remove_root=false
    status=1
  fi
  if [[ "$can_remove_root" == true ]]; then
    sudo rm -rf -- "$BUILD_ROOT" || status=1
  fi
  exit "$status"
}
trap cleanup EXIT

command -v sudo >/dev/null 2>&1 || die 'sudo is required on the GitHub-hosted runner'
mkdir -p -- "$BUILD_ROOT" "$ROOTFS" "$WORK/source" "$BUILD_AREA"
command -v curl >/dev/null 2>&1 || die 'curl is required on the GitHub-hosted runner'
command -v debootstrap >/dev/null 2>&1 || {
  sudo apt-get update
  sudo apt-get install --yes --no-install-recommends debootstrap debian-archive-keyring
}

sudo debootstrap --arch=i386 --variant=minbase --include=ca-certificates,debian-archive-keyring \
  bullseye "$ROOTFS" "https://snapshot.debian.org/archive/debian/$DEBIAN_SNAPSHOT"
sudo rm -f -- "$ROOTFS/etc/resolv.conf"
sudo cp -- /etc/resolv.conf "$ROOTFS/etc/resolv.conf"
sudo tee "$ROOTFS/etc/apt/sources.list" >/dev/null <<EOF
deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/$DEBIAN_SNAPSHOT bullseye main
EOF

sudo mkdir -p -- "$ROOTFS/work/source" "$ROOTFS/work/build"
sudo mount --bind "$SOURCE_ROOT" "$ROOTFS/work/source"
sudo mount --remount,bind,ro "$ROOTFS/work/source"
sudo mount --bind "$BUILD_AREA" "$ROOTFS/work/build"
sudo mount -t proc proc "$ROOTFS/proc"
sudo mount --rbind /dev "$ROOTFS/dev"
sudo mount --make-rslave "$ROOTFS/dev"
sudo mount --rbind /sys "$ROOTFS/sys"
sudo mount --make-rslave "$ROOTFS/sys"

CHROOT_STATUS=0
sudo chroot "$ROOTFS" /usr/bin/env DEBIAN_SNAPSHOT="$DEBIAN_SNAPSHOT" \
  /bin/bash -euo pipefail -s >"$LOG" 2>&1 <<'CHROOT' || CHROOT_STATUS=$?
export DEBIAN_FRONTEND=noninteractive LC_ALL=C TZ=UTC
test "$(dpkg --print-architecture)" = i386
apt-get -o Acquire::Check-Valid-Until=false -o Acquire::Retries=3 update
apt-get -o Acquire::Check-Valid-Until=false -o Acquire::Retries=3 --yes --no-install-recommends install \
  build-essential ca-certificates git nasm pkg-config util-linux xz-utils \
  libx264-dev libopus-dev libmp3lame-dev \
  libxcb1-dev libxcb-shm0-dev libxcb-shape0-dev libxcb-xfixes0-dev \
  time xvfb
mkdir -p /work/build/ffmpeg-build-root/results
dpkg-query -W -f='${binary:Package}=${Version}\n' \
  build-essential ca-certificates git nasm pkg-config util-linux xz-utils \
  libx264-dev libopus-dev libmp3lame-dev \
  libxcb1-dev libxcb-shm0-dev libxcb-shape0-dev libxcb-xfixes0-dev \
  time xvfb > /work/build/ffmpeg-build-root/results/ci-packages.txt
cd /work/source
export HERMES_I686_BUILD_ROOT=/work/build/ffmpeg-build-root JOBS=1 CC=gcc
bash scripts/build-v0232-ffmpeg-i686.sh --preflight-only
bash scripts/build-v0232-ffmpeg-i686.sh --prepare-only
bash scripts/build-v0232-ffmpeg-i686.sh
FFMPEG_SOURCE_COMMIT=bf1b838f2ab88b4f8fd83443325c782ea0e0f7fa \
  bash scripts/verify-v0232-ffmpeg-i686.sh --runtime \
    /work/build/ffmpeg-build-root/prefix/ffmpeg-9.0.1/bin/ffmpeg \
    /work/build/ffmpeg-build-root/prefix/ffmpeg-9.0.1/bin/ffprobe \
    /work/build/ffmpeg-build-root/results/ffmpeg-9.0.1/runtime-verification
CHROOT

if [[ "$CHROOT_STATUS" != 0 ]]; then
  printf 'FFmpeg i686 build failed inside disposable Debian 11 chroot (exit %s).\n' "$CHROOT_STATUS" >&2
  tail -n 100 -- "$LOG" >&2 || true
  if [[ -n "$SUMMARY_PATH" ]]; then
    {
      printf '# FFmpeg 9.0.1 hosted i686 build\n\n'
      printf 'Runner: standard GitHub-hosted Ubuntu 24.04 x64; disposable Debian 11 i386 chroot; no QEMU.\n\n'
      printf 'Debian snapshot: `%s`. Result: **FAIL** (chroot exit %s).\n\n' "$DEBIAN_SNAPSHOT" "$CHROOT_STATUS"
      printf 'No binary or build artifact was uploaded. Last 100 build-log lines:\n\n~~~text\n'
      tail -n 100 -- "$LOG" || true
      printf '~~~\n'
    } >>"$SUMMARY_PATH"
  fi
  exit "$CHROOT_STATUS"
fi

[[ -s "$RESULT_ROOT/smoke-check.txt" ]] || die 'missing FFmpeg smoke-check manifest'
[[ -s "$RESULT_ROOT/static-verification/ffmpeg-i686-verification.txt" ]] || die 'missing static verification report'
[[ -s "$RESULT_ROOT/runtime-verification/ffmpeg-i686-verification.txt" ]] || die 'missing native i686 runtime report'
[[ -s "$RESULT_ROOT/hermes-ffmpeg-i686-9.0.1.tar.xz.sha256" ]] || die 'missing local package SHA-256 record'
[[ -s "$RESULT_ROOT/ci-packages.txt" ]] || die 'missing Debian dependency version list'

if [[ -n "$SUMMARY_PATH" ]]; then
  {
    printf '# FFmpeg 9.0.1 hosted i686 build\n\n'
    printf 'Runner: standard GitHub-hosted Ubuntu 24.04 x64; disposable Debian 11 i386 chroot; no QEMU.\n'
    printf 'Debian snapshot: `%s`. Source is mounted read-only; build root and binaries are deleted at job exit.\n\n' "$DEBIAN_SNAPSHOT"
    printf 'No artifact upload, release, cache, or package publication is configured. Only text manifests and SHA-256 values are retained in this run.\n\n'
    printf '## Dependency package versions\n\n~~~text\n'
    cat "$RESULT_ROOT/ci-packages.txt"
    printf '~~~\n\n## Build smoke check\n\n~~~text\n'
    cat "$RESULT_ROOT/smoke-check.txt"
    printf '~~~\n\n## Static ELF and dependency evidence\n\n~~~text\n'
    cat "$RESULT_ROOT/static-verification/ffmpeg-i686-verification.txt"
    printf '~~~\n\n## Native synthetic runtime evidence\n\n~~~text\n'
    cat "$RESULT_ROOT/runtime-verification/ffmpeg-i686-verification.txt"
    printf '~~~\n\n'
    printf 'FFmpeg package archive SHA-256: `%s` (archive deleted after recording).\n' \
      "$(awk '{print $1}' "$RESULT_ROOT/hermes-ffmpeg-i686-9.0.1.tar.xz.sha256")"
    printf '\nResult: **PASS**. This is hosted i686 execution evidence, not B10 staging, PM integration, GPL redistribution approval, or cutover evidence.\n'
  } >>"$SUMMARY_PATH"
fi

printf 'FFmpeg hosted i686 build/runtime verification: PASS; ephemeral outputs will now be deleted.\n'
