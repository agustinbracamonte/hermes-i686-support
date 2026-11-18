#!/usr/bin/env bash
# Serial, checkpointed Node.js 26.12.1 source build for Linux i686 userspace.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/v0232-i686-build-common.sh
source "$SCRIPT_DIR/v0232-i686-build-common.sh"
# shellcheck source=scripts/v0232-node-toolchain.sh
source "$SCRIPT_DIR/v0232-node-toolchain.sh"

readonly VERSION=26.12.1
readonly I686_PATCH="$SCRIPT_DIR/../patches/node-v26.12.1-i686-build-fixes.patch"
readonly RANGES_PATCH="$SCRIPT_DIR/../patches/node-v26.12.1-i686-ranges-compat.patch"
readonly BIT_CAST_PATCH="$SCRIPT_DIR/../patches/node-v26.12.1-i686-bit-cast-compat.patch"
readonly OSSTREAM_PATCH="$SCRIPT_DIR/../patches/node-v26.12.1-i686-ostringstream-rvalue-compat.patch"
readonly MEMORY_SPAN_PATCH="$SCRIPT_DIR/../patches/node-v26.12.1-i686-v8-memory-span-compat.patch"
readonly I686_PATCH_SHA256=$(v0232_sha256 "$I686_PATCH")
readonly RANGES_PATCH_SHA256=$(v0232_sha256 "$RANGES_PATCH")
readonly BIT_CAST_PATCH_SHA256=$(v0232_sha256 "$BIT_CAST_PATCH")
readonly OSSTREAM_PATCH_SHA256=$(v0232_sha256 "$OSSTREAM_PATCH")
readonly MEMORY_SPAN_PATCH_SHA256=$(v0232_sha256 "$MEMORY_SPAN_PATCH")
readonly PATCH_SET_FINGERPRINT=$(v0232_fingerprint "$I686_PATCH_SHA256" "$RANGES_PATCH_SHA256" "$BIT_CAST_PATCH_SHA256" "$OSSTREAM_PATCH_SHA256" "$MEMORY_SPAN_PATCH_SHA256")
readonly SOURCE_URL=https://nodejs.org/dist/v26.12.1/node-v26.12.1.tar.xz
readonly SOURCE_SHA256=053e3b296859b6d8d93f99ef97fa9cec1c4ee171c72968100c649978c1dbd38c
readonly SOURCE_SHASUMS=https://nodejs.org/dist/v26.12.1/SHASUMS256.txt
readonly SOURCE_COMMIT=bc2e01dcf6acd5cf7d169b5f26cf89abaaeb41f1
readonly CXX_HEADERS_PACKAGE=libstdc++-11-dev
readonly CXX_HEADERS_VERSION=11.3.0-12
readonly CXX_HEADERS_ARCH=i386
readonly CXX_HEADERS_URL=https://deb.debian.org/debian/pool/main/g/gcc-11/libstdc++-11-dev_11.3.0-12_i386.deb
readonly CXX_HEADERS_SHA256=8402d1e5e1f09308fd5273b5554476c8ee6fc55c984ef2fe55f46ef7b117f58c
readonly SOURCE_LOCATION_FIXTURE="$SCRIPT_DIR/../tests/fixtures/node-source-location.cpp"
readonly RANGES_FIXTURE="$SCRIPT_DIR/../tests/fixtures/node-ranges-split-compat.cpp"
readonly BIT_CAST_FIXTURE="$SCRIPT_DIR/../tests/fixtures/node-bit-cast-compat.cpp"
readonly OSSTREAM_FIXTURE="$SCRIPT_DIR/../tests/fixtures/node-ostringstream-rvalue-compat.cpp"
readonly MEMORY_SPAN_FIXTURE="$SCRIPT_DIR/../tests/fixtures/node-v8-memory-span-compat.cpp"
readonly SCRIPT_FINGERPRINT=$(v0232_fingerprint \
  "$(v0232_sha256 "$0")" \
  "$(v0232_sha256 "$SCRIPT_DIR/v0232-i686-build-common.sh")" \
  "$(v0232_sha256 "$SCRIPT_DIR/v0232-node-toolchain.sh")" \
  "$(v0232_sha256 "$SOURCE_LOCATION_FIXTURE")" \
  "$(v0232_sha256 "$RANGES_FIXTURE")" \
  "$(v0232_sha256 "$BIT_CAST_FIXTURE")" \
  "$(v0232_sha256 "$OSSTREAM_FIXTURE")" \
  "$(v0232_sha256 "$MEMORY_SPAN_FIXTURE")" \
  "$I686_PATCH_SHA256" \
  "$RANGES_PATCH_SHA256" \
  "$BIT_CAST_PATCH_SHA256" \
  "$OSSTREAM_PATCH_SHA256" \
  "$MEMORY_SPAN_PATCH_SHA256")

MODE=build
case "${1:-}" in
  --help|-h)
    cat <<'HELP'
Usage: build-node-v0232-i686.sh [--preflight-only|--prepare-only]

Builds Node.js 26.12.1 in a native Linux i686 userspace, serially, with
resumable checkpoints. Build CPython 3.14.9 first; its i686 interpreter is the
Node build's Python prerequisite. Default build root: $HERMES_I686_BUILD_ROOT
or .work/v0232-i686.

--preflight-only  Check native process ABI, SSE2 support, compiler and tools.
--prepare-only    Fetch/verify/extract pinned Node sources without building.

