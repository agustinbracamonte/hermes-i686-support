# Hermes v0.23.2 i686 runtime builds

Updated 2026-11-24. This public workstream contains reproducible source-build procedures and hosted Debian 11 i386 build evidence. It retains no compiled CPython/Node binaries, wheelhouse, Púlsar source, or credentials.

## Locked source evidence

| Runtime | Source pin | Hash evidence |
|---|---|---|
| CPython 3.14.9 | Git tag object 17acf00d155cb8536eca1c3af3a8404db648e37f; commit ead82c07db1f111d613926ed1b6667411d768125; tree a0de950923dd481d2fd0f5bdc42ed9821763cbc4 | The build recipe fetches the tag from python/cpython and verifies the tag object, commit, tree, and clean checkout. python.org's source archive endpoint returned HTTP 403 here, so this work does not claim an official sdist SHA-256. |
| Node 26.12.1 | Official source tarball https://nodejs.org/dist/v26.12.1/node-v26.12.1.tar.xz; tag commit bc2e01dcf6acd5cf7d169b5f26cf89abaaeb41f1 | Official SHASUMS256.txt and locally downloaded bytes agree on SHA-256 053e3b296859b6d8d93f99ef97fa9cec1c4ee171c72968100c649978c1dbd38c. Tarball size: 62,570,464 bytes. |

Node's own v26.12.1 BUILDING.md labels Linux x86 as Experimental and lists GCC >=13.2 or Clang >=19.1 as current Linux toolchains. No official Linux i686 runtime binary exists. The checked-in recipe intentionally uses GCC >=13.2 and native i686 userspace; it does not alter x64 or ARM64 pins.

## Serial, resumable build recipes

Scripts:

- scripts/build-cpython-v0232-i686.sh
- scripts/build-node-v0232-i686.sh
- scripts/v0232-i686-build-common.sh

The build root is HERMES_I686_BUILD_ROOT or .work/v0232-i686. It must be a dedicated path without spaces. Both runtimes use one root-wide flock, reject JOBS other than 1, run GNU make with -j1, and write per-step SHA-256 fingerprints for source, configure, compile, install, and smoke-test checkpoints. A completed checkpoint is skipped only when its fingerprint and expected output still match. Partial make output can resume by rerunning the same command. A changed source, toolchain, script, or configure flag requires a new build root; the scripts do not delete a prior build tree.

The normal build refuses to run unless the shell itself is ELF32/EM_386 and the compiler targets i686. It does not select the target from uname -m. --prepare-only fetches/verifies sources without compiling and can run on a development x64 host. --preflight-only checks the native process ABI and toolchain before a build.

On the isolated i686 staging machine, first install the compiler and CPython development dependencies using that machine's approved package source. CPython needs the usual OpenSSL, zlib, SQLite, libffi, bzip2, lzma, readline and ncurses development headers. The scripts do not install system packages or silently change a host. The exact system package snapshot remains a staging input and must be recorded alongside the result manifest.

~~~bash
export HERMES_I686_BUILD_ROOT=/srv/hermes-i686-build/v0.23.2
scripts/build-cpython-v0232-i686.sh --preflight-only
scripts/build-cpython-v0232-i686.sh
scripts/build-node-v0232-i686.sh --preflight-only
scripts/build-node-v0232-i686.sh
~~~

The Node recipe consumes the CPython 3.14.9 i686 interpreter produced in that same root. It configures --dest-cpu=ia32 --with-intl=full-icu, keeps the bundled full ICU source, builds serially, installs under the root, and checks the resulting Node ELF32 header, Node/npm execution, process.arch, Spanish locale data, shared WebAssembly memory, and worker_threads. Result manifests include source hashes, compiler/linker versions, architecture, and installed executable hashes.

## pnpm 12.15.0 on i686

The regular npm package pnpm@12.15.0 is not a pure-JavaScript CLI. Its bin/pnpm.mjs wrapper downloads and launches a separate native pnpm executable. With COREPACK_ENABLE_NETWORK=0 and an empty temporary HOME, it fails with the explicit message that the native binary cannot be downloaded.

