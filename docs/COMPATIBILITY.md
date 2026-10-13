# Compatibility matrix

| Environment | Status | Evidence | Notes |
|---|---|---|---|
| Debian i386 userspace, Linux x86_64 kernel, CPython 3.11.5 32-bit | **PROBADO** | Hermes `0.20.0`; `cryptography 50.0.0`; `_rust.abi3.so` ELF i386 | The kernel/machine string can be `x86_64` while Python pointer width is 32. |
| Rust `stable-i686-unknown-linux-gnu` 1.97.1 | **PROBADO** | Native build of `cryptography 50.0.0` | Single build job recommended on constrained hosts. |
| OpenSSL 3.5.7 private static prefix | **PROBADO** | cryptography reports OpenSSL 3.5.7; `ldd` has no libssl/libcrypto | System stdlib OpenSSL remained 1.1.1v. |
| Raspberry Pi OS x86 with equivalent Debian i386 userspace | **NO PROBADO** | Target motivation only | Requires a fresh staged validation; do not infer compatibility from the Debian result. |
| Debian i386 release other than the validated environment | **NO PROBADO** | No execution evidence | Rebuild and rerun all checks. |
| ARM, armhf, aarch64 | **NO PROBADO / fuera de alcance** | Different ABI | This repository's i686 wheel cannot be used. |
| Hermes version newer than 0.20.0 | **NO PROBADO** | Dependency metadata may change | Inspect pins and rebuild native dependencies before upgrade. |

## Interpretation

`uname -m` is not an ABI proof. Require all of: 32-bit Python pointer width, native extension reported as `ELF 32-bit Intel 80386`, and compatible dynamic dependencies.
