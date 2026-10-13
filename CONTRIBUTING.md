# Contributing

## Before opening a change

- Keep all examples generic; use placeholders such as `PATH_TO_STAGING` and `EXAMPLE_VERSION`.
- Do not add binaries, wheelhouses, virtual environments, source caches or generated `dist/` content to Git.
- Never include credentials, personal paths, account data, messaging identities, session databases, logs or production configuration.
- Preserve the distinction between **PROBADO** and **NO PROBADO** in the compatibility matrix.

## Changes to native build support

1. Pin exact source versions and verify SHA-256 values.
2. Keep build output in an ignored workspace.
3. Validate Python pointer width, `file`, `readelf`, `objdump` and wheel checksum statically. Perform imports only under `docs/INSTALL.md`'s provenance-checked staging protocol.
4. Add a focused, non-destructive test or validation command.
5. Document the upstream revision, licenses and any local patch.

## Signal integration

Changes under `integrations/signal-cli/` must preserve its optional status and GPL/AGPL source-obligation documentation. Never test with or commit real account material.