The official @pnpm/wasm@12.15.0 npm package is a usable alternative under Node >=22.13. Its official npm metadata integrity is sha512-uxV61T7Sn34SAVUkzZf0xYNW0Ocw59OCHYRNdY2pOm4xE3Z+r2ptXOd2XTiWQBOZ8qgyMLs69F4ZHcUakvFR2Q==; the downloaded tarball independently hashes to SHA-256 172c9d9a2b8b82b00a67323ffa6d34c32f8706279661329ea460432b95c9da1f. It carries a 44,951,421-byte WebAssembly module, JavaScript/worker glue and no ELF, PE, Mach-O, or .node files.

The ordered Hermes patch patches/v0.23.2/0003-pnpm-wasm-i686.patch adds an i686-only PM artifact row and shell launchers that execute the package's WASM CLI with the pinned Node dependency. The x64 and ARM64 pnpm URLs and hashes are regression-checked and unchanged.

Verify the package using the exact Node executable under test:

~~~bash
NODE_BIN=/path/to/node \
PNPM_WRAPPER_ARCHIVE=/path/to/pnpm-12.15.0.tgz \
PNPM_WASM_ARCHIVE=/path/to/pnpm-wasm-12.15.0.tgz \
scripts/verify-v0232-pnpm-wasm.sh --require-ia32
~~~

The script verifies SHA-256 and npm SHA-512 integrity, proves the regular wrapper needs the native executable, then runs the WASM CLI and an offline install from a local file dependency using a temporary empty HOME. The --require-ia32 switch requires Node to report process.arch=ia32. The WASM runtime reserves shared memory up to 1 GiB and uses worker_threads, so RAM pressure and behavior on Púlsar's target must be checked before treating this as staging evidence.

Hermes PM currently depends on its managed Node package for pnpm. Until Node 26.12.1 is built, ELF32-verified, and pinned in the private staging lock, this work can cross-stage the pnpm WASM artifact itself but cannot claim a complete pnpm dependency closure or full PM install on i686.

## Offline wheel/lock reconciliation

`scripts/reconcile-v0232-wheelhouse.py` compares an exact target-resolved requirements export, the matching `uv.lock`, and an existing wheelhouse. It uses the supplied CPython interpreter's `pip debug --verbose` tags by default and rejects an interpreter whose pointer width or `sysconfig` platform is not Linux i686. It preserves the per-package `status` values `verified`, `no-compatible-wheel`, `compatible-wheel-not-present`, `wheel-not-in-lock`, `package-not-in-lock`, and `hash-mismatch`, and adds a `classification` to distinguish integrity errors from missing artifacts and source-build candidates.

Run it in the isolated i686 staging environment against the exact package plan produced by that environment's target-specific resolver. The input must contain one resolved `name==version` pin per package. Do not pass a universal `uv export` output directly: it preserves PEP 508 markers and can include platform-specific direct references, so it is not an i686-only plan. The reconciler rejects those lines instead of counting them as i686 dependencies.

~~~bash
/path/to/cpython-3.14.9-i686/bin/python3.14 scripts/reconcile-v0232-wheelhouse.py \
  --lock uv.lock \
  --requirements /path/to/staging-output/hermes-v0232-plan-i686-pins.txt \
  --wheelhouse /path/to/existing/verified-wheelhouse \
  --python /path/to/cpython-3.14.9-i686/bin/python3.14 \
  --output /tmp/hermes-v0232-wheel-reconciliation.json
~~~

