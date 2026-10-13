#!/usr/bin/env bash
# Strict fail-closed runtime contract for the validated CPython 3.11/i686 matrix.
set -euo pipefail
PYTHON_BIN=python3
while (($#)); do case "$1" in --python) PYTHON_BIN=${2:?missing python path}; shift 2;; -h|--help) echo "Usage: $0 [--python PATH]"; exit 0;; *) echo "Unknown argument: $1" >&2; exit 2;; esac; done
command -v "$PYTHON_BIN" >/dev/null 2>&1 || { echo 'Python executable not found' >&2; exit 1; }
"$PYTHON_BIN" - <<'PY'
import pathlib, platform, re, ssl, struct, subprocess, sys, sysconfig
errors=[]
if platform.python_implementation()!='CPython': errors.append('interpreter must be CPython')
if sys.version_info[:2]!=(3,11): errors.append('Python must be CPython 3.11')
if struct.calcsize('P')*8!=32: errors.append('Python interpreter must be 32-bit')
if 'OpenSSL 3.5.7' not in ssl.OPENSSL_VERSION: print(f'stdlib_openssl={ssl.OPENSSL_VERSION} (informational; cryptography backend is checked below)')
try:
 import cryptography
 from cryptography.hazmat.backends.openssl.backend import backend
 if cryptography.__version__!='50.0.0': errors.append('cryptography must be 50.0.0')
 if 'OpenSSL 3.5.7' not in backend.openssl_version_text(): errors.append('cryptography must use OpenSSL 3.5.7')
 root=pathlib.Path(cryptography.__file__).parent
 exts=list(root.glob('hazmat/bindings/_rust*.so'))
 if not exts: errors.append('cryptography native extension missing')
 for so in exts:
  desc=subprocess.check_output(['file','-b',str(so)],text=True)
  if 'ELF 32-bit' not in desc or 'Intel 80386' not in desc: errors.append('cryptography extension must be ELF i386')
  needed=re.findall(r'^\s*NEEDED\s+(\S+)',subprocess.check_output(['objdump','-p',str(so)],text=True),re.M)
  expected=['ld-linux.so.2','libc.so.6','libdl.so.2','libgcc_s.so.1','libpthread.so.0']
  if sorted(set(needed))!=expected: errors.append('cryptography extension dynamic dependency set differs from validated i386 profile')
  if any(re.search(r'lib(?:ssl|crypto)',x) for x in needed): errors.append('dynamic OpenSSL linkage is forbidden for this static profile')
  dynamic=subprocess.check_output(['readelf','-d',str(so)],text=True,stderr=subprocess.DEVNULL)
  if re.search(r'\((?:RPATH|RUNPATH)\)',dynamic): errors.append('embedded RPATH/RUNPATH is forbidden')
  link=subprocess.run(['ldd',str(so)],text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
  if link.returncode or 'not found' in link.stdout: errors.append('cryptography extension dynamic dependencies unresolved')
except Exception as exc:
 errors.append(f'cryptography import/backend validation failed ({type(exc).__name__})')
if errors:
 for e in errors: print('FAIL: '+e,file=sys.stderr)
 raise SystemExit(1)
print(f'python={sys.version.split()[0]} bits=32 sysconfig_platform={sysconfig.get_platform()} (not treated as ABI proof)')
print(f'cryptography={cryptography.__version__} cryptography_openssl={backend.openssl_version_text()}')
print(f'stdlib_openssl={ssl.OPENSSL_VERSION}')
print('runtime-check: PASS')
PY
