#!/usr/bin/env bash
# Apply and test the pinned patchset in a disposable archive of official upstream.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UPSTREAM=${1:?usage: test-v0232-patchset.sh CLEAN_UPSTREAM_CHECKOUT}
PIN="ae2a81ccc00e9b7c06301523e5bb09608397149c"
PYTHON=${HERMES_PYTHON:-python3}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -d "$UPSTREAM/.git" || -f "$UPSTREAM/.git" ]] || fail 'input is not a Git checkout'
[[ "$(git -C "$UPSTREAM" rev-parse HEAD)" == "$PIN" ]] || fail "input must be exact commit $PIN"
[[ -z "$(git -C "$UPSTREAM" status --porcelain --untracked-files=all)" ]] || fail 'input checkout must be clean'
"$PYTHON" -c 'import pytest' >/dev/null 2>&1 || fail 'set HERMES_PYTHON to an interpreter with pytest installed'

mkdir "$TMP/source"
git -C "$UPSTREAM" archive "$PIN" | tar -xf - -C "$TMP/source"
(
    cd "$TMP/source"
    for patch in "$ROOT"/patches/v0.23.2/[0-9][0-9][0-9][0-9]-*.patch; do
        git apply --check "$patch"
        git apply "$patch"
    done
    git init -q
    git add -A
    bash -n scripts/install.sh setup-hermes.sh
)
"$ROOT/scripts/validate-v0232-bootstrap-abi.sh" "$TMP/source"

test_home="$TMP/hermes-home"
mkdir -p "$test_home"
HERMES_HOME="$test_home" HERMES_PYTHON="$PYTHON" \
    "$TMP/source/scripts/run_tests.sh" \
    tests/pm/test_store.py tests/pm/test_pm_core.py tests/pm/test_downloader.py tests/pm/test_downloader_integrity.py \
    tests/pm/test_pnpm_wasm.py tests/pm/test_gh_i686.py \
    tests/pm/test_install_default_closure.py tests/pm/test_chromium.py tests/pm/test_cua_driver_package.py

echo 'v0.23.2-patchset: PASS (clean pinned source, patch application, PM ABI/ELF/download regression tests)'
