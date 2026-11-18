# Hermes Agent v0.23.2 i686 implementation status

Updated 2026-11-18. This is the public, generic compatibility workstream. It does not include a Hermes source checkout, private Púlsar code, credentials, sessions, wheels, or binaries.

## Pinned source

- Upstream: `https://github.com/NousResearch/hermes-agent`
- Tag object: `v0.23.2` → `28f57ed8e3dba4eceb67dfd3e3abda1a7604452d`
- Commit: `ae2a81ccc00e9b7c06301523e5bb09608397149c`
- Checkout used for implementation: disposable clone at the exact commit above; the public repo stores only an applicable patch.

## First milestone: process ABI, PM and bootstrap

The ordered patchset in `patches/v0.23.2/` changes the pinned upstream source to:

- Resolve Linux x86 from the running Python process's pointer width and ELF header. A 32-bit `EM_386` process under an x86_64 kernel selects `linux-i686`; an x32 or inconsistent process fails closed.
- Verify ELF class as well as `e_machine`. For i686 store entries, scan ELF payloads so an x64 shared object cannot be accepted beside an i686 executable.
- Have `scripts/install.sh` and `setup-hermes.sh` inspect the running Bash ELF and `getconf LONG_BIT` instead of mapping Linux targets from `uname -m` alone.
- Add the verified `uv` 0.13.5 glibc i686 row to `pm/lock.json` and the generated `install.sh` bootstrap pins. `setup-hermes.sh` reads the same lock row. Both bootstraps fail closed if their target row is absent; they never fall back to x64.
- Apply the mixed-ELF guard at the shared PM verification boundary used by install and doctor, so a package-specific `verify()` override cannot skip it.

Apply only to a clean checkout of the pinned source:

```bash
scripts/apply-v0232-patches.sh --check /path/to/hermes-agent-v0.23.2
scripts/apply-v0232-patches.sh --apply /path/to/hermes-agent-v0.23.2
```

The test harness archives the pinned commit into a temporary directory, applies the ordered patch series there, checks both bootstrap paths, and runs focused upstream tests:

```bash
HERMES_PYTHON=/path/to/python-with-pytest tests/test-v0232-patchset.sh /path/to/hermes-agent-v0.23.2
```

## Lock gaps and artifact evidence

The verified uv pin was the first binary `linux-i686` row added to the v0.23.2 lock. The pnpm 12.15.0 WASM artifact is also pinned for `linux-i686`. GitHub CLI 2.97.0 now has a locally verified Linux 386 asset row; 13 remaining Linux-x64 candidates need individually reviewed i686 artifact rows and digests before PM can install them:

`bws`, `chromium`, `cua-driver`, `ffmpeg`, `iron-proxy`, `just`, `llamacpp-cpu`, `llamacpp-cuda`, `llamacpp-hip`, `llamacpp-vulkan`, `node`, `python`, `ripgrep`.

The other six lock packages have different target semantics: `dmgbuild` and `llamacpp-metal` are macOS tools; `git` is supplied by the Linux host; `npm` is pinned as a target-independent `any` artifact; `termux-docker` is Android ARM64 only; `whispercpp-cpu` has no Linux-x64 row. Their absence is not a claim of i686 compatibility.

Runtime artifact checks performed for this milestone:

