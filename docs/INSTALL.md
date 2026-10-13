# Staged installation and artifact validation

## Scope and safety

Keep the running Hermes checkout, virtual environment, config and gateway unchanged. Build and run import checks only in a disposable, isolated staging root. Do not run native imports from arbitrary recovered wheels or invoke the resulting binary outside staging.

## Source archive provenance

The builder fetches the official PyPI-hosted `cryptography 50.0.0` sdist URL and verifies the PyPI-published SHA-256 before extraction:

- URL: `https://files.pythonhosted.org/packages/de/41/6cbdcf9142d00fe82836fbb51e503e58088575cf7a0fe1dbff6695bf0840/cryptography-50.0.0.tar.gz`
- SHA-256: `eeac2acb5a20ed25e0ad6d1df9891a520b78b404266b6d11778f25d5d691a6c9`

A separate download was performed from this URL during this correction; its SHA-256 matched. This validates the source input, not binary reproducibility.

## Build a new wheel

Use a clean 32-bit CPython 3.11 staging environment and the documented pinned build tools:

```bash
export CRYPTOGRAPHY_VERSION=50.0.0
export CRYPTOGRAPHY_SDIST_SHA256=eeac2acb5a20ed25e0ad6d1df9891a520b78b404266b6d11778f25d5d691a6c9
export OPENSSL_VERSION=3.5.7
export OPENSSL_SHA256=a8c0d28a529ca480f9f36cf5792e2cd21984552a3c8e4aa11a24aa31aeac98e8
export PYTHON_BIN=/opt/staging-i686/bin/python3.11
export WORKDIR=/opt/staging-i686/work/cryptography
export JOBS=1
./scripts/build-cryptography-i686.sh
```

The script downloads and checksum-validates source archives before extraction. It builds under `WORKDIR` and does not install into Hermes. The recipe has not been proven by a fresh clean build in this correction.

## Historical fixture versus new build output

The SHA-256 `71893373af19e01f446f3b3d98cf674c5cbf8d1842d01a1fd5ace41c097b9500` identifies only the *recovered historical wheel fixture* listed in `docs/ARTIFACTS.md`. It is not an expected hash for a future rebuild.

For a newly built wheel, calculate and record its own digest, then use that same digest for integrity verification and static ABI inspection:

```bash
NEW_WHEEL="$WORKDIR/dist/cryptography-50.0.0-cp311-abi3-linux_i686.whl"
NEW_SHA256=$(sha256sum "$NEW_WHEEL" | awk '{print $1}')
./scripts/verify-wheel.sh "$NEW_WHEEL" "$NEW_SHA256"
printf '%s  %s\n' "$NEW_SHA256" "$(basename "$NEW_WHEEL")" > "$WORKDIR/SHA256SUMS"
```

This proves only that the inspected file matches its recorded digest and passes static wheel/ELF checks. It does **not** establish that another build will produce identical bytes, nor independently attest that the output was produced from the claimed source. Do not claim binary reproducibility without independent clean rebuilds and byte-for-byte comparison.

## Runtime import test (staging only)

First place the selected, statically verified wheel under the isolated staging root and install it into a fresh venv there. The runtime checker re-verifies wheel provenance by digest, requires both Python and wheel beneath the supplied staging root, then imports the native extension only in that staged interpreter:

```bash
STAGE=/opt/staging-i686
WHEEL="$STAGE/wheelhouse/cryptography-50.0.0-cp311-abi3-linux_i686.whl"
WHEEL_SHA256=$(sha256sum "$WHEEL" | awk '{print $1}')
"$STAGE/venv/bin/python" -m pip install --no-index "$WHEEL"
./scripts/check-runtime.sh \
  --python "$STAGE/venv/bin/python" \
  --staging-root "$STAGE" \
  --wheel "$WHEEL" \
  --sha256 "$WHEEL_SHA256"
```

The checker uses `readelf`/`objdump` for static dependency inspection; it does not use `ldd`. A runtime import is a separate, explicitly staged execution test and is not performed by the static wheel verifier.

## Stage Hermes

Only after staging validations, create a fresh Hermes venv under the staged source and run that release's own version/config/import checks. Do not transplant an editable venv into production: console-script shebangs and editable metadata can contain staging paths. No production Hermes modification or service restart is authorized by this procedure.
