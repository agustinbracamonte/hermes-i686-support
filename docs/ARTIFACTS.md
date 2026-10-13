# Real artifact inventory

This manifest records observed local artifacts. The files themselves are intentionally excluded from Git and may become future release assets only after independent reproduction and review.

| Artifact | Version / tag | SHA-256 | Release treatment |
|---|---|---|---|
| `cryptography` wheel | `50.0.0`, `cp311-abi3-linux_i686` | `71893373af19e01f446f3b3d98cf674c5cbf8d1842d01a1fd5ace41c097b9500` | Candidate release asset |
| `cryptography` source | `50.0.0` | `eeac2acb5a20ed25e0ad6d1df9891a520b78b404266b6d11778f25d5d691a6c9` | Download/build input |
| OpenSSL source | `3.5.7` | `a8c0d28a529ca480f9f36cf5792e2cd21984552a3c8e4aa11a24aa31aeac98e8` | Download/build input |
| `cffi` wheel | `2.1.0`, CPython 3.11 i686 | Not independently rehashed for this document | Candidate dependency asset |
| `pycparser` wheel | `3.0`, pure Python | Not independently rehashed for this document | Candidate dependency asset |

## Build evidence

- Hermes: `0.20.0 (2026.8.3)`.
- Target Python: `3.11.5`, pointer width `32`.
- Rust: `1.97.1`, host `i686-unknown-linux-gnu`.
- Private OpenSSL: `3.5.7`, built with `-m32`.
- Installed native extension: ELF 32-bit Intel 80386.
- `readelf` dynamic dependencies: glibc/libgcc/libpthread/libdl only; no dynamic `libssl` or `libcrypto`.

## Excluded deliberately

- Whole toolchains, source trees, build caches and virtual environments.
- User configuration, auth state, credentials, sessions and logs tied to a person or machine.
- Private installation paths and machine-specific build output.

Use `scripts/collect-release-assets.sh` to make a fresh release-candidate directory and checksum manifest from a reviewed wheelhouse.
