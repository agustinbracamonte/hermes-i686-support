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
# Fake provider credential assignments must fail closed in worktree and redacted diagnostics.
for key in OPENAI_API_KEY TELEGRAM_BOT_TOKEN ANTHROPIC_API_KEY GITHUB_TOKEN AWS_SECRET_ACCESS_KEY; do
  printf '%s=%s\n' "$key" 'fixture-secret-value-with-alpha-suffix' > "$T/repo/fixture.txt"
  if "$T/repo/scripts/publication-audit.sh" >"$T/out" 2>&1; then echo "scanner missed credential assignment category: $key" >&2; exit 1; fi
  grep -Eq 'categories=.*credential_assignment' "$T/out" || { echo 'scanner did not classify credential assignment' >&2; exit 1; }
  if grep -Fq 'fixture-secret-value-with-alpha-suffix' "$T/out"; then echo 'scanner leaked matched value' >&2; exit 1; fi
done
rm -f "$T/repo/fixture.txt"
# Commit message bodies, not just author metadata, must be scanned and redacted.
for key in OPENAI_API_KEY TELEGRAM_BOT_TOKEN ANTHROPIC_API_KEY GITHUB_TOKEN AWS_SECRET_ACCESS_KEY; do
  git -C "$T/repo" -c user.name=Fixture -c user.email=fixture commit --allow-empty -qm "$key=fixture-secret-value-with-alpha-suffix"
  if "$T/repo/scripts/publication-audit.sh" >"$T/out" 2>&1; then echo 'scanner missed credential in commit message' >&2; exit 1; fi
  grep -Fq 'scope=commit:' "$T/out" || { echo 'scanner did not inspect commit message' >&2; exit 1; }
  if grep -Fq 'fixture-secret-value-with-alpha-suffix' "$T/out"; then echo 'scanner leaked commit-message value' >&2; exit 1; fi
done
# Also scan dangling commit messages that are not reachable from any ref or HEAD.
tree=$(git -C "$T/repo" write-tree)
parent=$(git -C "$T/repo" rev-parse HEAD)
printf '%s\n' 'AWS_SECRET_ACCESS_KEY=fixture-secret-value-with-alpha-suffix' |
  git -C "$T/repo" -c user.name=Fixture -c user.email=fixture commit-tree "$tree" -p "$parent" >/dev/null
if "$T/repo/scripts/publication-audit.sh" >"$T/out" 2>&1; then echo 'scanner missed credential in unreachable commit message' >&2; exit 1; fi
grep -Fq 'scope=unreachable-commit:' "$T/out" || { echo 'scanner did not inspect unreachable commit messages' >&2; exit 1; }
if grep -Fq 'fixture-secret-value-with-alpha-suffix' "$T/out"; then echo 'scanner leaked unreachable commit-message value' >&2; exit 1; fi
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
