#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BASE="$ROOT/integrations/signal-cli"
for script in "$BASE"/scripts/*.sh; do bash -n "$script"; done
for patch in "$BASE"/patches/*.patch; do test -s "$patch"; done
grep -Fq 'GPL-3.0-only' "$BASE/patches/README.md"
grep -Fq 'AGPL-3.0-only' "$BASE/patches/README.md"
grep -Fq 'Not release-ready' "$BASE/README.md"
echo 'signal-cli-script-layout: PASS'
