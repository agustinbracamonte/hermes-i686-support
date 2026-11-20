#!/usr/bin/env bash
# Serial, resumable FFmpeg 9.0.1 build for a Debian 11 i686 userspace.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/v0232-i686-build-common.sh
source "$SCRIPT_DIR/v0232-i686-build-common.sh"
# shellcheck source=scripts/v0232-ffmpeg-version.sh
source "$SCRIPT_DIR/v0232-ffmpeg-version.sh"

readonly VERSION=9.0.1
readonly TAG=n9.0.1
readonly TAG_OBJECT=501bb49457b9dfb25d6a208832e0a6e6cd53108d
readonly SOURCE_COMMIT=bf1b838f2ab88b4f8fd83443325c782ea0e0f7fa
readonly SOURCE_TREE=68fad6870d0f112fcf4e385d798bf268b2b938b0
readonly SOURCE_REPOSITORY=https://github.com/FFmpeg/FFmpeg.git
readonly PACKAGE_NAMES=(
  build-essential ca-certificates git pkg-config nasm
  libx264-dev libopus-dev libmp3lame-dev
  libxcb1-dev libxcb-shm0-dev libxcb-shape0-dev libxcb-xfixes0-dev
)
readonly PKG_CONFIG_MODULES=(
  x264 opus xcb xcb-shm xcb-shape xcb-xfixes
)
readonly CONFIGURE_ARGS=(
  --prefix=PREFIX_PLACEHOLDER
  --arch=x86 --cpu=i686
  --enable-gpl
  --enable-libx264 --enable-libopus --enable-libmp3lame
  --enable-libxcb --enable-libxcb-shm --enable-libxcb-shape --enable-libxcb-xfixes
  --disable-ffplay --disable-doc --disable-debug
)

MODE=build
case "${1:-}" in
  --help|-h)
    cat <<'HELP'
Usage: build-v0232-ffmpeg-i686.sh [--preflight-only|--prepare-only]

Builds FFmpeg 9.0.1 from the signed n9.0.1 source tag in a Debian 11 i386
userspace. Configure, compile, install, and package steps run serially with
source/toolchain/configuration checkpoints. No packages are installed by this
script. The source tree, prefix, state, manifest, and archive remain under
HERMES_I686_BUILD_ROOT (default: .work/v0232-i686).

--preflight-only  Validate native i686 process, Bullseye, compiler, and libraries.
--prepare-only    Fetch and verify the exact upstream tag, without compiling.

Inputs: HERMES_I686_BUILD_ROOT, CC, JOBS=1.
The output archive is a local build result; do not publish it from this repository.
HELP
    exit 0
    ;;
  --preflight-only) MODE=preflight ;;
  --prepare-only) MODE=prepare ;;
  "") ;;
  *) v0232_die "unknown argument: $1" ;;
esac

v0232_require_serial
CC_BIN=${CC:-gcc}

assert_i686_bullseye() {
  local qemu_env
  for qemu_env in QEMU_LD_PREFIX QEMU_CPU QEMU_SET_ENV QEMU_UNSET_ENV; do
    [[ -z "${!qemu_env:-}" ]] || v0232_die "refusing emulated build environment ($qemu_env is set)"
  done
  if grep -qi qemu "/proc/$$/maps"; then
    v0232_die 'refusing a build shell with QEMU mapped into its process image'
  fi
  v0232_assert_i686_process
  [[ "$(dpkg --print-architecture)" == i386 ]] || \
    v0232_die "dpkg architecture must be i386 (saw $(dpkg --print-architecture))"
  [[ "$(< /etc/debian_version)" == 11* ]] || \
    v0232_die "build requires Debian 11 (saw $(< /etc/debian_version))"
  v0232_assert_i686_compiler "$CC_BIN"
}

verify_build_dependencies() {
  local package module status
  for package in "${PACKAGE_NAMES[@]}"; do
    status=$(dpkg-query -W -f='${Status}' "$package" 2>/dev/null || true)
    [[ "$status" == 'install ok installed' ]] || \
      v0232_die "required Debian build package is not installed: $package"
  done
  for module in "${PKG_CONFIG_MODULES[@]}"; do
    pkg-config --exists "$module" || v0232_die "pkg-config module is unavailable: $module"
  done
}

