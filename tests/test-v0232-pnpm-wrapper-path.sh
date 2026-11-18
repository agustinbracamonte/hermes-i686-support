#!/usr/bin/env bash
# Fixture test for the Linux i686 pnpm launcher's controlled Node resolution.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

store="$TMP/runtime-store/node/26.12.1/bin"
entry="$TMP/runtime-store/pnpm/fixture"
controlled="$TMP/controlled-path"
host="$TMP/host-path"
mkdir -p "$store" "$entry/bin" "$entry/package/dist" "$controlled" "$host"

managed_node="$store/node"
cat >"$managed_node" <<'NODE'
#!/usr/bin/env bash
set -euo pipefail
printf 'managed-node' >>"$PNPM_NODE_LOG"
for arg in "$@"; do printf ' <%s>' "$arg" >>"$PNPM_NODE_LOG"; done
printf '\n' >>"$PNPM_NODE_LOG"
if [[ "$1" == --version ]]; then
  printf 'v26.12.1\n'
elif [[ "$1" == -p && "$2" == process.arch ]]; then
  printf 'ia32\n'
elif [[ "$1" == */pnpm.mjs && "$2" == --version ]]; then
  printf '12.15.0\n'
elif [[ "$1" == */pnpm.mjs && "$2" == --help ]]; then
  printf 'pnpm-help\n'
elif [[ "$1" == */pnpm.mjs && "$2" == install ]]; then
  printf 'pnpm-install-forwarded\n'
else
  printf 'unexpected managed Node arguments\n' >&2
  exit 90
fi
NODE
chmod 755 "$managed_node"

cat >"$host/node" <<'HOST'
#!/usr/bin/env bash
printf 'host-node-used\n' >>"$PNPM_NODE_LOG"
exit 91
HOST
chmod 755 "$host/node"
ln -s "$managed_node" "$controlled/node"

# Match the exact launcher emitted by the pinned Hermes pnpm PM patch.
grep -Fq 'exec node "$here/package/dist/{cli}" "$@"' \
  "$ROOT/patches/v0.23.2/0003-pnpm-wasm-i686.patch"
cat >"$entry/bin/pnpm" <<'WRAPPER'
#!/bin/sh
here="$(cd "$(dirname "$0")/.." && pwd)"
exec node "$here/package/dist/pnpm.mjs" "$@"
WRAPPER
chmod 755 "$entry/bin/pnpm"

path="$controlled:$host:/usr/bin:/bin"
env -i HOME="$TMP/home" PATH="$path" PNPM_NODE_LOG="$TMP/node.log" \
  bash -c 'test "$(command -v node)" = "$1/node" && test "$(readlink -f "$(command -v node)")" = "$2"' \
  _ "$controlled" "$managed_node"

result=$(cd "$TMP" && env -i HOME="$TMP/home" PATH="$path" \
  PNPM_NODE_LOG="$TMP/node.log" "$entry/bin/pnpm" --version)
[[ "$result" == 12.15.0 ]]
help_result=$(cd "$TMP" && env -i HOME="$TMP/home" PATH="$path" \
  PNPM_NODE_LOG="$TMP/node.log" "$entry/bin/pnpm" --help)
[[ "$help_result" == pnpm-help ]]
install_result=$(cd "$TMP" && env -i HOME="$TMP/home" PATH="$path" \
  PNPM_NODE_LOG="$TMP/node.log" "$entry/bin/pnpm" install --offline --ignore-scripts)
[[ "$install_result" == pnpm-install-forwarded ]]
grep -Fq "managed-node <$entry/package/dist/pnpm.mjs> <install> <--offline> <--ignore-scripts>" "$TMP/node.log"
! grep -Fq 'host-node-used' "$TMP/node.log"

help=$("$ROOT/scripts/test-v0232-pnpm-wasm-pm-stage.sh" --help)
grep -Fq -- '--node-bin PATH' <<<"$help"
missing_node=$("$ROOT/scripts/test-v0232-pnpm-wasm-pm-stage.sh" /tmp/untrusted-checkout --require-ia32 2>&1 || true)
grep -Fq -- '--require-ia32 requires --node-bin or PNPM_NODE_BIN' <<<"$missing_node"
missing_store=$(PNPM_NODE_BIN=/tmp/untrusted-runtime/node \
  "$ROOT/scripts/test-v0232-pnpm-wasm-pm-stage.sh" /tmp/untrusted-checkout 2>&1 || true)
grep -Fq 'explicit isolated --runtime-dir store' <<<"$missing_store"
missing_node_for_store=$("$ROOT/scripts/test-v0232-pnpm-wasm-pm-stage.sh" \
  /tmp/untrusted-checkout --runtime-dir /tmp/untrusted-runtime 2>&1 || true)
grep -Fq -- '--runtime-dir requires --node-bin or PNPM_NODE_BIN' <<<"$missing_node_for_store"
relative_store=$(PNPM_NODE_BIN=/tmp/untrusted-runtime/node \
  "$ROOT/scripts/test-v0232-pnpm-wasm-pm-stage.sh" /tmp/untrusted-checkout \
  --runtime-dir relative/runtime 2>&1 || true)
grep -Fq -- '--runtime-dir must be an absolute path' <<<"$relative_store"

python3 - "$ROOT/scripts/test-v0232-pnpm-wasm-pm-stage.sh" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text().splitlines()
start = next(i for i, line in enumerate(lines) if line.endswith("<<'PY'")) + 1
end = next(i for i in range(start, len(lines)) if lines[i] == "PY")
compile("\n".join(lines[start:end]), str(path), "exec")
PY
echo 'pnpm managed Node wrapper: PASS (path precedence and argv forwarding)'
