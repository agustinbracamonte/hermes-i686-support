# Hermes v0.23.2 i686: acceptance matrix

These are **review gates**, not claims of completed testing. Every result must be tagged: `NOT RUN`, `STATIC`, `HOSTED CI`, `NATIVE I686`, or `BLOCKED`. Record command, environment, exit status, provenance, and artifact hash when relevant.

## Gate 0 — inputs and isolation
- [ ] Exact official tag `v0.23.2` resolves to `ae2a81ccc00e9b7c06301523e5bb09608397149c`.
- [ ] A separate, sanitized workspace exists; no production HOME, systemd units, credentials, real channel services, state DB, signal-cli/WhatsApp identities, or live endpoints are mounted or accessed.
- [ ] No code silently invokes production `hermes update`, deploy, gateway restart, migration or PM global update.

## Gate 1 — architecture and PM selection
- [ ] Process ABI, not `uname` alone, determines i686 for a 32-bit userspace under x86_64 kernel.
- [ ] PM, installer `scripts/install.sh` and `setup-hermes.sh` agree on `linux-i686`, or explicitly fail closed with a clear error when unsupported.
- [ ] Validations reject ELF64/x86_64 executables and shared objects on i686, accept ELF32/EM_386, and keep legitimate Linux x64 / ARM64 paths working.
- [ ] Mandatory lock rows / runtime pins exist with verified hashes for Linux i686; no guessed hashes and no unwanted mutation to other architecture rows.

## Gate 2 — runtimes and Python dependencies
- [ ] CPython 3.14.9 i686 tested for SSL, sqlite, ctypes, native imports and pointer width.
- [ ] Node 26.12.1 i686 and npm version pinned to lock tested for ELF32 and simple JavaScript/npm execution.
- [ ] uv 0.13.5 Linux i686 tested using official asset and checksum.
- [ ] Selected `all` dependency inventory reconciled against exact `uv.lock` pins, tags and digests; candidate `cffi`/`psutil` are not counted without integration check.
- [ ] Native wheels have validated i686 compatibility and ELF32 extension objects, and isolated Python imports where applicable.
- [ ] Full isolated PM install/sync/doctor succeeds, with no x64 native libraries and no unexpected global PM update.

## Gate 3 — gateway, sessions, plugins (private integration only)
- [ ] Semantic compatibility matrix compares old customizations with exact v0.23.2 contracts; don't paste old adapter hunks.
- [ ] Session ownership is separated by profile; admission ordering and concurrent messages are covered by isolated test fixtures.
- [ ] Recovery barrier is tested before gateway publication.
- [ ] Telegram, WhatsApp, Signal adapters are exercised with **mocked/synthetic credentials and state**; failures don't cross profiles and don't claim to preserve real sessions untested.
- [ ] Reaction policy, WhatsApp sender restrictions, streaming, /react, media fallback, locale and memory/plugins have regression tests as applicable.
- [ ] Full Signal migration mapping explicitly signed off before any production consideration.

## Gate 4 — production change (NOT AUTHORIZED)
- [ ] Coherent backup of code, wheels, config, SQLite, systemd and messaging service identities; no secrets stored in Git.
- [ ] Restore validation of SQLite, paired identities and service state in a protected isolated environment.
- [ ] Full rollback rehearsal proven, including actual channel recovery behavior.
- [ ] Explicit, separate human authorization for production cutover.

## Delivery expectations
- One PR per cohesive change; attach minimal reproduction and tests.
- If target device unavailable, mark pending `NATIVE I686` checks; **do not mark Gate 2 complete**.
- Keep binary artifacts, private patches, messaging/session data and exact live host config out of this public repository.
- Leave production untouched, even if all earlier gates pass.
