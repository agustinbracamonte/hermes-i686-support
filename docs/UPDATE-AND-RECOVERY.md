# Update and recovery

## Update procedure

1. Record the live Hermes version, commit, wheel hashes and service state.
2. Inspect the target release metadata and native dependencies in a separate checkout.
3. Build/verify required i686 wheels in a private staging workspace.
4. Create a fresh staged venv; use only the staged config copy with secrets removed or replaced by test credentials.
5. Validate imports, ABI, linkage and the intended user-facing path.
6. Prepare a rollback archive before an approved cutover.

## Recovery package

A private backup should contain:

- source SHA and local patch;
- sanitized build manifest plus private configuration/state archive stored separately;
- wheelhouse artifacts and SHA-256 manifest;
- Rust/OpenSSL build inputs or exact retrieval hashes;
- a rollback sequence tested against a staging copy.

## Rollback

Do not restore files over a running gateway. In an approved maintenance window: stop the service, swap back the known-good source/venv and configuration snapshot, validate the old ABI/runtime, then start the prior service. Confirm the real delivery path before declaring recovery complete.

## Release preparation

Use `scripts/collect-release-assets.sh WHEELHOUSE_DIR`. Publish only the wheel(s) and `SHA256SUMS` as release assets, never in Git history. Rebuild from source for each new ABI or dependency version.
