#!/usr/bin/env bash
# Serial, checkpointed Node.js 26.12.1 source build for Linux i686 userspace.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/v0232-i686-build-common.sh
source "$SCRIPT_DIR/v0232-i686-build-common.sh"

readonly VERSION=26.12.1
readonly SOURCE_URL=https://nodejs.org/dist/v26.12.1/node-v26.12.1.tar.xz
readonly SOURCE_SHA256=053e3b296859b6d8d93f99ef97fa9cec1c4ee171c72968100c649978c1dbd38c
readonly SOURCE_SHASUMS=https://nodejs.org/dist/v26.12.1/SHASUMS256.txt
readonly SOURCE_COMMIT=bc2e01dcf6acd5cf7d169b5f26cf89abaaeb41f1
readonly SCRIPT_FINGERPRINT=$(v0232_fingerprint "$(v0232_sha256 "$0")" "$(v0232_sha256 "$SCRIPT_DIR/v0232-i686-build-common.sh")")

MODE=build
case "${1:-}" in
  --help|-h)
    cat <<'HELP'
Usage: build-node-v0232-i686.sh [--preflight-only|--prepare-only]

Builds Node.js 26.12.1 in a native Linux i686 userspace, serially, with
resumable checkpoints. Build CPython 3.14.9 first; its i686 interpreter is the
Node build's Python prerequisite. Default build root: $HERMES_I686_BUILD_ROOT
or .work/v0232-i686.

--preflight-only  Check native process ABI, compiler version/target and tools.
--prepare-only    Fetch/verify/extract pinned Node sources without building.

Optional inputs: HERMES_I686_BUILD_ROOT, NODE_SOURCE_ARCHIVE, CPYTHON_PREFIX,
CC, CXX, JOBS=1. GCC >=13.2 and GNU Make are required by the pinned upstream
build guide. The Node 26 x86 target is upstream Experimental.
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
  v0232_assert_i686_compiler "$CC_BIN"
  local cc_version cxx_version cc_target cxx_target minimum
  cc_version=$("$CC_BIN" -dumpfullversion -dumpversion)
  cxx_version=$("$CXX_BIN" -dumpfullversion -dumpversion)
  cc_target=$("$CC_BIN" -dumpmachine)
  cxx_target=$("$CXX_BIN" -dumpmachine)
  [[ "$cc_target" == "$cxx_target" ]] || v0232_die "C/C++ compiler targets differ ($cc_target vs $cxx_target)"
  [[ "$cxx_target" =~ ^i[3-6]86(-|$) ]] || v0232_die "$CXX_BIN targets '$cxx_target', not Linux i686"
  minimum=$(printf '%s\n' 13.2 "$cc_version" | sort -V | head -1)
  [[ "$minimum" == 13.2 ]] || v0232_die "Node 26 upstream requires GCC >=13.2 (found $cc_version)"
  minimum=$(printf '%s\n' 13.2 "$cxx_version" | sort -V | head -1)
  [[ "$minimum" == 13.2 ]] || v0232_die "Node 26 upstream requires G++ >=13.2 (found $cxx_version)"
  [[ "$cc_version" == "$cxx_version" ]] || v0232_die "GCC/G++ versions differ ($cc_version vs $cxx_version)"
}

if [[ "$MODE" == preflight ]]; then
  v0232_need awk flock ld make readelf sha256sum sort tar
  command -v "$CC_BIN" >/dev/null 2>&1 || v0232_die "missing C compiler: $CC_BIN"
  command -v "$CXX_BIN" >/dev/null 2>&1 || v0232_die "missing C++ compiler: $CXX_BIN"
  check_compiler
  v0232_log "preflight passed (CC=$CC_BIN $($CC_BIN -dumpfullversion -dumpversion), CXX=$CXX_BIN, make=$(make --version | head -1))"
  exit 0
fi

v0232_need awk curl flock sha256sum tar
if [[ "$MODE" == build ]]; then
  v0232_need ld make readelf sort
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
mkdir -p "$STATE" "$DOWNLOADS" "$(dirname "$SOURCE")" "$PREFIX" "$RESULTS"
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

NODE_PYTHON="$CPYTHON_PREFIX/bin/python3.14"
[[ -x "$NODE_PYTHON" ]] || v0232_die "build CPython 3.14.9 i686 first; missing $NODE_PYTHON"
PY_INFO=$("$NODE_PYTHON" -I -c 'import struct,sys; print(".".join(map(str,sys.version_info[:3])) + " " + str(struct.calcsize("P") * 8))')
[[ "$PY_INFO" == '3.14.9 32' ]] || v0232_die "Node build Python must be CPython 3.14.9 i686 (found $PY_INFO)"

