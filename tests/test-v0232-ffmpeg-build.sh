#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BUILD_SCRIPT="$ROOT/scripts/build-v0232-ffmpeg-i686.sh"
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

bash -n "$BUILD_SCRIPT"
help=$("$BUILD_SCRIPT" --help)
[[ "$help" == *'Debian 11 i386'* ]]
[[ "$help" == *'--preflight-only'* && "$help" == *'--prepare-only'* ]]

grep -Fq 'readonly TAG_OBJECT=501bb49457b9dfb25d6a208832e0a6e6cd53108d' "$BUILD_SCRIPT"
grep -Fq 'readonly SOURCE_COMMIT=bf1b838f2ab88b4f8fd83443325c782ea0e0f7fa' "$BUILD_SCRIPT"
grep -Fq 'readonly SOURCE_TREE=68fad6870d0f112fcf4e385d798bf268b2b938b0' "$BUILD_SCRIPT"
grep -Fq 'make -j1' "$BUILD_SCRIPT"
grep -Fq -- '--enable-libx264 --enable-libopus --enable-libmp3lame' "$BUILD_SCRIPT"
grep -Fq -- '--enable-libxcb --enable-libxcb-shm --enable-libxcb-shape --enable-libxcb-xfixes' "$BUILD_SCRIPT"
pkg_modules=$(sed -n '/readonly PKG_CONFIG_MODULES=(/,/^)/p' "$BUILD_SCRIPT")
[[ "$pkg_modules" != *libmp3lame* ]]
grep -Fq 'QEMU_LD_PREFIX QEMU_CPU QEMU_SET_ENV QEMU_UNSET_ENV' "$BUILD_SCRIPT"
grep -Fq 'refusing a build shell with QEMU mapped' "$BUILD_SCRIPT"
for qemu_env in QEMU_LD_PREFIX QEMU_CPU QEMU_SET_ENV QEMU_UNSET_ENV; do
  if env "$qemu_env=hermes-test" "$BUILD_SCRIPT" --preflight-only >"$TMP/qemu-env.log" 2>&1; then
    printf 'FFmpeg recipe unexpectedly accepted %s\n' "$qemu_env" >&2
    exit 1
  fi
  grep -Fq "refusing emulated build environment ($qemu_env is set)" "$TMP/qemu-env.log"
done
configure_args=$(sed -n '/readonly CONFIGURE_ARGS=(/,/^)/p' "$BUILD_SCRIPT")
[[ "$configure_args" != *'--enable-nonfree'* ]]
if grep -Eq '(^|[[:space:]])(sudo|apt-get)[[:space:]]' "$BUILD_SCRIPT"; then
  printf 'build script must not install packages or invoke sudo\n' >&2
  exit 1
fi

if readelf -h "/proc/$$/exe" | grep -q 'Class:.*ELF64'; then
  if "$BUILD_SCRIPT" --preflight-only >"$TMP/preflight.log" 2>&1; then
    printf 'FFmpeg preflight unexpectedly accepted the x86_64 host\n' >&2
    exit 1
  fi
  grep -Fq 'build must run in an i686 userspace process' "$TMP/preflight.log"
fi

if HERMES_I686_BUILD_ROOT=/ "$BUILD_SCRIPT" --prepare-only >"$TMP/root.log" 2>&1; then
  printf 'FFmpeg recipe unexpectedly accepted / as its build root\n' >&2
  exit 1
fi
grep -Fq 'build root must not be /' "$TMP/root.log"

link_root="$TMP/link-root"
outside="$TMP/outside"
mkdir -p "$link_root/prefix/ffmpeg-9.0.1" "$outside"
ln -s "$outside" "$link_root/prefix/ffmpeg-9.0.1/share"
if HERMES_I686_BUILD_ROOT="$link_root" "$BUILD_SCRIPT" --prepare-only >"$TMP/symlink.log" 2>&1; then
  printf 'FFmpeg recipe unexpectedly accepted an escaping prefix symlink\n' >&2
  exit 1
fi
grep -Fq 'symlink escapes its build directory' "$TMP/symlink.log"

# FFmpeg's out-of-tree configure links BUILD/src back to its pinned SOURCE.
# Permit that one explicitly named source root, while still rejecting any
# other target outside the build tree.
helper_root="$TMP/symlink-policy"
helper_source="$helper_root/source"
helper_build="$helper_root/build"
helper_outside="$TMP/untrusted"
mkdir -p "$helper_source" "$helper_build" "$helper_outside"
ln -s "$helper_source" "$helper_build/src"
(
  source "$ROOT/scripts/v0232-i686-build-common.sh"
  v0232_assert_symlink_tree "$helper_build" "$helper_source"
)
rm "$helper_build/src"
ln -s "$helper_outside" "$helper_build/untrusted"
if (
  source "$ROOT/scripts/v0232-i686-build-common.sh"
  v0232_assert_symlink_tree "$helper_build" "$helper_source"
) >"$TMP/symlink-allowlist.log" 2>&1; then
  printf 'FFmpeg symlink policy unexpectedly accepted a target outside BUILD and SOURCE\n' >&2
  exit 1
fi
grep -Fq 'symlink escapes its build directory' "$TMP/symlink-allowlist.log"

printf 'v0.23.2 FFmpeg build recipe guards: PASS\n'