if [[ "$MODE" == preflight ]]; then
  v0232_need dpkg grep readelf
  command -v "$CC_BIN" >/dev/null 2>&1 || v0232_die "missing C compiler: $CC_BIN"
  assert_i686_bullseye
  v0232_need awk dpkg-query flock git make nasm pkg-config sha256sum
  verify_build_dependencies
  v0232_log "preflight passed (CC=$CC_BIN, target=$($CC_BIN -dumpmachine), Debian 11 i386)"
  exit 0
fi

if [[ "$MODE" == build ]]; then
  v0232_need dpkg grep readelf
  command -v "$CC_BIN" >/dev/null 2>&1 || v0232_die "missing C compiler: $CC_BIN"
  assert_i686_bullseye
  v0232_need awk dpkg-query find flock git make nasm pkg-config realpath sha256sum tar
  verify_build_dependencies
else
  v0232_need awk find flock git realpath sha256sum
fi

ROOT=${HERMES_I686_BUILD_ROOT:-"$PWD/.work/v0232-i686"}
[[ "$ROOT" != *" "* ]] || v0232_die "build paths cannot contain spaces: $ROOT"
[[ ! -L "$ROOT" ]] || v0232_die "build root must not be a symlink: $ROOT"
[[ "$ROOT" != / ]] || v0232_die 'build root must not be /'
mkdir -p -- "$ROOT"
ROOT=$(cd "$ROOT" && pwd -P)

safe_directory() {
  local path=$1 resolved
  [[ ! -L "$path" ]] || v0232_die "refusing symlinked build directory: $path"
  mkdir -p -- "$path"
  resolved=$(realpath -e -- "$path") || v0232_die "cannot resolve build directory: $path"
  case "$resolved/" in
    "$ROOT/"*) ;;
    *) v0232_die "build directory escapes its root: $path -> $resolved" ;;
  esac
}

for directory in state src build prefix results; do
  safe_directory "$ROOT/$directory"
done
STATE="$ROOT/state/ffmpeg-$VERSION"
SOURCE="$ROOT/src/ffmpeg-$VERSION"
BUILD="$ROOT/build/ffmpeg-$VERSION"
PREFIX="$ROOT/prefix/ffmpeg-$VERSION"
RESULTS="$ROOT/results/ffmpeg-$VERSION"
ARCHIVE="$RESULTS/hermes-ffmpeg-i686-$VERSION.tar.xz"
ARCHIVE_DIGEST="$STATE/package.sha256"
STATIC_REPORT="$RESULTS/static-verification/ffmpeg-i686-verification.txt"
BUILD_INFO="$PREFIX/share/doc/hermes-ffmpeg-i686/BUILD-INFO.txt"
safe_directory "$STATE"
safe_directory "$BUILD"
safe_directory "$PREFIX"
safe_directory "$RESULTS"
safe_directory "$RESULTS/static-verification"
v0232_assert_symlink_tree "$STATE"
v0232_assert_symlink_tree "$BUILD"
v0232_assert_symlink_tree "$PREFIX"
v0232_assert_symlink_tree "$RESULTS"
v0232_build_lock "$ROOT"

local_configure_args=()
for argument in "${CONFIGURE_ARGS[@]}"; do
  local_configure_args+=("${argument/PREFIX_PLACEHOLDER/$PREFIX}")
done
CONFIGURE_DISPLAY=$(printf '%q ' "${local_configure_args[@]}")
SCRIPT_FINGERPRINT=$(v0232_fingerprint \
  "$(v0232_sha256 "$0")" \
  "$(v0232_sha256 "$SCRIPT_DIR/v0232-i686-build-common.sh")" \
  "$(v0232_sha256 "$SCRIPT_DIR/v0232-ffmpeg-version.sh")" \
  "$(v0232_sha256 "$SCRIPT_DIR/verify-v0232-ffmpeg-i686.sh")")

