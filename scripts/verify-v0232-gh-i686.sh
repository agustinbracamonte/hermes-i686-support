#!/usr/bin/env bash
# Verify the official GitHub CLI 2.97.0 Linux 386 asset against release metadata
# and the Hermes v0.23.2 lock row. This script never executes the ELF32 binary.
set -euo pipefail

UPSTREAM=${1:?usage: verify-v0232-gh-i686.sh PATCHED_HERMES_V0232_CHECKOUT}
PIN="ae2a81ccc00e9b7c06301523e5bb09608397149c"
[[ -d "$UPSTREAM/.git" || -f "$UPSTREAM/.git" ]] || { echo 'input is not a Git checkout' >&2; exit 1; }
[[ "$(git -C "$UPSTREAM" rev-parse HEAD)" == "$PIN" ]] || { echo "input must be exact commit $PIN" >&2; exit 1; }

read -r version url expected_sha < <(python3 - "$UPSTREAM/pm/lock.json" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1], encoding="utf-8"))
gh = lock["packages"]["gh"]
artifact = gh["artifacts"]["linux-i686"]
print(gh["version"], artifact["url"], artifact["sha256"])
PY
)
asset_name=gh_2.97.0_linux_386.tar.gz
asset_url="https://github.com/cli/cli/releases/download/v2.97.0/$asset_name"
[[ "$version" == 2.97.0 && "$url" == "$asset_url" ]] || {
    echo 'unexpected GitHub CLI i686 version or URL in pm/lock.json' >&2
    exit 1
}
[[ "$expected_sha" == ba556b1061cfc89fee62d1e59dfacd2ea646d8c3bb41cbef909ec6ed27071512 ]] || {
    echo 'unexpected GitHub CLI i686 release SHA-256 in pm/lock.json' >&2
    exit 1
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
checksums_url="https://github.com/cli/cli/releases/download/v2.97.0/gh_2.97.0_checksums.txt"
curl -fsSL "$checksums_url" -o "$TMP/checksums.txt"
python3 - "$TMP/checksums.txt" "$asset_name" "$expected_sha" <<'PY'
from pathlib import Path
import sys

rows = [line.split() for line in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines()]
matches = [row for row in rows if len(row) == 2 and row[1] == sys.argv[2]]
if len(matches) != 1 or matches[0][0] != sys.argv[3]:
    raise SystemExit("official release checksums file differs from the i686 lock pin")
PY

archive="$TMP/$asset_name"
if [[ -n "${GH_I686_ARCHIVE:-}" ]]; then
    [[ -f "$GH_I686_ARCHIVE" ]] || { echo "GH_I686_ARCHIVE not found: $GH_I686_ARCHIVE" >&2; exit 1; }
    cp -- "$GH_I686_ARCHIVE" "$archive"
else
    curl -fL --retry 3 --retry-delay 2 "$asset_url" -o "$archive"
fi
if command -v sha256sum >/dev/null 2>&1; then
    actual_sha=$(sha256sum "$archive" | cut -d' ' -f1)
else
    actual_sha=$(shasum -a 256 "$archive" | cut -d' ' -f1)
fi
[[ "$actual_sha" == "$expected_sha" ]] || {
    echo "GitHub CLI i686 archive SHA-256 mismatch: expected $expected_sha, got $actual_sha" >&2
    exit 1
}

member="gh_2.97.0_linux_386/bin/gh"
tar -tzf "$archive" | grep -Fx "$member" >/dev/null
mkdir "$TMP/extracted"
tar -xzf "$archive" -C "$TMP/extracted" "$member"
python3 - "$TMP/extracted/$member" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
header = path.read_bytes()[:20]
if len(header) < 20 or header[:4] != b"\x7fELF":
    raise SystemExit("gh: missing ELF header")
identity = (header[4], header[5], int.from_bytes(header[18:20], "little"))
if identity != (1, 1, 3):
    raise SystemExit(f"gh: expected ELF32/little-endian/EM_386, got {identity}")
print("gh: ELF32 little-endian EM_386")
PY

printf 'gh-2.97.0-linux-i686: PASS (official checksum file, archive SHA-256, ELF32; binary not executed)\n'
