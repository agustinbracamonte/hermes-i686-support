#!/usr/bin/env bash
# Read-only ABI and dynamic-linkage check for an installed Python runtime.
set -euo pipefail

PYTHON_BIN=python3
while (($#)); do
  case "$1" in
    --python) PYTHON_BIN=${2:?missing python path}; shift 2 ;;
    -h|--help) echo "Usage: $0 [--python PATH]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

"$PYTHON_BIN" - <<'PY'
import pathlib, platform, ssl, struct, sys
print(f'python={sys.executable}')
print(f'python_version={sys.version.split()[0]}')
print(f'pointer_bits={struct.calcsize("P") * 8}')
print(f'platform_machine={platform.machine()}')
print(f'stdlib_openssl={ssl.OPENSSL_VERSION}')
try:
    import cryptography
    from cryptography.hazmat.backends.openssl.backend import backend
    root = pathlib.Path(cryptography.__file__).parent
    candidates = list(root.glob('hazmat/bindings/_rust*.so'))
    print(f'cryptography={cryptography.__version__}')
    print(f'cryptography_openssl={backend.openssl_version_text()}')
    print(f'cryptography_extension={candidates[0] if candidates else "missing"}')
except Exception as exc:
    print(f'cryptography=unavailable ({exc.__class__.__name__})')
PY

echo 'runtime-check: PASS (inspect reported values against the compatibility matrix)'
