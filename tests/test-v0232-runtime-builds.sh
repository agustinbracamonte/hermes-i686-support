#!/usr/bin/env bash
# Fast, offline regression coverage for the i686 build helper and checkpoints.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

bash -n "$ROOT/scripts/build-cpython-v0232-i686.sh" \
  "$ROOT/scripts/build-node-v0232-i686.sh" \
  "$ROOT/scripts/v0232-i686-build-common.sh" \
  "$ROOT/scripts/v0232-node-toolchain.sh" \
  "$ROOT/scripts/ci-v0232-i686-runtime-build.sh"
"$ROOT/scripts/build-cpython-v0232-i686.sh" --help >/dev/null
"$ROOT/scripts/build-node-v0232-i686.sh" --help >/dev/null
grep -Fq -- '--openssl-no-asm' "$ROOT/scripts/build-node-v0232-i686.sh"
grep -Fq -- '-msse2' "$ROOT/patches/node-v26.12.1-i686-build-fixes.patch"
grep -Fq -- "'libraries': [ '-latomic' ]" "$ROOT/patches/node-v26.12.1-i686-build-fixes.patch"
grep -Fq 'v0232_require_cpu_feature sse2' "$ROOT/scripts/build-node-v0232-i686.sh"
grep -Fq 'node-i686-build-patches' "$ROOT/scripts/build-node-v0232-i686.sh"
grep -Fq 'CHROOT_STATUS=$?' "$ROOT/scripts/ci-v0232-i686-runtime-build.sh"
grep -Fq 'GITHUB_STEP_SUMMARY' "$ROOT/scripts/ci-v0232-i686-runtime-build.sh"

