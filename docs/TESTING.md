# Test evidence

The local preparation was validated without changing the live Hermes installation.

| Check | Result |
|---|---|
| Shell syntax for all scripts | PASS |
| Script smoke test | PASS |
| Tested Hermes Python preflight (`32-bit`) | PASS |
| Active runtime report (`cryptography 50.0.0`, OpenSSL 3.5.7) | PASS |
| Wheel tag and SHA-256 | PASS |
| Extracted wheel native ELF | PASS: 32-bit Intel 80386 |
| Release-asset checksum manifest | PASS: 4 artifacts |
| Generic-path scan in scripts | PASS |

No build was rerun because compiling OpenSSL/cryptography would be resource-intensive and unnecessary to validate the recovered artifact procedure. The original completed artifact and source hashes are documented instead.
