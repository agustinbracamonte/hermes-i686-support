# Troubleshooting

## `platform.machine()` says x86_64

This can reflect the kernel, not the Python ABI. Use `struct.calcsize('P') * 8`; the tested target requires `32`.

## `cryptography` attempts a source build during Hermes install

Build the exact pinned version first, verify it, place it in the staged wheelhouse, and install with a protected-wheel policy. Do not upgrade the live venv to experiment.

## `maturin` is importable but not found

The build backend executable directory must be on `PATH`. The build script invokes the temporary venv with `PATH="$WORKDIR/venv/bin:$PATH"` for this reason.

## `_rust.abi3.so` is not i386

Stop. Verify the target Python, Rust host, `CARGO_BUILD_TARGET`, compiler flags and linker. Delete only the target output in the private workspace, not the live venv.

## Static-only dependency inspection

Use `readelf -d` and `objdump -p` to inspect `NEEDED`, RPATH and RUNPATH entries in untrusted ELF files. Never invoke `ldd` on untrusted ELF: implementations may execute the file's interpreter. Runtime loading belongs only in an isolated staging root after source/artifact provenance and checksums have been validated, as described in `docs/INSTALL.md`.

## Static OpenSSL was not used

Check `OPENSSL_DIR`, `OPENSSL_STATIC=1`, and rebuild in a clean target directory.

## Build is slow

Use `JOBS=1`, preserve the workspace, and inspect active compiler processes/recent objects before treating it as stuck. Never restart a healthy build solely because it is slow.

## Patch will not apply to a new Hermes release

Do not force it. Run `git apply --check` in a disposable worktree, locate the corresponding current code and port the intent with focused tests.
