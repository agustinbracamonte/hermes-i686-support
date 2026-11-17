# Hermes Agent v0.23.2 i686 implementation status

Updated 2026-11-17. This is the public, generic compatibility workstream. It does not include a Hermes source checkout, private Púlsar code, credentials, sessions, wheels, or binaries.

## Pinned source

- Upstream: `https://github.com/NousResearch/hermes-agent`
- Tag object: `v0.23.2` → `28f57ed8e3dba4eceb67dfd3e3abda1a7604452d`
- Commit: `ae2a81ccc00e9b7c06301523e5bb09608397149c`
- Checkout used for implementation: disposable clone at the exact commit above; the public repo stores only an applicable patch.

## First milestone: process ABI, PM and bootstrap

The patchset in `patches/v0.23.2/0001-linux-i686-process-abi.patch` changes the pinned upstream source to:

- Resolve Linux x86 from the running Python process's pointer width and ELF header. A 32-bit `EM_386` process under an x86_64 kernel selects `linux-i686`; an x32 or inconsistent process fails closed.
- Verify ELF class as well as `e_machine`. For i686 store entries, scan ELF payloads so an x64 shared object cannot be accepted beside an i686 executable.
- Have `scripts/install.sh` and `setup-hermes.sh` inspect the running Bash ELF and `getconf LONG_BIT` instead of mapping Linux targets from `uname -m` alone.
- Keep the i686 target recognized while leaving its unavailable artifact pins absent. Both bootstrap paths refuse to stage uv when the `linux-i686` row is missing; they never fall back to x64.

Apply only to a clean checkout of the pinned source:

```bash
scripts/apply-v0232-patches.sh --check /path/to/hermes-agent-v0.23.2
scripts/apply-v0232-patches.sh --apply /path/to/hermes-agent-v0.23.2
```

The test harness archives the pinned commit into a temporary directory, applies the patch there, checks both bootstrap probes, and runs focused upstream tests:

```bash
HERMES_PYTHON=/path/to/python-with-pytest tests/test-v0232-patchset.sh /path/to/hermes-agent-v0.23.2
```

## Lock gaps and artifact evidence

The official v0.23.2 `pm/lock.json` contains no `linux-i686` row. The 16 existing Linux-x64 candidates below need individually reviewed i686 artifact rows and digests before PM can install them:

`bws`, `chromium`, `cua-driver`, `ffmpeg`, `gh`, `iron-proxy`, `just`, `llamacpp-cpu`, `llamacpp-cuda`, `llamacpp-hip`, `llamacpp-vulkan`, `node`, `pnpm`, `python`, `ripgrep`, `uv`.

The other six lock packages have different target semantics: `dmgbuild` and `llamacpp-metal` are macOS tools; `git` is supplied by the Linux host; `npm` is pinned as a target-independent `any` artifact; `termux-docker` is Android ARM64 only; `whispercpp-cpu` has no Linux-x64 row. Their absence is not a claim of i686 compatibility.

Runtime artifact checks performed for this milestone:

