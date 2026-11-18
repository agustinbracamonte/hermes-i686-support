#!/usr/bin/env bash
# Static fixture coverage for the FFmpeg i686 evidence helper.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

bash -n "$ROOT/scripts/verify-v0232-ffmpeg-i686.sh"
bash -n "$ROOT/scripts/v0232-ffmpeg-version.sh"
grep -Fq 'FFMPEG_VERSION=$("$FFMPEG_BIN" -hide_banner -version 2>&1' \
  "$ROOT/scripts/verify-v0232-ffmpeg-i686.sh"
grep -Fq '/proc/$FFMPEG_PID/exe' "$ROOT/scripts/verify-v0232-ffmpeg-i686.sh"
grep -Fq 'process $pid did not resolve' "$ROOT/scripts/verify-v0232-ffmpeg-i686.sh"
grep -Fq 'live FFprobe process' "$ROOT/scripts/verify-v0232-ffmpeg-i686.sh"
grep -Fq -- '-threads:v 1' "$ROOT/scripts/verify-v0232-ffmpeg-i686.sh"
source "$ROOT/scripts/v0232-ffmpeg-version.sh"
[[ "$(v0232_validate_ffmpeg_release_pair \
  e47273f4d9227152dcbf543cebaf9e2430ddbcc4 \
  'ffmpeg version n9.0.1-11-ge47273f4d9' \
  'ffprobe version n9.0.1-11-ge47273f4d9')" == n9.0.1-11-ge47273f4d9 ]]
[[ "$(v0232_validate_ffmpeg_release_pair \
  bf1b838f2ab88b4f8fd83443325c782ea0e0f7fa \
  'ffmpeg version n9.0.1' 'ffprobe version n9.0.1')" == n9.0.1 ]]
if v0232_validate_ffmpeg_release_pair \
  e47273f4d9227152dcbf543cebaf9e2430ddbcc4 \
  'ffmpeg version 8.0' 'ffprobe version 8.0' >/dev/null; then
  echo 'FFmpeg verifier accepted an incorrect release version' >&2
  exit 1
fi
if v0232_validate_ffmpeg_release_pair \
  e47273f4d9227152dcbf543cebaf9e2430ddbcc4 \
  'ffmpeg version n9.0.1-11-ge47273f4d9' 'ffprobe version n9.0.1' >/dev/null; then
  echo 'FFmpeg verifier accepted mismatched FFmpeg/FFprobe versions' >&2
  exit 1
fi
if v0232_validate_ffmpeg_release_pair \
  bf1b838f2ab88b4f8fd83443325c782ea0e0f7fa \
  'ffmpeg version n9.0.10' 'ffprobe version n9.0.10' >/dev/null; then
  echo 'FFmpeg verifier accepted a prefix-matching but different release' >&2
  exit 1
fi
if v0232_validate_ffmpeg_release_pair \
  e47273f4d9227152dcbf543cebaf9e2430ddbcc4 \
  'ffmpeg version n9.0.1-12-gfffffffffff' 'ffprobe version n9.0.1-12-gfffffffffff' >/dev/null; then
  echo 'FFmpeg verifier accepted a different source-lineage build' >&2
  exit 1
fi
"$ROOT/scripts/verify-v0232-ffmpeg-i686.sh" --help >/dev/null

python3 - "$TMP" <<'PY'
from pathlib import Path
import struct
import sys

root = Path(sys.argv[1])
for name, elf_class, machine, elf_type in (("i686", 1, 3, 2), ("x64", 2, 62, 2), ("dso", 1, 3, 3)):
    header = bytearray(52 if elf_class == 1 else 64)
    header[:16] = b"\x7fELF" + bytes([elf_class, 1, 1, 0]) + bytes(8)
    if elf_class == 1:
        struct.pack_into("<HHIIIIIHHHHHH", header, 16, elf_type, machine, 1, 0, 0, 0, 0, 52, 32, 0, 40, 0, 0)
    else:
        struct.pack_into("<HHIQQQIHHHHHH", header, 16, elf_type, machine, 1, 0, 0, 0, 0, 64, 56, 0, 64, 0, 0)
    path = root / name
    path.write_bytes(header)
    path.chmod(0o755)
PY

mkdir "$TMP/static-report"
FFMPEG_SOURCE_COMMIT=e47273f4d9227152dcbf543cebaf9e2430ddbcc4 \
  "$ROOT/scripts/verify-v0232-ffmpeg-i686.sh" --static-only \
  "$TMP/i686" "$TMP/i686" "$TMP/static-report"
grep -Fxq 'validation_mode=static' "$TMP/static-report/ffmpeg-i686-verification.txt"
grep -Fxq 'native_i686_execution=NOT_RUN' "$TMP/static-report/ffmpeg-i686-verification.txt"
grep -Fxq 'source_commit_claimed=e47273f4d9227152dcbf543cebaf9e2430ddbcc4' \
  "$TMP/static-report/ffmpeg-i686-verification.txt"
grep -Fxq 'ffmpeg_elf=ELF32 little-endian Intel 80386' "$TMP/static-report/ffmpeg-i686-verification.txt"

mkdir "$TMP/wrong-elf-report"
set +e
output=$("$ROOT/scripts/verify-v0232-ffmpeg-i686.sh" --static-only \
  "$TMP/x64" "$TMP/x64" "$TMP/wrong-elf-report" 2>&1)
status=$?
set -e
[[ $status -eq 1 && "$output" == *'FFmpeg must be ELF32 little-endian EM_386'* ]]
[[ ! -e "$TMP/wrong-elf-report/ffmpeg-i686-verification.txt" ]]

mkdir "$TMP/dso-report"
set +e
output=$("$ROOT/scripts/verify-v0232-ffmpeg-i686.sh" --static-only \
  "$TMP/dso" "$TMP/dso" "$TMP/dso-report" 2>&1)
status=$?
set -e
[[ $status -eq 1 && "$output" == *'not an executable ELF image'* ]]
[[ ! -e "$TMP/dso-report/ffmpeg-i686-verification.txt" ]]

mkdir "$TMP/fake-bin" "$TMP/new-glibc-report"
REAL_READELF_BIN=$(command -v readelf)
cat >"$TMP/fake-bin/readelf" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == --version-info ]]; then
  printf 'Version: GLIBC_2.32\n'
else
  exec "$REAL_READELF_BIN" "$@"
fi
SH
chmod +x "$TMP/fake-bin/readelf"
set +e
output=$(PATH="$TMP/fake-bin:$PATH" REAL_READELF_BIN="$REAL_READELF_BIN" \
  "$ROOT/scripts/verify-v0232-ffmpeg-i686.sh" --static-only \
  "$TMP/i686" "$TMP/i686" "$TMP/new-glibc-report" 2>&1)
status=$?
set -e
[[ $status -eq 1 && "$output" == *"requires GLIBC_2.32, newer than Debian 11's GLIBC_2.31"* ]]
[[ ! -e "$TMP/new-glibc-report/ffmpeg-i686-verification.txt" ]]

mkdir "$TMP/native-report"
set +e
output=$("$ROOT/scripts/verify-v0232-ffmpeg-i686.sh" --runtime \
  "$TMP/i686" "$TMP/i686" "$TMP/native-report" 2>&1)
status=$?
set -e
[[ $status -eq 1 && "$output" == *'build must run in an i686 userspace process'* ]]
[[ ! -e "$TMP/native-report/ffmpeg-i686-verification.txt" ]]

echo 'FFmpeg verifier static fixtures: PASS'