CC_INFO=$("$CC_BIN" --version | head -1)
CXX_INFO=$("$CXX_BIN" --version | head -1)
MAKE_INFO=$(make --version | head -1)
LD_INFO=$(ld --version | head -1)
TOOLCHAIN_FINGERPRINT=$(v0232_fingerprint "$CC_INFO" "$CXX_INFO" "$MAKE_INFO" "$LD_INFO" "$PY_INFO" "$(uname -sr)" "$ROOT")
configure_build() {
  cd "$BUILD"
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u MAKEFLAGS -u CONFIG_SITE \
    LC_ALL=C TZ=UTC PATH="$(dirname "$NODE_PYTHON"):$PATH" PYTHON="$NODE_PYTHON" \
    CC="$CC_BIN" CXX="$CXX_BIN" CFLAGS='-O2 -g0' CXXFLAGS='-O2 -g0' \
    "$SOURCE/configure" --prefix="$PREFIX" --dest-cpu=ia32 --with-intl=full-icu
}

compile_build() {
  cd "$BUILD"
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u CONFIG_SITE \
    LC_ALL=C TZ=UTC PATH="$(dirname "$NODE_PYTHON"):$PATH" PYTHON="$NODE_PYTHON" \
    MAKEFLAGS= make -j1
}

install_build() {
  cd "$BUILD"
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u CONFIG_SITE \
    LC_ALL=C TZ=UTC PATH="$(dirname "$NODE_PYTHON"):$PATH" PYTHON="$NODE_PYTHON" \
    MAKEFLAGS= make -j1 install
}

smoke_test() {
  local node="$PREFIX/bin/node" npm_cli="$PREFIX/lib/node_modules/npm/bin/npm-cli.js" report="$RESULTS/node-$VERSION.txt"
  [[ -x "$node" ]] || v0232_die "missing installed Node binary: $node"
  [[ -f "$npm_cli" ]] || v0232_die "Node install is missing bundled npm: $npm_cli"
  v0232_assert_i686_elf "$node"
  [[ "$("$node" --version)" == "v$VERSION" ]] || v0232_die "installed Node reports an unexpected version"
  [[ "$("$node" -p 'process.arch')" == ia32 ]] || v0232_die "installed Node does not report process.arch=ia32"
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
    printf 'source_url=%s\nsource_sha256=%s\nsource_shasums=%s\nsource_tag_commit=%s\n' "$SOURCE_URL" "$SOURCE_SHA256" "$SOURCE_SHASUMS" "$SOURCE_COMMIT"
    printf 'compiler=%s\ncxx=%s\nmake=%s\nlinker=%s\npython=%s\n' "$CC_INFO" "$CXX_INFO" "$MAKE_INFO" "$LD_INFO" "$PY_INFO"
    printf 'toolchain_fingerprint=%s\nscript_sha256=%s\nnode_elf=' "$TOOLCHAIN_FINGERPRINT" "$SCRIPT_FINGERPRINT"
    v0232_elf_identity "$node"
    printf 'node_version=%s\nnode_arch=%s\nnpm_version=%s\nnode_sha256=%s\nintl=full-icu;locale=es-AR\nwasm_shared_memory=1GiB-maximum\nworker_threads=PASS\n' "$($node --version)" "$($node -p 'process.arch')" "$npm_version" "$(v0232_sha256 "$node")"
  } >"$report"
}

CONFIG_FINGERPRINT=$(v0232_fingerprint "$SOURCE_FINGERPRINT" "$TOOLCHAIN_FINGERPRINT" "$SCRIPT_FINGERPRINT" "$PREFIX" "$PY_INFO" "CC=$CC_BIN" "CXX=$CXX_BIN" 'CFLAGS=-O2 -g0' '--dest-cpu=ia32' '--with-intl=full-icu')
BUILD_FINGERPRINT=$(v0232_fingerprint "$CONFIG_FINGERPRINT" 'make -j1')
INSTALL_FINGERPRINT=$(v0232_fingerprint "$BUILD_FINGERPRINT" "$PREFIX" 'make -j1 install')
SMOKE_FINGERPRINT=$(v0232_fingerprint "$INSTALL_FINGERPRINT" 'ELF32; Node; npm; WebAssembly shared-memory; worker_threads; es-AR Intl')

v0232_checkpoint "$STATE" configure "$CONFIG_FINGERPRINT" "$SOURCE/config.gypi" configure_build
v0232_checkpoint "$STATE" compile "$BUILD_FINGERPRINT" "$SOURCE/out/Release/node" compile_build
v0232_checkpoint "$STATE" install "$INSTALL_FINGERPRINT" "$PREFIX/bin/node" install_build
v0232_checkpoint "$STATE" smoke "$SMOKE_FINGERPRINT" "$RESULTS/node-$VERSION.txt" smoke_test
v0232_log "Node $VERSION i686 build and smoke checks passed; see $RESULTS/node-$VERSION.txt"
