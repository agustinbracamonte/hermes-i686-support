#!/usr/bin/env bash
# Exercise the inline ABI probes from both standalone bootstrap scripts.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
UPSTREAM=${1:?usage: validate-v0232-bootstrap-abi.sh UPSTREAM_CHECKOUT}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
expect_fail() {
    if "$@" >/dev/null 2>&1; then fail "unexpected success: $*"; fi
}

for script in scripts/install.sh setup-hermes.sh; do
    sed -n '/^# --- BEGIN: Linux process ABI probe ---$/,/^# --- END: Linux process ABI probe ---$/p' \
        "$UPSTREAM/$script" | sed '1d;$d' > "$TMP/$(basename "$script").abi"
    [[ -s "$TMP/$(basename "$script").abi" ]] || fail "ABI probe missing from $script"
done
cmp -s "$TMP/install.sh.abi" "$TMP/setup-hermes.sh.abi" || fail 'bootstrap ABI probes have drifted'
# shellcheck disable=SC1091
source "$TMP/install.sh.abi"

make_elf() {
    python3 - "$1" "$2" "$3" <<'PY'
import pathlib, sys
path, elf_class, machine = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
header = bytearray(64)
header[:4] = b"\x7fELF"
header[4:6] = bytes((elf_class, 1))
header[18:20] = machine.to_bytes(2, "little")
pathlib.Path(path).write_bytes(header)
PY
}

make_elf "$TMP/i686" 1 3
make_elf "$TMP/x64" 2 62
make_elf "$TMP/arm64" 2 183
make_elf "$TMP/x32" 1 62
[[ $(linux_process_arch_from_elf "$TMP/i686" x86_64 32) == i686 ]] || fail '32-bit process under x86_64 kernel was not i686'
[[ $(linux_process_arch_from_elf "$TMP/x64" x86_64 64) == x64 ]] || fail 'x64 regression'
[[ $(linux_process_arch_from_elf "$TMP/arm64" aarch64 64) == arm64 ]] || fail 'ARM64 regression'
expect_fail linux_process_arch_from_elf "$TMP/x32" x86_64 32
expect_fail linux_process_arch_from_elf "$TMP/x64" x86_64 32

case "$(uname -m):$(getconf LONG_BIT 2>/dev/null || true)" in
    x86_64:64|amd64:64) expected=x64 ;;
    x86_64:32|amd64:32|i386:32|i486:32|i586:32|i686:32) expected=i686 ;;
    aarch64:64|arm64:64) expected=arm64 ;;
    *) fail "unsupported validation host: $(uname -m) / $(getconf LONG_BIT 2>/dev/null || echo unknown)" ;;
esac
actual=$(linux_process_arch)
[[ "$actual" == "$expected" ]] || fail "actual shell ABI mismatch: expected $expected, got $actual"
sed -n '/^uv_bootstrap_target() {/,/^}/p' "$UPSTREAM/scripts/install.sh" > "$TMP/install-target.sh"
[[ -s "$TMP/install-target.sh" ]] || fail 'install.sh target resolver missing'
# shellcheck disable=SC1091
source "$TMP/install-target.sh"
actual_target=$(uv_bootstrap_target) || fail 'install.sh rejected the current Linux process ABI'
[[ "$actual_target" == "linux-$expected" || "$actual_target" == "linux-$expected-"* ]] \
    || fail "install.sh target disagrees with process ABI: $actual_target"

# The v0.23.2 lock has no i686 uv row yet. The installer must refuse it,
# while the existing x64 and ARM64 rows remain available.
sed -n '/^# --- BEGIN GENERATED: bootstrap pins /,/^# --- END GENERATED: bootstrap pins ---$/p' \
    "$UPSTREAM/scripts/install.sh" > "$TMP/pins.sh"
# shellcheck disable=SC1091
source "$TMP/pins.sh"
expect_fail uv_bootstrap_pin linux-i686
uv_bootstrap_pin linux-x64 || fail 'lost the x64 uv pin'
[[ "$UV_PIN_SHA256" =~ ^[a-f0-9]{64}$ ]] || fail 'x64 uv pin digest malformed'
uv_bootstrap_pin linux-arm64 || fail 'lost the ARM64 uv pin'
[[ "$UV_PIN_SHA256" =~ ^[a-f0-9]{64}$ ]] || fail 'ARM64 uv pin digest malformed'

sed -n '/^pin() {/,/^}/p' "$UPSTREAM/setup-hermes.sh" > "$TMP/setup-pin.sh"
[[ -s "$TMP/setup-pin.sh" ]] || fail 'setup-hermes lock reader missing'
# shellcheck disable=SC1091
source "$TMP/setup-pin.sh"
lock="$UPSTREAM/pm/lock.json"
target=linux-i686
[[ -z "$(pin url)" && -z "$(pin sha256)" ]] || fail 'setup-hermes found an unpinned i686 uv artifact'
target=linux-x64
[[ -n "$(pin url)" && "$(pin sha256)" =~ ^[a-f0-9]{64}$ ]] || fail 'setup-hermes lost the x64 uv lock row'
target=linux-arm64
[[ -n "$(pin url)" && "$(pin sha256)" =~ ^[a-f0-9]{64}$ ]] || fail 'setup-hermes lost the ARM64 uv lock row'

echo 'v0.23.2-bootstrap-abi: PASS (i686/x64/ARM64 fixtures; real host process ABI; no i686 pin fallback)'
