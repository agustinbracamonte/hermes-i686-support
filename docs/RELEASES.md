# Preparing a potential GitHub Release

No publication is authorized. The repository currently contains source, documentation and scripts; binaries must not be committed.

## Binary policy

The collector accepts exactly one manifest-approved artifact: `cryptography-50.0.0-cp311-abi3-linux_i686.whl`. It verifies the expected SHA-256, wheel metadata, ELF32 i386 architecture, extension presence, dynamic dependencies and runtime resolution. `cffi` and `pycparser` are not approved by the current collector. Signal CLI remains experimental; no JAR, JNI or native Signal binary may be collected or published.

## Procedure (requires separate explicit approval)

1. Rebuild from verified sources in a clean i686 staging environment; the revised build recipe has not yet been independently clean-built.
2. Run `tests/test-scripts.sh`, `tests/test-signal-cli-integration.sh` and `scripts/publication-audit.sh`.
3. Run `scripts/check-runtime.sh` inside the intended fresh 32-bit runtime.
4. After an explicit asset approval, create a one-entry manifest with the exact filename and approved SHA-256, then use `scripts/collect-release-assets.sh SOURCE_DIR EMPTY_OUT_DIR APPROVAL_MANIFEST`.
5. Recheck the generated `SHA256SUMS`, licenses, SBOM and notices. Creating assets does not authorize GitHub publication.
6. Only after separate explicit approval may an operator create a remote, push, tag, draft or publish a Release.

## No release created

No GitHub repository, remote, tag or Release has been created by this project.
