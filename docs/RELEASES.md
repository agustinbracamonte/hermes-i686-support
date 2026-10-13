# Preparing GitHub Releases

This repository contains instructions and scripts only. Do **not** commit wheels, toolchains, OpenSSL prefixes, virtual environments, source tarballs or `dist/` content.

## Candidate release layout

```
cryptography-50.0.0-cp311-abi3-linux_i686.whl
cffi-2.1.0-...-i686.whl
pycparser-3.0-py3-none-any.whl
SHA256SUMS
BUILD-MANIFEST.md
```

## Procedure

1. Build from verified source in a clean i686 staging environment.
2. Run `verify-wheel.sh` for every native wheel.
3. Run a fresh-venv import/runtime check.
4. Generate `SHA256SUMS` using `collect-release-assets.sh`.
5. Attach the reviewed files to a GitHub Release; do not put them into Git.
6. State the exact Python ABI, Rust host, OpenSSL source hash and validation output in the release notes.

## No release created

No GitHub repository, remote, tag or Release has been created by this project.
