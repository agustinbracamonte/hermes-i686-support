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

# Exercise each Linux target selector with an x86_64 kernel fixture. The
# ELF fixtures above separately prove how the process ABI is derived.
fake_kernel=x86_64
fake_arch=i686
uname() {
    case "${1:-}" in
        -s) echo Linux ;;
        -m) echo "$fake_kernel" ;;
        *) command uname "$@" ;;
    esac
}
linux_process_arch() { echo "$fake_arch"; }
actual_target=$(uv_bootstrap_target) || fail 'install.sh rejected a simulated i686 process'
[[ "$actual_target" == linux-i686 ]] || fail "install.sh mapped simulated i686 to $actual_target"
fake_arch=x64
actual_target=$(uv_bootstrap_target) || fail 'install.sh rejected a simulated x64 process'
[[ "$actual_target" == linux-x64 ]] || fail "install.sh changed x64 target mapping: $actual_target"

# setup-hermes.sh must use the same process ABI and preserve Darwin mappings.
sed -n '/^setup_target_arch() {/,/^}/p' "$UPSTREAM/setup-hermes.sh" > "$TMP/setup-target.sh"
[[ -s "$TMP/setup-target.sh" ]] || fail 'setup-hermes target resolver missing'
# shellcheck disable=SC1091
source "$TMP/setup-target.sh"
fake_arch=i686
[[ $(setup_target_arch linux) == i686 ]] || fail 'setup-hermes mapped an i686 process incorrectly'
fake_kernel=arm64
[[ $(setup_target_arch darwin) == arm64 ]] || fail 'setup-hermes changed Darwin ARM64 mapping'
fake_kernel=x86_64
[[ $(setup_target_arch darwin) == x64 ]] || fail 'setup-hermes changed Darwin x64 mapping'

# Bootstrap pins must match the real lock exactly. The x64/ARM64 values are
# explicitly retained; no neighboring architecture pin is regenerated.
sed -n '/^# --- BEGIN GENERATED: bootstrap pins /,/^# --- END GENERATED: bootstrap pins ---$/p' \
    "$UPSTREAM/scripts/install.sh" > "$TMP/pins.sh"
# shellcheck disable=SC1091
source "$TMP/pins.sh"
assert_generated_pin_matches_lock() {
    local target="$1" expected_url expected_sha
    uv_bootstrap_pin "$target" || fail "install.sh has no uv pin for $target"
    read -r expected_url expected_sha < <(python3 - "$UPSTREAM/pm/lock.json" "$target" <<'PY'
import json, sys
row = json.load(open(sys.argv[1], encoding="utf-8"))["packages"]["uv"]["artifacts"][sys.argv[2]]
print(row["url"], row["sha256"])
PY
    )
    [[ "$UV_PIN_URL" == "$expected_url" && "$UV_PIN_SHA256" == "$expected_sha" ]] \
        || fail "install.sh pin for $target differs from pm/lock.json"
    [[ "$UV_PIN_SHA256" =~ ^[a-f0-9]{64}$ ]] || fail "$target uv digest malformed"
}
assert_generated_pin_matches_lock linux-i686
assert_generated_pin_matches_lock linux-x64
assert_generated_pin_matches_lock linux-arm64
[[ "$UV_PIN_SHA256" == 4bb69cf95ed13f23713bb7bc09f241896ea0c75b7c557e615a20604b82f9c403 ]] \
    || fail 'ARM64 uv digest changed from the v0.23.2 lock'
uv_bootstrap_pin linux-x64
[[ "$UV_PIN_SHA256" == f68d291c75783122dad58ab77def0e13f3233f358731db5d6d7e8715603b928f ]] \
    || fail 'x64 uv digest changed from the v0.23.2 lock'
expect_fail uv_bootstrap_pin linux-i686-musl

sed -n '/^pin() {/,/^}/p' "$UPSTREAM/setup-hermes.sh" > "$TMP/setup-pin.sh"
[[ -s "$TMP/setup-pin.sh" ]] || fail 'setup-hermes lock reader missing'
# shellcheck disable=SC1091
source "$TMP/setup-pin.sh"
lock="$UPSTREAM/pm/lock.json"
target=linux-i686
[[ "$(pin url)" == 'https://github.com/astral-sh/uv/releases/download/0.13.5/uv-i686-unknown-linux-gnu.tar.gz' ]] \
    || fail 'setup-hermes lost the verified i686 uv URL'
[[ "$(pin sha256)" == f5713d6c05d77d01de9655270d713ba87ed45391752f489c80bbf1690bccc17c ]] \
    || fail 'setup-hermes lost the verified i686 uv digest'
target=linux-x64
[[ -n "$(pin url)" && "$(pin sha256)" =~ ^[a-f0-9]{64}$ ]] || fail 'setup-hermes lost the x64 uv lock row'
target=linux-arm64
[[ -n "$(pin url)" && "$(pin sha256)" =~ ^[a-f0-9]{64}$ ]] || fail 'setup-hermes lost the ARM64 uv lock row'

# The fail-closed path remains covered using an explicit lock fixture after
# the real i686 row is added.
python3 - "$UPSTREAM/pm/lock.json" "$TMP/lock-without-i686.json" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1], encoding="utf-8"))
lock["packages"]["uv"]["artifacts"].pop("linux-i686")
json.dump(lock, open(sys.argv[2], "w", encoding="utf-8"))
PY
lock="$TMP/lock-without-i686.json"
target=linux-i686
[[ -z "$(pin url)" && -z "$(pin sha256)" ]] || fail 'setup-hermes ignored the missing-pin fixture'

echo 'v0.23.2-bootstrap-abi: PASS (i686/x64/ARM64 target fixtures; real host process ABI; lock-backed uv pins; fail-closed fixture)'