Optional inputs: HERMES_I686_BUILD_ROOT, NODE_SOURCE_ARCHIVE, CPYTHON_PREFIX,
CC, CXX, JOBS=1. GCC >=13.2 or Clang >=19.1 and GNU Make are required by the
pinned upstream build guide. C and C++ compilers must use the same family,
version, and Linux i686 target. The CPU must support SSE2. For C++20's
<source_location>, this recipe extracts (does not install) a hash-pinned
Debian GCC 11 i386 header package and keeps linking to the Bullseye runtime.
The Node 26 x86 target is upstream Experimental.
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
CXX_BIN=${CXX:-g++}

check_compiler() {
  v0232_assert_i686_process
  # Node's pinned zlib.gyp enables its SSE2 slide-hash implementation for ia32.
  v0232_require_cpu_feature sse2
  v0232_node_check_compiler_pair "$CC_BIN" "$CXX_BIN" >/dev/null
}

if [[ "$MODE" == preflight ]]; then
  v0232_need awk flock ld make readelf sha256sum sort tar
  command -v "$CC_BIN" >/dev/null 2>&1 || v0232_die "missing C compiler: $CC_BIN"
  command -v "$CXX_BIN" >/dev/null 2>&1 || v0232_die "missing C++ compiler: $CXX_BIN"
  check_compiler
  v0232_log "preflight passed (CC=$CC_BIN, CXX=$CXX_BIN, make=$(make --version | head -1))"
  exit 0
fi

v0232_need awk curl flock sha256sum tar
if [[ "$MODE" == build ]]; then
  v0232_need diff dpkg-deb dpkg-query ld ldd make mktemp patch paste readelf readlink sort
  command -v "$CC_BIN" >/dev/null 2>&1 || v0232_die "missing C compiler: $CC_BIN"
  command -v "$CXX_BIN" >/dev/null 2>&1 || v0232_die "missing C++ compiler: $CXX_BIN"
  check_compiler
fi

ROOT=${HERMES_I686_BUILD_ROOT:-"$PWD/.work/v0232-i686"}
[[ "$ROOT" != *" "* ]] || v0232_die "Node build paths cannot contain spaces: $ROOT"
mkdir -p "$ROOT"
ROOT=$(cd "$ROOT" && pwd)
STATE="$ROOT/state/node-$VERSION"
DOWNLOADS="$ROOT/downloads"
SOURCE="$ROOT/src/node-v$VERSION"
BUILD="$SOURCE"
PREFIX=${NODE_PREFIX:-"$ROOT/prefix/node-$VERSION"}
CPYTHON_PREFIX=${CPYTHON_PREFIX:-"$ROOT/prefix/cpython-3.14.9"}
NODE_SOURCE_ARCHIVE=${NODE_SOURCE_ARCHIVE:-"$DOWNLOADS/node-v$VERSION.tar.xz"}
RESULTS="$ROOT/results"
TOOLCHAIN_ROOT="$ROOT/toolchain"
CXX_HEADERS_DEB="$DOWNLOADS/${CXX_HEADERS_PACKAGE}_${CXX_HEADERS_VERSION}_${CXX_HEADERS_ARCH}.deb"
CXX_HEADERS_ROOT="$TOOLCHAIN_ROOT/${CXX_HEADERS_PACKAGE}-${CXX_HEADERS_VERSION}"
CXX_HEADERS_INCLUDE="$CXX_HEADERS_ROOT/usr/include/c++/11"
CXX_SOURCE_LOCATION_OVERLAY="$TOOLCHAIN_ROOT/source-location-overlay-gcc-11"
mkdir -p "$STATE" "$DOWNLOADS" "$(dirname "$SOURCE")" "$PREFIX" "$RESULTS" "$TOOLCHAIN_ROOT"
v0232_build_lock "$ROOT"

verify_source_archive() {
  local actual
  actual=$(v0232_sha256 "$NODE_SOURCE_ARCHIVE")
  [[ "$actual" == "$SOURCE_SHA256" ]] || v0232_die "Node source SHA-256 mismatch: $actual (expected $SOURCE_SHA256); keep the file for inspection and use a clean archive path"
  tar -tJf "$NODE_SOURCE_ARCHIVE" | awk -v expected="node-v$VERSION/configure" '$0 == expected { found=1 } END { exit !found }' || v0232_die "Node source archive has an unexpected root/layout"
  tar -tJf "$NODE_SOURCE_ARCHIVE" | awk -v expected="node-v$VERSION/deps/icu-small/README-FULL-ICU.txt" '$0 == expected { found=1 } END { exit !found }' || v0232_die "Node source archive is missing its pinned full ICU sources"
}

download_source() {
  mkdir -p "$(dirname "$NODE_SOURCE_ARCHIVE")"
  if [[ ! -f "$NODE_SOURCE_ARCHIVE" ]]; then
    local partial="$NODE_SOURCE_ARCHIVE.part.$$"
    rm -f -- "$partial"
    curl --fail --location --retry 3 --retry-delay 2 "$SOURCE_URL" -o "$partial"
    mv -- "$partial" "$NODE_SOURCE_ARCHIVE"
  fi
  verify_source_archive
}

extract_source() {
  [[ ! -e "$SOURCE" ]] || v0232_die "source destination exists without a source checkpoint: $SOURCE"
  local temporary
  temporary=$(mktemp -d "$ROOT/src/.node-$VERSION.extracting.XXXXXX")
  tar -xJf "$NODE_SOURCE_ARCHIVE" --strip-components=1 -C "$temporary"
  [[ -x "$temporary/configure" ]] || v0232_die "extracted Node source has no configure script"
  [[ -f "$temporary/deps/icu-small/README-FULL-ICU.txt" ]] || v0232_die "extracted Node source has no full ICU tree"
  mv -- "$temporary" "$SOURCE"
}

