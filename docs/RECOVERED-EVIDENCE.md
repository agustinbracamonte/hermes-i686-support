# Recovered evidence and logs

## Recovered reproducible artifacts

- Wheelhouse with i686 `cryptography` wheels, `cffi`, and pure-Python `pycparser`.
- `cryptography 50.0.0` source archive and completed i686 wheel.
- OpenSSL 3.5.7 source archive plus its recorded SHA-256.
- A private OpenSSL prefix built with `-m32`.
- Rust i686 toolchain metadata and Cargo target output.
- Historical ELF, `readelf`, `ldd`, package-version and checksum observations recorded in earlier notes. Do not run `ldd` on untrusted ELF; current verification uses static `readelf`/`objdump` inspection.

## Technical log result

No concise, standalone build log or reusable build script was found in the recovered workspace. The workspace mainly contained source trees, virtual environments, generated object files and Cargo fingerprints. Those are not committed because they are large, machine-specific and can contain absolute paths.

The replacement is intentional: reusable scripts plus checksums and ABI diagnostics reproduce the relevant procedure without publishing opaque build caches or host-specific records.
