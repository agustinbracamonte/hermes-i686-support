# Third-party notices

This repository's own scripts and documentation are MIT-licensed; it does **not** relicense third-party projects or binary artifacts.

| Component | Intended role | License status | Upstream |
|---|---|---|---|
| Hermes Agent | Application supported by these instructions | MIT | https://github.com/NousResearch/hermes-agent |
| pyca/cryptography | Python native dependency | Apache-2.0 OR BSD-3-Clause (see upstream distribution) | https://github.com/pyca/cryptography |
| OpenSSL | Private static TLS dependency in the tested wheel | Apache-2.0 | https://www.openssl.org/source/ |
| signal-cli | Optional integration, not bundled | GPL-3.0-only; source obligations apply to distributed modified binaries | https://github.com/AsamK/signal-cli |
| libsignal | Optional JNI integration, not bundled | AGPL-3.0-only; source obligations apply to distributed modified binaries/network use | https://github.com/signalapp/libsignal |

## Release rule

Before attaching a binary to any future GitHub Release, generate a version-specific notice file/SBOM from the actual dependency graph, include required license texts and source/patch access, and verify the resulting bundle. The optional Signal artifacts are **not currently approved for redistribution**.

The license table is a release-preparation aid, not legal advice. Verify upstream license files and dependency metadata at the pinned revisions before publishing.
