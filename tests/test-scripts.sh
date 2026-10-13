#!/usr/bin/env bash
# Self-contained suite; does not import native code or require recovered i686 artifacts.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
for script in "$ROOT"/scripts/*.sh "$ROOT"/integrations/signal-cli/scripts/*.sh "$ROOT"/tests/*.sh; do bash -n "$script"; done
out=$("$ROOT/scripts/preflight.sh" --python "${PYTHON_UNDER_TEST:-python3}")
printf '%s\n' "$out" | grep -Fq 'preflight: PASS'
"$ROOT/tests/test-static-validation.sh"
"$ROOT/tests/test-publication-audit.sh"
"$ROOT/tests/test-signal-provenance.sh"
"$ROOT/tests/test-signal-cli-integration.sh"
echo 'scripts: PASS (self-contained syntax, static, privacy and provenance tests; no i686 execution)'
