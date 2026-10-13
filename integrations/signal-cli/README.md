# Optional Signal CLI integration for i386

This optional guide documents a local, staged build path for `signal-cli` on a Debian i386 userspace. It does not configure, link, start or restart Signal. Hermes users who do not use Signal can ignore this directory.

## Validated build evidence

| Component | Recovered version | Result |
|---|---:|---|
| signal-cli | `0.14.9` | Java entry point started with a private Java 21 i386 runtime |
| libsignal | `0.103.0` | JNI built for Linux i386 |
| Java runtime | 21.0.12, i386 | `os.arch=i386` |
| Rust | 1.98.1, `i686-unknown-linux-gnu` | Native JNI build |
| CMake | 3.22.6 | Needed by BoringSSL build |

The Java JAR is mostly portable Java bytecode. The packaged solution is **not portable across CPU ABIs**, because it includes `libsignal_jni_i386.so`; other architectures must build/package their matching JNI resource.

## Recovered compatibility work

- Java source/target and build logic retargeted from Java 25 to Java 21 because a Linux i386 Java 25 runtime was unavailable.
- Java 25-only unnamed variables were made Java-21-compatible.
- The Java entry point was made `public static void main(String[] args)` for Java 21.
- A JSON-schema dependency was selected for JVM 17 compatibility after metadata inspection.
- The JNI build used i686 Rust, a newer private CMake, private libclang, a protoc wrapper, SSE2 (after CPU capability confirmation), and a minimal `libsignal` protobuf include-root correction.

## Reproduce in staging

1. Obtain clean upstream source checkouts at the recorded versions and verify their commits/tags.
2. Provision a private i386 Java 21 runtime, Rust i686 toolchain, CMake >=3.22, libclang and protoc appropriate for the pinned sources.
3. Apply reviewed, version-pinned patches kept under `patches/` **only after regenerating and auditing them**.
4. Run `scripts/preflight.sh` and `scripts/verify-artifacts.sh` against a staging directory.
5. Perform a dedicated native-load probe. `--version` alone is insufficient proof that JNI loads.

No account linking is part of this procedure. Keep any future daemon loopback-only and account state in a private mode-700 directory.

## Hermes integration (optional)

After a separately approved Signal deployment, configure Hermes through its supported configuration interface to target a local loopback Signal service. Keep the service lifecycle independent from the Hermes gateway, retain explicit allowlists, and verify an authorized real inbound/reply flow before calling it operational. Do not place account state or service secrets inside Hermes source/configuration repositories.

## Redistribution status

**Not release-ready.** `signal-cli` is GPL-3.0-only and `libsignal` is AGPL-3.0-only. A release of modified artifacts requires complete corresponding source/patch access, complete third-party notices/SBOM, upstream-license verification and a fresh privacy/ABI/checksum review. This repository intentionally ships neither their sources nor binaries.