| Pin | Public source evidence | Result |
|---|---|---|
| uv 0.13.5 | [Official release](https://github.com/astral-sh/uv/releases/tag/0.13.5) metadata lists `uv-i686-unknown-linux-gnu.tar.gz`; GitHub's asset digest is `f5713d6c05d77d01de9655270d713ba87ed45391752f489c80bbf1690bccc17c` | Asset exists; bytes were not downloaded or executed. The lock row remains absent pending the dedicated pin-verification change. |
| CPython 3.14.9+20261021 | [python-build-standalone release](https://github.com/astral-sh/python-build-standalone/releases/tag/20261021) has x86_64 and AArch64 Linux builds, plus i686 Windows builds; no i686 Linux build | No official Linux i686 binary identified. Build and verify CPython in isolated staging. |
| Node 26.12.1 | Official [`SHASUMS256.txt`](https://nodejs.org/dist/v26.12.1/SHASUMS256.txt) lists `node-v26.12.1.tar.xz` as `053e3b296859b6d8d93f99ef97fa9cec1c4ee171c72968100c649978c1dbd38c`; binary list has `linux-x64`, `linux-arm64`, and x64-musl Linux assets, no 32-bit Linux asset | Source checksum is recorded for a future build. No official i686 runtime binary or digest was found. |

The CPython source archive SHA-256 was not captured: the python.org source URL returned HTTP 403 from this environment. Obtain and verify its official source digest before starting the build. The uv release metadata reports a SHA-256 for its i686 archive, but this task did not download and recompute the archive bytes.

The 102-dependency wheel counts in `CODEX-HANDOFF-V0232.md` are operator-reported staging findings, not reproduced in this implementation. The reported breakdown (44 exact locked matches, 48 compatible locked wheels to retrieve, 10 without locked i686-compatible wheels) must be reconciled against the exact v0.23.2 `uv.lock`, selected extras, wheel tags, and digests before any candidate or build count is treated as confirmed. No wheel was built or added here.

## Test evidence

Every result is specific to the execution host and command. The focused harness runs against an archived copy so it cannot modify the operator's source checkout.

Executed in this work session:

- `HERMES_PYTHON=/tmp/hermes-v0232-test-venv/bin/python tests/test-v0232-patchset.sh /tmp/hermes-agent-v0232` — exit 0; patch applied to a clean archive of the pinned commit; 53 tests passed across `test_store.py`, `test_downloader.py`, and `test_downloader_integrity.py`.
- `tests/test-scripts.sh` — exit 0; existing self-contained shell, static, publication, and Signal-provenance checks passed.
- `ruff check pm/package.py pm/store.py tests/pm/test_store.py` on the patched source — exit 0.
- `bash -n scripts/install.sh setup-hermes.sh` and `git diff --check` on the patched source — exit 0.
- `scripts/apply-v0232-patches.sh --check` and `--apply` — both succeeded against the exact commit; the apply check used a disposable clone.

| Check | Evidence label | Status |
|---|---|---|
| Pinned tag object and commit | STATIC | Verified by `git rev-parse v0.23.2` and `git rev-parse 'v0.23.2^{commit}'`. |
| Mixed kernel/process ABI logic | STATIC | ELF32/EM_386 under x86_64 kernel fixture selects i686; x32 and inconsistent width fixtures fail closed. |
| Bootstrap selection | HOSTED CI | Linux x86_64 Bash and Python select x64 on this host; fixtures cover i686/x64/ARM64; both lock readers refuse the missing i686 uv row. |
| ELF executable/shared-object validation | STATIC | ELF32/EM_386 accepted; ELF64, wrong `e_machine`/endianness, and mixed-width i686 tree fixtures rejected. |
| Downloader checksum enforcement | HOSTED CI | Focused upstream local-server tests exercise wrong-digest rejection without public network downloads. |
| Native Linux i686 Python and Bash | NOT RUN | No native i686 userspace or interpreter is attached to this environment. |
| Native ARM64 | NOT RUN | ARM64 is covered with ELF fixtures; no ARM64 execution host was attached. |
| Full PM install, Python wheels, Node/npm, gateway | NOT RUN | i686 lock rows and runtimes are not staged; no full install was attempted. |

The host for this implementation is Linux x86_64. The test environment was built with the checkout's `pm.build_env` using bootstrap CPython 3.12.14 and the managed CPython 3.14.9 test interpreter. A passing x86_64 or fixture test is not native i686 evidence. Use an isolated Debian 11 i386 staging image/device for the remaining runtime gates in `V0232-ACCEPTANCE.md`.

## Next engineering milestones

1. **Runtime build:** source-build CPython 3.14.9 serially with SSL, SQLite, ctypes and test imports; record the exact source hash, compiler, config flags, output ELF identity, and checksums.
2. **Node:** test whether Node 26.12.1 can be built for i686 in a checkpointed, low-memory job; verify ELF32, npm version, simple JS and npm execution. Do not reuse x64 lock pins.
3. **uv pin and PM rows:** download the official uv 0.13.5 i686 asset into isolated staging, independently compare its bytes with the release digest, smoke-test ELF32, then add only the exact verified lock/bootstrap pins. Check all applicable tools and keep unsupported targets explicit.
4. **Wheels:** reproduce the 102-dependency inventory from the pinned lock and actual extras, retrieve exact locked-compatible wheels with checksums, and serial-build only packages with no compatible locked wheel. Verify wheel tags, extension ELF headers and isolated imports.
5. **Púlsar migration:** continue only in the separate private repository described by `PRIVATE-INTEGRATION-SETUP.md`. Use [`PULSAR-V0232-MIGRATION-CHECKLIST.md`](PULSAR-V0232-MIGRATION-CHECKLIST.md) as a sanitized contract/test plan; no private source was available or copied into this public repo.
