#!/usr/bin/env bash
# Behavioral positive and negative integration tests, using real staged assets when present.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PYTHON_I686=${PYTHON_I686:-${HOME}/.hermes/hermes-agent/.venv/bin/python}
REAL_WHEEL=${REAL_WHEEL:-${HOME}/.hermes/wheelhouse/cryptography-50.0.0-cp311-abi3-linux_i686.whl}
REAL_SHA=71893373af19e01f446f3b3d98cf674c5cbf8d1842d01a1fd5ace41c097b9500
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail(){ echo "FAIL: $*" >&2; exit 1; }
expect_fail(){ if "$@" >"$TMP/out" 2>&1; then fail "unexpected success: $*"; fi; }

sha=$(sha256sum "$REAL_WHEEL" | cut -d' ' -f1)
[[ $sha == "$REAL_SHA" ]] || fail 'staged wheel digest mismatch'
"$ROOT/scripts/verify-wheel.sh" "$REAL_WHEEL" "$REAL_SHA" >/dev/null || fail 'real i686 wheel rejected'
expect_fail "$ROOT/scripts/verify-wheel.sh" "$REAL_WHEEL" "$(printf '0%.0s' {1..64})"

# Generate validly-tagged fake wheels with malformed/64-bit native ELF; ensure strict checker rejects.
"$PYTHON_I686" - "$TMP/fakes" <<'PY'
import pathlib,struct,sys,zipfile
p=pathlib.Path(sys.argv[1]);p.mkdir()
elf64=b'\x7fELF'+bytes([2,1,1])+bytes(9)+struct.pack('<HHIQQQIHHHHHH',3,62,1,0,0,0,0,64,0,0,0,0,0)
for name,body in [('bad64',elf64),('badmagic',b'not-an-elf')]:
 d=p/name; d.mkdir()
 with zipfile.ZipFile(d/'cryptography-50.0.0-cp311-abi3-linux_i686.whl','w') as z:
  z.writestr('cryptography-50.0.0.dist-info/WHEEL','Wheel-Version: 1.0\nRoot-Is-Purelib: false\nTag: cp311-abi3-linux_i686\n')
  z.writestr('cryptography-50.0.0.dist-info/METADATA','Name: cryptography\nVersion: 50.0.0\n')
  z.writestr('cryptography/hazmat/bindings/_rust.abi3.so',body)
PY
for bad in "$TMP"/fakes/*/*.whl; do d=$(sha256sum "$bad"|cut -d' ' -f1); expect_fail "$ROOT/scripts/verify-wheel.sh" "$bad" "$d"; done
"$ROOT/scripts/check-runtime.sh" --python "$PYTHON_I686" >/dev/null || fail 'valid staged i686 Python runtime rejected'
expect_fail "$ROOT/scripts/check-runtime.sh" --python python3
# Build preflight must reject the host Python ABI before creating a work directory or downloading inputs.
expect_fail env PYTHON_BIN=python3 WORKDIR="$TMP/should-not-exist" CRYPTOGRAPHY_SDIST_SHA256="$(printf '0%.0s' {1..64})" OPENSSL_SHA256="$(printf '0%.0s' {1..64})" "$ROOT/scripts/build-cryptography-i686.sh"
[[ ! -e $TMP/should-not-exist ]] || fail 'build preflight created workdir before refusing wrong ABI'

# Release only accepts exact manifest-listed artifact and rejects extra unapproved wheels.
mkdir -p "$TMP/source"
cp "$REAL_WHEEL" "$TMP/source/$(basename "$REAL_WHEEL")"
printf '%s  %s\n' "$REAL_SHA" "$(basename "$REAL_WHEEL")" > "$TMP/approved.txt"
out="$TMP/release-out"
"$ROOT/scripts/collect-release-assets.sh" "$TMP/source" "$out" "$TMP/approved.txt" >/dev/null || fail 'approved release asset rejected'
(cd "$out" && sha256sum -c SHA256SUMS >/dev/null) || fail 'release output checksum failed'
[[ $(find "$out" -maxdepth 1 -type f -name '*.whl' | wc -l) -eq 1 ]] || fail 'collector copied unexpected wheels'
[[ -f "$out/$(basename "$REAL_WHEEL")" ]] || fail 'collector omitted the approved wheel'
# A checksum mismatch for the approved exact filename is rejected.
cp "$REAL_WHEEL" "$TMP/source/cryptography-50.0.0-cp311-abi3-linux_i686.whl"
printf '%s  %s\n' "$(printf '0%.0s' {1..64})" "$(basename "$REAL_WHEEL")" > "$TMP/wrong.txt"
expect_fail "$ROOT/scripts/collect-release-assets.sh" "$TMP/source" "$TMP/release-out2" "$TMP/wrong.txt"
printf '%s  %s\n' "$REAL_SHA" "$(basename "$REAL_WHEEL")" > "$TMP/approved.txt"
# Unapproved JAR/JNI artifacts are never copied; manifest cannot authorize them.
printf '%s  %s\n' "$REAL_SHA" 'signal-cli-i386.jar' > "$TMP/signal.txt"
expect_fail "$ROOT/scripts/collect-release-assets.sh" "$TMP/source" "$TMP/release-out3" "$TMP/signal.txt"

echo 'strict-scripts: PASS (real wheel positive; hash/ELF/runtime/release negatives rejected)'
