#!/usr/bin/env bash
# Exercise the privacy scanner against a temporary repository without exposing matched data.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
mkdir -p "$T/repo/scripts"
cp "$ROOT/scripts/publication-audit.sh" "$T/repo/scripts/"
git -C "$T/repo" init -q
git -C "$T/repo" -c user.name=Fixture -c user.email=fixture commit --allow-empty -qm fixture
printf 'ordinary public text\n' > "$T/repo/README.md"
"$T/repo/scripts/publication-audit.sh" >/dev/null
# A fake private-key marker must be detected from working tree and then from committed history.
printf '%s\n' '-----BEGIN PRIVATE KEY''-----' > "$T/repo/fixture.txt"
if "$T/repo/scripts/publication-audit.sh" >"$T/out" 2>&1; then echo 'scanner missed working-tree key marker' >&2; exit 1; fi
grep -Fq 'categories=private_key' "$T/out" || { echo 'scanner did not classify key marker' >&2; exit 1; }
# Never expose matching contents in diagnostics.
if grep -Fq 'BEGIN PRIVATE KEY' "$T/out"; then echo 'scanner leaked matched content' >&2; exit 1; fi
rm "$T/repo/fixture.txt"
printf '%s\n' 'user@''example.invalid' > "$T/repo/committed.txt"
git -C "$T/repo" add committed.txt
git -C "$T/repo" -c user.name=Fixture -c user.email=fixture commit -qm fixture-pii
if "$T/repo/scripts/publication-audit.sh" >"$T/out" 2>&1; then echo 'scanner missed PII in reachable history' >&2; exit 1; fi
grep -Fq 'scope=history' "$T/out" || { echo 'scanner did not inspect history objects' >&2; exit 1; }
if grep -Fq 'user@''example.invalid' "$T/out"; then echo 'scanner leaked matched content' >&2; exit 1; fi
echo 'publication-audit-tests: PASS (worktree and Git history findings, redacted diagnostics)'