Keep the exact plan-generation command and resolver version with the private staging evidence. The tool is read-only with respect to the lock and wheelhouse: it does not download, build, rename, or install artifacts. JSON schema v4 reports each locked source distribution by filename, SHA-256, and optional byte size, plus a locked-sdist count; it deliberately omits artifact URLs and absolute input paths. It also lists target-compatible wheelhouse files that are not exact locked artifacts under `wheelhouse_anomalies`; these can make the command exit 1 even if a package row has a verified wheel, so an extra unlocked wheel cannot be hidden by a matching locked file. A malformed locked sdist entry without a filename and SHA-256 fails closed. The `classification` values are `verified-wheel`, `integrity-failure`, `unlocked-wheel`, `plan-lock-mismatch`, `source-build-candidate`, `unresolved-artifact-gap`, and `locked-wheel-missing-locally`. The wheelhouse anomaly summary also uses `unexpected-wheel` for a target-compatible artifact outside the plan. A `source-build-candidate` is emitted only when the lock has an sdist for the package and has no target-compatible locked wheel. It is a candidate, not evidence that source bytes were fetched or a wheel was built. A missing compatible wheel without locked sdist is `unresolved-artifact-gap`; a locked compatible wheel missing from the local wheelhouse is `locked-wheel-missing-locally`, even if an sdist is also recorded. Hash mismatches remain `integrity-failure` and are never relabeled as source-build candidates. The JSON `classification_summary` makes these counts easy to distinguish. The process exits 1 when any package lacks a verified local wheel or the target-compatible wheelhouse contains an unclaimed wheel. `wheelhouse_anomaly_summary` separates unlocked wheels, hash-mismatched files, plan/lock mismatches, and wheels belonging to an unplanned distribution. An expected source-build candidate is a nonzero incomplete-inventory result, not by itself an integrity error. Wheels built locally from a locked sdist still need staging build provenance and an explicit lock-integration policy; this tool does not mislabel a locally built wheel as a registry artifact.

The 101-package plan, 92 reportedly verified wheels, nine reported gaps, and isolated `cffi`/`psutil` sync remain operator-supplied findings. This public work did not inspect or copy those files. Fixture tests cover wheel matching, missing-lock-row, missing-target-wheel, digest-mismatch, locked source-distribution metadata, malformed source hashes, output-path protection, incompatible-host and universal-marker rejection; they are not evidence about Púlsar's wheelhouse.

The optional report is written to a mode-0600 temporary file in the destination directory, flushed, and atomically replaced. This prevents a destination changed to a symlink or hard link after validation from truncating the linked target, and avoids exposing a partial JSON report. Synthetic regression fixtures deliberately insert each link after the initial path checks; they verify that the sentinel target remains unchanged.

## Earlier source and host checks (before hosted run #28)

- CPython build script fetched v3.14.9 and verified the exact tag object, commit and tree. A second run reused the source checkpoint.
- Node source tarball was downloaded from nodejs.org, matched the official SHASUMS256 entry, and the --prepare-only extraction/resume path passed twice using those verified bytes.
- tests/test-v0232-runtime-builds.sh — pass: shell syntax, JOBS=2 rejection, bad Node archive hash rejection, ELF32/x64 fixtures, and checkpoint resume/fingerprint rejection.
- python3 tests/test-v0232-wheel-reconcile.py — **28 synthetic local-fixture cases passed**. Coverage includes i686 tag/hash matching, missing target wheels, source-distribution metadata/classification, unclaimed compatible wheels, plan/lock mismatches, output-path aliases, incompatible target identity, universal marker-bearing plans, and atomic report replacement under raced symlink/hard-link destinations.
- Baseline reproduction for PR #27: ran those 17 tests against PR #26 base `d685cf8cb3c729275d6b4c9ad62af442f58fc1e0`; all 15 prior checks passed and exactly the two new race tests failed because the synthetic sentinel was overwritten by the report. The updated PR #27 head passes all 17.
- Read-only parser check against the unchanged official v0.23.2 `uv.lock` at commit `ae2a81ccc00e9b7c06301523e5bb09608397149c` — 355 package groups, 3,282 locked wheels, and 322 locked source distributions parsed; lock SHA-256 `d0ae8bfd20db7a8ca0e75418df718315c58088b120366227cc62ee8fe25d4274`. No wheel or source archive was fetched.
- Both runtime scripts' --prepare-only paths passed with nonexistent compiler paths after source verification/extraction; repeated runs reused checkpoints. Their --preflight-only paths rejected the x86_64 ELF64 process before build.
- scripts/verify-v0232-pnpm-wasm.sh with the actual official npm tarballs — pass on Node v24.22.1, process.arch=x64; it ran pnpm 12.15.0 and completed an offline local-file install.
- scripts/test-v0232-pnpm-wasm-pm-stage.sh — pass against the patched v0.23.2 checkout and the already downloaded WASM tarball. PM downloaded it from loopback, verified the pinned SHA-256, installed the store entry and ran the shared ELF scan; it did not execute Node or pnpm.
- tests/test-v0232-patchset.sh — pass against a clean checkout of the exact Hermes commit. The ordered patch series applied and 103 focused PM core/install/doctor/store/downloader/pnpm tests passed; one macOS-only case was skipped on Linux.