ARCHIVE_FINGERPRINT=$(v0232_fingerprint "$SOURCE_URL" "$SOURCE_SHA256" "$SCRIPT_FINGERPRINT")
v0232_checkpoint "$STATE" source-archive "$ARCHIVE_FINGERPRINT" "$NODE_SOURCE_ARCHIVE" download_source
verify_source_archive
SOURCE_FINGERPRINT=$(v0232_fingerprint "$ARCHIVE_FINGERPRINT" "$(v0232_sha256 "$NODE_SOURCE_ARCHIVE")" "$VERSION")
v0232_checkpoint "$STATE" extract "$SOURCE_FINGERPRINT" "$SOURCE/configure" extract_source
if [[ "$MODE" == prepare ]]; then
  v0232_log "verified Node $VERSION source: archive sha256=$SOURCE_SHA256, upstream tag commit=$SOURCE_COMMIT"
  exit 0
fi

verify_cxx_headers_package() {
  local actual package version architecture
  [[ -f "$CXX_HEADERS_DEB" ]] || v0232_die "missing pinned C++ header package: $CXX_HEADERS_DEB"
  actual=$(v0232_sha256 "$CXX_HEADERS_DEB")
  [[ "$actual" == "$CXX_HEADERS_SHA256" ]] || \
    v0232_die "C++ header package SHA-256 mismatch: $actual (expected $CXX_HEADERS_SHA256)"
  package=$(dpkg-deb -f "$CXX_HEADERS_DEB" Package)
  version=$(dpkg-deb -f "$CXX_HEADERS_DEB" Version)
  architecture=$(dpkg-deb -f "$CXX_HEADERS_DEB" Architecture)
  [[ "$package" == "$CXX_HEADERS_PACKAGE" && "$version" == "$CXX_HEADERS_VERSION" && "$architecture" == "$CXX_HEADERS_ARCH" ]] || \
    v0232_die "unexpected C++ header package identity: $package=$version/$architecture"
}

download_cxx_headers_package() {
  if [[ ! -f "$CXX_HEADERS_DEB" ]]; then
    local partial="$CXX_HEADERS_DEB.part.$$" actual
    rm -f -- "$partial"
    curl --fail --location --retry 3 --retry-delay 2 "$CXX_HEADERS_URL" -o "$partial"
    actual=$(v0232_sha256 "$partial")
    if [[ "$actual" != "$CXX_HEADERS_SHA256" ]]; then
      rm -f -- "$partial"
      v0232_die "downloaded C++ header package SHA-256 mismatch: $actual (expected $CXX_HEADERS_SHA256)"
    fi
    mv -- "$partial" "$CXX_HEADERS_DEB"
  fi
  verify_cxx_headers_package
}

extract_cxx_headers_package() {
  local temporary
  temporary=$(mktemp -d "$TOOLCHAIN_ROOT/.${CXX_HEADERS_PACKAGE}.extracting.XXXXXX")
  if ! dpkg-deb -x "$CXX_HEADERS_DEB" "$temporary"; then
    rm -rf -- "$temporary"
    v0232_die "failed to extract the pinned C++ header package"
  fi
  if [[ ! -s "$temporary/usr/include/c++/11/source_location" ]]; then
    rm -rf -- "$temporary"
    v0232_die "pinned C++ header package is missing its source_location header"
  fi
  if [[ -e "$CXX_HEADERS_ROOT" ]]; then
    if [[ ! -d "$CXX_HEADERS_ROOT" || -L "$CXX_HEADERS_ROOT" ]]; then
      rm -rf -- "$temporary"
      v0232_die "C++ header extraction destination is not a directory: $CXX_HEADERS_ROOT"
    fi
    if diff -qr "$CXX_HEADERS_ROOT" "$temporary" >/dev/null; then
      rm -rf -- "$temporary"
      v0232_log "reconciled complete C++ header extraction after an interrupted checkpoint"
      return 0
    fi
    rm -rf -- "$temporary"
    v0232_die "existing C++ header extraction differs from the pinned package; use a new build root: $CXX_HEADERS_ROOT"
  fi
  mv -- "$temporary" "$CXX_HEADERS_ROOT"
}

verify_cxx_headers_tree() {
  [[ -s "$CXX_HEADERS_INCLUDE/source_location" ]] || v0232_die "missing extracted <source_location> header"
}

prepare_source_location_overlay() {
  local temporary
  [[ -s "$CXX_HEADERS_INCLUDE/source_location" ]] || \
    v0232_die "missing pinned GCC 11 source_location header"
  if [[ -e "$CXX_SOURCE_LOCATION_OVERLAY" || -L "$CXX_SOURCE_LOCATION_OVERLAY" ]]; then
    [[ -d "$CXX_SOURCE_LOCATION_OVERLAY" && ! -L "$CXX_SOURCE_LOCATION_OVERLAY" ]] || \
      v0232_die "source_location overlay is not a regular directory: $CXX_SOURCE_LOCATION_OVERLAY"
    if diff -q "$CXX_SOURCE_LOCATION_OVERLAY/source_location" \
        "$CXX_HEADERS_INCLUDE/source_location" >/dev/null; then
      v0232_log "reused verified source_location-only header overlay"
      return 0
    fi
    v0232_die "existing source_location overlay differs from the pinned package; use a new build root"
  fi
  temporary=$(mktemp -d "$TOOLCHAIN_ROOT/.source-location-overlay.XXXXXX")
  if ! install -m 0644 "$CXX_HEADERS_INCLUDE/source_location" "$temporary/source_location"; then
    rm -rf -- "$temporary"
    v0232_die "failed to create source_location-only header overlay"
  fi
  if ! mv -- "$temporary" "$CXX_SOURCE_LOCATION_OVERLAY"; then
    rm -rf -- "$temporary"
    v0232_die "failed to install source_location-only header overlay"
  fi
}

