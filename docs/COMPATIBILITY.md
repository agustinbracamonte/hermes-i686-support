# Compatibility matrix

Status labels describe evidence only: **PROVEN** means the named configuration was directly exercised; **EXPERIMENTAL** means documented or partially checked without full reproducible validation; **NOT TESTED** means no evidence. Do not generalize across versions or architectures.

| Environment | Status | Evidence | Notes |
|---|---|---|---|
| Debian i386 userspace, Linux x86_64 kernel, CPython 3.11.5 32-bit | **PROVEN (recovered staging evidence)** | Hermes 0.20.0; cryptography 50.0.0; `_rust.abi3.so` ELF i386 | Kernel/machine string may be x86_64 while the Python process is 32-bit. Pointer width and ELF machine are the ABI checks; `sysconfig.get_platform()` alone is not authoritative. |
| Rust 1.97.1 `i686-unknown-linux-gnu` | **PROVEN for recovered build; rebuild script experimental** | Recovered cryptography 50.0.0 native build evidence | Revised automated build recipe has not itself been rerun cleanly. |
| Private static OpenSSL 3.5.7 for cryptography | **PROVEN for recovered wheel; rebuild recipe experimental** | cryptography backend reports OpenSSL 3.5.7; extension has no dynamic libssl/libcrypto dependency | Python stdlib `ssl` may use system OpenSSL 1.1.1v; this does not establish the cryptography backend version. |
| Raspberry Pi OS x86 with equivalent Debian i386 userspace | **NOT TESTED** | Target motivation only | Fresh staged validation required. |
| Other Debian releases, newer Hermes/Python/cryptography/Rust/OpenSSL versions | **NOT TESTED** | No execution evidence | Rebuild and rerun the full checks. |
| ARM, armhf, aarch64 | **OUT OF SCOPE / NOT TESTED** | Different ABI | i686 wheel cannot be used. |
| Signal CLI i386 port | **EXPERIMENTAL** | Recovered build artifacts and source patches inspected; no clean-room reproducibility/license bundle | Do not publish JAR, JNI or native binaries. |

## ABI proof

`uname -m` and Python's `sysconfig.get_platform()` can reflect the host/kernel instead of the process ABI. Require a 32-bit CPython pointer width, a correctly tagged wheel, each native extension identified as ELF32 Intel 80386, and resolved dynamic dependencies. Cryptography must import as exactly 50.0.0 and its own backend must report OpenSSL 3.5.7. The stdlib `ssl.OPENSSL_VERSION` is informational and can legitimately differ.
