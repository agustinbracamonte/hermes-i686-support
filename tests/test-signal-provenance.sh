#!/usr/bin/env bash
# Synthetic local provenance tests; no upstream source or native build is required.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$ROOT/integrations/signal-cli/scripts/verify-patched-checkout.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
repo="$T/repo"; mkdir -p "$repo"; git -C "$repo" init -q; git -C "$repo" config user.name Fixture; git -C "$repo" config user.email fixture
printf 'base\n' > "$repo/source.txt"; git -C "$repo" add source.txt; git -C "$repo" commit -qm base; git -C "$repo" tag v-test
printf 'authorized\n' >> "$repo/source.txt"; git -C "$repo" diff > "$T/authorized.patch"; sha=$(sha256sum "$T/authorized.patch" | cut -d' ' -f1)
"$HELPER" "$repo" v-test "$T/authorized.patch" "$sha" >/dev/null || { echo 'valid pinned patch rejected' >&2; exit 1; }
printf 'extra modification\n' >> "$repo/source.txt"
if "$HELPER" "$repo" v-test "$T/authorized.patch" "$sha" >"$T/out" 2>&1; then echo 'helper accepted additional source modification' >&2; exit 1; fi
git -C "$repo" reset --hard -q HEAD; git -C "$repo" apply "$T/authorized.patch"
printf 'unexpected extra file\n' > "$repo/untracked.txt"
if "$HELPER" "$repo" v-test "$T/authorized.patch" "$sha" >"$T/out" 2>&1; then echo 'helper accepted extra untracked source file' >&2; exit 1; fi
rm "$repo/untracked.txt"
if "$HELPER" "$repo" v-test "$T/authorized.patch" "$(printf '0%.0s' {1..64})" >"$T/out" 2>&1; then echo 'helper accepted wrong patch digest' >&2; exit 1; fi
git -C "$repo" add source.txt; git -C "$repo" commit -qm unexpected
if "$HELPER" "$repo" v-test "$T/authorized.patch" "$sha" >"$T/out" 2>&1; then echo 'helper accepted HEAD beyond pinned tag' >&2; exit 1; fi
echo 'signal-provenance-tests: PASS (exact tag+patch accepted; extras, wrong digest and moved HEAD rejected)'