These checks establish source, hash, PM staging, and host-side WASM behavior as of the earlier work session. At that point they did not establish i686 CPython/Node builds or i686 pnpm execution. Hosted run #28, recorded below, later added those userspace build and smoke-test results. Neither the earlier host checks nor run #28 establishes a B10 run or full Hermes PM closure. The staging-only 92 wheel artifacts reported by Púlsar were not downloaded, rebuilt, or inspected.

## Hosted Debian 11 i386 build — Actions run #28

Run [#28](https://github.com/agustinbracamonte/hermes-i686-support/actions/runs/44455559422) completed successfully on PR #11 head `f09eca83d0e72bfe1415eabc1c1256d22f7b8f91`. The workflow used a hosted Ubuntu 24.04 runner with a Debian 11 i386 userspace/chroot and no QEMU. The Clang 19.1.7 i386 package passed preflight; its SHA-256 `d52c7089346ebc4616d3e9e3bbee6eb0848455a9abb777746fdd32812ce981d3` matched signed APT metadata.

- CPython 3.14.9: ELF32, little-endian Intel 80386, 32-bit pointers; SHA-256 `8cef39b6947193697c241d839a8a5284592f3027530de94ca13968caeec1f14f`. Smoke checks included OpenSSL 1.1.1w, SQLite 3.34.1 and ctypes.
- Node 26.12.1: ELF32/EM_386, `process.arch=ia32`, npm 11.20.0; node SHA-256 `fe371ba1480fd0040cdea4e4a3ab2079edd45c9c33efd11d84c898661dcf086f`. The run passed six V8 span probes, worker_threads, shared WebAssembly memory and full ICU `es-AR`. Node targeted SSE2 and used `--openssl-no-asm`; target performance is not measured.
- `@pnpm/wasm@12.15.0`: tarball SHA-256 `172c9d9a2b8b82b00a67323ffa6d34c32f8706279661329ea460432b95c9da1f`; npm integrity `sha512-uxV61T7Sn34SAVUkzZf0xYNW0Ocw59OCHYRNdY2pOm4xE3Z+r2ptXOd2XTiWQBOZ8qgyMLs69F4ZHcUakvFR2Q==`. Its 44,951,421-byte WASM module passed an offline local-file install under Node ia32, with no native executable.
- The Actions artifacts endpoint returned an empty list. No runtime binary was retained or uploaded.

This proves hosted Debian 11 i386 userspace execution, not a physical B10 staging run. It does not verify the real Hermes PM lock/install/doctor, all dependencies, private staging, ARM64, or B10 memory/performance. No reported Púlsar wheel was fetched or rebuilt.

## Next staging checks

1. Validate the required compiler and CPython system dependencies in the approved isolated Debian 11 i386 staging image. No binary artifact from run #28 is available to transfer; run the documented serial recipes in an authorized build environment or use a separately approved, zero-cost private artifact route after recording provenance and independently checking each digest.
2. Run `verify-v0232-pnpm-wasm.sh --require-ia32` against the Node executable used by staging, then capture memory use and offline install results.
3. Reconcile the Node pin in the private staging lock and verify full PM install/sync/doctor and dependency closure.
4. Run the offline reconciler in Púlsar staging against its actual resolved plan, lock, and existing wheelhouse. Do not retrieve the reported 92 wheels again; resolve the nine gaps and document local source builds separately.
5. Record B10 memory/performance, ARM64, and recovery/rollback evidence independently. No staging host was accessed by this public task.
