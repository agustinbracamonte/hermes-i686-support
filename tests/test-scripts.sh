#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

for script in preflight.sh check-runtime.sh verify-wheel.sh build-cryptography-i686.sh collect-release-assets.sh; do
  path="$ROOT/scripts/$script"
  test -f "$path"
  bash -n "$path"
done

out=$("$ROOT/scripts/preflight.sh" --python "${PYTHON_UNDER_TEST:-python3}")
printf '%s\n' "$out" | grep -Fq 'preflight: PASS'

out=$("$ROOT/scripts/check-runtime.sh" --python "${PYTHON_UNDER_TEST:-python3}")
printf '%s\n' "$out" | grep -Fq 'runtime-check:'

grep -Fq 'verify=(cd "$OUT_DIR" && sha256sum -c SHA256SUMS)' "$ROOT/scripts/collect-release-assets.sh"
grep -Fq 'curl tar make gcc perl sha256sum' "$ROOT/scripts/build-cryptography-i686.sh"

echo 'scripts: PASS'
