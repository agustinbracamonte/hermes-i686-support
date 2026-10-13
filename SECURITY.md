# Security policy

## Scope

This repository contains build and verification tooling. It must never receive production configuration, credentials, session state, messaging identities, phone numbers, cookies, tokens, databases, logs or account data.

## Reporting

For a suspected secret or privacy exposure, **do not open a public issue containing it**. Contact the maintainer privately through the contact channel listed in the future repository security settings. Until then, do not publish reports or artifacts.

## Supported material

Support applies to the latest documented scripts and the current planned release-assets manifest. Generated wheels and integration artifacts require a fresh checksum, ABI verification and license review for every release.

## Disclosure handling

Immediately revoke exposed credentials through the originating provider, remove the artifact from future releases, and rewrite public history only after assessing downstream copies. Do not assume deleting a file is sufficient remediation.
