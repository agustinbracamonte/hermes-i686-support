# Proposed releases — not published

No repository, remote, tag or GitHub Release exists yet.

## Public repository tag

Proposed initial source tag: `hermes-v0.20.0-i686.1`

It denotes support material validated against Hermes Agent `0.20.0`, not an official Hermes release and not an upstream fork.

## Proposed source release contents

- This repository's source, MIT `LICENSE`, `THIRD_PARTY_NOTICES.md`, `SECURITY.md` and `CONTRIBUTING.md`.
- Documentation and reproducible scripts only.
- No user configuration, session state, personal paths, logs, source caches or binaries.

## Candidate binary assets

| Asset | Technical result | License/privacy gate | Proposed disposition |
|---|---|---|---|
| `cryptography-50.0.0-cp311-abi3-linux_i686.whl` | SHA-256, ABI and runtime checked | Include cryptography/OpenSSL notices and source-access details | Candidate after final review |
| `cffi` / `pycparser` dependency wheels | Present in recovered wheelhouse | Rebuild/check exact hashes and licenses | Candidate only after independent validation |
| Older cryptography wheel in recovered wheelhouse | Present, but not selected for runtime verification | Version-specific validation missing | Do not publish |
| `signal-cli-i386.jar`, `libsignal-client-…-i386.jar`, JNI `.so` | ABI and archive checks pass | GPL/AGPL source, patches, complete dependency notices/SBOM incomplete | **Do not publish** |

## Exact pre-publication sequence

1. Run `scripts/publication-audit.sh`; it must pass against the worktree and all reachable Git commits.
2. Verify each selected wheel with `verify-wheel.sh`, then regenerate `SHA256SUMS` in a clean release directory.
3. Produce a version-specific SBOM/notices set and perform a license review of every embedded/bundled dependency.
4. For any Signal artifact, publish complete corresponding modified source and exact patches under the applicable GPL/AGPL terms, or omit it.
5. Create the empty public remote only after explicit approval; push the reviewed tag.
6. Create a draft Release, attach only approved assets plus checksums, review it, then publish only after a second explicit approval.

For `pulsar-extensions`, create a separate **private** remote only after a separate approval. It must never be attached as a release asset or submodule of this public repository.
