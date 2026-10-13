# Hermes i686 Support

Reproducible guidance and scripts for running **Hermes Agent** on a 32-bit Debian/i386 userspace, including Raspberry Pi OS x86 installations where the kernel may report `x86_64`.

> This is a local preparation for a future public GitHub repository. It has no remote and has not been published.

## Scope

- Build and verify a local `cryptography` wheel for Python 3.11 i686.
- Use a private static OpenSSL prefix to avoid system OpenSSL ABI constraints.
- Validate Python pointer width, native ELF objects, dynamic linkage and checksums.
- Stage an Hermes install without modifying a running gateway.

## Non-goals

- It does not ship Hermes, Python, Rust, OpenSSL, wheels, credentials or user configuration.
- It does not claim ARM/Raspberry Pi hardware support; **x86/i386 userland** is the target.
- It does not update or restart a live gateway.

## Quick start

```bash
./scripts/preflight.sh --python /path/to/python3.11 --require-i686
./scripts/build-cryptography-i686.sh  # set both required SHA-256 variables first
./scripts/verify-wheel.sh dist/cryptography-*.whl EXPECTED_SHA256
./scripts/check-runtime.sh --python /path/to/staged-venv/bin/python
```

Read `docs/INSTALL.md` before building. The matrix in `docs/COMPATIBILITY.md` distinguishes verified evidence from design-only guidance.

## Evidence status

The recovered Debian i386 runtime/wheel evidence is **PROVEN** for the exact matrix in `docs/COMPATIBILITY.md`. The revised build recipe has not been clean-rebuilt and remains **EXPERIMENTAL**. Signal CLI i386 is experimental and excluded from release assets. No JAR, JNI or native Signal binaries may be published.

## Release assets

Built wheels remain outside Git. `scripts/collect-release-assets.sh SOURCE_DIR EMPTY_OUT_DIR APPROVAL_MANIFEST` copies only the single exact cryptography 50.0.0 i686 wheel listed with an approved SHA-256 in the manifest, and reruns `verify-wheel.sh` before copying. There is no Signal artifact allowance. Collection is not publication authorization.
