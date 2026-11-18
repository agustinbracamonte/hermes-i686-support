# FFmpeg 9.0.1 i686 validation

Hermes v0.23.2 currently pins the BtbN GPL build named `ffmpeg-n9.0.1-11-ge47273f4d9-linux64-gpl-9.0.tar.xz`; its published checksum is for x64 only. The suffix identifies FFmpeg commit `e47273f4d9227152dcbf543cebaf9e2430ddbcc4`, 11 commits beyond the signed upstream `n9.0.1` tag at `bf1b838f2ab88b4f8fd83443325c782ea0e0f7fa`. The suffix commit is not signed. It is the recommended compatibility-build source pin because it matches the existing x64 artifact's source lineage; a policy requiring signed source tags should use the tag and record the 11-commit difference.

There is no verified i686 FFmpeg binary, PM hash, or lock row yet. Do not reuse the x64 digest. Build from the selected full upstream commit in an isolated Debian 11 i386 environment, serially, and retain the source commit/tree, configure arguments, compiler and dependency package versions, output hashes, and linker closure. The proposed feature profile enables GPL, libx264, libopus, libmp3lame, libxcb/X11 capture, native AAC, and `lavfi`; it must not enable `--enable-nonfree`. The resulting build has GPL redistribution obligations that require review before packaging.

## Artifact verification

The helper `scripts/verify-v0232-ffmpeg-i686.sh` has two explicit modes. Static mode never runs the binaries:

```bash
scripts/verify-v0232-ffmpeg-i686.sh --static-only \
  /path/to/ffmpeg /path/to/ffprobe /tmp/ffmpeg-static-report
```

It checks both files are executable little-endian ELF32/EM_386 images and records their SHA-256, `DT_NEEDED` libraries, and maximum GLIBC symbol versions. It rejects a requirement newer than Bullseye's GLIBC 2.31. A claimed source commit is recorded only when provided in `FFMPEG_SOURCE_COMMIT`; the verifier cannot prove source provenance from an executable.

Runtime mode must run inside a native Debian 11 i386 userspace. The helper checks its own process ABI, rejects QEMU-marked environments, and inspects live FFmpeg and FFprobe PIDs to confirm `/proc/PID/exe` resolves to each supplied ELF32 binary. It checks `getconf LONG_BIT`, `dpkg --print-architecture`, library resolution and ELF32 library dependencies. It captures FFmpeg's version banner from either output stream and requires a 9.0.1 build string matching the selected signed-tag or BtbN-lineage source pin. It then checks required build options, encodes and decodes synthetic H.264, AAC, Opus and MP3 samples, captures a frame from an isolated Xvfb display through `x11grab`, and records peak RSS for the H.264 encode.

Runtime mode invokes the supplied FFmpeg and FFprobe executables and uses `ldd`; use it only for binaries built from the reviewed source in an isolated staging environment. Static mode never invokes the supplied executables.

```bash
FFMPEG_SOURCE_COMMIT=e47273f4d9227152dcbf543cebaf9e2430ddbcc4 \
  scripts/verify-v0232-ffmpeg-i686.sh --runtime \
  /path/to/ffmpeg /path/to/ffprobe /tmp/ffmpeg-i686-report
```

The runtime report is safe to retain as staging evidence, but static fixture results are not execution evidence. A PM lock row can be added only after the selected source is built, the target artifact and its full PM archive are hashed, the runtime/dependency checks pass, and the actual staging PM install verifies that digest. Do not upload binaries or private staging data to this public repository.

## Current test evidence

`tests/test-v0232-ffmpeg-verifier.sh` creates minimal synthetic ELF headers and checks the static report, rejection of ELF64, and refusal to claim native runtime from this x86_64 shell. These are static guard regressions only. No FFmpeg source was built or executed in this test, and no i686 runtime or PM closure is established.