ensure_source() {
  if [[ ! -d "$SOURCE/.git" ]]; then
    [[ -d "$SOURCE" ]] || mkdir -p -- "$SOURCE"
    [[ -z "$(find "$SOURCE" -mindepth 1 -maxdepth 1 -print -quit)" ]] || \
      v0232_die "source path exists without Git metadata and is not empty: $SOURCE"
    git init -q "$SOURCE"
    git -C "$SOURCE" remote add origin "$SOURCE_REPOSITORY"
  fi
  [[ "$(git -C "$SOURCE" remote get-url origin)" == "$SOURCE_REPOSITORY" ]] || \
    v0232_die "source origin is not the pinned public repository: $SOURCE"

  if ! git -C "$SOURCE" show-ref --verify --quiet "refs/tags/$TAG"; then
    git -C "$SOURCE" fetch --depth=1 --no-tags origin \
      "refs/tags/$TAG:refs/tags/$TAG"
  fi

  local tag_object commit tree head dirty
  tag_object=$(git -C "$SOURCE" rev-parse "refs/tags/$TAG^{tag}")
  commit=$(git -C "$SOURCE" rev-parse "refs/tags/$TAG^{commit}")
  tree=$(git -C "$SOURCE" rev-parse "refs/tags/$TAG^{tree}")
  [[ "$tag_object" == "$TAG_OBJECT" ]] || v0232_die "FFmpeg tag object mismatch: $tag_object"
  [[ "$commit" == "$SOURCE_COMMIT" ]] || v0232_die "FFmpeg commit mismatch: $commit"
  [[ "$tree" == "$SOURCE_TREE" ]] || v0232_die "FFmpeg source tree mismatch: $tree"

  if head=$(git -C "$SOURCE" rev-parse --verify HEAD 2>/dev/null); then
    [[ "$head" == "$SOURCE_COMMIT" ]] || v0232_die "source HEAD is $head, expected $SOURCE_COMMIT"
  else
    git -C "$SOURCE" checkout --quiet --detach "$SOURCE_COMMIT"
  fi
  dirty=$(git -C "$SOURCE" status --porcelain)
  [[ -z "$dirty" ]] || v0232_die "pinned FFmpeg source checkout is not clean: $SOURCE"
  [[ -x "$SOURCE/configure" ]] || v0232_die 'pinned FFmpeg source has no executable configure script'
}

SOURCE_FINGERPRINT=$(v0232_fingerprint "$TAG" "$TAG_OBJECT" "$SOURCE_COMMIT" "$SOURCE_TREE" "$SCRIPT_FINGERPRINT")
[[ ! -L "$SOURCE" ]] || v0232_die "refusing symlinked source directory: $SOURCE"
safe_directory "$SOURCE"
v0232_assert_symlink_tree "$SOURCE"
ensure_source
v0232_assert_symlink_tree "$SOURCE"
v0232_checkpoint "$STATE" source "$SOURCE_FINGERPRINT" "$SOURCE/.git" true
if [[ "$MODE" == prepare ]]; then
  v0232_log "verified FFmpeg $VERSION source: tag=$TAG tag_object=$TAG_OBJECT commit=$SOURCE_COMMIT tree=$SOURCE_TREE"
  exit 0
fi

PACKAGE_VERSIONS=$(for package in "${PACKAGE_NAMES[@]}"; do
  dpkg-query -W -f='${binary:Package}=${Version}\n' "$package"
done)
PKG_MODULE_VERSIONS=$(for module in "${PKG_CONFIG_MODULES[@]}"; do
  printf '%s=%s\n' "$module" "$(pkg-config --modversion "$module")"
done)
CC_INFO=$("$CC_BIN" --version | head -n 1)
CC_TARGET=$("$CC_BIN" -dumpmachine)
MAKE_INFO=$(make --version | head -n 1)
NASM_INFO=$(nasm -v)
TOOLCHAIN_FINGERPRINT=$(v0232_fingerprint \
  "$CC_INFO" "$CC_TARGET" "$MAKE_INFO" "$NASM_INFO" \
  "$PACKAGE_VERSIONS" "$PKG_MODULE_VERSIONS" "$(uname -sr)" "$ROOT")

configure_build() {
  cd "$BUILD"
  env -u CFLAGS -u CPPFLAGS -u LDFLAGS -u MAKEFLAGS -u CONFIG_SITE \
    LC_ALL=C TZ=UTC SOURCE_DATE_EPOCH=0 CC="$CC_BIN" CFLAGS='-O2 -g0 -march=i686' \
    "$SOURCE/configure" "${local_configure_args[@]}"
  v0232_assert_symlink_tree "$BUILD" "$SOURCE"
}

