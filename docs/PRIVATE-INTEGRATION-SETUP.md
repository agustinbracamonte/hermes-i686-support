# Set up a SEPARATE PRIVATE repository for Púlsar integration

This document is **public and generic**. It does not contain a private checkout, tokens, production configuration or account identities.

The public `hermes-i686-support` repository is appropriate for portable architecture fixes only. It must not become the repository for the user's customized Telegram / WhatsApp / Signal gateway.

## One-time manual repository creation
Create an **empty PRIVATE** GitHub repository in an account whose Codex Cloud installation can access it. Suggested name: `pulsar-hermes-v0232`. Do **not** choose `Nova`; that project is unrelated to this workflow. Keep the public i686 support repo independent.

The current ChatGPT GitHub connector can create branches, files and PRs but does **not expose an API action to create a new repository**. Repository creation therefore requires a user action (GitHub UI, or separately authenticated GitHub CLI).

## Bootstrap source — isolated, not production
The operator's agent should prepare a **sanitized and reviewable** private integration tree with:
1. The official `NousResearch/hermes-agent` `v0.23.2` source pinned to commit `ae2a81ccc00e9b7c06301523e5bb09608397149c`.
2. New i686 PM/installer patches and tests already developed **only in staging**, separated into individual commits or patchsets.
3. Private functional adaptations (if authorized), with their secrets and runtime state entirely absent.
4. Existing sanitized compatibility matrix/checkpoint summarizing **what is tested versus not tested**. Source of truth must remain commit history and CI/test logs, not chat memory.
5. Root `AGENTS.md` and a `docs/STATUS.md` describing scope, no-production constraint, version pins, and next steps.

Before any push, explicitly review **all tracked and untracked paths and diff contents** for accidental secrets. Be particularly careful with `.env`, `auth.json`, `config.yaml`, `state.db`, `.hermes/`, backups, credentials, OAuth, chats, device identities, Signal store, WhatsApp sessions, runtime logs, compiled wheels, binaries and private keys. A `.gitignore` cannot protect secrets that were already committed. Prefer importing only allowlisted source and tests into a fresh repository rather than pushing the original laboratory directory wholesale.

Do **not** force-push the production code checkout and do not change its Git remotes. Do not assume a repository is private until GitHub confirms it.

## Codex Cloud
- Connect GitHub to Codex Cloud (this may require separate GitHub App authorization from ChatGPT's GitHub connector).
- First run Codex against `hermes-i686-support`, branch `codex/hermes-v0232-i686`, for generic ABI/PM/bootstrap work.
- After the private repository is created and its sanitized source is available, point subsequent Codex tasks to its private branch for gateway/session/adapter migrations.
- Never supply live tokens or Telegram / Signal / WhatsApp linked state to Codex. Test with synthetic fixtures.
- Leave production switch, state restore and final live-channel validation to an explicitly authorized, separately reviewed local procedure.

## Recommended incremental delivery
- PR 1: ABI detection, bootstrap paths and regression tests.
- PR 2: PM target, lock pin completeness and verification logic.
- PR 3: build scripts / source proofs / offline wheelhouse sync.
- PR 4+: private gateway session/profile admission/recovery and channel adapters, each with synthetic tests.
- Gate 4 production cutover is *not* part of the Codex Cloud task.
