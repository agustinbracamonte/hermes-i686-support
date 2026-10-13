#!/usr/bin/env bash
# Self-contained static checks; no recovered i686 Python/wheel is required.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
python3 - "$T" <<'PY'
import pathlib,sys,zipfile
root=pathlib.Path(sys.argv[1])
# A deliberately malformed ELF payload must be rejected without ever executing it.
wheel=root/'cryptography-50.0.0-cp311-abi3-linux_i686.whl'
with zipfile.ZipFile(wheel,'w') as z:
 z.writestr('cryptography-50.0.0.dist-info/WHEEL','Wheel-Version: 1.0\nRoot-Is-Purelib: false\nTag: cp311-abi3-linux_i686\n')
 z.writestr('cryptography-50.0.0.dist-info/METADATA','Name: cryptography\nVersion: 50.0.0\n')
 z.writestr('cryptography/hazmat/bindings/_rust.abi3.so',b'not-an-elf')
PY
sha=$(sha256sum "$T/cryptography-50.0.0-cp311-abi3-linux_i686.whl" | cut -d' ' -f1)
if "$ROOT/scripts/verify-wheel.sh" "$T/cryptography-50.0.0-cp311-abi3-linux_i686.whl" "$sha" >"$T/out" 2>&1; then echo 'static verifier accepted malformed ELF' >&2; exit 1; fi
if grep -Eiq '(^|[[:space:]/])ldd([[:space:]]|$)' "$ROOT/scripts/verify-wheel.sh" "$ROOT/scripts/check-runtime.sh"; then echo 'ELF checker still references ldd' >&2; exit 1; fi
# Runtime validation must refuse execution without an isolated root and validated wheel provenance.
if "$ROOT/scripts/check-runtime.sh" --python python3 >"$T/out" 2>&1; then echo 'runtime check accepted missing provenance/staging arguments' >&2; exit 1; fi
bash -n "$ROOT/scripts/verify-wheel.sh" "$ROOT/scripts/check-runtime.sh"
echo 'static-validation-tests: PASS (malformed ELF rejected without execution; runtime requires staged provenance)'