compile_build() {
  cd "$BUILD"
  env -u CFLAGS -u CPPFLAGS -u LDFLAGS -u CONFIG_SITE LC_ALL=C TZ=UTC \
    SOURCE_DATE_EPOCH=0 MAKEFLAGS= make -j1
  v0232_assert_symlink_tree "$BUILD" "$SOURCE"
}

install_build() {
  cd "$BUILD"
  env -u CFLAGS -u CPPFLAGS -u LDFLAGS -u CONFIG_SITE LC_ALL=C TZ=UTC \
    SOURCE_DATE_EPOCH=0 MAKEFLAGS= make -j1 install
  v0232_assert_symlink_tree "$PREFIX"
}

run_smoke_checks() {
  local ffmpeg="$PREFIX/bin/ffmpeg" ffprobe="$PREFIX/bin/ffprobe"
  local ffmpeg_banner ffprobe_banner release encoders config
  [[ -x "$ffmpeg" && -x "$ffprobe" ]] || v0232_die 'install did not produce executable FFmpeg and FFprobe'
  v0232_assert_i686_elf "$ffmpeg"
  v0232_assert_i686_elf "$ffprobe"
  ffmpeg_banner=$("$ffmpeg" -hide_banner -version 2>&1 | sed -n '1p')
  ffprobe_banner=$("$ffprobe" -hide_banner -version 2>&1 | sed -n '1p')
  release=$(v0232_validate_ffmpeg_release_pair "$SOURCE_COMMIT" "$ffmpeg_banner" "$ffprobe_banner") || \
    v0232_die "installed version banners do not match the pinned source ($ffmpeg_banner / $ffprobe_banner)"
  config=$("$ffmpeg" -hide_banner -buildconf 2>&1)
  for option in --enable-gpl --enable-libx264 --enable-libopus --enable-libmp3lame --enable-libxcb; do
    [[ "$config" == *"$option"* ]] || v0232_die "FFmpeg build configuration omits $option"
  done
  [[ "$config" != *'--enable-nonfree'* ]] || v0232_die 'nonfree FFmpeg configuration is not accepted'
  encoders=$("$ffmpeg" -hide_banner -encoders 2>&1)
  for encoder in aac libx264 libopus libmp3lame; do
    [[ "$encoders" == *"$encoder"* ]] || v0232_die "required encoder is unavailable: $encoder"
  done
  {
    printf 'ffmpeg_version=%s\nffprobe_version=%s\n' "$ffmpeg_banner" "$ffprobe_banner"
    printf 'release=%s\nffmpeg_sha256=%s\nffprobe_sha256=%s\n' \
      "$release" "$(v0232_sha256 "$ffmpeg")" "$(v0232_sha256 "$ffprobe")"
    printf 'build_config_sha256=%s\n' "$(v0232_fingerprint "$config")"
    printf 'elf32_em_386=PASS\nrequired_encoders=PASS\n'
  } >"$RESULTS/smoke-check.txt.tmp"
  mv -f -- "$RESULTS/smoke-check.txt.tmp" "$RESULTS/smoke-check.txt"
}

write_build_info() {
  local verifier_report="$STATIC_REPORT"
  mkdir -p -- "$(dirname "$BUILD_INFO")"
  {
    printf 'schema=hermes-ffmpeg-i686-build-v1\n'
    printf 'source_tag=%s\nsource_tag_object=%s\nsource_commit=%s\nsource_tree=%s\n' \
      "$TAG" "$TAG_OBJECT" "$SOURCE_COMMIT" "$SOURCE_TREE"
    printf 'source_repository=%s\ncompiler=%s\ncompiler_target=%s\nmake=%s\nnasm=%s\n' \
      "$SOURCE_REPOSITORY" "$CC_INFO" "$CC_TARGET" "$MAKE_INFO" "$NASM_INFO"
    printf 'configure_arguments=%s\nmake_jobs=1\nsource_date_epoch=0\n' "$CONFIGURE_DISPLAY"
    printf 'toolchain_fingerprint=%s\nscript_sha256=%s\n' "$TOOLCHAIN_FINGERPRINT" "$SCRIPT_FINGERPRINT"
    printf 'ffmpeg_sha256=%s\nffprobe_sha256=%s\n' \
      "$(v0232_sha256 "$PREFIX/bin/ffmpeg")" "$(v0232_sha256 "$PREFIX/bin/ffprobe")"
    printf '\n[debian_packages]\n%s\n[build_dependencies]\n%s\n' \
      "$PACKAGE_VERSIONS" "$PKG_MODULE_VERSIONS"
    printf '\n[static_verification]\n'
    cat "$verifier_report"
  } >"$BUILD_INFO.tmp"
  mv -f -- "$BUILD_INFO.tmp" "$BUILD_INFO"
  cp -- "$verifier_report" "$(dirname "$BUILD_INFO")/STATIC-VERIFICATION.txt"
}

