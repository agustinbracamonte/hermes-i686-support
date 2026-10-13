#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
BASE="$ROOT/integrations/signal-cli"
for script in "$BASE"/scripts/*.sh; do bash -n "$script"; done
for patch in "$BASE"/patches/*.patch; do test -s "$patch"; done
printf '%s  %s\n' 65324d5d5dfd40f7392fd05a7f57a53927c0742bd1815c0156cc3ef7cc581e4d "$BASE/patches/signal-cli-v0.14.9-java21-i386.patch" 0effc12567d12d6137e6a97a231b3af7d39feb6745264487692d38c4ed882215 "$BASE/patches/libsignal-v0.103.0-i386-protobuf-root.patch" | sha256sum -c - >/dev/null
grep -Fq 'GPL-3.0-only' "$BASE/patches/README.md"
grep -Fq 'AGPL-3.0-only' "$BASE/patches/README.md"
grep -Fq 'Not release-ready' "$BASE/README.md"
echo 'signal-cli-structure: PASS (syntax/layout only; no JNI functional test was performed)'
