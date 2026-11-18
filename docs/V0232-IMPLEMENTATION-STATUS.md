# Hermes Agent v0.23.2 i686 implementation status

Updated 2026-11-17. This is the public, generic compatibility workstream. It does not include a Hermes source checkout, private Púlsar code, credentials, sessions, wheels, or binaries.

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

The verified uv pin below is the first `linux-i686` row added to the v0.23.2 lock. The 15 remaining Linux-x64 candidates need individually reviewed i686 artifact rows and digests before PM can install them:

`bws`, `chromium`, `cua-driver`, `ffmpeg`, `gh`, `iron-proxy`, `just`, `llamacpp-cpu`, `llamacpp-cuda`, `llamacpp-hip`, `llamacpp-vulkan`, `node`, `pnpm`, `python`, `ripgrep`.

The other six lock packages have different target semantics: `dmgbuild` and `llamacpp-metal` are macOS tools; `git` is supplied by the Linux host; `npm` is pinned as a target-independent `any` artifact; `termux-docker` is Android ARM64 only; `whispercpp-cpu` has no Linux-x64 row. Their absence is not a claim of i686 compatibility.

Runtime artifact checks performed for this milestone:

| Pin | Public source evidence | Result |
|---|---|---|
| uv 0.13.5 | [Official release](https://github.com/astral-sh/uv/releases/tag/0.13.5), asset `uv-i686-unknown-linux-gnu.tar.gz`, 17,987,531 bytes. GitHub release API digest: `sha256:f5713d6c05d77d01de9655270d713ba87ed45391752f489c80bbf1690bccc17c`; published `.sha256` sidecar asset digest: `sha256:bf04536e7b5564ab322ab286a8033830d53bc8462ed04e81407208d6a11df5a1` | Downloaded the archive; locally computed SHA-256 and the published sidecar both matched the GitHub release digest. Extracted `uv` and `uvx` are ELF32, little-endian, `EM_386`. The binary was not executed on x86_64. The exact URL and digest are now in the `linux-i686` lock row and generated shell bootstrap pin. |
| CPython 3.14.9+20261021 | [python-build-standalone release](https://github.com/astral-sh/python-build-standalone/releases/tag/20261021) has x86_64 and AArch64 Linux builds, plus i686 Windows builds; no i686 Linux build | No official Linux i686 binary identified. Build and verify CPython in isolated staging. |
| Node 26.12.1 | Official [`SHASUMS256.txt`](https://nodejs.org/dist/v26.12.1/SHASUMS256.txt) lists `node-v26.12.1.tar.xz` as `053e3b296859b6d8d93f99ef97fa9cec1c4ee171c72968100c649978c1dbd38c`; binary list has `linux-x64`, `linux-arm64`, and x64-musl Linux assets, no 32-bit Linux asset | Source checksum is recorded for a future build. No official i686 runtime binary or digest was found. |

`scripts/verify-v0232-uv-i686.sh --runtime` is available for a native staging execution check. It verifies the running shell is ELF32/EM_386 with 32-bit pointer width, refuses QEMU-marked or QEMU-mapped shells, then verifies the official archive and lock digest and runs both `uv` and `uvx` with a temporary cache to check version 0.13.5. Pass an already downloaded archive through `UV_I686_ARCHIVE` to avoid fetching its bytes again; the official checksum sidecar is still checked. This execution mode has not yet been run on native i686.

The CPython source archive SHA-256 was not captured: the python.org source URL returned HTTP 403 from this environment. Obtain and verify its official source digest before starting the build. The uv archive bytes were downloaded and independently recomputed as described above.

The 102-dependency wheel counts in `CODEX-HANDOFF-V0232.md` are operator-reported staging findings, not reproduced in this implementation. The reported breakdown (44 exact locked matches, 48 compatible locked wheels to retrieve, 10 without locked i686-compatible wheels) must be reconciled against the exact v0.23.2 `uv.lock`, selected extras, wheel tags, and digests before any candidate or build count is treated as confirmed. No wheel was built or added here.

## Test evidence

Every result is specific to the execution host and command. The focused harness runs against an archived copy so it cannot modify the operator's source checkout.

Executed in this work session:

- `HERMES_PYTHON=/tmp/hermes-v0232-test-venv/bin/python tests/test-v0232-patchset.sh /tmp/hermes-agent-v0232` — exit 0; both ordered patches applied to a clean archive of the pinned commit; 56 tests passed across `test_store.py`, `test_downloader.py`, and `test_downloader_integrity.py`.
- `HERMES_PYTHON=/tmp/hermes-v0232-test-venv/bin/python scripts/run_tests.sh tests/pm/test_store.py tests/pm/test_pm_core.py` — exit 0; 68 tests passed and one macOS-only case skipped. Coverage includes 32-bit userspace under x86_64 kernel selection and `doctor` rejecting mixed ELF in a custom package entry.
- `HERMES_PYTHON=/tmp/hermes-v0232-test-venv/bin/python scripts/run_tests.sh tests/hermes_cli/test_local_runtime_pm.py` — exit 0; all 9 PM-owned local runtime adoption tests passed after routing that check through the common ELF guard.
- `UV_I686_ARCHIVE=/tmp/uv-i686-unknown-linux-gnu-0.13.5.tar.gz scripts/verify-v0232-uv-i686.sh /tmp/hermes-v0232-uv-dev` — exit 0; downloaded official checksum sidecar, recomputed archive SHA-256, checked `uv`/`uvx` ELF headers, and verified generated shell pins match the lock.
- `scripts/apply-v0232-patches.sh --apply /workspace/hermes-uv-verifier-check` followed by `UV_I686_ARCHIVE=/tmp/uv-i686-unknown-linux-gnu-0.13.5.tar.gz scripts/verify-v0232-uv-i686.sh --static-only /workspace/hermes-uv-verifier-check` — exit 0 against upstream commit `ae2a81ccc00e9b7c06301523e5bb09608397149c`; reused the existing archive, matched the official sidecar/lock SHA-256, verified both ELF32 headers and bootstrap pins. Binary execution was not run.
- `tests/test-v0232-uv-runtime-guard.sh` — exit 0 on x86_64; `--runtime` refused before source or network access because the running shell is not ELF32/EM_386. No uv binary was executed.
- `UV_I686_ARCHIVE=/tmp/uv-i686-unknown-linux-gnu-0.13.5.tar.gz HERMES_PYTHON=/tmp/hermes-v0232-test-venv/bin/python scripts/test-v0232-uv-i686-pm-stage.sh /tmp/hermes-v0232-uv-dev` — exit 0; PM fetched the already verified archive from loopback, enforced the lock digest, installed it into an isolated temporary store, and checked both ELF32 executables without running them.
- `scripts/apply-v0232-patches.sh --check /tmp/hermes-agent-v0232` — exit 0; full ordered patch series applies cleanly to the exact official source commit.
- `tests/test-scripts.sh` — exit 0; self-contained shell, static, publication, Signal-provenance, and uv runtime-guard checks passed. No i686 execution was performed.
- `python3 scripts/gen-bootstrap-pins.py --check` on the patched source — exit 0; the i686 bootstrap fragment matches `pm/lock.json`.
- `ruff check pm/package.py pm/store.py pm/install.py pm/cli.py hermes_cli/local_runtime/binaries.py tests/pm/test_store.py tests/pm/test_pm_core.py` on the patched source — exit 0.
- `bash -n scripts/install.sh setup-hermes.sh` and `git diff --check` on the patched source — exit 0.
- `scripts/apply-v0232-patches.sh --apply` — exit 0 on a disposable clone; the original pinned source checkout remained clean.

| Check | Evidence label | Status |
|---|---|---|
| Pinned tag object and commit | STATIC | Verified by `git rev-parse v0.23.2` and `git rev-parse 'v0.23.2^{commit}'`. |
| Mixed kernel/process ABI logic | STATIC | ELF32/EM_386 under x86_64 kernel fixture selects i686; x32 and inconsistent width fixtures fail closed. |
| Bootstrap selection and lock pin | HOSTED CI + STATIC | Shell fixtures select i686 under x86_64, keep x64/ARM64 mapping and digests unchanged, and check `install.sh`'s generated pin plus `setup-hermes.sh`'s lock reader. A missing-row lock fixture remains fail-closed. |
| uv 0.13.5 asset hash and ELF | HOSTED CI | The 17,987,531-byte official release archive matched both GitHub's release digest and the published checksum sidecar. `uv` and `uvx` headers are ELF32/EM_386. Neither binary was executed. |
| PM lock/download/install | HOSTED CI | An isolated PM cross-stage downloaded the local copy of the exact official archive over loopback and verified the lock SHA, extraction, store entry and ELF class. |
| ELF executable/shared-object validation | HOSTED CI + STATIC | ELF32/EM_386 accepted; ELF64, wrong `e_machine`/endianness, mixed-width payloads, and a custom `Package.verify()` override are rejected through the common PM verifier. `doctor` reports the incompatibility. |
| Downloader checksum enforcement | HOSTED CI | Focused upstream local-server tests exercise wrong-digest rejection; the real uv archive also passed PM's lock-backed SHA check. |
| Native Linux i686 Python and Bash | NOT RUN | No native i686 userspace or interpreter is attached to this environment. |
| Native ARM64 | NOT RUN | ARM64 is covered with ELF fixtures; no ARM64 execution host was attached. |
| Full PM install, Python wheels, Node/npm, gateway | NOT RUN | i686 lock rows and runtimes are not staged; no full install was attempted. |

The host for this implementation is Linux x86_64. The test environment was built with the checkout's `pm.build_env` using bootstrap CPython 3.12.14 and the managed CPython 3.14.9 test interpreter. A passing x86_64 or fixture test is not native i686 evidence. Use an isolated Debian 11 i386 staging image/device for the remaining runtime gates in `V0232-ACCEPTANCE.md`.

## Next engineering milestones

1. **CPython:** prepare and validate a serial, resumable CPython 3.14.9 i686 source-build recipe with checkpoints, exact source checksum, SSL/SQLite/ctypes checks, and ELF32 validation.
2. **Node:** prepare the same checkpointed workflow for Node 26.12.1; verify the final ELF32 binary and npm without reusing x64 pins.
3. **pnpm:** confirm whether the 12.15.0 package is a JavaScript distribution usable under Node i686, and add reproducible PM/install coverage without an extra native executable if verified.
4. **Remaining PM rows:** review each applicable missing tool against release assets and digests; keep unsupported packages explicit and do not infer compatibility from version names.
5. **Wheel integration:** add a sanitized reconciliation tool for Púlsar's reported 92 verified compatible wheels and nine unresolved dependencies. It must compare package/version/tags/hashes to the exact lock and report operator-provided versus locally reproduced evidence without downloading those wheels again.
6. **Púlsar migration:** continue only in the separate private repository described by `PRIVATE-INTEGRATION-SETUP.md`. Use [`PULSAR-V0232-MIGRATION-CHECKLIST.md`](PULSAR-V0232-MIGRATION-CHECKLIST.md) as a sanitized contract/test plan; no private source was available or copied into this public repo.

## Review follow-up and boundaries

- The PR #2 request to verify uv before adding a pin is resolved locally: the release API digest, published checksum sidecar, downloaded bytes, and extracted ELF32 executables agree. The next PR adds this as an ordered patch after PR #2.
- The missing-pin regression now uses an explicit lock fixture. The patchset also covers ELF validation at the shared PM admission/install/doctor boundary so subclass-specific `verify()` implementations cannot bypass it.
- Native i686 validation on the operator's staging host remains pending. This public workstream has no access to the B10 or private Púlsar code; the i686 uv binary was not executed here.
- PR #2 remains open and unmerged. No deployment, production access, private customization, wheel upload, or channel session was used.