CONFIGURE_FINGERPRINT=$(v0232_fingerprint "$SOURCE_FINGERPRINT" "$TOOLCHAIN_FINGERPRINT" "$SCRIPT_FINGERPRINT" "$PREFIX" "$CONFIGURE_DISPLAY")
BUILD_FINGERPRINT=$(v0232_fingerprint "$CONFIGURE_FINGERPRINT" 'make -j1' 'SOURCE_DATE_EPOCH=0')
INSTALL_FINGERPRINT=$(v0232_fingerprint "$BUILD_FINGERPRINT" "$PREFIX" 'make -j1 install')
SMOKE_FINGERPRINT=$(v0232_fingerprint "$INSTALL_FINGERPRINT" 'ELF32; release-banner; GPL-codecs; no-nonfree')
STATIC_FINGERPRINT=$(v0232_fingerprint "$SMOKE_FINGERPRINT" "$(v0232_sha256 "$SCRIPT_DIR/verify-v0232-ffmpeg-i686.sh")")
INFO_FINGERPRINT=$(v0232_fingerprint "$STATIC_FINGERPRINT" "$PACKAGE_VERSIONS" "$PKG_MODULE_VERSIONS")
ARCHIVE_FINGERPRINT=$(v0232_fingerprint "$INFO_FINGERPRINT" 'tar --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -cJf')

v0232_checkpoint "$STATE" configure "$CONFIGURE_FINGERPRINT" "$BUILD/Makefile" configure_build
v0232_checkpoint "$STATE" compile "$BUILD_FINGERPRINT" "$BUILD/ffmpeg" compile_build
v0232_checkpoint "$STATE" install "$INSTALL_FINGERPRINT" "$PREFIX/bin/ffmpeg" install_build
v0232_checkpoint "$STATE" smoke "$SMOKE_FINGERPRINT" "$RESULTS/smoke-check.txt" run_smoke_checks
static_verify() {
  FFMPEG_SOURCE_COMMIT="$SOURCE_COMMIT" \
    "$SCRIPT_DIR/verify-v0232-ffmpeg-i686.sh" --static-only \
    "$PREFIX/bin/ffmpeg" "$PREFIX/bin/ffprobe" "$RESULTS/static-verification"
}
v0232_checkpoint "$STATE" static-verify "$STATIC_FINGERPRINT" "$STATIC_REPORT" static_verify
v0232_checkpoint "$STATE" build-info "$INFO_FINGERPRINT" "$BUILD_INFO" write_build_info
create_archive() {
  [[ ! -L "$ARCHIVE" ]] || v0232_die "refusing symlinked package output: $ARCHIVE"
  tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    --format=posix -cJf "$ARCHIVE" -C "$PREFIX" .
  v0232_sha256 "$ARCHIVE" >"$ARCHIVE_DIGEST.tmp"
  mv -f -- "$ARCHIVE_DIGEST.tmp" "$ARCHIVE_DIGEST"
}
v0232_checkpoint "$STATE" package "$ARCHIVE_FINGERPRINT" "$ARCHIVE" create_archive
[[ -f "$ARCHIVE_DIGEST" ]] || v0232_die 'package checkpoint is missing its recorded archive digest'
ARCHIVE_SHA256=$(v0232_sha256 "$ARCHIVE")
[[ "$ARCHIVE_SHA256" == "$(<"$ARCHIVE_DIGEST")" ]] || \
  v0232_die 'packaged archive digest changed since the checkpoint; use a new build root'
sha256sum -- "$ARCHIVE" >"$RESULTS/$(basename "$ARCHIVE").sha256"
v0232_log "FFmpeg $VERSION source build completed; local artifact=$ARCHIVE"
v0232_log "artifact SHA-256: $ARCHIVE_SHA256"
v0232_log "build evidence: $BUILD_INFO"
