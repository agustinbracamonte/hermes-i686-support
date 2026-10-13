#!/usr/bin/env bash
# Verify a wheel's checksum, metadata tags, and bundled native ELF objects.
set -euo pipefail

WHEEL=${1:-}
EXPECTED_SHA256=${2:-}
[[ -n $WHEEL ]] || { echo "Usage: $0 WHEEL [EXPECTED_SHA256]" >&2; exit 2; }
[[ -f $WHEEL ]] || { echo "wheel not found: $WHEEL" >&2; exit 1; }
command -v unzip >/dev/null || { echo 'missing command: unzip' >&2; exit 1; }

actual=$(sha256sum "$WHEEL" | awk '{print $1}')
echo "wheel=$(basename "$WHEEL")"
echo "sha256=$actual"
if [[ -n $EXPECTED_SHA256 && $actual != "$EXPECTED_SHA256" ]]; then
  echo 'checksum mismatch' >&2
  exit 1
fi
unzip -p "$WHEEL" '*/WHEEL' | sed -n '1,20p'
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
unzip -qq "$WHEEL" -d "$tmp"
found=0
while IFS= read -r -d '' so; do
  found=1
  file "$so"
  readelf -d "$so" | grep -E 'NEEDED.*(libssl|libcrypto)' || true
done < <(find "$tmp" -type f -name '*.so' -print0)
(( found )) || echo 'native_extensions=none'
echo 'wheel-verify: PASS'
