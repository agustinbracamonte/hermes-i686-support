#!/usr/bin/env bash
# Verify the official uv 0.13.5 i686 asset against its release checksum and
# the pinned Hermes v0.23.2 lock row. Static mode never executes the binary;
# --runtime executes it only after proving this shell is a native ELF32 process.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MODE=static
usage() {
    cat <<'HELP'
Usage: verify-v0232-uv-i686.sh [--static-only|--runtime] PATCHED_HERMES_V0232_CHECKOUT

Static mode verifies the official checksum sidecar, archive SHA-256, lock pin,
bootstrap pins and ELF32/EM_386 headers without executing uv. Runtime mode first
requires this script's shell to be a 32-bit ELF32/EM_386 process, rejects
QEMU-marked or QEMU-mapped shells, then runs the verified uv/uvx binaries in an
isolated temporary cache and checks version 0.13.5.

Set UV_I686_ARCHIVE to reuse an already downloaded archive; the official checksum
sidecar is still fetched and compared. Runtime mode is intended for native i686
staging and is not evidence of execution on x86_64.
HELP
}
if [[ "${1:-}" == --help || "${1:-}" == -h ]]; then
    usage
    exit 0
elif [[ "${1:-}" == --runtime ]]; then
    MODE=runtime
    shift
elif [[ "${1:-}" == --static-only ]]; then
    shift
fi
UPSTREAM=${1:?usage: verify-v0232-uv-i686.sh [--static-only|--runtime] PATCHED_HERMES_V0232_CHECKOUT}
PIN="ae2a81ccc00e9b7c06301523e5bb09608397149c"
if [[ "$MODE" == runtime ]]; then
    if ! command -v readelf >/dev/null 2>&1 || ! command -v getconf >/dev/null 2>&1 || ! command -v grep >/dev/null 2>&1; then
        echo 'runtime mode requires readelf, getconf and grep' >&2
        exit 1
    fi
    executable="/proc/$$/exe"
    [[ -e "$executable" ]] || { echo "cannot identify runtime shell at $executable" >&2; exit 1; }
    class=$(readelf -h "$executable" | awk '/Class:/ { print $2; exit }')
    machine=$(readelf -h "$executable" | awk '/Machine:/ { sub(/^[[:space:]]*Machine:[[:space:]]*/, ""); print; exit }')
    bits=$(getconf LONG_BIT)
    [[ "$class" == ELF32 && "$machine" == 'Intel 80386' && "$bits" == 32 ]] || {
        echo "runtime must run in an i686 userspace process (saw $class $machine, LONG_BIT=$bits; uname is ignored)" >&2
        exit 1
    }
    for qemu_env in QEMU_LD_PREFIX QEMU_CPU QEMU_SET_ENV QEMU_UNSET_ENV; do
        [[ -z "${!qemu_env:-}" ]] || {
            echo "runtime refuses a QEMU-marked process ($qemu_env is set)" >&2
            exit 1
        }
    done
    [[ -r "/proc/$$/maps" ]] || { echo 'cannot inspect runtime shell mappings for emulation' >&2; exit 1; }
    ! grep -qi qemu "/proc/$$/maps" || {
        echo 'runtime refuses a shell with QEMU mapped into its process image' >&2
        exit 1
    }
fi
[[ -d "$UPSTREAM/.git" || -f "$UPSTREAM/.git" ]] || { echo 'input is not a Git checkout' >&2; exit 1; }
[[ "$(git -C "$UPSTREAM" rev-parse HEAD)" == "$PIN" ]] || { echo "input must be exact commit $PIN" >&2; exit 1; }

