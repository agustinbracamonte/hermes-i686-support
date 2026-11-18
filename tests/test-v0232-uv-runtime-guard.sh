#!/usr/bin/env bash
# Ensure runtime mode refuses x86_64 before looking for source or downloading assets.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/scripts/verify-v0232-uv-i686.sh"
bash -n "$SCRIPT"
"$SCRIPT" --help >/dev/null

set +e
output=$("$SCRIPT" --runtime /path/that/does/not/exist 2>&1)
status=$?
set -e
[[ $status -eq 1 ]] || { echo 'runtime guard returned an unexpected status' >&2; exit 1; }
[[ "$output" == *'runtime must run in an i686 userspace process'* ]] || {
    echo "runtime mode did not refuse the x86_64 process before touching inputs: $output" >&2
    exit 1
}
[[ "$output" != *'curl'* && "$output" != *'download'* ]] || {
    echo 'runtime mode attempted asset access before the native ABI guard' >&2
    exit 1
}
echo 'uv i686 runtime guard: PASS (x86_64 refused before input/network access)'
