#!/usr/bin/env bash
# Verify a wheel against the validated cryptography i686 ABI profile.
set -euo pipefail
WHEEL=${1:-}; EXPECTED_SHA256=${2:-}; EXPECTED_TAG=${EXPECTED_TAG:-cp311-abi3-linux_i686}
[[ -n $WHEEL && -n $EXPECTED_SHA256 ]] || { echo "Usage: $0 WHEEL EXPECTED_SHA256" >&2; exit 2; }
[[ -f $WHEEL ]] || { echo 'wheel not found' >&2; exit 1; }
[[ $EXPECTED_SHA256 =~ ^[a-fA-F0-9]{64}$ ]] || { echo 'expected SHA-256 must be 64 hex characters' >&2; exit 2; }
for cmd in unzip sha256sum file readelf objdump ldd; do command -v "$cmd" >/dev/null || { echo "missing command: $cmd" >&2; exit 1; }; done
actual=$(sha256sum "$WHEEL" | awk '{print $1}')
[[ ${actual,,} == ${EXPECTED_SHA256,,} ]] || { echo 'checksum mismatch' >&2; exit 1; }
[[ $(basename "$WHEEL") == "cryptography-50.0.0-${EXPECTED_TAG}.whl" ]] || { echo "wheel name/version/ABI not approved: expected cryptography-50.0.0-${EXPECTED_TAG}.whl" >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
unzip -qq "$WHEEL" -d "$tmp"
metadata=$(find "$tmp" -type f -path '*/WHEEL' -print -quit)
[[ -n $metadata ]] || { echo 'missing WHEEL metadata' >&2; exit 1; }
grep -Fxq 'Root-Is-Purelib: false' "$metadata" || { echo 'expected native wheel' >&2; exit 1; }
[[ $(grep -c '^Tag:' "$metadata") == 1 ]] || { echo 'wheel must declare exactly one platform/ABI tag' >&2; exit 1; }
grep -Fxq "Tag: $EXPECTED_TAG" "$metadata" || { echo 'ABI/platform tag mismatch' >&2; exit 1; }
package_metadata=$(find "$tmp" -type f -path '*/METADATA' -print -quit)
[[ -n $package_metadata ]] || { echo 'missing package METADATA' >&2; exit 1; }
grep -Eiq '^Name: cryptography[[:space:]]*$' "$package_metadata" || { echo 'wheel package name mismatch' >&2; exit 1; }
grep -Eiq '^Version: 50\.0\.0[[:space:]]*$' "$package_metadata" || { echo 'wheel package version mismatch' >&2; exit 1; }
mapfile -d '' extensions < <(find "$tmp" -type f -name '*.so' -print0)
(( ${#extensions[@]} > 0 )) || { echo 'no cryptography native extensions found' >&2; exit 1; }
rust_found=0
for so in "${extensions[@]}"; do
  desc=$(file -b "$so")
  [[ $desc == *'ELF 32-bit'* && $desc == *'Intel 80386'* ]] || { echo "native extension is not ELF i386: ${so#$tmp/}" >&2; exit 1; }
  header=$(LC_ALL=C readelf -h "$so")
  grep -Eq 'Class:[[:space:]]+ELF32' <<<"$header" || { echo 'ELF class is not 32-bit' >&2; exit 1; }
  grep -Eq 'Machine:[[:space:]]+Intel 80386' <<<"$header" || { echo 'ELF machine is not i386' >&2; exit 1; }
  dynamic=$(LC_ALL=C readelf -d "$so")
  mapfile -t needed < <(objdump -p "$so" | awk '$1=="NEEDED" {print $2}' | sort -u)
  expected_needed=(ld-linux.so.2 libc.so.6 libdl.so.2 libgcc_s.so.1 libpthread.so.0)
  [[ "${needed[*]}" == "${expected_needed[*]}" ]] || { echo "unexpected dynamic dependency set: ${so#$tmp/}" >&2; exit 1; }
  grep -Eq 'libssl|libcrypto' <<<"${needed[*]}" && { echo "unexpected dynamic OpenSSL dependency: ${so#$tmp/}" >&2; exit 1; }
  grep -Eq '(RPATH|RUNPATH)' <<<"$dynamic" && { echo "embedded RPATH/RUNPATH forbidden: ${so#$tmp/}" >&2; exit 1; }
  if [[ $(basename "$so") == _rust*.so ]]; then rust_found=1; fi
  # ldd must resolve dependencies on the current i386 userspace, and may not report missing objects.
  linkage=$(LC_ALL=C ldd "$so" 2>&1) || { echo "dynamic dependency resolution failed: ${so#$tmp/}" >&2; exit 1; }
  grep -q 'not found' <<<"$linkage" && { echo "unresolved dynamic dependency: ${so#$tmp/}" >&2; exit 1; }
done
(( rust_found == 1 )) || { echo 'cryptography _rust extension missing' >&2; exit 1; }
echo "wheel=$(basename "$WHEEL")"; echo "sha256=$actual"; echo "native_extensions=${#extensions[@]}"; echo 'wheel-verify: PASS'