patch_fixture="$TMP/node-source"
mkdir -p "$patch_fixture/deps/zlib" "$patch_fixture/deps/openssl"
cat >"$patch_fixture/deps/zlib/zlib.gyp" <<'GYP'
            ['target_arch in "ia32 x64" and OS!="ios"', {
              'defines': [ 'INFLATE_CHUNK_SIMD_SSE2' ],
              'conditions': [
                ['target_arch=="x64"', {
                  'defines': [ 'INFLATE_CHUNK_READ_64LE' ],
                }],
              ],
            }],
            ['target_arch in "ia32 x64" and OS!="ios"', {
              'dependencies': [ 'zlib_data_chunk_simd' ],
              'sources': [ '<(ZLIB_ROOT)/slide_hash_simd.h' ]
            }],
              ],
              'defines': [ 'DEFLATE_SLIDE_HASH_SSE2' ],
              'conditions': [
                ['target_arch=="x64"', {
                  'defines': [ 'INFLATE_CHUNK_READ_64LE' ],
                }],
GYP
cat >"$patch_fixture/deps/openssl/openssl.gyp" <<'GYP'
        #'OPENSSL_NO_DEPRECATED',
      ],
      'conditions': [
        ['openssl_no_asm==1', {
          'includes': ['./openssl-cl_no_asm.gypi'],
        }, 'target_arch=="arm64" and OS=="win"', {
GYP
patch --silent --dry-run --batch --fuzz=0 -p1 -d "$patch_fixture" \
  <"$ROOT/patches/node-v26.12.1-i686-build-fixes.patch"
patch --silent --batch --forward --fuzz=0 -p1 -d "$patch_fixture" \
  <"$ROOT/patches/node-v26.12.1-i686-build-fixes.patch"
grep -Fq "['target_arch==\"ia32\"', {" "$patch_fixture/deps/zlib/zlib.gyp"
[[ $(grep -Fc "'cflags': [ '-msse2' ]" "$patch_fixture/deps/zlib/zlib.gyp") -eq 2 ]]
grep -Fq "['OS==\"linux\" and target_arch==\"ia32\" and clang==1', {" "$patch_fixture/deps/openssl/openssl.gyp"
grep -Fq "'libraries': [ '-latomic' ]" "$patch_fixture/deps/openssl/openssl.gyp"
patch --silent --dry-run --reverse --fuzz=0 -p1 -d "$patch_fixture" \
  <"$ROOT/patches/node-v26.12.1-i686-build-fixes.patch"
grep -Fq 'readonly CXX_HEADERS_PACKAGE=libstdc++-11-dev' "$ROOT/scripts/build-node-v0232-i686.sh"
grep -Fq 'readonly CXX_HEADERS_VERSION=11.3.0-12' "$ROOT/scripts/build-node-v0232-i686.sh"
grep -Fq 'readonly CXX_HEADERS_ARCH=i386' "$ROOT/scripts/build-node-v0232-i686.sh"
grep -Fq 'readonly CXX_HEADERS_SHA256=8402d1e5e1f09308fd5273b5554476c8ee6fc55c984ef2fe55f46ef7b117f58c' "$ROOT/scripts/build-node-v0232-i686.sh"
grep -Fq 'dpkg-deb -x "$CXX_HEADERS_DEB" "$temporary"' "$ROOT/scripts/build-node-v0232-i686.sh"
grep -Fq 'diff -qr "$CXX_HEADERS_ROOT" "$temporary"' "$ROOT/scripts/build-node-v0232-i686.sh"
grep -Fq 'CXX_HEADER_FLAGS=(-isystem "$CXX_SOURCE_LOCATION_OVERLAY")' "$ROOT/scripts/build-node-v0232-i686.sh"
! grep -Fq 'CXX_HEADER_FLAGS=(-nostdinc++' "$ROOT/scripts/build-node-v0232-i686.sh"
grep -Fq 'source-location-overlay' "$ROOT/scripts/build-node-v0232-i686.sh"
grep -Fq 'verify_cxx_header_selection' "$ROOT/scripts/build-node-v0232-i686.sh"
grep -Fq 'CXX_RUNTIME_PACKAGE_VERSION' "$ROOT/scripts/build-node-v0232-i686.sh"
grep -Fq 'GLIBCXX_3.4.28' "$ROOT/scripts/build-node-v0232-i686.sh"
grep -Fq 'source-location-probe' "$ROOT/scripts/build-node-v0232-i686.sh"
sed -n '/^compile_build() {/,/^}/p' "$ROOT/scripts/build-node-v0232-i686.sh" | \
  grep -Fq 'CXXFLAGS="-O2 -g0 ${CXX_HEADER_FLAGS[*]}"'
sed -n '/^install_build() {/,/^}/p' "$ROOT/scripts/build-node-v0232-i686.sh" | \
  grep -Fq 'CXXFLAGS="-O2 -g0 ${CXX_HEADER_FLAGS[*]}"'
grep -Fq 'node-source-location-probe.txt' "$ROOT/scripts/ci-v0232-i686-runtime-build.sh"
grep -Fq 'node-cxx-header-selection.txt' "$ROOT/scripts/ci-v0232-i686-runtime-build.sh"
grep -Fq 'node-cxx-header-selection.trace' "$ROOT/scripts/ci-v0232-i686-runtime-build.sh"
grep -Fq 'C++ standard-library selection trace (Bullseye vector header missing)' "$ROOT/scripts/build-node-v0232-i686.sh"
grep -Fq 'v0232_node_trace_has_gcc10_vector "$trace"' "$ROOT/scripts/build-node-v0232-i686.sh"
grep -Fq 'cat "$trace" >&2' "$ROOT/scripts/build-node-v0232-i686.sh"
grep -Fq '#include <vector>' "$ROOT/tests/fixtures/node-source-location.cpp"
grep -Fq 'std::vector<int> copy = values' "$ROOT/tests/fixtures/node-source-location.cpp"
grep -Fq 'sizeof(std::source_location) == sizeof(void*)' "$ROOT/tests/fixtures/node-source-location.cpp"
grep -Fq 'std::source_location::current()' "$ROOT/tests/fixtures/node-source-location.cpp"

set +e
output=$(GITHUB_ACTIONS=false RUNNER_ENVIRONMENT=self-hosted RUNNER_ARCH=X64 \
  "$ROOT/scripts/ci-v0232-i686-runtime-build.sh" "$ROOT" "$TMP/should-not-build" 2>&1)
status=$?
set -e
[[ $status -eq 1 && "$output" == *'only GitHub Actions is allowed'* ]]
[[ ! -e "$TMP/should-not-build" ]]

for script in build-cpython-v0232-i686.sh build-node-v0232-i686.sh; do
  set +e
  output=$(JOBS=2 "$ROOT/scripts/$script" --preflight-only 2>&1)
  status=$?
  set -e
  [[ $status -eq 1 ]] || { printf '%s accepted JOBS=2\n' "$script" >&2; exit 1; }
  [[ "$output" == *'serial builds only'* ]] || { printf '%s did not explain the serial-build restriction\n' "$script" >&2; exit 1; }
done

bad_archive="$TMP/not-node-source.tar.xz"
printf 'not an upstream archive\n' >"$bad_archive"
set +e
output=$(HERMES_I686_BUILD_ROOT="$TMP/bad-source-root" NODE_SOURCE_ARCHIVE="$bad_archive" \
  "$ROOT/scripts/build-node-v0232-i686.sh" --prepare-only 2>&1)
status=$?
set -e
[[ $status -eq 1 && "$output" == *'Node source SHA-256 mismatch'* ]]

python3 - "$TMP" <<'PY'
from pathlib import Path
import struct
import sys

root = Path(sys.argv[1])
for name, elf_class, machine in (("i686.elf", 1, 3), ("x64.elf", 2, 62)):
    header = bytearray(52 if elf_class == 1 else 64)
    header[:16] = b"\x7fELF" + bytes([elf_class, 1, 1, 0]) + bytes(8)
    if elf_class == 1:
        struct.pack_into("<HHIIIIIHHHHHH", header, 16, 2, machine, 1, 0, 0, 0, 0, 52, 32, 0, 40, 0, 0)
    else:
        struct.pack_into("<HHIQQQIHHHHHH", header, 16, 2, machine, 1, 0, 0, 0, 0, 64, 56, 0, 64, 0, 0)
    (root / name).write_bytes(header)
PY

source "$ROOT/scripts/v0232-i686-build-common.sh"
source "$ROOT/scripts/v0232-node-toolchain.sh"
printf 'processor : 0\nflags : fpu sse2 ssse3\n' >"$TMP/cpuinfo-sse2"
v0232_require_cpu_feature sse2 "$TMP/cpuinfo-sse2"
printf 'processor : 0\nflags : fpu ssse3\n' >"$TMP/cpuinfo-no-sse2"
set +e
output=$( (v0232_require_cpu_feature sse2 "$TMP/cpuinfo-no-sse2") 2>&1 )
status=$?
set -e
[[ $status -eq 1 && "$output" == *'requires CPU feature '\''sse2'\'''* ]]
[[ "$(v0232_elf_identity "$TMP/i686.elf")" == 'ELF32 little-endian Intel 80386' ]]
if v0232_elf_identity "$TMP/x64.elf" >/dev/null; then
  echo 'ELF guard accepted a 64-bit fixture' >&2
  exit 1
fi

python3 - "$TMP" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
template = '''#!{python}
import sys
family, version, target = {family!r}, {version!r}, {target!r}
if sys.argv[1] == "--version":
    print(("Debian clang version " if family == "clang" else "gcc (GCC) ") + version)
elif sys.argv[1] in ("-dumpfullversion", "-dumpversion"):
    print(version)
elif sys.argv[1] == "-dumpmachine":
    print(target)
else:
    raise SystemExit(2)
'''

def compiler(name, family, version, target="i686-linux-gnu"):
    path = root / name
    path.write_text(template.format(
        python=sys.executable, family=family, version=version, target=target,
    ), encoding="utf-8")
    path.chmod(0o755)
    return path

for args in (
    ("clang19", "clang", "19.1.7", "i686-unknown-linux-gnu"),
    ("clangxx19", "clang", "19.1.7", "i686-unknown-linux-gnu"),
    ("clang190", "clang", "19.0.1", "i686-unknown-linux-gnu"),
    ("gcc13", "gcc", "13.2.1", "i686-linux-gnu"),
    ("gxx13", "gcc", "13.2.1", "i686-linux-gnu"),
    ("gcc12", "gcc", "12.4.0", "i686-linux-gnu"),
    ("gccx64", "gcc", "13.2.1", "x86_64-linux-gnu"),
):
    compiler(*args)
PY

header_root="$TMP/debian-header-root"
mkdir -p "$header_root/usr/lib/gcc/i686-linux-gnu/10" "$header_root/usr/include/c++/10"
: >"$header_root/usr/include/c++/10/vector"
gcc10_trace="$TMP/gcc10-header.trace"
printf '. %s\n' "$header_root/usr/lib/gcc/i686-linux-gnu/10/../../../../include/c++/10/vector" >"$gcc10_trace"
v0232_node_trace_has_gcc10_vector "$gcc10_trace" "$header_root/usr/include/c++/10/vector"
gcc11_trace="$TMP/gcc11-header.trace"
mkdir -p "$header_root/toolchain/usr/include/c++/11"
: >"$header_root/toolchain/usr/include/c++/11/vector"
printf '. %s\n' "$header_root/toolchain/usr/include/c++/11/vector" >"$gcc11_trace"
if v0232_node_trace_has_gcc10_vector "$gcc11_trace" "$header_root/usr/include/c++/10/vector"; then
  echo 'header trace accepted a GCC 11 vector header as Bullseye GCC 10' >&2
  exit 1
fi

[[ "$(v0232_node_check_compiler_pair "$TMP/clang19" "$TMP/clangxx19")" == 'clang 19.1.7 i686-unknown-linux-gnu' ]]
[[ "$(v0232_node_check_compiler_pair "$TMP/gcc13" "$TMP/gxx13")" == 'gcc 13.2.1 i686-linux-gnu' ]]
set +e
output=$(v0232_node_check_compiler_pair "$TMP/clang190" "$TMP/clang190" 2>&1)
status=$?
set -e
[[ $status -eq 1 && "$output" == *'Clang >=19.1'* ]]
set +e
output=$(v0232_node_check_compiler_pair "$TMP/gcc12" "$TMP/gcc12" 2>&1)
status=$?
set -e
[[ $status -eq 1 && "$output" == *'GCC >=13.2'* ]]
set +e
output=$(v0232_node_check_compiler_pair "$TMP/clang19" "$TMP/gxx13" 2>&1)
status=$?
set -e
[[ $status -eq 1 && "$output" == *'families differ'* ]]
set +e
output=$(v0232_node_check_compiler_pair "$TMP/gccx64" "$TMP/gccx64" 2>&1)
status=$?
set -e
[[ $status -eq 1 && "$output" == *'not Linux i686'* ]]

state="$TMP/checkpoints"
mkdir -p "$state"
counter="$TMP/counter"
do_work() { printf 'once\n' >>"$counter"; }
v0232_checkpoint "$state" resume 'fingerprint-1' "$counter" do_work
v0232_checkpoint "$state" resume 'fingerprint-1' "$counter" do_work
[[ $(wc -l <"$counter") -eq 1 ]]
set +e
output=$( (v0232_checkpoint "$state" resume 'fingerprint-2' "$counter" do_work) 2>&1 )
status=$?
set -e
[[ $status -eq 1 && "$output" == *'does not match this source/toolchain/configuration'* ]]

echo 'v0.23.2 runtime build helpers: PASS (offline syntax, serial guard, ELF32 fixture and resumable checkpoint)'
