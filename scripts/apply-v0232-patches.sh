#!/usr/bin/env bash
# Apply the public v0.23.2 patchset only to a clean, exact upstream checkout.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PATCH_DIR="$ROOT/patches/v0.23.2"
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
mapfile -t patches < <(find "$PATCH_DIR" -maxdepth 1 -type f -name '[0-9][0-9][0-9][0-9]-*.patch' -print | sort)
[[ ${#patches[@]} -gt 0 ]] || { echo "no patches found in $PATCH_DIR" >&2; exit 1; }

head=$(git -C "$source_dir" rev-parse HEAD)
[[ "$head" == "$PIN" ]] || { echo "expected Hermes v0.23.2 commit $PIN, found $head" >&2; exit 1; }
[[ -z "$(git -C "$source_dir" status --porcelain --untracked-files=all)" ]] || {
    echo "upstream checkout must be clean before patching" >&2
    exit 1
}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
git -C "$source_dir" archive "$PIN" | tar -xf - -C "$TMP"
for patch in "${patches[@]}"; do
    (cd "$TMP" && git apply --check "$patch" && git apply "$patch")
done

if [[ "$mode" == --apply ]]; then
    for patch in "${patches[@]}"; do
        git -C "$source_dir" apply "$patch"
    done
    echo "Applied Hermes v0.23.2 i686 patch series to $source_dir"
else
    echo "Patch series applies cleanly to Hermes v0.23.2 ($head)"
fi
