#!/usr/bin/env bash
# Read-only environment preflight for a 32-bit Hermes staging build.
set -euo pipefail

PYTHON_BIN=python3
REQUIRE_I686=0
while (($#)); do
  case "$1" in
    --python) PYTHON_BIN=${2:?missing python path}; shift 2 ;;
    --require-i686) REQUIRE_I686=1; shift ;;
    -h|--help) echo "Usage: $0 [--python PATH] [--require-i686]"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v "$PYTHON_BIN" >/dev/null || { echo "missing Python: $PYTHON_BIN" >&2; exit 1; }
command -v file >/dev/null || { echo "missing command: file" >&2; exit 1; }
command -v sha256sum >/dev/null || { echo "missing command: sha256sum" >&2; exit 1; }

bits=$("$PYTHON_BIN" -c 'import struct; print(struct.calcsize("P") * 8)')
machine=$("$PYTHON_BIN" -c 'import platform; print(platform.machine())')
pyver=$("$PYTHON_BIN" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
echo "python=$PYTHON_BIN version=$pyver pointer_bits=$bits platform_machine=$machine"
if command -v rustc >/dev/null; then
  echo "rust_host=$(rustc -vV | awk -F': ' '/^host:/{print $2}')"
else
  echo 'rust_host=absent'
fi
if command -v gcc >/dev/null; then echo "gcc_target=$(gcc -dumpmachine)"; fi
if (( REQUIRE_I686 )) && [[ $bits != 32 ]]; then
  echo "expected 32-bit Python, found $bits-bit" >&2
  exit 1
fi
echo 'preflight: PASS'
