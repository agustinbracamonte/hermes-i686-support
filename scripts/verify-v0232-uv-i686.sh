#!/usr/bin/env bash
# Verify the official uv 0.13.5 i686 asset against its release checksum and
# the pinned Hermes v0.23.2 lock row. This script never executes the binary.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UPSTREAM=${1:?usage: verify-v0232-uv-i686.sh PATCHED_HERMES_V0232_CHECKOUT}
PIN="ae2a81ccc00e9b7c06301523e5bb09608397149c"
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
printf 'uv-0.13.5-linux-i686: PASS (release sidecar, archive SHA-256, uv/uvx ELF32; binary not executed)\n'
