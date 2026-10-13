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

"$ROOT/scripts/check-runtime.sh" --python "${PYTHON_I686:-${HOME}/.hermes/hermes-agent/.venv/bin/python}" >/dev/null
"$ROOT/tests/test-strict-scripts.sh"
"$ROOT/tests/test-publication-audit.sh"
echo 'scripts: PASS (syntax and behavioral tests)'
