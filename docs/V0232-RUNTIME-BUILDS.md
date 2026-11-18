# Hermes v0.23.2 i686 runtime builds

Updated 2026-11-18. This public workstream contains reproducible source-build procedures only. It has no compiled CPython/Node binaries, no wheelhouse, no Púlsar source, and no credentials.

## Locked source evidence

| Runtime | Source pin | Hash evidence |
|---|---|---|
| CPython 3.14.9 | Git tag object 17acf00d155cb8536eca1c3af3a8404db648e37f; commit ead82c07db1f111d613926ed1b6667411d768125; tree a0de950923dd481d2fd0f5bdc42ed9821763cbc4 | The build recipe fetches the tag from python/cpython and verifies the tag object, commit, tree, and clean checkout. python.org's source archive endpoint returned HTTP 403 here, so this work does not claim an official sdist SHA-256. |
| Node 26.12.1 | Official source tarball https://nodejs.org/dist/v26.12.1/node-v26.12.1.tar.xz; tag commit bc2e01dcf6acd5cf7d169b5f26cf89abaaeb41f1 | Official SHASUMS256.txt and locally downloaded bytes agree on SHA-256 053e3b296859b6d8d93f99ef97fa9cec1c4ee171c72968100c649978c1dbd38c. Tarball size: 62,570,464 bytes. |

Node's own v26.12.1 BUILDING.md labels Linux x86 as Experimental and lists GCC >=13.2 or Clang >=19.1 as current Linux toolchains. No official Linux i686 runtime binary exists. The checked-in recipe accepts either minimum when C/C++ compiler family, version, and Linux i686 target agree; it does not alter x64 or ARM64 pins. Bullseye's default GCC 10.2 is too old.

Debian's signed bullseye-security i386 package index lists Clang 19.1.7 as `1:19.1.7-3~deb11u1`, with package SHA-256 `d52c7089346ebc4616d3e9e3bbee6eb0848455a9abb777746fdd32812ce981d3`. The `InRelease` signature validated against the local Debian archive keyring, and its `Packages.xz` digest matched the downloaded index. The metadata declares transitive `libc6 >=2.29`; the same Bullseye security index provides glibc `2.31-13+deb11u14`. Hosted run #4 downloaded the actual `.deb`; its digest matched the signed package index and Clang's i686 target preflight passed. The local x64 proxy still blocks this archived package, so the runner result is the only actual package-install evidence.

## Serial, resumable build recipes

Scripts:

- scripts/build-cpython-v0232-i686.sh
- scripts/build-node-v0232-i686.sh
- scripts/v0232-i686-build-common.sh
- scripts/v0232-node-toolchain.sh

The build root is HERMES_I686_BUILD_ROOT or .work/v0232-i686. It must be a dedicated path without spaces. Both runtimes use one root-wide flock, reject JOBS other than 1, run GNU make with -j1, and write per-step SHA-256 fingerprints for source, configure, compile, install, and smoke-test checkpoints. A completed checkpoint is skipped only when its fingerprint and expected output still match. Partial make output can resume by rerunning the same command. A changed source, toolchain, script, or configure flag requires a new build root; the scripts do not delete a prior build tree.

The normal build refuses to run unless the shell itself is ELF32/EM_386 and the compiler targets i686. It does not select the target from uname -m. --prepare-only fetches/verifies sources without compiling and can run on a development x64 host. --preflight-only checks the native process ABI and toolchain before a build.

On the isolated i686 staging machine, first install the compiler and CPython development dependencies using that machine's approved package source. Use GCC >=13.2 or Clang >=19.1 for Node; Clang can be selected with `CC=clang-19 CXX=clang++-19`. CPython needs the usual OpenSSL, zlib, SQLite, libffi, bzip2, lzma, readline and ncurses development headers. The scripts do not install system packages or silently change a host. The exact system package snapshot remains a staging input and must be recorded alongside the result manifest.

~~~bash
export HERMES_I686_BUILD_ROOT=/srv/hermes-i686-build/v0.23.2
scripts/build-cpython-v0232-i686.sh --preflight-only
scripts/build-cpython-v0232-i686.sh
scripts/build-node-v0232-i686.sh --preflight-only
scripts/build-node-v0232-i686.sh
~~~

