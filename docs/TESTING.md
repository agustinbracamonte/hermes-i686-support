# Test evidence and current status

This table distinguishes previously recovered observations from tests actually rerun for this correction. A historical `PASS` is not a current validation claim.

| Check | Evidence/status |
|---|---|
| Python 3.11.5, 32-bit interpreter; cryptography 50.0.0 backend using OpenSSL 3.5.7 | Previously observed in staged Hermes runtime; strict runtime script rerun successfully on this runtime |
| Wheel SHA-256, WHEEL metadata tag, native extension ELF class/machine, and dependency closure | Strict verifier rerun against recovered wheel; PASS |
| False-checksum wheel | Negative behavioral test; rejected |
| Validly tagged wheel containing ELF64 x86_64 extension | Negative behavioral test; rejected |
| Malformed/non-ELF native extension | Negative behavioral test; rejected |
| Runtime on system Python (64-bit, wrong Python/crypto profile) | Negative behavioral test; rejected |
| Build preflight on wrong-width system Python | Negative behavioral test; refused before creating work directory or downloading inputs |
| Exact approved release asset | Positive test; only the approved wheel plus SHA256SUMS copied |
| Wrong release checksum and Signal JAR approval attempt | Negative integration tests; both rejected |
| Shell syntax | Rechecked for all scripts/tests |
| Full filesystem/history privacy audit | Rechecked separately before archive |
| OpenSSL/cryptography rebuild with the revised pinned toolchain | **NOT RUN**; resource-intensive; build instructions remain experimental until a fresh clean rebuild |
| Signal JAR/JNI integration | **EXPERIMENTAL; NOT APPROVED FOR RELEASE**. Do not distribute JAR, JNI or native binaries. |

Tests use the staged wheel and its fixed expected digest. Set `REAL_WHEEL` and `PYTHON_I686` to other reviewed fixture paths when running outside this host; the fixture must match the recorded digest unless the test digest is deliberately updated after review.
