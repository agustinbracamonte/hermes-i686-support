# Staged installation

## 1. Do not start with the live installation

Keep the running Hermes checkout, venv, config and gateway unchanged. Work in a separate directory and use a fresh 32-bit CPython 3.11 interpreter.

## 2. Install build prerequisites in the staging environment

The tested Debian i386 host had `build-essential`, `gcc`, `make`, `perl`, `pkg-config`, `libc6-dev:i386`, `libffi-dev:i386`, and `libssl-dev:i386`. Package names may differ across releases; install them only in the staging/build host, not by modifying a running Hermes service.

## 3. Verify the ABI

```bash
./scripts/preflight.sh --python /opt/python-i686/bin/python3.11 --require-i686
```

A valid mixed environment can report `platform.machine() == x86_64` while Python reports `pointer_bits=32`.

## 4. Build the protected dependency

Set exact source checksums before running the builder:

```bash
export CRYPTOGRAPHY_VERSION=50.0.0
export CRYPTOGRAPHY_SDIST_SHA256=eeac2acb5a20ed25e0ad6d1df9891a520b78b404266b6d11778f25d5d691a6c9
export OPENSSL_VERSION=3.5.7
export OPENSSL_SHA256=a8c0d28a529ca480f9f36cf5792e2cd21984552a3c8e4aa11a24aa31aeac98e8
export PYTHON_BIN=/opt/python-i686/bin/python3.11
export WORKDIR=$PWD/.work/cryptography-i686
export JOBS=1
./scripts/build-cryptography-i686.sh
```

The script uses a persistent workspace and only builds in that workspace. It never installs into Hermes.

## 5. Validate the wheel and staged runtime

```bash
./scripts/verify-wheel.sh "$WORKDIR/dist/cryptography-50.0.0-cp311-abi3-linux_i686.whl" 71893373af19e01f446f3b3d98cf674c5cbf8d1842d01a1fd5ace41c097b9500
./scripts/check-runtime.sh --python /path/to/staging/.venv/bin/python
```

Accept only an i386 `_rust` extension and an `ldd` result without dynamic `libssl.so` or `libcrypto.so` when static OpenSSL was requested.

## 6. Stage Hermes

Create a fresh venv in the staged Hermes source, install from a local wheelhouse and require the completed cryptography wheel. Run the target release's own version/config/import checks. Do not transplant an editable venv to production: console-script shebangs and editable metadata can contain staging paths.
