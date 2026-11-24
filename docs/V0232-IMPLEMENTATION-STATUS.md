# Hermes Agent v0.23.2 i686 implementation status

Updated 2026-11-24. This is the public, generic compatibility workstream. It contains no Hermes source checkout, private Púlsar code, credentials, sessions, wheelhouse, or retained runtime binaries. Hosted Debian 11 i386 build evidence from Actions run #28 is recorded below.

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

The verified uv pin was the first binary `linux-i686` row added to the v0.23.2 lock. The pnpm 12.15.0 WASM artifact is now also pinned for `linux-i686`; 14 remaining Linux-x64 candidates need individually reviewed i686 artifact rows and digests before PM can install them:

`bws`, `chromium`, `cua-driver`, `ffmpeg`, `gh`, `iron-proxy`, `just`, `llamacpp-cpu`, `llamacpp-cuda`, `llamacpp-hip`, `llamacpp-vulkan`, `node`, `python`, `ripgrep`.

The other six lock packages have different target semantics: `dmgbuild` and `llamacpp-metal` are macOS tools; `git` is supplied by the Linux host; `npm` is pinned as a target-independent `any` artifact; `termux-docker` is Android ARM64 only; `whispercpp-cpu` has no Linux-x64 row. Their absence is not a claim of i686 compatibility.

Runtime artifact checks performed for this milestone:

| Pin | Public source evidence | Result |
|---|---|---|
| uv 0.13.5 | [Official release](https://github.com/astral-sh/uv/releases/tag/0.13.5), asset `uv-i686-unknown-linux-gnu.tar.gz`, 17,987,531 bytes. GitHub release API digest: `sha256:f5713d6c05d77d01de9655270d713ba87ed45391752f489c80bbf1690bccc17c`; published `.sha256` sidecar asset digest: `sha256:bf04536e7b5564ab322ab286a8033830d53bc8462ed04e81407208d6a11df5a1` | Downloaded the archive; locally computed SHA-256 and the published sidecar both matched the GitHub release digest. Extracted `uv` and `uvx` are ELF32, little-endian, `EM_386`. The binary was not executed on x86_64. The exact URL and digest are now in the `linux-i686` lock row and generated shell bootstrap pin. |
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
- `tests/test-v0232-patchset.sh` with ordered patch 0003 — exit 0; 103 focused tests passed and one macOS-only test skipped. The set includes PM core/install/doctor coverage and three pnpm-WASM package/lock regressions.
- `scripts/test-v0232-pnpm-wasm-pm-stage.sh` — exit 0; PM fetched the official WASM tarball over loopback, enforced the lock SHA, installed the i686 store entry, and checked its launcher layout and ELF scan without executing it.
- `scripts/verify-v0232-pnpm-wasm.sh` with the official npm tarballs — exit 0 on Node 24.22.1 x64; the regular package failed closed when native-binary network access was disabled, while `@pnpm/wasm` ran version and offline local-file install checks.
- `scripts/build-cpython-v0232-i686.sh --prepare-only` — exit 0; exact CPython tag object/commit/tree verified; repeated invocation reused its source checkpoint.
- `scripts/build-node-v0232-i686.sh --prepare-only` — exit 0; official Node source SHA verified and extraction checkpoint resumed. Both build scripts' `--preflight-only` reject this ELF64 x86_64 process before compiling.
- `tests/test-v0232-runtime-builds.sh` — exit 0; syntax, serial-job rejection, bad archive hash, ELF32/x64 fixture, and checkpoint fingerprint coverage passed.
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
| CPython/Node source preparation | HOSTED CI + STATIC | CPython tag object/commit/tree and Node official source checksum verified; source extraction and checkpoints resume. No compilation performed. |
| Hosted Debian 11 i386 userspace | HOSTED CI | Actions run #28 built CPython 3.14.9 and Node 26.12.1 as ELF32/EM_386 and passed runtime smoke checks. This is hosted userspace evidence, not B10 hardware validation. |
| Native ARM64 | NOT RUN | ARM64 is covered with ELF fixtures; no ARM64 execution host was attached. |
| Hosted CPython/Node builds and pnpm WASM on i686 | HOSTED CI | Run #28 passed CPython, Node, six V8 spans, worker_threads, shared WebAssembly memory, ICU es-AR and pnpm WASM offline-install checks in a Debian 11 i386 chroot. No binaries were retained. |
| B10-native runtimes and full PM install/lock/doctor | NOT RUN | Run #28 was hosted CI, produced no retained binaries, and did not exercise Púlsar's lock or wheelhouse. B10 performance, ARM64, and complete dependency closure remain unverified. The reported 92 wheels were not fetched again. |

The host for this implementation is Linux x86_64. The test environment was built with the checkout's `pm.build_env` using bootstrap CPython 3.12.14 and the managed CPython 3.14.9 test interpreter. A passing x86_64 or fixture test is not native i686 evidence. Use an isolated Debian 11 i386 staging image/device for the remaining runtime gates in `V0232-ACCEPTANCE.md`.

## Hosted Debian 11 i386 runtime results — Actions run #28 (2026-11-19)

Run #28 (workflow `v0.23.2 native i686 runtimes`, job `135329601952`) succeeded on PR #11 head `f09eca83d0e72bfe1415eabc1c1256d22f7b8f91`. Hosted Ubuntu 24.04 used a Debian 11 i386 userspace/chroot without QEMU.

- Clang 19.1.7 i386 package passed the preflight with SHA-256 `d52c7089346ebc4616d3e9e3bbee6eb0848455a9abb777746fdd32812ce981d3`, matching signed APT metadata.
- CPython 3.14.9 ran as ELF32/EM_386, 32-bit pointers; SHA-256 `8cef39b6947193697c241d839a8a5284592f3027530de94ca13968caeec1f14f`.
- Node 26.12.1 ran as ELF32/EM_386 with `process.arch=ia32`, npm 11.20.0; Node SHA-256 `fe371ba1480fd0040cdea4e4a3ab2079edd45c9c33efd11d84c898661dcf086f`.
- Six V8 spans, worker_threads, shared WebAssembly memory, and ICU `es-AR` passed. Node targeted SSE2 and used `--openssl-no-asm`; B10 performance has not been measured.
- `@pnpm/wasm@12.15.0` ran under Node ia32; SHA-256 `172c9d9a2b8b82b00a67323ffa6d34c32f8706279661329ea460432b95c9da1f`, with npm integrity `sha512-uxV61T7Sn34SAVUkzZf0xYNW0Ocw59OCHYRNdY2pOm4xE3Z+r2ptXOd2XTiWQBOZ8qgyMLs69F4ZHcUakvFR2Q==`. An offline local-file install passed; the package had no native executable.
- The workflow artifact list was empty; it retained/uploaded no binaries.

This is hosted i386 userspace evidence, not a B10 staging install. It does not close the full PM/lock/dependency, private customization, ARM64, memory/performance, backup/restore, or rollback gates. The reported wheelhouse was not inspected.

## Next engineering milestones

1. Run the CPython 3.14.9 and Node 26.12.1 recipes on isolated ELF32/i686 staging with the documented compiler and system dependencies; capture interpreter/runtime ELF hashes and smoke results.
2. Run the pnpm WASM CLI and offline install with that Node using `--require-ia32`; measure memory on the target before accepting it for Púlsar.
3. Add and verify the locally built Node artifact in the private staging lock, then test the full PM dependency closure there. Do not publish the binary in this public repository.
4. Review the 14 remaining PM rows against official assets and digests; keep unsupported packages explicit.
5. Run the offline wheel/lock reconciler in Púlsar staging against the actual plan, lock, and existing wheelhouse; resolve the nine gaps without downloading the reported 92 wheels again.
6. Continue Púlsar's private migration only in the separate repository described by `PRIVATE-INTEGRATION-SETUP.md`; this public work contains no private source or customization details.

## Review follow-up and boundaries

- The PR #2 request to verify uv before adding a pin is resolved locally: the release API digest, published checksum sidecar, downloaded bytes, and extracted ELF32 executables agree. The next PR adds this as an ordered patch after PR #2.
- The missing-pin regression now uses an explicit lock fixture. The patchset also covers ELF validation at the shared PM admission/install/doctor boundary so subclass-specific `verify()` implementations cannot bypass it.
- Native i686 validation on the operator's staging host remains pending. This public workstream has no access to the B10 or private Púlsar code; the i686 uv binary was not executed here.
- PR #2 remains open and unmerged. No deployment, production access, private customization, wheel upload, or channel session was used.

## Wheelhouse report parent-race guard — HOST / synthetic, 2026-11-21

Public PR #28 follows PR #27's atomic report replacement guard. A deterministic baseline test swaps the report's parent directory for a symlink after path validation; PR #27 writes the synthetic report through that symlink into the outside target. A second baseline test moves the wheelhouse into a previously missing output-parent path; the unguarded writer places its report inside the wheelhouse.

An additional regression starts with the report parent already symlinked. On PR #27, the baseline followed that symlink and wrote `summary.json` into the outside directory. The PR #28 guard rejects it before writing.

The follow-up pins each path component with `O_DIRECTORY | O_NOFOLLOW`, uses descriptor-relative temporary-file/replace/cleanup operations, checks the validated directory identity before and after replacement, refuses parents inside the captured wheelhouse inode, and refuses destination entries that alias protected inputs. Newly created parent directories retain the existing umask-based mode behavior.

Verification on Python 3.12.14 / Linux x86_64:

- `python3 tests/test-v0232-wheel-reconcile.py -q` — 23 passed, including baseline-reproduced initial and raced parent symlinks, moved-wheelhouse write, replacement with another real directory, parent move at atomic replace, and missing-parent creation.
- `python3 -m py_compile scripts/reconcile-v0232-wheelhouse.py tests/test-v0232-wheel-reconcile.py` — exit 0.
- `git diff --check` — exit 0.
- SHA-256: reconciler `b1a7d54ff6cb205e88490f9ed4849a9b664157597dbaede8b8f906dbc4450937`; tests `ce62774416118a83d72fe008302d7a47936f25b5a36ca768b5973f4977bc6b33`.

This is a local host filesystem test only. It does not establish native i686 or ARM64 behavior, validate Púlsar's actual lock/wheelhouse, or provide Hermes installation evidence. No reported wheel was fetched or rebuilt and no CI run was started.

## Wheel reconciler Python 3.14.9 host recheck — 2026-11-22 17:35 UTC

Re-fetched the PR #28 head `fa2a52417d6bfbf38b4da54d4cb863e6ea6d4bbd` reconciler and test files through GitHub into a disposable host directory. Local Git blob IDs match the public head: reconciler `6701a4e6f55212e0dcae25720eb252aa2d5fb45b`; test `83afe0f8e868be91b50128c41331bd28ceb1d090`. SHA-256 values match PR #28's recorded hashes: `b1a7d54ff6cb205e88490f9ed4849a9b664157597dbaede8b8f906dbc4450937` and `ce62774416118a83d72fe008302d7a47936f25b5a36ca768b5973f4977bc6b33`.

Command on CPython 3.14.9 / pytest 9.1.1 / Linux x86_64:

```sh
PYTHONDONTWRITEBYTECODE=1 PYTHONPATH=. /tmp/hermes-v0232-test-venv/bin/python -m pytest -q -p no:cacheprovider tests/test-v0232-wheel-reconcile.py
```

Result: exit 0, **23 passed, 3 subtests passed in 1.25s**. The fixtures cover the report directory's symlink/rename/alias races and use synthetic wheelhouse and lock files only. No real wheelhouse, lock, or reported wheel was accessed; nothing was downloaded, installed, rebuilt, or uploaded, and no Actions workflow was started.

This is a Python 3.14.9 host x86_64 filesystem regression. It is not native i686 or ARM64 evidence and does not establish the Hermes package-manager install, dependency closure, or B10 staging.


## Official Linux/i686 release-asset check — 2026-11-24

At the pinned Hermes v0.23.2 source commit, `pm/lock.json` selects `just` 1.59.0 and `ripgrep` 15.2.0. Read-only GitHub Releases API metadata was checked for those exact upstream tags:

- [casey/just 1.59.0](https://github.com/casey/just/releases/tag/1.59.0): the published Linux assets include AArch64, ARM/ARMv7, LoongArch64, RISC-V and x86_64; the release contains no Linux i686 asset.
- [BurntSushi/ripgrep 15.2.0](https://github.com/BurntSushi/ripgrep/releases/tag/15.2.0): the published Linux assets include AArch64, ARMv7, s390x and x86_64; its i686 asset is Windows-only, with no Linux i686 asset.

The API metadata is available at [the just release endpoint](https://api.github.com/repos/casey/just/releases/tags/1.59.0) and [the ripgrep release endpoint](https://api.github.com/repos/BurntSushi/ripgrep/releases/tags/15.2.0). This confirms that neither exact upstream release can supply a generic Linux/i686 binary row. No digest was borrowed from another architecture, and no lock row was added. Púlsar's reported local ripgrep i686 pin remains operator-supplied until its sanitized source/build provenance and artifact digest are reviewed; it is not evidence for a public upstream binary.

This was a metadata-only check: no release archive or sidecar was downloaded, no binary was executed, and no test/build or Actions run was started. Next, resolve the remaining PM candidates only when exact upstream assets or reviewed, reproducible i686 source-build manifests are available.