verify_source_location_overlay() {
  [[ -d "$CXX_SOURCE_LOCATION_OVERLAY" && ! -L "$CXX_SOURCE_LOCATION_OVERLAY" ]] || \
    v0232_die "missing source_location-only header overlay"
  diff -q "$CXX_SOURCE_LOCATION_OVERLAY/source_location" \
    "$CXX_HEADERS_INCLUDE/source_location" >/dev/null || \
    v0232_die "source_location overlay does not match the pinned package header"
}

CXX_HEADERS_PACKAGE_FINGERPRINT=$(v0232_fingerprint "$CXX_HEADERS_PACKAGE" "$CXX_HEADERS_VERSION" "$CXX_HEADERS_ARCH" "$CXX_HEADERS_URL" "$CXX_HEADERS_SHA256" "$SCRIPT_FINGERPRINT")
v0232_checkpoint "$STATE" cxx-headers-package "$CXX_HEADERS_PACKAGE_FINGERPRINT" "$CXX_HEADERS_DEB" download_cxx_headers_package
verify_cxx_headers_package
CXX_HEADERS_TREE_FINGERPRINT=$(v0232_fingerprint "$CXX_HEADERS_PACKAGE_FINGERPRINT" "$SOURCE_FINGERPRINT" "$CXX_HEADERS_SHA256")
v0232_checkpoint "$STATE" cxx-headers-extract "$CXX_HEADERS_TREE_FINGERPRINT" "$CXX_HEADERS_INCLUDE/source_location" extract_cxx_headers_package
verify_cxx_headers_tree
CXX_SOURCE_LOCATION_OVERLAY_FINGERPRINT=$(v0232_fingerprint "$CXX_HEADERS_TREE_FINGERPRINT" "$CXX_HEADERS_SHA256" "$SCRIPT_FINGERPRINT")
v0232_checkpoint "$STATE" source-location-overlay "$CXX_SOURCE_LOCATION_OVERLAY_FINGERPRINT" "$CXX_SOURCE_LOCATION_OVERLAY/source_location" prepare_source_location_overlay
verify_source_location_overlay
CXX_HEADER_FLAGS=(-isystem "$CXX_SOURCE_LOCATION_OVERLAY")

verify_cxx_header_selection() {
  local trace="$RESULTS/node-cxx-header-selection.trace"
  local report="$RESULTS/node-cxx-header-selection.txt"
  local vector_header vector_header_resolved
  if ! printf '#include <source_location>\n#include <vector>\n' | \
      "$CXX_BIN" -std=c++20 -H "${CXX_HEADER_FLAGS[@]}" -x c++ -fsyntax-only - \
      >/dev/null 2>"$trace"; then
    printf 'C++ standard-library selection trace (compiler probe failed):\n' >&2
    cat "$trace" >&2
    v0232_die "failed to compile the source_location/Bullseye-header selection probe"
  fi
  grep -Fq "$CXX_SOURCE_LOCATION_OVERLAY/source_location" "$trace" || \
    { printf 'C++ standard-library selection trace (source_location overlay missing):\n' >&2; cat "$trace" >&2; v0232_die "Clang did not select the pinned source_location-only overlay"; }
  v0232_node_trace_has_gcc10_vector "$trace" || \
    { printf 'C++ standard-library selection trace (Bullseye vector header missing):\n' >&2; cat "$trace" >&2; v0232_die "Clang did not retain Bullseye GCC 10 standard-library headers"; }
  if grep -Fq "$CXX_HEADERS_ROOT/usr/include/c++/11/" "$trace"; then
    printf 'C++ standard-library selection trace (unexpected GCC 11 headers):\n' >&2
    cat "$trace" >&2
    v0232_die "Clang selected a GCC 11 standard-library header outside the source_location overlay"
  fi
  vector_header=$(awk '$NF ~ /\/vector$/ { print $NF; exit }' "$trace")
  vector_header_resolved=$(readlink -f -- "$vector_header")
  {
    printf 'source_location_overlay=%s/source_location\n' "$CXX_SOURCE_LOCATION_OVERLAY"
    printf 'bullseye_standard_library_header=%s\n' "$vector_header"
    printf 'bullseye_standard_library_header_resolved=%s\n' "$vector_header_resolved"
    grep -F "$CXX_SOURCE_LOCATION_OVERLAY/source_location" "$trace"
  } >"$report.tmp"
  mv -f -- "$report.tmp" "$report"
  cat "$report"
}

apply_i686_build_patches() {
  apply_one_i686_patch() {
    local patch_file=$1
    if patch --silent --dry-run --reverse --fuzz=0 -p1 -d "$SOURCE" <"$patch_file" >/dev/null 2>&1; then
      v0232_log "$(basename "$patch_file") is already applied"
      return 0
    fi
    patch --silent --batch --forward --fuzz=0 -p1 -d "$SOURCE" <"$patch_file"
  }

  apply_one_i686_patch "$I686_PATCH"
  apply_one_i686_patch "$RANGES_PATCH"
  apply_one_i686_patch "$BIT_CAST_PATCH"
  apply_one_i686_patch "$OSSTREAM_PATCH"
  apply_one_i686_patch "$MEMORY_SPAN_PATCH"
}

