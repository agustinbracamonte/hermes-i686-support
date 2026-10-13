#!/usr/bin/env bash
# Strict fail-closed runtime contract for the validated CPython 3.11/i686 matrix.
set -euo pipefail
PYTHON_BIN=python3
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
while (($#)); do case "$1" in --python) PYTHON_BIN=${2:?missing python path}; shift 2;; --staging-root) STAGING_ROOT=${2:?missing staging root}; shift 2;; --wheel) WHEEL=${2:?missing approved wheel}; shift 2;; --sha256) EXPECTED_SHA256=${2:?missing wheel SHA-256}; shift 2;; -h|--help) echo "Usage: $0 --python PATH --staging-root DIR --wheel WHEEL --sha256 SHA256"; exit 0;; *) echo "Unknown argument: $1" >&2; exit 2;; esac; done
[[ -n ${STAGING_ROOT:-} && -n ${WHEEL:-} && -n ${EXPECTED_SHA256:-} ]] || { echo 'runtime import checks require an isolated staging root and provenance-validated wheel' >&2; exit 2; }
root=$(realpath -e "$STAGING_ROOT") || { echo 'staging root does not exist' >&2; exit 1; }
python=$(realpath -e "$PYTHON_BIN") || { echo 'Python executable not found' >&2; exit 1; }
wheel=$(realpath -e "$WHEEL") || { echo 'approved wheel not found' >&2; exit 1; }
[[ $python == "$root"/* && $wheel == "$root"/* ]] || { echo 'Python and wheel must reside under the isolated staging root' >&2; exit 1; }
"$SCRIPT_DIR/verify-wheel.sh" "$wheel" "$EXPECTED_SHA256" >/dev/null
wheel_extension_sha=$(python3 - "$wheel" <<'PY'
import hashlib,sys,zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
 names=[n for n in z.namelist() if n.startswith('cryptography/hazmat/bindings/_rust') and n.endswith('.so')]
 if len(names)!=1: raise SystemExit('wheel must contain exactly one cryptography _rust extension')
 print(hashlib.sha256(z.read(names[0])).hexdigest())
PY
)
STAGING_ROOT="$root" WHEEL_EXTENSION_SHA256="$wheel_extension_sha" "$python" -I - <<'PY'
import hashlib, importlib.util, os, pathlib, platform, re, ssl, struct, subprocess, sys, sysconfig
errors=[]
stage=pathlib.Path(os.environ['STAGING_ROOT']).resolve()
if not pathlib.Path(sys.prefix).resolve().is_relative_to(stage):
 print('FAIL: interpreter prefix is outside staging root',file=sys.stderr); raise SystemExit(1)
spec=importlib.util.find_spec('cryptography')
if not spec or not spec.origin or not pathlib.Path(spec.origin).resolve().is_relative_to(stage):
 print('FAIL: cryptography package is outside staging root',file=sys.stderr); raise SystemExit(1)
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
  if pathlib.Path(so).resolve().is_relative_to(pathlib.Path(os.environ['STAGING_ROOT'])) is False: errors.append('cryptography imported outside staging root')
  if hashlib.sha256(pathlib.Path(so).read_bytes()).hexdigest()!=os.environ['WHEEL_EXTENSION_SHA256']: errors.append('loaded cryptography extension differs from provenance-validated wheel')
  desc=subprocess.check_output(['file','-b',str(so)],text=True)
  if 'ELF 32-bit' not in desc or 'Intel 80386' not in desc: errors.append('cryptography extension must be ELF i386')
  needed=re.findall(r'^\s*NEEDED\s+(\S+)',subprocess.check_output(['objdump','-p',str(so)],text=True),re.M)
  expected=['ld-linux.so.2','libc.so.6','libdl.so.2','libgcc_s.so.1','libpthread.so.0']
  if sorted(set(needed))!=expected: errors.append('cryptography extension dynamic dependency set differs from validated i386 profile')
  if any(re.search(r'lib(?:ssl|crypto)',x) for x in needed): errors.append('dynamic OpenSSL linkage is forbidden for this static profile')
  dynamic=subprocess.check_output(['readelf','-d',str(so)],text=True,stderr=subprocess.DEVNULL)
  if re.search(r'\((?:RPATH|RUNPATH)\)',dynamic): errors.append('embedded RPATH/RUNPATH is forbidden')
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
