# Diagnostics

Run these checks from the support repository or a staged installation:

```bash
./scripts/preflight.sh --python /path/to/python3.11 --require-i686
./scripts/check-runtime.sh --python /path/to/stage/venv/bin/python --staging-root /path/to/stage --wheel /path/to/stage/wheelhouse/cryptography-50.0.0-cp311-abi3-linux_i686.whl --sha256 SHA256
./scripts/verify-wheel.sh /path/to/cryptography-wheel.whl SHA256
```

## Required evidence

1. `pointer_bits=32` from the selected Python.
2. Wheel tag compatible with the intended ABI, for example `cp311-abi3-linux_i686`.
3. `_rust.abi3.so` shown by `file` as `ELF 32-bit ... Intel 80386`.
4. Use `readelf -d` / `objdump -p` for static dependency inspection; runtime imports are only for a provenance-validated build in isolated staging. Historical `ldd` notes are not part of the current verifier.
5. With static private OpenSSL, no dynamic `libssl` / `libcrypto` dependency.
6. `cryptography_openssl` reports the intended private OpenSSL release.

## Important distinction

A 64-bit kernel string does not invalidate a 32-bit Python userspace. Conversely, an i386 Debian package architecture does not prove the interpreter or every native extension is i386: validate each layer.