PATCH_FINGERPRINT=$(v0232_fingerprint "$SOURCE_FINGERPRINT" "$PATCH_SET_FINGERPRINT")
v0232_checkpoint "$STATE" node-i686-build-patches "$PATCH_FINGERPRINT" "$SOURCE/deps/openssl/openssl.gyp" apply_i686_build_patches

NODE_PYTHON="$CPYTHON_PREFIX/bin/python3.14"
[[ -x "$NODE_PYTHON" ]] || v0232_die "build CPython 3.14.9 i686 first; missing $NODE_PYTHON"
PY_INFO=$("$NODE_PYTHON" -I -c 'import struct,sys; print(".".join(map(str,sys.version_info[:3])) + " " + str(struct.calcsize("P") * 8))')
[[ "$PY_INFO" == '3.14.9 32' ]] || v0232_die "Node build Python must be CPython 3.14.9 i686 (found $PY_INFO)"

probe_source_location() {
  local probe_binary="$ROOT/tmp/node-source-location-probe"
  local probe_report="$RESULTS/node-source-location-probe.txt"
  mkdir -p "$(dirname "$probe_binary")"
  "$CXX_BIN" -std=c++20 -O2 -Wall -Wextra -Werror "${CXX_HEADER_FLAGS[@]}" \
    "$SOURCE_LOCATION_FIXTURE" -o "$probe_binary"
  v0232_assert_i686_elf "$probe_binary"
  "$probe_binary" >"$probe_report"
  rm -f -- "$probe_binary"
  {
    printf 'package=%s=%s\npackage_arch=%s\npackage_sha256=%s\n' "$CXX_HEADERS_PACKAGE" "$CXX_HEADERS_VERSION" "$CXX_HEADERS_ARCH" "$CXX_HEADERS_SHA256"
    printf 'source_location_overlay=%s\ncompiler=%s\n' "$CXX_SOURCE_LOCATION_OVERLAY" "$CXX_INFO"
    cat "$probe_report"
  } >"$probe_report.tmp"
  mv -f -- "$probe_report.tmp" "$probe_report"
  cat "$probe_report"
}

probe_ranges_split() {
  local probe_binary="$ROOT/tmp/node-ranges-split-probe"
  local probe_report="$RESULTS/node-ranges-split-probe.txt"
  mkdir -p "$(dirname "$probe_binary")"
  "$CXX_BIN" -std=c++20 -O2 -Wall -Wextra -Werror "${CXX_HEADER_FLAGS[@]}" \
    "$RANGES_FIXTURE" -o "$probe_binary"
  v0232_assert_i686_elf "$probe_binary"
  "$probe_binary" >"$probe_report"
  grep -Fxq 'ranges_split_view=PASS' "$probe_report" || \
    v0232_die "Node's GCC 10 ranges split compatibility probe returned unexpected output"
  rm -f -- "$probe_binary"
  {
    printf 'compiler=%s\nnode_i686_build_patch_sha256=%s\nnode_ranges_compat_patch_sha256=%s\nnode_patch_set_fingerprint=%s\n' \
      "$CXX_INFO" "$I686_PATCH_SHA256" "$RANGES_PATCH_SHA256" "$PATCH_SET_FINGERPRINT"
    cat "$probe_report"
  } >"$probe_report.tmp"
  mv -f -- "$probe_report.tmp" "$probe_report"
  cat "$probe_report"
}

probe_bit_cast() {
  local probe_binary="$ROOT/tmp/node-bit-cast-probe"
  local probe_report="$RESULTS/node-bit-cast-probe.txt"
  mkdir -p "$(dirname "$probe_binary")"
  "$CXX_BIN" -std=c++20 -O2 -Wall -Wextra -Werror "${CXX_HEADER_FLAGS[@]}" \
    "$BIT_CAST_FIXTURE" -o "$probe_binary"
  v0232_assert_i686_elf "$probe_binary"
  "$probe_binary"
  rm -f -- "$probe_binary"
  {
    printf 'compiler=%s\nnode_bit_cast_compat_patch_sha256=%s\nnode_patch_set_fingerprint=%s\n' \
      "$CXX_INFO" "$BIT_CAST_PATCH_SHA256" "$PATCH_SET_FINGERPRINT"
    printf 'node_bit_cast_probe=PASS\n'
  } >"$probe_report.tmp"
  mv -f -- "$probe_report.tmp" "$probe_report"
  cat "$probe_report"
}

probe_ostringstream_compat() {
  local probe_binary="$ROOT/tmp/node-ostringstream-rvalue-probe"
  local probe_report="$RESULTS/node-ostringstream-rvalue-probe.txt"
  mkdir -p "$(dirname "$probe_binary")"
  "$CXX_BIN" -std=c++20 -O2 -Wall -Wextra -Werror "${CXX_HEADER_FLAGS[@]}" \
    "$OSSTREAM_FIXTURE" -o "$probe_binary"
  v0232_assert_i686_elf "$probe_binary"
  "$probe_binary"
  rm -f -- "$probe_binary"
  {
    printf 'compiler=%s\nnode_ostringstream_compat_patch_sha256=%s\nnode_patch_set_fingerprint=%s\n' \
      "$CXX_INFO" "$OSSTREAM_PATCH_SHA256" "$PATCH_SET_FINGERPRINT"
    printf 'node_ostringstream_rvalue_compat_probe=PASS\n'
  } >"$probe_report.tmp"
  mv -f -- "$probe_report.tmp" "$probe_report"
  cat "$probe_report"
}