The Node recipe consumes the CPython 3.14.9 i686 interpreter produced in that same root. It configures --dest-cpu=ia32 --with-intl=full-icu --openssl-no-asm, keeps the bundled full ICU source, builds serially, installs under the root, and checks the resulting Node ELF32 header, Node/npm execution, process.arch, Spanish locale data, shared WebAssembly memory, and worker_threads. Node's zlib build has two ia32 targets that compile SSE2 intrinsics: `zlib_data_chunk_simd` and `zlib`. Run #7 showed the first patch covered only the latter; run #8 compiled both successfully. Run #8 then failed linking OpenSSL's helper executable because Clang emitted unresolved `__atomic_*` references. Node's own `node.gyp` already adds `-latomic` to its Linux/Clang target; the build patch now adds the same library only to OpenSSL CLI on Linux ia32/Clang. The combined patch also keeps the `-msse2` flags limited to the two ia32 zlib targets. Its SHA-256 is `c1b97940c0d05a25fe7a31647723e7444130be51ea5da297142e926ed2fa5a0a`. Patch application is resumable and the digest is included in the build fingerprint and result manifest. Preflight requires `sse2` in `/proc/cpuinfo`, intentionally refusing pre-SSE2 32-bit CPUs. Disabling OpenSSL assembly uses generic implementations and may reduce crypto throughput; measure it on Púlsar's target before accepting it. Result manifests include source hashes, patch hash, compiler/linker versions, architecture, required CPU feature, OpenSSL assembly mode, and installed executable hashes.

## Isolated build option

