#!/usr/bin/env bash
# Serial, checkpointed CPython 3.14.9 source build for Linux i686 userspace.
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=scripts/v0232-i686-build-common.sh
source "$SCRIPT_DIR/v0232-i686-build-common.sh"

readonly VERSION=3.14.9
readonly TAG=v3.14.9
readonly TAG_OBJECT=17acf00d155cb8536eca1c3af3a8404db648e37f
readonly SOURCE_COMMIT=ead82c07db1f111d613926ed1b6667411d768125
readonly SOURCE_TREE=a0de950923dd481d2fd0f5bdc42ed9821763cbc4
readonly SOURCE_REPOSITORY=https://github.com/python/cpython.git
readonly SCRIPT_FINGERPRINT=$(v0232_fingerprint "$(v0232_sha256 "$0")" "$(v0232_sha256 "$SCRIPT_DIR/v0232-i686-build-common.sh")")

MODE=build
case "${1:-}" in
  --help|-h)
    cat <<'HELP'
Usage: build-cpython-v0232-i686.sh [--preflight-only|--prepare-only]

Builds CPython 3.14.9 in a native Linux i686 userspace, serially, with resumable
checkpoints. Default build root: $HERMES_I686_BUILD_ROOT or .work/v0232-i686.

--preflight-only  Check native process ABI, compiler target, and serial tools.
--prepare-only    Fetch/verify the pinned CPython source without building.

Optional inputs: HERMES_I686_BUILD_ROOT, CPYTHON_SOURCE_DIR, CC, CXX, JOBS=1.
The source checkout is never modified by configure/build/install.
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

if [[ "$MODE" == preflight ]]; then
  v0232_need awk flock git ld make readelf sha256sum
  command -v "$CC_BIN" >/dev/null 2>&1 || v0232_die "missing C compiler: $CC_BIN"
  command -v "$CXX_BIN" >/dev/null 2>&1 || v0232_die "missing C++ compiler: $CXX_BIN"
  v0232_assert_i686_process
  v0232_assert_i686_compiler "$CC_BIN"
  v0232_log "preflight passed (CC=$CC_BIN, CXX=$CXX_BIN, make=$(make --version | head -1))"
  exit 0
fi

v0232_need awk flock git sha256sum
if [[ "$MODE" == build ]]; then
  v0232_need ld make readelf
  command -v "$CC_BIN" >/dev/null 2>&1 || v0232_die "missing C compiler: $CC_BIN"
  command -v "$CXX_BIN" >/dev/null 2>&1 || v0232_die "missing C++ compiler: $CXX_BIN"
  v0232_assert_i686_process
  v0232_assert_i686_compiler "$CC_BIN"
fi

ROOT=${HERMES_I686_BUILD_ROOT:-"$PWD/.work/v0232-i686"}
[[ "$ROOT" != *" "* ]] || v0232_die "Node-compatible build paths cannot contain spaces: $ROOT"
mkdir -p "$ROOT"
ROOT=$(cd "$ROOT" && pwd)
STATE="$ROOT/state/cpython-$VERSION"
SOURCE=${CPYTHON_SOURCE_DIR:-"$ROOT/src/cpython-$VERSION"}
BUILD="$ROOT/build/cpython-$VERSION"
PREFIX=${CPYTHON_PREFIX:-"$ROOT/prefix/cpython-$VERSION"}
RESULTS="$ROOT/results"
mkdir -p "$STATE" "$BUILD" "$PREFIX" "$RESULTS"
v0232_build_lock "$ROOT"

ensure_source() {
  if [[ ! -d "$SOURCE/.git" ]]; then
    [[ ! -e "$SOURCE" ]] || v0232_die "source path exists without Git metadata: $SOURCE"
    mkdir -p "$(dirname "$SOURCE")"
    git init -q "$SOURCE"
    git -C "$SOURCE" remote add origin "$SOURCE_REPOSITORY"
  fi

  if ! git -C "$SOURCE" show-ref --verify --quiet "refs/tags/$TAG"; then
    git -C "$SOURCE" fetch --depth=1 --no-tags origin "refs/tags/$TAG:refs/tags/$TAG"
  fi

  local tag_object commit tree head dirty
  tag_object=$(git -C "$SOURCE" rev-parse "refs/tags/$TAG^{tag}")
  commit=$(git -C "$SOURCE" rev-parse "refs/tags/$TAG^{commit}")
  tree=$(git -C "$SOURCE" rev-parse "refs/tags/$TAG^{tree}")
  [[ "$tag_object" == "$TAG_OBJECT" ]] || v0232_die "$TAG object mismatch: $tag_object"
  [[ "$commit" == "$SOURCE_COMMIT" ]] || v0232_die "$TAG commit mismatch: $commit"
  [[ "$tree" == "$SOURCE_TREE" ]] || v0232_die "$TAG tree mismatch: $tree"

  if head=$(git -C "$SOURCE" rev-parse --verify HEAD 2>/dev/null); then
    [[ "$head" == "$SOURCE_COMMIT" ]] || v0232_die "source HEAD is $head, expected $SOURCE_COMMIT"
  else
    git -C "$SOURCE" checkout --quiet --detach "$SOURCE_COMMIT"
  fi
  dirty=$(git -C "$SOURCE" status --porcelain)
  [[ -z "$dirty" ]] || v0232_die "pinned source checkout is not clean: $SOURCE"
  [[ -x "$SOURCE/configure" ]] || v0232_die "pinned source has no executable configure script"
}