probe_memory_span_compat() {
  local probe_binary="$ROOT/tmp/node-v8-memory-span-probe"
  local probe_report="$RESULTS/node-v8-memory-span-probe.txt"
  mkdir -p "$(dirname "$probe_binary")"
  "$CXX_BIN" -std=c++20 -O2 -Wall -Wextra -Werror "${CXX_HEADER_FLAGS[@]}" \
    "$MEMORY_SPAN_FIXTURE" -o "$probe_binary"
  v0232_assert_i686_elf "$probe_binary"
  "$probe_binary" >"$probe_report"
  grep -Fxq 'memory_span_nonempty_copy=PASS' "$probe_report" || \
    v0232_die "Node's V8 memory-span nonempty copy probe returned unexpected output"
  grep -Fxq 'memory_span_empty_copy=PASS' "$probe_report" || \
    v0232_die "Node's V8 memory-span empty copy probe returned unexpected output"
  rm -f -- "$probe_binary"
  {
    printf 'compiler=%s\nnode_v8_memory_span_compat_patch_sha256=%s\nnode_patch_set_fingerprint=%s\n' \
      "$CXX_INFO" "$MEMORY_SPAN_PATCH_SHA256" "$PATCH_SET_FINGERPRINT"
    cat "$probe_report"
  } >"$probe_report.tmp"
  mv -f -- "$probe_report.tmp" "$probe_report"
  cat "$probe_report"
}

