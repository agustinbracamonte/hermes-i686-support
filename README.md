# Hermes i686 Support

Pinned, checksum-verified build guidance and scripts for running **Hermes Agent** on a 32-bit Debian/i386 userspace, including Raspberry Pi OS x86 installations where the kernel may report `x86_64`. No binary reproducibility claim is made.

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

Read `docs/INSTALL.md` first. The runtime command below is only for isolated staging and requires the staged wheel's validated digest.

```bash
./scripts/preflight.sh --python /path/to/python3.11 --require-i686
./scripts/build-cryptography-i686.sh  # set both required SHA-256 variables first
./scripts/verify-wheel.sh dist/cryptography-*.whl EXPECTED_SHA256
./scripts/check-runtime.sh --python /path/to/stage/venv/bin/python --staging-root /path/to/stage --wheel /path/to/stage/wheelhouse/cryptography-50.0.0-cp311-abi3-linux_i686.whl --sha256 EXPECTED_SHA256
```

The matrix in `docs/COMPATIBILITY.md` distinguishes recovered evidence from current execution and design-only guidance.

## Evidence status

Previously recovered Debian i386 runtime/wheel evidence is **PROVEN only for that recovered exact matrix** in `docs/COMPATIBILITY.md`; it was not re-executed in this correction. The revised build recipe has not been clean-rebuilt and remains **EXPERIMENTAL**. Signal CLI i386 is experimental and excluded from release assets. No JAR, JNI or native Signal binaries may be published.

## Release assets

Built wheels remain outside Git. `scripts/collect-release-assets.sh SOURCE_DIR EMPTY_OUT_DIR APPROVAL_MANIFEST` copies only the single exact cryptography 50.0.0 i686 wheel listed with an approved SHA-256 in the manifest, and reruns `verify-wheel.sh` before copying. There is no Signal artifact allowance. Collection is not publication authorization.
