#!/usr/bin/env bash
# Apply the public v0.23.2 patchset only to a clean, exact upstream checkout.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PATCH="$ROOT/patches/v0.23.2/0001-linux-i686-process-abi.patch"
PIN="ae2a81ccc00e9b7c06301523e5bb09608397149c"

usage() {
    echo "usage: $0 --check|--apply UPSTREAM_CHECKOUT" >&2
    exit 2
}

[[ $# == 2 ]] || usage
mode=$1
source_dir=$(realpath -e "$2")
[[ "$mode" == --check || "$mode" == --apply ]] || usage
[[ -d "$source_dir/.git" || -f "$source_dir/.git" ]] || { echo "not a Git checkout: $source_dir" >&2; exit 1; }
[[ -f "$PATCH" ]] || { echo "missing patch: $PATCH" >&2; exit 1; }

head=$(git -C "$source_dir" rev-parse HEAD)
[[ "$head" == "$PIN" ]] || { echo "expected Hermes v0.23.2 commit $PIN, found $head" >&2; exit 1; }
[[ -z "$(git -C "$source_dir" status --porcelain --untracked-files=all)" ]] || {
    echo "upstream checkout must be clean before patching" >&2
    exit 1
}
git -C "$source_dir" apply --check "$PATCH"
if [[ "$mode" == --apply ]]; then
    git -C "$source_dir" apply "$PATCH"
    echo "Applied Hermes v0.23.2 i686 patchset to $source_dir"
else
    echo "Patch applies cleanly to Hermes v0.23.2 ($head)"
fi