CC_INFO=$("$CC_BIN" --version | head -1)
CXX_INFO=$("$CXX_BIN" --version | head -1)
MAKE_INFO=$(make --version | head -1)
LD_INFO=$(ld --version | head -1)
check_cxx_runtime() {
  local linker_path
  linker_path=$("$CXX_BIN" -print-file-name=libstdc++.so)
  [[ "$linker_path" == /* && -e "$linker_path" ]] || \
    v0232_die "C++ compiler did not resolve an installed libstdc++.so linker input: $linker_path"
  CXX_RUNTIME_LIBSTDCPP_PATH=$(readlink -f "$linker_path")
  CXX_RUNTIME_PACKAGE_VERSION=$(dpkg-query -W -f='${Version}' libstdc++6)
  [[ "$CXX_RUNTIME_PACKAGE_VERSION" == 10.* ]] || \
    v0232_die "expected the Debian 11 libstdc++6 runtime from GCC 10, found $CXX_RUNTIME_PACKAGE_VERSION"
}
check_cxx_runtime
verify_cxx_header_selection
TOOLCHAIN_FINGERPRINT=$(v0232_fingerprint "$CC_INFO" "$CXX_INFO" "$MAKE_INFO" "$LD_INFO" "$PY_INFO" "$CXX_RUNTIME_LIBSTDCPP_PATH" "$CXX_RUNTIME_PACKAGE_VERSION" "$(uname -sr)" "$ROOT")
configure_build() {
  cd "$BUILD"
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u MAKEFLAGS -u CONFIG_SITE \
    LC_ALL=C TZ=UTC PATH="$(dirname "$NODE_PYTHON"):$PATH" PYTHON="$NODE_PYTHON" \
    CC="$CC_BIN" CXX="$CXX_BIN" CFLAGS='-O2 -g0' CXXFLAGS="-O2 -g0 ${CXX_HEADER_FLAGS[*]}" \
    "$SOURCE/configure" --prefix="$PREFIX" --dest-cpu=ia32 --with-intl=full-icu --openssl-no-asm
}

compile_build() {
  cd "$BUILD"
  env -u CFLAGS -u CPPFLAGS -u LDFLAGS -u CONFIG_SITE \
    LC_ALL=C TZ=UTC PATH="$(dirname "$NODE_PYTHON"):$PATH" PYTHON="$NODE_PYTHON" \
    CXXFLAGS="-O2 -g0 ${CXX_HEADER_FLAGS[*]}" \
    MAKEFLAGS= make -j1
}

install_build() {
  cd "$BUILD"
  env -u CFLAGS -u CPPFLAGS -u LDFLAGS -u CONFIG_SITE \
    LC_ALL=C TZ=UTC PATH="$(dirname "$NODE_PYTHON"):$PATH" PYTHON="$NODE_PYTHON" \
    CXXFLAGS="-O2 -g0 ${CXX_HEADER_FLAGS[*]}" \
    MAKEFLAGS= make -j1 install
}

smoke_test() {
  local node="$PREFIX/bin/node" npm_cli="$PREFIX/lib/node_modules/npm/bin/npm-cli.js" report="$RESULTS/node-$VERSION.txt"
  [[ -x "$node" ]] || v0232_die "missing installed Node binary: $node"
  [[ -f "$npm_cli" ]] || v0232_die "Node install is missing bundled npm: $npm_cli"
  v0232_assert_i686_elf "$node"
  [[ "$("$node" --version)" == "v$VERSION" ]] || v0232_die "installed Node reports an unexpected version"
  [[ "$("$node" -p 'process.arch')" == ia32 ]] || v0232_die "installed Node does not report process.arch=ia32"
  NODE_CXX_RUNTIME_PATH=$(ldd "$node" | awk '$1 == "libstdc++.so.6" && $2 == "=>" { print $3; exit }')
  [[ -n "$NODE_CXX_RUNTIME_PATH" && -e "$NODE_CXX_RUNTIME_PATH" ]] || \
    v0232_die "installed Node does not resolve its libstdc++.so.6 runtime dependency"
  NODE_CXX_RUNTIME_PATH=$(readlink -f "$NODE_CXX_RUNTIME_PATH")
  [[ "$NODE_CXX_RUNTIME_PATH" == "$CXX_RUNTIME_LIBSTDCPP_PATH" ]] || \
    v0232_die "Node resolved an unexpected C++ runtime: $NODE_CXX_RUNTIME_PATH (compiler linked against $CXX_RUNTIME_LIBSTDCPP_PATH)"
  NODE_GLIBCXX_REQUIREMENTS=$(readelf --version-info "$node" | awk '/Name: GLIBCXX_/ { sub(/^.*Name: /, ""); print $1 }' | sort -Vu | paste -sd, -)
  NODE_GLIBCXX_MAX=$(readelf --version-info "$node" | awk '/Name: GLIBCXX_/ { sub(/^.*Name: /, ""); print $1 }' | sort -V | tail -1)
  [[ -n "$NODE_GLIBCXX_MAX" ]] || v0232_die "Node has no recorded GLIBCXX runtime version requirements"
  if [[ "$NODE_GLIBCXX_MAX" =~ ^GLIBCXX_3\.4\.([0-9]+)$ ]]; then
    (( BASH_REMATCH[1] <= 28 )) || \
      v0232_die "Node requires $NODE_GLIBCXX_MAX, newer than Bullseye libstdc++6's GLIBCXX_3.4.28 ceiling"
  elif [[ "$NODE_GLIBCXX_MAX" != GLIBCXX_3.4 ]]; then
    v0232_die "unrecognized maximum Node GLIBCXX requirement: $NODE_GLIBCXX_MAX"
  fi
  local npm_version="$($node "$npm_cli" --version)"
  "$node" - <<'NODE'
const { Worker } = require('node:worker_threads');
if (process.arch !== 'ia32') throw new Error(`process.arch=${process.arch}`);
const memory = new WebAssembly.Memory({ initial: 256, maximum: 16384, shared: true });
if (!(memory.buffer instanceof SharedArrayBuffer)) throw new Error('shared WebAssembly memory unavailable');
const worker = new Worker('const { parentPort } = require("node:worker_threads"); parentPort.postMessage("worker-ok")', { eval: true });
worker.once('error', error => { console.error(error); process.exitCode = 1; });
worker.once('message', message => {
  if (message !== 'worker-ok') process.exitCode = 1;
  console.log(`wasm_shared_memory=${memory.buffer.byteLength}`);
  console.log(`worker_threads=${message}`);
  worker.terminate();
});
NODE
  "$node" - <<'NODE'
const locale = new Intl.DateTimeFormat('es-AR', { dateStyle: 'short' }).resolvedOptions().locale;
if (!locale.toLowerCase().startsWith('es')) throw new Error(`Spanish locale data unavailable: ${locale}`);
console.log(`intl_locale=${locale}`);
NODE
  {
    printf 'source_url=%s\nsource_sha256=%s\nsource_shasums=%s\nsource_tag_commit=%s\nnode_i686_build_patch_sha256=%s\nnode_ranges_compat_patch_sha256=%s\nnode_bit_cast_compat_patch_sha256=%s\nnode_ostringstream_compat_patch_sha256=%s\nnode_patch_set_fingerprint=%s\n' \
      "$SOURCE_URL" "$SOURCE_SHA256" "$SOURCE_SHASUMS" "$SOURCE_COMMIT" \
      "$I686_PATCH_SHA256" "$RANGES_PATCH_SHA256" "$BIT_CAST_PATCH_SHA256" "$OSSTREAM_PATCH_SHA256" "$PATCH_SET_FINGERPRINT"
    printf 'node_v8_memory_span_compat_patch_sha256=%s\n' "$MEMORY_SPAN_PATCH_SHA256"
    printf 'cxx_headers_package=%s=%s\ncxx_headers_arch=%s\ncxx_headers_url=%s\ncxx_headers_sha256=%s\ncxx_headers_metadata=Debian Bookworm signed main i386 Packages index\n' "$CXX_HEADERS_PACKAGE" "$CXX_HEADERS_VERSION" "$CXX_HEADERS_ARCH" "$CXX_HEADERS_URL" "$CXX_HEADERS_SHA256"
    printf 'cxx_headers_runtime_policy=extracted headers only; no GCC 11 runtime installed\nsource_location_probe=PASS; pointer-sized std::source_location; caller file/function/line checked\n'
    printf 'compiler_libstdcxx_path=%s\nruntime_libstdcxx_package=libstdc++6=%s\nnode_libstdcxx_path=%s\nnode_glibcxx_requirements=%s\nnode_glibcxx_max=%s\n' "$CXX_RUNTIME_LIBSTDCPP_PATH" "$CXX_RUNTIME_PACKAGE_VERSION" "$NODE_CXX_RUNTIME_PATH" "$NODE_GLIBCXX_REQUIREMENTS" "$NODE_GLIBCXX_MAX"
    printf 'compiler=%s\ncxx=%s\nmake=%s\nlinker=%s\npython=%s\n' "$CC_INFO" "$CXX_INFO" "$MAKE_INFO" "$LD_INFO" "$PY_INFO"
    printf 'toolchain_fingerprint=%s\nscript_sha256=%s\nnode_elf=' "$TOOLCHAIN_FINGERPRINT" "$SCRIPT_FINGERPRINT"
    v0232_elf_identity "$node"
    printf 'node_version=%s\nnode_arch=%s\nnpm_version=%s\nnode_sha256=%s\ntarget_cpu_features=sse2\nopenssl_asm=disabled\nintl=full-icu;locale=es-AR\nwasm_shared_memory=1GiB-maximum\nworker_threads=PASS\n' "$($node --version)" "$($node -p 'process.arch')" "$npm_version" "$(v0232_sha256 "$node")"
  } >"$report"
}

SOURCE_LOCATION_FINGERPRINT=$(v0232_fingerprint "$CXX_HEADERS_TREE_FINGERPRINT" "$CXX_HEADERS_SHA256" "$CXX_INFO" "$CXX_RUNTIME_LIBSTDCPP_PATH" "$CXX_RUNTIME_PACKAGE_VERSION" "${CXX_HEADER_FLAGS[*]}" "$(v0232_sha256 "$SOURCE_LOCATION_FIXTURE")")
v0232_checkpoint "$STATE" source-location-probe "$SOURCE_LOCATION_FINGERPRINT" "$RESULTS/node-source-location-probe.txt" probe_source_location
RANGES_FINGERPRINT=$(v0232_fingerprint "$PATCH_SET_FINGERPRINT" "$CXX_INFO" "$CXX_RUNTIME_LIBSTDCPP_PATH" "${CXX_HEADER_FLAGS[*]}" "$(v0232_sha256 "$RANGES_FIXTURE")")
v0232_checkpoint "$STATE" ranges-split-probe "$RANGES_FINGERPRINT" "$RESULTS/node-ranges-split-probe.txt" probe_ranges_split
BIT_CAST_FINGERPRINT=$(v0232_fingerprint "$PATCH_SET_FINGERPRINT" "$CXX_INFO" "$CXX_RUNTIME_LIBSTDCPP_PATH" "${CXX_HEADER_FLAGS[*]}" "$(v0232_sha256 "$BIT_CAST_FIXTURE")")
v0232_checkpoint "$STATE" bit-cast-probe "$BIT_CAST_FINGERPRINT" "$RESULTS/node-bit-cast-probe.txt" probe_bit_cast
OSSTREAM_FINGERPRINT=$(v0232_fingerprint "$PATCH_SET_FINGERPRINT" "$CXX_INFO" "$CXX_RUNTIME_LIBSTDCPP_PATH" "${CXX_HEADER_FLAGS[*]}" "$(v0232_sha256 "$OSSTREAM_FIXTURE")")
v0232_checkpoint "$STATE" ostringstream-rvalue-probe "$OSSTREAM_FINGERPRINT" "$RESULTS/node-ostringstream-rvalue-probe.txt" probe_ostringstream_compat
MEMORY_SPAN_FINGERPRINT=$(v0232_fingerprint "$PATCH_SET_FINGERPRINT" "$CXX_INFO" "$CXX_RUNTIME_LIBSTDCPP_PATH" "${CXX_HEADER_FLAGS[*]}" "$(v0232_sha256 "$MEMORY_SPAN_FIXTURE")")
v0232_checkpoint "$STATE" v8-memory-span-probe "$MEMORY_SPAN_FINGERPRINT" "$RESULTS/node-v8-memory-span-probe.txt" probe_memory_span_compat
CONFIG_FINGERPRINT=$(v0232_fingerprint "$SOURCE_FINGERPRINT" "$PATCH_FINGERPRINT" "$TOOLCHAIN_FINGERPRINT" "$CXX_HEADERS_TREE_FINGERPRINT" "$SOURCE_LOCATION_FINGERPRINT" "$RANGES_FINGERPRINT" "$BIT_CAST_FINGERPRINT" "$OSSTREAM_FINGERPRINT" "$MEMORY_SPAN_FINGERPRINT" "$SCRIPT_FINGERPRINT" "$PREFIX" "$PY_INFO" "CC=$CC_BIN" "CXX=$CXX_BIN" 'CFLAGS=-O2 -g0' "CXXFLAGS=-O2 -g0 ${CXX_HEADER_FLAGS[*]}" '--dest-cpu=ia32' '--with-intl=full-icu' '--openssl-no-asm')
BUILD_FINGERPRINT=$(v0232_fingerprint "$CONFIG_FINGERPRINT" 'make -j1')
INSTALL_FINGERPRINT=$(v0232_fingerprint "$BUILD_FINGERPRINT" "$PREFIX" 'make -j1 install')
SMOKE_FINGERPRINT=$(v0232_fingerprint "$INSTALL_FINGERPRINT" 'ELF32; Node; npm; WebAssembly shared-memory; worker_threads; es-AR Intl')

v0232_checkpoint "$STATE" configure "$CONFIG_FINGERPRINT" "$SOURCE/config.gypi" configure_build
v0232_checkpoint "$STATE" compile "$BUILD_FINGERPRINT" "$SOURCE/out/Release/node" compile_build
v0232_checkpoint "$STATE" install "$INSTALL_FINGERPRINT" "$PREFIX/bin/node" install_build
v0232_checkpoint "$STATE" smoke "$SMOKE_FINGERPRINT" "$RESULTS/node-$VERSION.txt" smoke_test
v0232_log "Node $VERSION i686 build and smoke checks passed; see $RESULTS/node-$VERSION.txt"