GitHub documents standard hosted Linux runners as free for public repositories, with a standard runner exposing 4 CPUs and 16 GB RAM ([runner specs](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), [Actions billing](https://docs.github.com/en/billing/concepts/product-billing/github-actions)). This repository is public. PR #8 uses an ephemeral Debian 11 i386 userland/chroot on a hosted x86_64 Linux runner. Runs #5–#8 verified Clang package bytes against signed APT metadata and built CPython 3.14.9 as ELF32; hashes are in the manifest evidence below. Run #8 compiled both ia32 zlib targets, then failed at OpenSSL CLI link due to unresolved atomic helper symbols. The combined patch adds `-latomic` to that Linux/ia32/Clang link target. Hosted run #9 ([44255938174](https://github.com/agustinbracamonte/hermes-i686-support/actions/runs/44255938174), source head `db18284d90fe4b70bb3996239e9037010e4a09d6`) is in progress; at the latest check it was fetching the exact public PR source. This route does not establish B10 memory headroom, Púlsar staging compatibility, or ARM64 execution.

Any CI workflow must use no repository secrets, let APT verify its signed index and the `.deb` digest, avoid uploading binaries, keep only non-sensitive test summaries/hashes, and discard the runner after the job. Debian 11's LTS ended 2026-08-31. PR #8 implements this hosted validation; recorded attempts and limits are below.

## Hosted build workflow in PR #8

PR #8 adds .github/workflows/v0232-i686-runtime.yml and scripts/ci-v0232-i686-runtime-build.sh to test the hosted Debian 11 i386 route. The workflow is limited to owner-authored PRs targeting the Clang-toolchain branch. It requests empty token permissions, uses no checkout action or configured secrets, downloads the public PR archive at its exact head SHA, and uploads no artifacts. The runner reports GitHub's implicit metadata:read permission; the workflow never reads or passes that token. Its helper refuses local and self-hosted machines, including the B10.

The hosted job bootstraps a Debian 11 i386 rootfs from the fixed Debian snapshot 20260912T092708Z and obtains security updates from Debian's archived bullseye-security repository. APT verifies signed repository metadata, downloads Clang 1:19.1.7-3~deb11u1, and checks the package SHA-256 d52c7089346ebc4616d3e9e3bbee6eb0848455a9abb777746fdd32812ce981d3 before installation. It then runs the existing i686 process/compiler preflights and serial, checkpointed CPython and Node builds, followed by the pnpm WASM CLI and offline-file-install check under Node with process.arch=ia32. Only source hashes, package versions, result manifests and test summaries are retained in the Actions log/summary; binaries stay on the disposable runner.

The first hosted run verified the signed Bullseye snapshot and created an i386 rootfs, then failed before compiling: it used the wrong security component and requested nonexistent gdbm-dev. The second run loaded the signed security package index after correcting the component and package names, but the snapshot server returned 404 for all packages from the security pool before installation. The third run downloaded 167 MB from the official archive but stopped at the Clang cache/hash gate. Run #4 (`44240968415`, source head `56387f52f56309b0652d44b3bc5c55e3fe7cf5bb`) verified the downloaded Clang `.deb` against the signed APT index and passed its i686 preflight; CPython passed ELF32 smoke checks, while Node failed in OpenSSL assembly. Runs #5 (`44244683708`) and #6 (`44247738533`) confirmed the signed Clang digest and built CPython 3.14.9; executable SHA-256 values were `feb9bbe20801ec7b481d2e4cd04d1787eca1fe489bf5cf51826a1da65c3c619a` and `23b6cb39fc312ad1bb3fdfb0c08a9b33cc162740c7696ca314b174ec44cbcddb`. Node failed in zlib's ia32 SSE2 code on both runs. Run #6 proved setting configure CFLAGS did not alter the generated target. A checkpointed patch now adds `-msse2` only to the `target_arch==ia32` zlib build; run #7 will test it. No Node manifest, binary, npm or pnpm result exists yet. A hosted pass proves only the disposable i386 userland on that runner; it does not establish B10 memory headroom, Púlsar staging behavior, or ARM64 execution. Debian 11's LTS ended 2026-08-31.

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

Keep the exact plan-generation command and resolver version with the private staging evidence. The tool is read-only with respect to the lock and wheelhouse: it does not download, build, rename, or install artifacts. Its JSON report contains package names, wheel filenames and hashes, lock/plan fingerprints, counts, and target tag fingerprint; it omits absolute input paths. A nonzero exit means a wheel is missing, incompatible, unpinned, or has the wrong digest. A lock-matched prebuilt wheel can be counted as verified. Wheels built locally from a locked sdist still need staging build provenance and an explicit lock-integration policy; this tool does not mislabel a locally built wheel as a registry artifact.

The 101-package plan, 92 reportedly verified wheels, nine reported gaps, and isolated `cffi`/`psutil` sync remain operator-supplied findings. This public work did not inspect or copy those files. Fixture tests cover matching, missing-lock-row, missing-target-wheel, digest-mismatch, incompatible-host and universal-marker rejection; they are not evidence about Púlsar's wheelhouse.

## Checks run in this work session

- CPython build script fetched v3.14.9 and verified the exact tag object, commit and tree. A second run reused the source checkpoint.
- Node source tarball was downloaded from nodejs.org, matched the official SHASUMS256 entry, and the --prepare-only extraction/resume path passed twice using those verified bytes.
- The combined i686 build patch passed dry-run, apply, and reverse-detection against the exact public Node v26.12.1 `deps/zlib/zlib.gyp` and `deps/openssl/openssl.gyp` files plus local fixtures. It scopes `-msse2` to ia32 zlib targets and `-latomic` to the Linux ia32 Clang OpenSSL CLI target. This verifies patch application only; run #9 must validate the link.
- tests/test-v0232-runtime-builds.sh — pass: shell syntax, serial guards, bad Node archive hash rejection, ELF32/x64 fixtures, checkpoint resume/fingerprint rejection, compiler-version/target fixtures, Linux-only CPython compiler guard including `i686-w64-mingw32` rejection, scoped Node zlib/OpenSSL patch application and reverse detection, Node `--openssl-no-asm` and CPU SSE2 requirement checks (including an absent-SSE2 fixture), and static hosted-helper failure-summary guards. These checks do not prove a Node build.
- python3 tests/test-v0232-wheel-reconcile.py — pass: three local-fixture cases cover i686 tag/hash matching, a missing target wheel, a changed digest, and refusal to infer target tags from this x86_64 host.
- Both runtime scripts' --prepare-only paths passed with nonexistent compiler paths after source verification/extraction; repeated runs reused checkpoints. Their --preflight-only paths rejected the x86_64 ELF64 process before build.
- scripts/verify-v0232-pnpm-wasm.sh with the actual official npm tarballs — pass on Node v24.22.1, process.arch=x64; it ran pnpm 12.15.0 and completed an offline local-file install.
- scripts/test-v0232-pnpm-wasm-pm-stage.sh — pass against the patched v0.23.2 checkout and the already downloaded WASM tarball. PM downloaded it from loopback, verified the pinned SHA-256, installed the store entry and ran the shared ELF scan; it did not execute Node or pnpm.
- tests/test-v0232-patchset.sh — pass against a clean checkout of the exact Hermes commit. The ordered patch series applied and 103 focused PM core/install/doctor/store/downloader/pnpm tests passed; one macOS-only case was skipped on Linux.

These checks establish source, hash, PM staging, and host-side WASM behavior. Hosted runs #4–#8 built and smoke-tested CPython ELF32 in disposable Debian i386 userland; run #8's binary SHA-256 is `983771076e787e2e5fb20cd3ffc0d8352f1e6de973cdf2ae337e5c3298056ee6`. They do not establish an install or runtime check on Púlsar's B10. Run #8 compiled the patched zlib targets but failed to link OpenSSL CLI on unresolved atomic symbols. Node and pnpm WASM execution under ia32 remain unverified while hosted run #9 is in progress; full Hermes PM closure also requires staging. The local development environment is x86_64 and its GCC targets x86_64, so no local target build was attempted. The staging-only 92 wheel artifacts reported by Púlsar were not downloaded, rebuilt, or inspected.

## Next staging checks

1. Review hosted run #9 after the ia32 OpenSSL CLI atomic-link patch; require Node, npm and pnpm WASM ELF32 results before proceeding. Do not treat the hosted runner as B10 staging evidence.
2. Build CPython, then Node, serially; retain each result manifest and the source/system package records.
3. Run verify-v0232-pnpm-wasm.sh --require-ia32 against the built Node. Capture memory use and check the offline install result.
4. Have Púlsar validate those outputs in its staging environment and reconcile the Node pin into its real lock. No staging host was accessed by this public task.
5. Run the offline reconciler in Púlsar staging against its actual resolved plan, lock, and existing wheelhouse. Do not retrieve the reported 92 wheels again; resolve the nine gaps and document local source builds separately.
