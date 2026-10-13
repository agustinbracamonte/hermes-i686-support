# Reproducible build procedure (experimental until clean rebuild)

This recipe targets only the validated profile: CPython 3.11 32-bit, cryptography 50.0.0, OpenSSL 3.5.7, Rust 1.97.1 i686, CMake 3.22.6, GCC 10.2.1, GNU Make 4.3, Perl 5.32.1, maturin 1.14.1. It fails closed when Python pointer width/version, Rust host/version, CMake/GCC/Make/Perl version, source archive digests, or release versions do not match. Python build tools are pinned to pip 25.0.1, setuptools 78.1.0 and wheel 0.45.1. These pins describe the recipe; the updated build itself remains experimental until a fresh clean rebuild.

## OpenSSL configuration flags

`build-cryptography-i686.sh` invokes:

```text
./Configure linux-x86 -m32 -fPIC --prefix=<WORKDIR>/prefix/openssl no-shared no-tests no-ssl3 no-weak-ssl-ciphers
```

- `linux-x86`: OpenSSL's 32-bit x86 Linux target.
- `-m32`: emit i386 objects.
- `-fPIC`: position-independent code.
- `--prefix=...`: isolated private prefix; no system install.
- `no-shared`: static OpenSSL libraries, so cryptography does not dynamically load system libssl/libcrypto.
- `no-tests`: skip upstream tests in this constrained build step; a separate runtime/ABI test suite is required.
- `no-ssl3` and `no-weak-ssl-ciphers`: disable obsolete SSLv3 and weak cipher suites.

The script builds under a private work directory, never installs into the active Hermes environment, and checks the resulting wheel separately. The revised recipe has not yet been clean-built; treat it as **EXPERIMENTAL**, not as proven reproducible. Do not substitute unpinned tools or omit archive SHA-256 environment variables.