| Pin | Public source evidence | Result |
|---|---|---|
| uv 0.13.5 | [Official release](https://github.com/astral-sh/uv/releases/tag/0.13.5), asset `uv-i686-unknown-linux-gnu.tar.gz`, 17,987,531 bytes. GitHub release API digest: `sha256:f5713d6c05d77d01de9655270d713ba87ed45391752f489c80bbf1690bccc17c`; published `.sha256` sidecar asset digest: `sha256:bf04536e7b5564ab322ab286a8033830d53bc8462ed04e81407208d6a11df5a1` | Downloaded the archive; locally computed SHA-256 and the published sidecar both matched the GitHub release digest. Extracted `uv` and `uvx` are ELF32, little-endian, `EM_386`. The binary was not executed on x86_64. The exact URL and digest are now in the `linux-i686` lock row and generated shell bootstrap pin. |
| GitHub CLI 2.97.0 | [Official release](https://github.com/cli/cli/releases/tag/v2.97.0), asset `gh_2.97.0_linux_386.tar.gz`, 13,818,702 bytes. Official release checksum file: `ba556b1061cfc89fee62d1e59dfacd2ea646d8c3bb41cbef909ec6ed27071512` | Downloaded the archive; the local SHA-256 matches the published checksum file. The extracted `gh` is ELF32, little-endian, `EM_386`, statically linked. A loopback PM cross-stage verified the locked hash and ELF guard. The binary was not executed on x86_64; `linux-x64` and ARM64 lock rows were unchanged. |
| CPython 3.14.9+20261021 | [python-build-standalone release](https://github.com/astral-sh/python-build-standalone/releases/tag/20261021) has x86_64 and AArch64 Linux builds, plus i686 Windows builds; no i686 Linux build | No official Linux i686 binary identified. Build and verify CPython in isolated staging. |
| Node 26.12.1 | Official [`SHASUMS256.txt`](https://nodejs.org/dist/v26.12.1/SHASUMS256.txt) lists `node-v26.12.1.tar.xz` as `053e3b296859b6d8d93f99ef97fa9cec1c4ee171c72968100c649978c1dbd38c`; binary list has `linux-x64`, `linux-arm64`, and x64-musl Linux assets, no 32-bit Linux asset | Source checksum is recorded for a future build. No official i686 runtime binary or digest was found. |
| pnpm 12.15.0 WASM | Official npm package `@pnpm/wasm`; `engines.node >=22.13`; tarball npm integrity `sha512-uxV61T7Sn34SAVUkzZf0xYNW0Ocw59OCHYRNdY2pOm4xE3Z+r2ptXOd2XTiWQBOZ8qgyMLs69F4ZHcUakvFR2Q==` | Tarball SHA-256 `172c9d9a2b8b82b00a67323ffa6d34c32f8706279661329ea460432b95c9da1f` verified locally. The package contains a 44,951,421-byte WASM module and no native ELF/PE/Mach-O/`.node` file. Host Node 24.22.1 x64 ran pnpm and a local offline install; i686 execution remains pending. |

The CPython source-build recipe now pins Git tag object `17acf00d155cb8536eca1c3af3a8404db648e37f`, commit `ead82c07db1f111d613926ed1b6667411d768125`, and tree `a0de950923dd481d2fd0f5bdc42ed9821763cbc4`. The python.org source archive URL still returns HTTP 403, so no official sdist SHA-256 is claimed. Node source commit `bc2e01dcf6acd5cf7d169b5f26cf89abaaeb41f1` was resolved separately; its downloaded source tar matched the official release hash above. Node upstream marks Linux x86 as Experimental and currently requires GCC >=13.2 or Clang >=19.1 in its Linux build guide.

## Púlsar staging report (operator-supplied, not reproduced here)

The latest report supersedes the older 102-dependency estimate in `CODEX-HANDOFF-V0232.md`: the current plan selects 101 dependencies; 92/92 reported compatible wheels have been downloaded and verified in staging; nine have no compatible wheel for that plan. `cffi 2.1.1` and `psutil 7.2.2` reportedly passed an isolated offline sync but have not been integrated with the real lock. Púlsar also reports local i686 pins for uv 0.13.5, FFmpeg 9.0.1, ripgrep 15.2.0 and gh 2.97.0, plus local bootstrap/ABI fixes. None of those results is treated as reproduced by this public work.

No Púlsar wheel was re-downloaded, inspected, built, or added in this milestone. The offline reconciler is implemented and tested against synthetic fixtures only. The counts, lock coverage, and `cffi`/`psutil` integration remain operator evidence pending a run against Púlsar's actual lock and existing staging wheelhouse.

## Test evidence

Every result is specific to the execution host and command. The focused harness runs against an archived copy so it cannot modify the operator's source checkout.

Executed in this work session:

- `HERMES_PYTHON=/tmp/hermes-v0232-test-venv/bin/python tests/test-v0232-patchset.sh /tmp/hermes-agent-v0232` — exit 0; both ordered patches applied to a clean archive of the pinned commit; 56 tests passed across `test_store.py`, `test_downloader.py`, and `test_downloader_integrity.py`.
- `HERMES_PYTHON=/tmp/hermes-v0232-test-venv/bin/python scripts/run_tests.sh tests/pm/test_store.py tests/pm/test_pm_core.py` — exit 0; 68 tests passed and one macOS-only case skipped. Coverage includes 32-bit userspace under x86_64 kernel selection and `doctor` rejecting mixed ELF in a custom package entry.
- `HERMES_PYTHON=/tmp/hermes-v0232-test-venv/bin/python scripts/run_tests.sh tests/hermes_cli/test_local_runtime_pm.py` — exit 0; all 9 PM-owned local runtime adoption tests passed after routing that check through the common ELF guard.
- `UV_I686_ARCHIVE=/tmp/uv-i686-unknown-linux-gnu-0.13.5.tar.gz scripts/verify-v0232-uv-i686.sh /tmp/hermes-v0232-uv-dev` — exit 0; downloaded official checksum sidecar, recomputed archive SHA-256, checked `uv`/`uvx` ELF headers, and verified generated shell pins match the lock.
- `UV_I686_ARCHIVE=/tmp/uv-i686-unknown-linux-gnu-0.13.5.tar.gz HERMES_PYTHON=/tmp/hermes-v0232-test-venv/bin/python scripts/test-v0232-uv-i686-pm-stage.sh /tmp/hermes-v0232-uv-dev` — exit 0; PM fetched the already verified archive from loopback, enforced the lock digest, installed it into an isolated temporary store, and checked both ELF32 executables without running them.
- `scripts/apply-v0232-patches.sh --check /tmp/hermes-agent-v0232` — exit 0; full ordered patch series applies cleanly to the exact official source commit.
- `tests/test-scripts.sh` — exit 0; existing self-contained shell, static, publication, and Signal-provenance checks passed.
- `python3 scripts/gen-bootstrap-pins.py --check` on the patched source — exit 0; the i686 bootstrap fragment matches `pm/lock.json`.
- `ruff check pm/package.py pm/store.py pm/install.py pm/cli.py hermes_cli/local_runtime/binaries.py tests/pm/test_store.py tests/pm/test_pm_core.py` on the patched source — exit 0.
- `bash -n scripts/install.sh setup-hermes.sh` and `git diff --check` on the patched source — exit 0.
- `scripts/apply-v0232-patches.sh --apply` — exit 0 on a disposable clone; the original pinned source checkout remained clean.
- `tests/test-v0232-patchset.sh` with ordered patches 0001–0004 — exit 0; 105 focused tests passed and one macOS-only test skipped. The set includes PM core/install/doctor coverage, pnpm-WASM regressions, and the GitHub CLI i686 URL/lock-row checks.
- `scripts/test-v0232-pnpm-wasm-pm-stage.sh` — exit 0; PM fetched the official WASM tarball over loopback, enforced the lock SHA, installed the i686 store entry, and checked its launcher layout and ELF scan without executing it.
- `scripts/verify-v0232-pnpm-wasm.sh` with the official npm tarballs — exit 0 on Node 24.22.1 x64; the regular package failed closed when native-binary network access was disabled, while `@pnpm/wasm` ran version and offline local-file install checks.
- `GH_I686_ARCHIVE=/tmp/gh_2.97.0_linux_386.tar.gz scripts/verify-v0232-gh-i686.sh /tmp/hermes-v0232-gh-pin` — exit 0; official checksum file, locally computed archive digest, and extracted ELF32/EM_386 header matched. The binary was not executed.
- `GH_I686_ARCHIVE=/tmp/gh_2.97.0_linux_386.tar.gz HERMES_PYTHON=/tmp/hermes-v0232-test-venv/bin/python scripts/test-v0232-gh-i686-pm-stage.sh /tmp/hermes-v0232-gh-pin` — exit 0; loopback download passed PM lock/hash/extraction/ELF verification for the i686 target without executing `gh`.
- On the patched source, `HERMES_PYTHON=/tmp/hermes-v0232-test-venv/bin/python scripts/run_tests.sh tests/pm/test_gh_i686.py` — exit 0; two tests cover the exact i686 URL/lock pin and unchanged x64/ARM64 URL selection.
- `scripts/build-cpython-v0232-i686.sh --prepare-only` — exit 0; exact CPython tag object/commit/tree verified; repeated invocation reused its source checkpoint.
- `scripts/build-node-v0232-i686.sh --prepare-only` — exit 0; official Node source SHA verified and extraction checkpoint resumed. Both build scripts' `--preflight-only` reject this ELF64 x86_64 process before compiling.
- After adding the compiler helper to the Node script fingerprint, `HERMES_I686_BUILD_ROOT=/tmp/hermes-v0232-node-clang-prep NODE_SOURCE_ARCHIVE=/tmp/v0232-sources/node-v26.12.1.tar.xz scripts/build-node-v0232-i686.sh --prepare-only` passed twice, reusing the verified source/extraction checkpoints without downloading or compiling.
- `tests/test-v0232-runtime-builds.sh` — exit 0; syntax, serial-job rejection, bad archive hash, ELF32/x64 fixture, checkpoint fingerprints, GCC/Clang version/target fixtures, Node `--openssl-no-asm` and CPU SSE2 checks (including an absent-SSE2 fixture), applying/reversing the scoped zlib and OpenSSL linker patches, and static hosted-helper failure-summary guards passed. These local checks do not prove a Node build.
- `python3 tests/test-v0232-wheel-reconcile.py` — exit 0; four synthetic-fixture cases cover lock hash/tag match, no lock row, no compatible wheel, digest mismatch, rejection of this host as an i686 tag source, and rejection of universal export markers.
- Against the pinned public Hermes lock, `uv export --locked --offline --no-emit-project --no-annotate --format requirements.txt` emitted platform-marked entries and an Android VCS reference. That universal export is not an i686 dependency plan; the reconciler now rejects marker-bearing entries, and the staging plan must come from the target-specific resolver.
- Both `--prepare-only` paths passed using nonexistent compiler paths and reused checkpoints.

| Check | Evidence label | Status |
|---|---|---|
| Pinned tag object and commit | STATIC | Verified by `git rev-parse v0.23.2` and `git rev-parse 'v0.23.2^{commit}'`. |
| Mixed kernel/process ABI logic | STATIC | ELF32/EM_386 under x86_64 kernel fixture selects i686; x32 and inconsistent width fixtures fail closed. |
| Bootstrap selection and lock pin | HOSTED CI + STATIC | Shell fixtures select i686 under x86_64, keep x64/ARM64 mapping and digests unchanged, and check `install.sh`'s generated pin plus `setup-hermes.sh`'s lock reader. A missing-row lock fixture remains fail-closed. |
| uv 0.13.5 asset hash and ELF | HOSTED CI | The 17,987,531-byte official release archive matched both GitHub's release digest and the published checksum sidecar. `uv` and `uvx` headers are ELF32/EM_386. Neither binary was executed. |
| PM lock/download/install | HOSTED CI | An isolated PM cross-stage downloaded the local copy of the exact official archive over loopback and verified the lock SHA, extraction, store entry and ELF class. |
| ELF executable/shared-object validation | HOSTED CI + STATIC | ELF32/EM_386 accepted; ELF64, wrong `e_machine`/endianness, mixed-width payloads, and a custom `Package.verify()` override are rejected through the common PM verifier. `doctor` reports the incompatibility. |
| Downloader checksum enforcement | HOSTED CI | Focused upstream local-server tests exercise wrong-digest rejection; the real uv archive also passed PM's lock-backed SHA check. |
| pnpm WASM lock/package stage | HOSTED CI | Official npm integrity and SHA-256 verified; PM downloaded from loopback, enforced the pinned i686 digest, staged launchers/module, and rejected invalid manifests/modules in fixtures. x64/ARM64 pnpm URLs and hashes are asserted unchanged. |
| pnpm WASM CLI and offline install | HOSTED CI, x64 process | Node 24.22.1 x64 ran `@pnpm/wasm@12.15.0` and installed a local-file fixture offline. This is not native i686 evidence. |
| Bullseye Clang 19.1.7 i386 package | HOSTED CI | Downloaded `.deb` SHA-256 matched the SHA-256 in the signed security index; Clang's i686 target preflight passed. |
| CPython 3.14.9 ELF32 build and smoke checks | HOSTED CI (i386 chroot on x86_64 runner) | Runs #4–#12 built and smoke-tested under Debian 11 i386 userspace. Run #5 SHA-256: `feb9bbe20801ec7b481d2e4cd04d1787eca1fe489bf5cf51826a1da65c3c619a`; run #6: `23b6cb39fc312ad1bb3fdfb0c08a9b33cc162740c7696ca314b174ec44cbcddb`; run #7: `89751d5686ebbac10203bde40a483c4bb38a0a687d37e3200842b64ba5896ce1`; run #8: `983771076e787e2e5fb20cd3ffc0d8352f1e6de973cdf2ae337e5c3298056ee6`; run #9: `ed8338f5c01c3ca49d435ffc36c9878d1df1a859b24cec62a7da8641afafd8a7`; run #10: `a3c568543f767d775dfb3b9d4853485cbed0189c0a550206cf5ddc2cec3df34e`; run #11: `82943c4285d9d97b21e7f3709be03e09e8888a88036e890c6e9f27efd576c970`; run #12: `284fd97f7c7d1fc83f7031d8ccd96ab1ce9f14d90a67544e675a47487f82d950`. The runner did not provide B10 staging evidence or retain the binaries. |
| Node 26.12.1 i686 build | HOSTED CI (i386 chroot on x86_64 runner) | Runs #4–#11 exposed OpenSSL, zlib, atomic, source-location, header/runtime and Make flag issues. Run #12 passed Node compiler preflight but failed the header-selection assertion because its `-H` trace did not match `/usr/include/c++/10/vector`. The failed trace was not printed, so the actual include path is unknown. The follow-up prints the trace and retains it in the Actions summary; no Node manifest or Node/npm/pnpm pass resulted. |
| Native ARM64 | NOT RUN | ARM64 is covered with ELF fixtures; no ARM64 execution host was attached. |
| Púlsar/B10 native i686 staging | NOT RUN | No staging route was supplied or accessed. Hosted CPython evidence does not establish B10 resource use, Node/pnpm compatibility, or gateway behavior. |
| Full PM install, Python wheels, Node/npm, gateway | NOT RUN | No Node i686 artifact/lock row or complete dependency closure exists here. The 92 reported wheels were not downloaded again and no full install was attempted. |

The local implementation host is Linux x86_64. Its test environment was built with the checkout's `pm.build_env` using bootstrap CPython 3.12.14 and the managed CPython 3.14.9 test interpreter. Local fixtures are not staging evidence. Hosted runs #5–#12 verified the Clang package SHA-256 `d52c7089346ebc4616d3e9e3bbee6eb0848455a9abb777746fdd32812ce981d3` against signed APT metadata and smoke-tested CPython as ELF32/EM_386. Run #12's CPython SHA-256 is `284fd97f7c7d1fc83f7031d8ccd96ab1ce9f14d90a67544e675a47487f82d950`. Its Node compiler preflight passed, but the header-selection assertion failed to observe `/usr/include/c++/10/vector`; the prior helper did not print the trace, so Clang's selected path is not yet known. The follow-up emits and retains the trace before changing include paths. No Node compilation, npm or pnpm check occurred in run #12. The OpenSSL workaround's crypto-performance cost remains unmeasured on B10. Debian 11's default GCC 10.2 is below Node 26's compiler requirement, so the hosted Clang route remains the candidate.

## Next engineering milestones

PR #8 adds an owner-gated GitHub-hosted runtime build using signed Debian metadata. It requests empty token permissions; the runner reports implicit metadata:read, which the workflow never reads or passes. It uses no configured secrets or binary uploads and refuses non-hosted runners. Run #1 verified the main snapshot and bootstrapped i386, then found an incorrect security component plus a nonexistent gdbm-dev package. Run #2 loaded the signed security index but the snapshot host returned 404 for the security pool .debs. Run #3 downloaded the archive packages but exited at the Clang package cache/hash gate before installation. Run #4 (`44240968415`, source head `56387f52f56309b0652d44b3bc5c55e3fe7cf5bb`) verified the Clang package digest against the signed index and built/smoke-tested CPython 3.14.9 in i386 userspace, then failed during Node's OpenSSL assembly compile. Runs #5 (`44244683708`) and #6 (`44247738533`) matched the Clang package SHA-256 to signed APT metadata and built CPython ELF32 with hashes `feb9bbe20801ec7b481d2e4cd04d1787eca1fe489bf5cf51826a1da65c3c619a` and `23b6cb39fc312ad1bb3fdfb0c08a9b33cc162740c7696ca314b174ec44cbcddb`. Run #7 (`44250238773`, source head `78767e74157490176d05e997a53b89544c628465`) again matched Clang to the signed APT index and built/smoke-tested CPython ELF32, SHA-256 `89751d5686ebbac10203bde40a483c4bb38a0a687d37e3200842b64ba5896ce1`; Node failed in `zlib_data_chunk_simd`. Run #8 (`44253329566`, source head `2ca1fb8abd193c5d9bf9b2739e2e5332ee0b5d8f`) again matched Clang and built/smoke-tested CPython ELF32, SHA-256 `983771076e787e2e5fb20cd3ffc0d8352f1e6de973cdf2ae337e5c3298056ee6`; the two zlib targets compiled with the ia32 SSE2 patch, then OpenSSL CLI link failed on unresolved `__atomic_*` symbols. The combined patch adds `-latomic` only to OpenSSL CLI for Linux ia32/Clang, has SHA-256 `c1b97940c0d05a25fe7a31647723e7444130be51ea5da297142e926ed2fa5a0a`, and is covered by exact-source application checks plus local fixtures. Run #9 (`44255938174`) completed: Clang's signed package hash matched, CPython ELF32 passed (SHA-256 `ed8338f5c01c3ca49d435ffc36c9878d1df1a859b24cec62a7da8641afafd8a7`), both zlib targets compiled, and OpenSSL CLI linked with `-latomic`; Node then stopped at missing `<source_location>`. Run #10 (`44263422952`, source head `ac428c9f1935cf3dcd9cafe5d74693497ca4b31c`) verified the GCC 11 headers and executed the caller/ABI probe as ELF32; CPython passed with SHA-256 `a3c568543f767d775dfb3b9d4853485cbed0189c0a550206cf5ddc2cec3df34e`. Node compilation still lacked the header because `compile_build` unset `CXXFLAGS`. Run #11 confirmed Make-time flags reach Node but exposed a link failure from mixing all GCC 11 headers with Bullseye's GCC 10 runtime. The next patch overlays only `<source_location>`, keeps the default GCC 10 headers/runtime, and adds vector/unordered-map probe coverage. Measure OpenSSL performance and memory on staging.

1. Review the next hosted run's emitted C++ include trace and use the observed paths to correct the GCC 10 header-selection check without mixing GCC header generations. Do not treat the hosted runner as B10 staging evidence.
2. Run the CPython 3.14.9 and Node 26.12.1 recipes on isolated ELF32/i686 staging with the documented compiler and system dependencies; capture interpreter/runtime ELF hashes and smoke results.
3. Run the pnpm WASM CLI and offline install with that Node using `--require-ia32`; measure memory on the target before accepting it for Púlsar.
4. Add and verify the locally built Node artifact in the private staging lock, then test the full PM dependency closure there. Do not publish the binary in this public repository.
5. Review the 13 remaining PM rows against official assets and digests; keep unsupported packages explicit.
6. Run the offline wheel/lock reconciler in Púlsar staging against the actual plan, lock, and existing wheelhouse; resolve the nine gaps without downloading the reported 92 wheels again.
7. Continue Púlsar's private migration only in the separate repository described by `PRIVATE-INTEGRATION-SETUP.md`; this public work contains no private source or customization details.

## Review follow-up and boundaries

- The PR #2 request to verify uv before adding a pin is resolved by the ordered patch in PR #3: the release API digest, published checksum sidecar, downloaded bytes, and extracted ELF32 executables agree.
- The missing-pin regression now uses an explicit lock fixture. The patchset also covers ELF validation at the shared PM admission/install/doctor boundary so subclass-specific `verify()` implementations cannot bypass it.
- Native i686 validation on the operator's staging host remains pending. This public workstream has no access to the B10 or private Púlsar code; the i686 uv binary was not executed here.
- PR #2 remains open and unmerged. No deployment, production access, private customization, wheel upload, or channel session was used.
