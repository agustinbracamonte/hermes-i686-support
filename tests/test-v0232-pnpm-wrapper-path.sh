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
grep -Fq -- '--node-store PATH' <<<"$help"
missing_node=$("$ROOT/scripts/test-v0232-pnpm-wasm-pm-stage.sh" /tmp/untrusted-checkout --require-ia32 2>&1 || true)
grep -Fq -- '--require-ia32 requires --node-bin or PNPM_NODE_BIN' <<<"$missing_node"
missing_store=$(PNPM_NODE_BIN=/tmp/untrusted-runtime/node \
  "$ROOT/scripts/test-v0232-pnpm-wasm-pm-stage.sh" /tmp/untrusted-checkout 2>&1 || true)
grep -Fq 'explicit isolated --node-store' <<<"$missing_store"
missing_node_for_store=$("$ROOT/scripts/test-v0232-pnpm-wasm-pm-stage.sh" \
  /tmp/untrusted-checkout --node-store /tmp/untrusted-runtime 2>&1 || true)
grep -Fq -- '--node-store requires --node-bin or PNPM_NODE_BIN' <<<"$missing_node_for_store"
relative_store=$(PNPM_NODE_BIN=/tmp/untrusted-runtime/node \
  "$ROOT/scripts/test-v0232-pnpm-wasm-pm-stage.sh" /tmp/untrusted-checkout \
  --node-store relative/runtime 2>&1 || true)
grep -Fq -- '--node-store must be an absolute path' <<<"$relative_store"

# Mock the shell runner around a pre-existing Node store and a symlink to that
# store. The runner must pass its own mktemp child to PM in both cases, and it
# must leave every file in the supplied Node store untouched.
mock_bin="$TMP/mock-bin"
fake_checkout="$TMP/fake-checkout"
node_store="$TMP/preexisting-node-store"
node_store_link="$TMP/node-store-link"
mkdir -p "$mock_bin" "$fake_checkout/.git" "$node_store"
printf 'verified fixture archive\n' >"$TMP/pnpm-wasm.tgz"
printf 'fixture node\n' >"$node_store/node"
chmod 755 "$node_store/node"
ln -s "$node_store" "$node_store_link"
cat >"$mock_bin/git" <<'GIT'
#!/usr/bin/env bash
[[ "$1" == -C && "$3" == rev-parse && "$4" == HEAD ]] || exit 97
printf 'ae2a81ccc00e9b7c06301523e5bb09608397149c\n'
GIT
cat >"$mock_bin/python" <<'PYTHON'
#!/bin/sh
{
  printf 'runtime=%s\n' "$HERMES_RUNTIME_DIR"
  printf 'node_store=%s\n' "$PNPM_NODE_STORE"
} >"$PNPM_TEST_RECORD"
PYTHON
chmod 755 "$mock_bin/git" "$mock_bin/python"
store_snapshot() {
  find "$node_store" -type f -print0 | sort -z | xargs -0 -r sha256sum
}
before_store=$(store_snapshot)
for selected_store in "$node_store" "$node_store_link"; do
  record="$TMP/runner-record"
  PATH="$mock_bin:$PATH" TMPDIR="$selected_store" HERMES_PYTHON="$mock_bin/python" \
    PNPM_WASM_ARCHIVE="$TMP/pnpm-wasm.tgz" PNPM_TEST_RECORD="$record" \
    "$ROOT/scripts/test-v0232-pnpm-wasm-pm-stage.sh" "$fake_checkout" \
    --node-bin "$selected_store/node" --node-store "$selected_store"
  runtime=$(sed -n 's/^runtime=//p' "$record")
  passed_store=$(sed -n 's/^node_store=//p' "$record")
  stage_root=${runtime%/tools}
  case "$stage_root" in
    /tmp/hermes-pnpm-stage.*|/var/tmp/hermes-pnpm-stage.*) ;;
    *) echo "runner used an unexpected temp path: $runtime" >&2; exit 1 ;;
  esac
  [[ "$passed_store" == "$selected_store" ]]
  [[ "$runtime" != "$selected_store" ]]
  [[ ! -e "$runtime" ]]
  [[ "$stage_root" != "$(realpath "$selected_store")"* ]]
  [[ "$(store_snapshot)" == "$before_store" ]]
done
grep -Fq 'HERMES_RUNTIME_DIR="$TMP/tools"' "$ROOT/scripts/test-v0232-pnpm-wasm-pm-stage.sh"
grep -Fq 'store = Path(os.environ["HERMES_RUNTIME_DIR"]).resolve()' \
  "$ROOT/scripts/test-v0232-pnpm-wasm-pm-stage.sh"
! grep -Eq 'HERMES_RUNTIME_DIR=.*PNPM_NODE_STORE|mkdir[^\n]*PNPM_NODE_STORE' \
  "$ROOT/scripts/test-v0232-pnpm-wasm-pm-stage.sh"

python3 - "$ROOT/scripts/test-v0232-pnpm-wasm-pm-stage.sh" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text().splitlines()
start = next(i for i, line in enumerate(lines) if line.endswith("<<'PY'")) + 1
end = next(i for i in range(start, len(lines)) if lines[i] == "PY")
compile("\n".join(lines[start:end]), str(path), "exec")
PY
echo 'pnpm managed Node wrapper: PASS (path precedence, argv forwarding, and read-only Node store staging)'
