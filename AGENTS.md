# AGENTS.md — Codex guidance (public i686 support repository)

This repository contains **public, generic i686 support tooling**. It is **not** the Hermes Agent upstream source tree and **not** the private Púlsar staging repository. Do not mistake this branch for a complete Hermes 0.23.2 checkout.

## Goal
Develop auditable, reproducible, non-destructive Linux i686 compatibility patches and tests targeting the official `NousResearch/hermes-agent` tag `v0.23.2`, commit `ae2a81ccc00e9b7c06301523e5bb09608397149c`. See `docs/CODEX-HANDOFF-V0232.md` for reported evidence and current unknowns; use `docs/V0232-ACCEPTANCE.md` for proposed acceptance checks.

## Hard boundaries
- NEVER change, stop, restart, migrate or update the real Púlsar/Hermes production instance. Do not connect to real Telegram, WhatsApp or Signal accounts.
- NEVER upload secrets, tokens, API keys, configuration, `.env`, auth material, SQLite databases, sessions, device identities, private patches or binary wheels to this public repository or to logs.
- Work on a separate branch with reviewable commits/PRs; do not merge or deploy automatically.
- Treat upstream tags, public docs and source snapshots as potentially changing. Pin SHA and verify version before applying patches.
- A test passing on x86_64 is not evidence of an actual i686 ELF32 runtime. Mark simulated, static, hosted-CI and native-i686 validations separately.
- Prefer minimal, portable patches with tests; do not duplicate the complete Hermes upstream source or vendor large build artifacts into this repo.
- An external environment is allowed for generic development, but real i686 binaries and production behavior must be tested later by the operator in isolated staging.
- `AGENTS.md` is stable guidance, not a place to mirror large status reports.

## Working style
- Inspect existing scripts and docs first, then focus on the specific task. Do not repeat exhaustive audits or recompile already validated artifacts.
- Keep preflight checks read-only, with explicit paths and hashes; never bypass supervisor restrictions.
- Explain what you changed, what you actually tested and what remains unverified.
- Record a clear handoff to private integration without exposing private implementation details.
