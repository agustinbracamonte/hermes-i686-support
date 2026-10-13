# Test matrix and current results

Tests are deliberately separated so the default suite does not execute recovered/native binaries or depend on the user's private wheelhouse.

## Self-contained suite

Command: `tests/test-scripts.sh` (run in this correction)

- Shell syntax for project/test/Signal scripts: **PASS**.
- Host-Python preflight: **PASS**.
- Static wheel verifier negatives (malformed ELF rejected without execution; no `ldd` use): **PASS**.
- Runtime checker refuses missing staging root/wheel provenance: **PASS**.
- Publication scanner fixture: provider/API-key assignment detections in worktree, reachable and dangling commit messages, redacted diagnostics, private-key and historical PII cases: **PASS**.
- Signal provenance helper synthetic fixtures: exact tag+authorized patch accepted; additional source changes, wrong digest and moved HEAD rejected: **PASS**.
- Signal CLI syntax/layout/licensing-state checks: **PASS**, structure only.

These tests do not establish successful JNI loading or Signal operation.

## Staged i686/native integration suite

Command: `tests/test-i686-integration.sh`; it requires explicit `I686_STAGING_ROOT`, `PYTHON_I686`, and `REAL_WHEEL` paths with the interpreter and historical wheel located under the isolated staging root. It statically verifies the historical wheel fixture, tests malformed/ELF64/hash/runtime/release negatives, and imports native code only through `check-runtime.sh` after wheel SHA validation and staging-path checks.

**Not run in this correction:** no isolated, user-designated i686 staging root was supplied. We did not use the recovered wheelhouse or Hermes venv as a substitute. The previous historical results remain historical, not a new runtime validation.

## Source archive and reproducibility

The official PyPI JSON metadata identifies the sdist URL and SHA-256 recorded in `docs/INSTALL.md`. Downloading that exact URL during this correction succeeded and the bytes matched SHA-256 `eeac2acb5a20ed25e0ad6d1df9891a520b78b404266b6d11778f25d5d691a6c9`.

No clean rebuild or independent byte-for-byte rebuild comparison was performed. The wheel hash `71893373af19e01f446f3b3d98cf674c5cbf8d1842d01a1fd5ace41c097b9500` refers only to the recovered historical fixture; it is not a prediction for a new build.

## Signal status

Signal remains **EXPERIMENTAL / NOT RELEASE-READY**. The Signal integration test is syntax/layout/provenance-script coverage only; it does not compile JNI or verify a native load, protocol operation, or live service. No Signal binary was produced or published.
