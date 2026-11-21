# Hermes v0.23.2 i686 runtime builds

Updated 2026-11-17. This public workstream contains reproducible source-build procedures only. It has no compiled CPython/Node binaries, no wheelhouse, no Púlsar source, and no credentials.

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

`scripts/reconcile-v0232-wheelhouse.py` compares an exact target-resolved requirements export, the matching `uv.lock`, and an existing wheelhouse. It uses the supplied CPython interpreter's `pip debug --verbose` tags by default and rejects an interpreter whose pointer width or `sysconfig` platform is not Linux i686. It reports each package as `verified`, `no-compatible-wheel`, `compatible-wheel-not-present`, `wheel-not-in-lock`, `package-not-in-lock`, or `hash-mismatch`.

Run it in the isolated i686 staging environment against the exact package plan produced by that environment's target-specific resolver. The input must contain one resolved `name==version` pin per package. Do not pass a universal `uv export` output directly: it preserves PEP 508 markers and can include platform-specific direct references, so it is not an i686-only plan. The reconciler rejects those lines instead of counting them as i686 dependencies.

~~~bash
/path/to/cpython-3.14.9-i686/bin/python3.14 scripts/reconcile-v0232-wheelhouse.py \
  --lock uv.lock \
  --requirements /path/to/staging-output/hermes-v0232-plan-i686-pins.txt \
  --wheelhouse /path/to/existing/verified-wheelhouse \
  --python /path/to/cpython-3.14.9-i686/bin/python3.14 \
  --output /tmp/hermes-v0232-wheel-reconciliation.json
~~~

Keep the exact plan-generation command and resolver version with the private staging evidence. The tool is read-only with respect to the lock and wheelhouse: it does not download, build, rename, or install artifacts. JSON schema v2 also reports each locked source distribution by filename, SHA-256, and optional byte size, plus a locked-sdist count; it deliberately omits artifact URLs and absolute input paths. A malformed locked sdist entry without a filename and SHA-256 fails closed. This metadata identifies candidate inputs for a reproducible source build; it does not claim that the source bytes were fetched, that a wheel was built, or that a locally built wheel is covered by the lock. A nonzero exit still means a wheel is missing, incompatible, unpinned, or has the wrong digest. A lock-matched prebuilt wheel can be counted as verified. Wheels built locally from a locked sdist still need staging build provenance and an explicit lock-integration policy; this tool does not mislabel a locally built wheel as a registry artifact.

The 101-package plan, 92 reportedly verified wheels, nine reported gaps, and isolated `cffi`/`psutil` sync remain operator-supplied findings. This public work did not inspect or copy those files. Fixture tests cover wheel matching, missing-lock-row, missing-target-wheel, digest-mismatch, locked source-distribution metadata, malformed source hashes, output-path protection, incompatible-host and universal-marker rejection; they are not evidence about Púlsar's wheelhouse.

## Checks run in this work session

- CPython build script fetched v3.14.9 and verified the exact tag object, commit and tree. A second run reused the source checkpoint.
- Node source tarball was downloaded from nodejs.org, matched the official SHASUMS256 entry, and the --prepare-only extraction/resume path passed twice using those verified bytes.
- tests/test-v0232-runtime-builds.sh — pass: shell syntax, JOBS=2 rejection, bad Node archive hash rejection, ELF32/x64 fixtures, and checkpoint resume/fingerprint rejection.
- python3 tests/test-v0232-wheel-reconcile.py — pass: 15 synthetic local-fixture cases cover i686 tag/hash matching, missing target wheels, mismatched digests, source-distribution metadata, malformed sdist hashes, output-path aliases, rejection of non-Linux/non-i686 tag sources, and universal marker-bearing plans.
- Read-only parser check against the unchanged official v0.23.2 `uv.lock` at commit `ae2a81ccc00e9b7c06301523e5bb09608397149c` — 355 package groups, 3,282 locked wheels, and 322 locked source distributions parsed; lock SHA-256 `d0ae8bfd20db7a8ca0e75418df718315c58088b120366227cc62ee8fe25d4274`. No wheel or source archive was fetched.
- Both runtime scripts' --prepare-only paths passed with nonexistent compiler paths after source verification/extraction; repeated runs reused checkpoints. Their --preflight-only paths rejected the x86_64 ELF64 process before build.
- scripts/verify-v0232-pnpm-wasm.sh with the actual official npm tarballs — pass on Node v24.22.1, process.arch=x64; it ran pnpm 12.15.0 and completed an offline local-file install.
- scripts/test-v0232-pnpm-wasm-pm-stage.sh — pass against the patched v0.23.2 checkout and the already downloaded WASM tarball. PM downloaded it from loopback, verified the pinned SHA-256, installed the store entry and ran the shared ELF scan; it did not execute Node or pnpm.
- tests/test-v0232-patchset.sh — pass against a clean checkout of the exact Hermes commit. The ordered patch series applied and 103 focused PM core/install/doctor/store/downloader/pnpm tests passed; one macOS-only case was skipped on Linux.

These checks establish source, hash, PM staging, and host-side WASM behavior. They do not establish a native i686 CPython build, Node build, pnpm WASM execution, or full Hermes PM closure. This environment is x86_64 and its GCC targets x86_64, so neither source build was attempted. The staging-only 92 wheel artifacts reported by Púlsar were not downloaded, rebuilt, or inspected.

## Next staging checks

1. Run both preflights in the isolated ELF32/i686 userspace; ensure the compiler is GCC >=13.2 and the CPython source-build prerequisites are present.
2. Build CPython, then Node, serially; retain each result manifest and the source/system package records.
3. Run verify-v0232-pnpm-wasm.sh --require-ia32 against the built Node. Capture memory use and check the offline install result.
4. Have Púlsar validate those outputs in its staging environment and reconcile the Node pin into its real lock. No staging host was accessed by this public task.
5. Run the offline reconciler in Púlsar staging against its actual resolved plan, lock, and existing wheelhouse. Do not retrieve the reported 92 wheels again; resolve the nine gaps and document local source builds separately.
