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
grep -Fq 'CHROOT_STATUS=$?' "$ROOT/scripts/ci-v0232-i686-runtime-build.sh"
grep -Fq 'GITHUB_STEP_SUMMARY' "$ROOT/scripts/ci-v0232-i686-runtime-build.sh"

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
    ("gccwin", "gcc", "13.2.1", "i686-w64-mingw32"),
):
    compiler(*args)
PY

v0232_assert_i686_compiler "$TMP/gcc13"
set +e
output=$(v0232_assert_i686_compiler "$TMP/gccwin" 2>&1)
status=$?
set -e
[[ $status -eq 1 && "$output" == *'not Linux i686'* ]]

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