read -r version url expected_sha < <(python3 - "$UPSTREAM/pm/lock.json" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1], encoding="utf-8"))
uv = lock["packages"]["uv"]
artifact = uv["artifacts"]["linux-i686"]
print(uv["version"], artifact["url"], artifact["sha256"])
PY
)
[[ "$version" == 0.13.5 ]] || { echo "unexpected uv version: $version" >&2; exit 1; }
asset_name=uv-i686-unknown-linux-gnu.tar.gz
asset_url="https://github.com/astral-sh/uv/releases/download/0.13.5/$asset_name"
[[ "$url" == "$asset_url" ]] || { echo "unexpected i686 asset URL in pm/lock.json: $url" >&2; exit 1; }
[[ "$expected_sha" == f5713d6c05d77d01de9655270d713ba87ed45391752f489c80bbf1690bccc17c ]] \
    || { echo 'unexpected i686 release SHA-256 in pm/lock.json' >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
curl -fsSL "$asset_url.sha256" -o "$TMP/release.sha256"
read -r release_sha release_name < "$TMP/release.sha256"
[[ "$release_sha" == "$expected_sha" && "$release_name" == "$asset_name" ]] \
    || { echo 'official release checksum sidecar differs from the i686 lock pin' >&2; exit 1; }

archive="$TMP/$asset_name"
if [[ -n "${UV_I686_ARCHIVE:-}" ]]; then
    [[ -f "$UV_I686_ARCHIVE" ]] || { echo "UV_I686_ARCHIVE not found: $UV_I686_ARCHIVE" >&2; exit 1; }
    cp -- "$UV_I686_ARCHIVE" "$archive"
else
    curl -fL --retry 3 --retry-delay 2 "$asset_url" -o "$archive"
fi
if command -v sha256sum >/dev/null 2>&1; then
    actual_sha=$(sha256sum "$archive" | cut -d' ' -f1)
else
    actual_sha=$(shasum -a 256 "$archive" | cut -d' ' -f1)
fi
[[ "$actual_sha" == "$expected_sha" ]] || {
    echo "uv i686 archive SHA-256 mismatch: expected $expected_sha, got $actual_sha" >&2
    exit 1
}

tar -tzf "$archive" | grep -Fx "uv-i686-unknown-linux-gnu/uv" >/dev/null
tar -tzf "$archive" | grep -Fx "uv-i686-unknown-linux-gnu/uvx" >/dev/null
mkdir "$TMP/extracted"
tar -xzf "$archive" -C "$TMP/extracted"
python3 - "$TMP/extracted/uv-i686-unknown-linux-gnu/uv" "$TMP/extracted/uv-i686-unknown-linux-gnu/uvx" <<'PY'
from pathlib import Path
import sys

for value in sys.argv[1:]:
    path = Path(value)
    header = path.read_bytes()[:20]
    if len(header) < 20 or header[:4] != b"\x7fELF":
        raise SystemExit(f"{path.name}: missing ELF header")
    identity = (header[4], header[5], int.from_bytes(header[18:20], "little"))
    if identity != (1, 1, 3):
        raise SystemExit(f"{path.name}: expected ELF32/little-endian/EM_386, got {identity}")
    print(f"{path.name}: ELF32 little-endian EM_386")
PY

python3 "$UPSTREAM/scripts/gen-bootstrap-pins.py" --check
if [[ "$MODE" == runtime ]]; then
    uv_bin="$TMP/extracted/uv-i686-unknown-linux-gnu/uv"
    uvx_bin="$TMP/extracted/uv-i686-unknown-linux-gnu/uvx"
    uv_version=$(UV_CACHE_DIR="$TMP/cache" "$uv_bin" --version 2>&1)
    uvx_version=$(UV_CACHE_DIR="$TMP/cache" "$uvx_bin" --version 2>&1)
    grep -Eq '(^|[[:space:]])0\.13\.5($|[[:space:]])' <<<"$uv_version" || {
        echo "uv returned an unexpected version: $uv_version" >&2
        exit 1
    }
    grep -Eq '(^|[[:space:]])0\.13\.5($|[[:space:]])' <<<"$uvx_version" || {
        echo "uvx returned an unexpected version: $uvx_version" >&2
        exit 1
    }
    UV_CACHE_DIR="$TMP/cache" "$uv_bin" cache dir >/dev/null
    UV_CACHE_DIR="$TMP/cache" "$uvx_bin" --help >/dev/null
    printf 'uv-0.13.5-linux-i686: PASS (native ELF32 execution; uv=%s; uvx=%s)\n' \
        "$uv_version" "$uvx_version"
else
    printf 'uv-0.13.5-linux-i686: PASS (release sidecar, archive SHA-256, uv/uvx ELF32; execution NOT RUN)\n'
fi
