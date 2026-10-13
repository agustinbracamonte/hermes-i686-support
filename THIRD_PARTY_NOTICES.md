# Third-party notices

This repository's own scripts and documentation are MIT-licensed; it does **not** relicense third-party projects or binary artifacts.

| Component | Intended role | License status | Upstream |
|---|---|---|---|
| Hermes Agent | Application supported by these instructions | MIT | https://github.com/NousResearch/hermes-agent |
| pyca/cryptography | Python native dependency | Apache-2.0 OR BSD-3-Clause (see upstream distribution) | https://github.com/pyca/cryptography |
| OpenSSL | Private static TLS dependency in the tested wheel | Apache-2.0 | https://www.openssl.org/source/ |
| signal-cli | Optional integration, not bundled | GPL-3.0-only; source obligations apply to distributed modified binaries | https://github.com/AsamK/signal-cli |
| libsignal | Optional JNI integration, not bundled | AGPL-3.0-only; source obligations apply to distributed modified binaries/network use | https://github.com/signalapp/libsignal |

The optional Signal patch files and their license texts are under `integrations/signal-cli/patches/` and `integrations/signal-cli/LICENSES/`. They remain excluded from binary releases unless the full corresponding-source and dependency-notice obligations are met.

## Release rule

Before attaching a binary to any future GitHub Release, generate a version-specific notice file/SBOM from the actual dependency graph, include required license texts and source/patch access, and verify the resulting bundle. Do not rely on a Signal fat JAR to preserve notices: its build may exclude `META-INF/LICENSE*` and `META-INF/NOTICE*`; supply an external reconciled notice bundle. The optional Signal artifacts are **not currently approved for redistribution**.

The license table is a release-preparation aid, not legal advice. Verify upstream license files and dependency metadata at the pinned revisions before publishing.
