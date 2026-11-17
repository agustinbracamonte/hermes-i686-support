# Codex Cloud: first implementation task for Hermes v0.23.2

**Execute code work, not another broad audit.** Read `AGENTS.md`, `docs/CODEX-HANDOFF-V0232.md`, `docs/V0232-ACCEPTANCE.md` and `docs/PRIVATE-INTEGRATION-SETUP.md` before doing anything else.

## Primary task (public, generic)
Implement a tested, repeatable **v0.23.2 Linux i686 compatibility patchset** for mixed-architecture hosts (x86_64 kernel / i386 userspace).

1. Fetch/check out upstream official `NousResearch/hermes-agent` tag `v0.23.2`, verify annotated tag resolves to `ae2a81ccc00e9b7c06301523e5bb09608397149c`. Keep upstream in an ephemeral workspace or clean source checkout; don't duplicate entire upstream as new tracked files.
2. Inspect and modify the necessary `pm` target selection / ELF validation and `scripts/install.sh`, `setup-hermes.sh` selection logic. A 32-bit Python process under x86_64 kernel MUST NOT be mistaken for x64. Design fail-closed handling of unsupported targets and unavailable lock rows. Preserve x64, ARM64 and ordinary i686 behavior. If a code path cannot prove process/userland ABI safely, require explicit validated override rather than blindly selecting x64.
3. Deliver minimal, clearly applicable patches within `patches/v0.23.2/`, plus a safe patch-application/validation wrapper if useful. Include tests in `tests/` using fixtures/mocks for real 32-bit process / 64-bit kernel architecture mismatch, ELF32/EM_386 vs ELF64, ARM64 and x64 regression, and downloader hash enforcement.
4. Analyze `pm/lock.json` for required rows and official i686 artifact availability, **without** constructing fake hashes, mutating other-platform pins or attempting to build the entire runtime in a hosted task. Document the exact missing inputs and an incremental plan for Python 3.14.9, Node 26.12.1, uv 0.13.5 and the 102 dependencies.
5. Run available tests and static checks in your workspace. Record the actual environment, commands and results. Where native i686 cannot be tested, mark `NOT RUN` and provide an executable isolated test plan for the B10.
6. Open a focused PR from your working branch with a clear description, actual tested evidence and remaining steps. Leave it unmerged. The next PR can address wheelhouse build tooling.

## Secondary task (documentation only until private repo exists)
Produce a **sanitized** migration checklist and synthetic test plan for Hermes v0.20 Púlsar customizations moving to v0.23.2: new profile session authority, serialized admission, recovery barrier, Telegram/WhatsApp/Signal plugin adapters, media, reactions, locale, memory and plugin continuity. Do not claim to possess or port private customization source not in the repository.

## Hard prohibitions
- No live gateway, no production filesystem access, no real credentials, no WhatsApp/Signal live identity, no channel logins.
- No Nova, no deployment, no update, no cutover.
- No use of the separate private repo `Nova` as a stand-in for the Púlsar workspace.
- No binary/secret uploads to the public repository.
- Don't waste work re-auditing completed older versions; v0.23.2 exact commit is the baseline.

## Completion report
Provide the PR URL and enumerate: changed files, actual tests, status of i686 vs x64/ARM64, missing source artifact SHA256s and unvalidated requirements; recommend the next *specific* engineering milestone.