SOURCE_FINGERPRINT=$(v0232_fingerprint "cpython-$VERSION" "$TAG_OBJECT" "$SOURCE_COMMIT" "$SOURCE_TREE" "$SCRIPT_FINGERPRINT")
ensure_source
v0232_checkpoint "$STATE" source "$SOURCE_FINGERPRINT" "$SOURCE/.git" true
if [[ "$MODE" == prepare ]]; then
  v0232_log "verified CPython $VERSION source: tag=$TAG commit=$SOURCE_COMMIT tree=$SOURCE_TREE"
  exit 0
fi

CC_INFO=$("$CC_BIN" --version | head -1)
CXX_INFO=$("$CXX_BIN" --version | head -1)
MAKE_INFO=$(make --version | head -1)
LD_INFO=$(ld --version | head -1)
TOOLCHAIN_FINGERPRINT=$(v0232_fingerprint "$CC_INFO" "$CXX_INFO" "$MAKE_INFO" "$LD_INFO" "$(uname -sr)" "$ROOT")
configure_build() {
  cd "$BUILD"
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u MAKEFLAGS -u CONFIG_SITE \
    LC_ALL=C TZ=UTC CC="$CC_BIN" CXX="$CXX_BIN" CFLAGS='-O2 -g0' CXXFLAGS='-O2 -g0' \
    "$SOURCE/configure" --prefix="$PREFIX" --with-ensurepip=install
}

compile_build() {
  cd "$BUILD"
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u CONFIG_SITE LC_ALL=C TZ=UTC \
    MAKEFLAGS= make -j1
}

install_build() {
  cd "$BUILD"
  env -u CFLAGS -u CXXFLAGS -u CPPFLAGS -u LDFLAGS -u CONFIG_SITE LC_ALL=C TZ=UTC \
    MAKEFLAGS= make -j1 install
}

smoke_test() {
  local python="$PREFIX/bin/python3.14" report="$RESULTS/cpython-$VERSION.txt"
  [[ -x "$python" ]] || v0232_die "missing installed interpreter: $python"
  v0232_assert_i686_elf "$python"
  env -u PYTHONHOME -u PYTHONPATH -u LD_LIBRARY_PATH "$python" -I -c \
    'import ctypes, ensurepip, platform, sqlite3, ssl, struct, sys; assert sys.version_info[:3] == (3, 14, 9), sys.version; assert struct.calcsize("P") == 4; db=sqlite3.connect(":memory:"); assert db.execute("select 1").fetchone() == (1,); assert ssl.OPENSSL_VERSION; ctypes.CDLL(None); print("python=" + sys.version.split()[0]); print("pointer_bits=" + str(struct.calcsize("P") * 8)); print("openssl=" + ssl.OPENSSL_VERSION); print("sqlite=" + sqlite3.sqlite_version); print("ensurepip=" + ensurepip.version())' \
    >"$report.tmp"
  {
    printf 'source_tag=%s\nsource_tag_object=%s\nsource_commit=%s\nsource_tree=%s\n' "$TAG" "$TAG_OBJECT" "$SOURCE_COMMIT" "$SOURCE_TREE"
    printf 'source_repository=%s\ncompiler=%s\ncxx=%s\nmake=%s\nlinker=%s\n' "$SOURCE_REPOSITORY" "$CC_INFO" "$CXX_INFO" "$MAKE_INFO" "$LD_INFO"
    printf 'toolchain_fingerprint=%s\nscript_sha256=%s\npython_elf=' "$TOOLCHAIN_FINGERPRINT" "$SCRIPT_FINGERPRINT"
    v0232_elf_identity "$python"
    printf 'python_sha256=%s\n' "$(v0232_sha256 "$python")"
    cat "$report.tmp"
  } >"$report"
  rm -f -- "$report.tmp"
}

CONFIG_FINGERPRINT=$(v0232_fingerprint "$SOURCE_FINGERPRINT" "$TOOLCHAIN_FINGERPRINT" "$SCRIPT_FINGERPRINT" "$PREFIX" "CC=$CC_BIN" "CXX=$CXX_BIN" 'CFLAGS=-O2 -g0' '--with-ensurepip=install')
BUILD_FINGERPRINT=$(v0232_fingerprint "$CONFIG_FINGERPRINT" 'make -j1')
INSTALL_FINGERPRINT=$(v0232_fingerprint "$BUILD_FINGERPRINT" "$PREFIX" 'make -j1 install')
SMOKE_FINGERPRINT=$(v0232_fingerprint "$INSTALL_FINGERPRINT" 'ELF32; ssl; sqlite3; ctypes; ensurepip')

v0232_checkpoint "$STATE" configure "$CONFIG_FINGERPRINT" "$BUILD/Makefile" configure_build
v0232_checkpoint "$STATE" compile "$BUILD_FINGERPRINT" "$BUILD/python" compile_build
v0232_checkpoint "$STATE" install "$INSTALL_FINGERPRINT" "$PREFIX/bin/python3.14" install_build
v0232_checkpoint "$STATE" smoke "$SMOKE_FINGERPRINT" "$RESULTS/cpython-$VERSION.txt" smoke_test
v0232_log "CPython $VERSION i686 build and smoke checks passed; see $RESULTS/cpython-$VERSION.txt"
