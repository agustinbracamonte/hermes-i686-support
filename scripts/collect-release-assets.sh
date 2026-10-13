#!/usr/bin/env bash
# Prepare local GitHub Release candidates without adding binaries to Git.
set -euo pipefail

SOURCE_DIR=${1:-}
OUT_DIR=${2:-dist/release-assets}
[[ -n $SOURCE_DIR && -d $SOURCE_DIR ]] || { echo "Usage: $0 WHEELHOUSE_DIR [OUT_DIR]" >&2; exit 2; }
mkdir -p "$OUT_DIR"
find "$SOURCE_DIR" -maxdepth 1 -type f -name '*.whl' -exec cp -f {} "$OUT_DIR"/ \;
(
  cd "$OUT_DIR"
  find . -maxdepth 1 -type f -name '*.whl' -printf '%f\n' | sort | xargs -r sha256sum > SHA256SUMS
)
printf 'assets=%s\n' "$(find "$OUT_DIR" -maxdepth 1 -type f -name '*.whl' | wc -l)"
echo "manifest=$OUT_DIR/SHA256SUMS"
echo 'verify=(cd "$OUT_DIR" && sha256sum -c SHA256SUMS)'
echo 'release-assets: PASS (do not commit dist/)'
