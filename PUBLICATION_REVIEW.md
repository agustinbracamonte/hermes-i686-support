# PUBLICATION REVIEW — prepared, not published

**Status:** no remote, push, GitHub repository, tag, Release, deployment, gateway restart or Signal restart was performed.

## Repositories

| Repository | Intended visibility | Branch | Head | Status |
|---|---|---|---|---|
| `hermes-i686-support` | Public | `publication-ready` | Local reviewed history | Publication preparation only |
| `pulsar-extensions` | Private | `publication-ready` | Local reviewed history | Publication preparation only |

The repositories remain separate. Neither has a Git remote.

## Privacy review

### Public repository

- Full reachable Git history, working tree and commit metadata passed `scripts/publication-audit.sh`.
- Git history was rebuilt with a non-routable placeholder identity; old local commit objects were expired and garbage-collected.
- No tracked wheel, JAR, shared library, archive, SQLite database, session, log, configuration, auth file or production data is present.
- Generated release candidates remain under ignored `dist/` and are not Git-tracked.
- The optional Signal integration excludes all account data, identities, phone numbers, session state, contacts, messages, attachments, tokens and daemon configuration.

### Private repository

- Tracked history review passed for private paths, emails, phone patterns, keys and token patterns after excluding Git patch index hashes (which are not phone data).
- `vendor/` is ignored and not tracked; its disposable Hermes staging checkout is not part of the private repository.
- No tracked/visible workspace candidates for `.env`, `auth.json`, `config.yaml`, state databases, SQLite, JSONL or logs were found.
- The repository contains functional policy and patch material, therefore it must remain private.

## Licenses

| Component | Verified license posture | Distribution consequence |
|---|---|---|
| Hermes Agent | MIT | Support documentation can reference it; preserve notices if copying code. |
| cryptography | Apache-2.0 OR BSD-3-Clause | Include its license/notice choices in any wheel release. |
| OpenSSL 3 | Apache-2.0 | Include Apache-2.0 notice and source/version details with a statically linked wheel. |
| signal-cli | GPL-3.0-only | Modified binary distribution requires corresponding source and patch availability. |
| libsignal | AGPL-3.0-only | Modified artifact/network deployment has stronger source-availability obligations. |

`LICENSE`, `THIRD_PARTY_NOTICES.md`, `SECURITY.md` and `CONTRIBUTING.md` are prepared for the public repository. The Signal patch files retain GPL/AGPL status and include the applicable license texts. The private repository has private-use license terms plus third-party/security/contribution notes.

## Technical verification

### Hermes i686 support

- Shell syntax and script smoke tests: PASS.
- Publication privacy scanner: PASS.
- 32-bit Python preflight: PASS.
- `cryptography` wheel SHA-256, ABI tag and extracted ELF: PASS.
- Release-asset checksum manifest: PASS.
- No artifact was copied into Git.

### Signal CLI optional integration

Recovered validated evidence:

- signal-cli `0.14.9`; libsignal `0.103.0`.
- Java 21 i386 runtime; Rust host `i686-unknown-linux-gnu`; CMake 3.22.6.
- JNI is ELF 32-bit Intel 80386 and links to standard i386 system libraries.
- Built JARs contain the expected x86/i386 JNI resource names.
- Patch application checks against clean upstream tags: PASS.
- Integration script layout, shell syntax, architecture/linkage/checksum verification: PASS.

The Java application layer is portable bytecode in principle; the packaged result is architecture-specific because its JNI resource is i386. A separate JNI build/package is required per target architecture.

## Prepared files

### Public

- Reproducible i686 installation/build/diagnostic/recovery documentation.
- Release plan tied to `hermes-v0.20.0-i686.1`.
- Generic preflight, runtime, wheel verification, release-asset and publication-audit scripts.
- Optional `integrations/signal-cli/` with source-bound patches, build/package/verify scripts and GPL/AGPL texts.

### Private

- Deterministic reaction policy, native Hermes plugin/hook layout, private memory/automation skills and reversible core patch reference.
- Private repository security, contribution and third-party notices.

## Binary disposition

| Candidate | Result |
|---|---|
| `cryptography 50.0.0` CPython 3.11 i686 wheel | Technically verified; candidate only after version-specific notices/SBOM and final release review. |
| cffi / pycparser wheels | Not independently revalidated in this review; not approved. |
| Older cryptography wheel | Not selected for runtime validation; do not publish. |
| Signal CLI JAR, libsignal client JAR, JNI shared object | Technically inspected but **not approved**: complete corresponding source, dependency SBOM/notices and GPL/AGPL release package remain required. |

## Risks and pending work

1. Compatibility is proven only for the documented Debian i386/Python 3.11/Hermes 0.20.0 staging evidence; Raspberry Pi OS x86 remains untested.
2. Every future Hermes, Python, Rust, OpenSSL or Signal revision requires a fresh staged rebuild and ABI/license review.
3. No independent, clean-room rebuild of the Signal artifacts was run in this review; only recovered artifacts, source-bound patches and checks passed.
4. Signal binary publication is blocked by GPL/AGPL corresponding-source and full dependency-notice requirements.
5. A public repository needs a final human license review before enabling Releases.

## Exact publication steps — require explicit approval

1. Confirm the intended GitHub owner/organization and public/private visibility.
2. Run both privacy scans and tests again from clean worktrees.
3. For public wheel assets, independently rebuild, verify SHA-256/ELF/runtime, produce an SBOM and complete notices.
4. Omit Signal artifacts unless the complete GPL/AGPL source-and-notices bundle has been produced and reviewed.
5. Create the public remote, push only `publication-ready`, and create the source tag `hermes-v0.20.0-i686.1`.
6. Create a **draft** Release with only approved assets and `SHA256SUMS`; obtain a second explicit approval before publishing it.
7. Separately create the private remote for `pulsar-extensions`; never cross-link, submodule or attach it to the public repository.
