# Build details

The builder intentionally requires source checksums as environment variables. This prevents a successful download from being mistaken for a trusted input.

## Inputs validated in the tested build

| Input | Version | SHA-256 |
|---|---:|---|
| OpenSSL | 3.5.7 | `a8c0d28a529ca480f9f36cf5792e2cd21984552a3c8e4aa11a24aa31aeac98e8` |
| cryptography sdist | 50.0.0 | `eeac2acb5a20ed25e0ad6d1df9891a520b78b404266b6d11778f25d5d691a6c9` |

## Key environment

```bash
export RUSTUP_TOOLCHAIN=stable-i686-unknown-linux-gnu
export OPENSSL_DIR="$WORKDIR/prefix/openssl"
export OPENSSL_STATIC=1
export CC=gcc CXX=g++
export CFLAGS='-m32 -fPIC' CXXFLAGS='-m32 -fPIC'
export CARGO_TARGET_I686_UNKNOWN_LINUX_GNU_LINKER=gcc
export CARGO_BUILD_TARGET=i686-unknown-linux-gnu
export CARGO_BUILD_JOBS=1
export CARGO_TARGET_DIR="$WORKDIR/cargo-target"
```

The reusable script sets these internally after confirming the requested Python has a 32-bit pointer width. It keeps source, OpenSSL prefix, venv and Cargo target in `WORKDIR` so a failed or interrupted build can resume without touching Hermes.

## Why static OpenSSL

The tested extension dynamically links glibc/libgcc/libpthread/libdl but not `libssl` or `libcrypto`. This isolates the modern TLS dependency from an older system OpenSSL.
