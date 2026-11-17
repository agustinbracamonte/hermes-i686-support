# Sanitized Púlsar migration checklist for Hermes v0.23.2

This is a contract and synthetic-test plan for a future private integration. It does not claim access to, or porting of, private Púlsar patches. Work belongs in the separate private repository described in `PRIVATE-INTEGRATION-SETUP.md`.

## Before mapping behavior

- [ ] Pin the integration source to Hermes Agent v0.23.2 commit `ae2a81ccc00e9b7c06301523e5bb09608397149c`.
- [ ] Prepare an allowlisted, sanitized adaptation inventory: source path, old behavior, new upstream contract, owner, test fixture, and status.
- [ ] Review upstream v0.20 and v0.23.2 contracts semantically. Do not transplant old diff hunks without understanding the new owner and lifecycle.
- [ ] Use synthetic profiles, tokens, messages, media, and device state only. Keep real channel services and production files disconnected.
- [ ] Record `NOT RUN`, `STATIC`, `HOSTED CI`, or `NATIVE I686` per check with command and artifact provenance.

## Migration contracts and regression fixtures

| Area | Contract to map | Synthetic regression coverage |
|---|---|---|
| Profile session authority | A session belongs to one profile; profile-local state cannot be read or written through another profile's paths. | Two temporary profile roots with distinct session IDs and fake message histories; assert no cross-profile reads, writes, or recovery. |
| Serialized admission | Concurrent messages for one conversation are admitted in order and do not create duplicate or overlapping turns. | Deterministic barrier-controlled concurrent requests; assert admission order, one active turn, and no lost message. |
| Recovery barrier | Recovery and state validation complete before a gateway starts publishing or accepting work. | Corrupt and interrupted synthetic state; assert startup remains closed until recovery completes or returns a scoped error. |
| Telegram adapter | New adapter hooks preserve supported send, edit, reply, stream, and delivery behavior. | Mock transport and synthetic update objects; test success, retry, malformed update, and profile isolation. |
| WhatsApp adapter | Sender restrictions, supported reactions, media fallback, and error handling match the authorized capability matrix. | Fake sender IDs and local media fixtures; assert unauthorized senders are rejected and media fallback is deterministic. |
| Signal adapter | Adapter initialization and delivery respect the new plugin contract and the migration boundary for paired identity state. | Fake subprocess/API transport and synthetic identity metadata; assert no real Signal store is opened and failure is profile-scoped. |
| Streaming and `/react` | Partial output and reaction commands obey the new gateway event and capability contracts. | Mock event sequences for stream start/update/final, unsupported reactions, retries, and concurrent reactions. |
| Media | MIME detection, download limits, conversion fallback, and cleanup preserve the new adapter contract. | Tiny local byte fixtures, fake MIME values, malformed media, size-limit and conversion failure cases. |
| Locale | Locale selection remains profile scoped and fallback behavior is stable. | Two profiles with different locales plus an invalid locale; assert message formatting and fallback. |
| Memory and plugins | Memory paths, plugin declarations, initialization, and continuity follow v0.23.2 ownership rules. | Temporary profile memory trees and fake plugins; assert ordering, idempotence, recovery, and no shared mutable state. |

## Review gates

- [ ] Each old customization has one semantic disposition: ported, replaced by upstream, intentionally dropped, or blocked with an owner.
- [ ] Tests use fake transports and temporary roots; they do not connect to Telegram, WhatsApp, Signal, or a production gateway.
- [ ] Concurrent admission and recovery tests run repeatedly in isolated subprocesses.
- [ ] Profile boundaries are checked on success, retry, timeout, and recovery failure paths.
- [ ] Media, reactions, locale, memory, and plugin continuity have explicit acceptance assertions, not only startup smoke tests.
- [ ] Signal mapping is separately reviewed because paired identity state cannot be validated from source-only tests.
- [ ] No production migration or channel login is part of these development milestones.
