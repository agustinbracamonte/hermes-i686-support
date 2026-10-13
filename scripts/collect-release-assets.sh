#!/usr/bin/env bash
# Copy only explicitly approved, checksummed release artifacts.
set -euo pipefail
SOURCE_DIR=${1:-}; OUT_DIR=${2:-dist/release-assets}; MANIFEST=${3:-}
[[ -n $SOURCE_DIR && -d $SOURCE_DIR && -n $MANIFEST && -f $MANIFEST ]] || { echo "Usage: $0 WHEELHOUSE_DIR OUT_DIR APPROVAL_MANIFEST" >&2; exit 2; }
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
mkdir -p "$OUT_DIR"
if find "$OUT_DIR" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  echo 'output directory contains pre-existing artifacts; use an empty directory' >&2; exit 1
fi
python3 - "$SOURCE_DIR" "$OUT_DIR" "$MANIFEST" "$SCRIPT_DIR/verify-wheel.sh" <<'PY'
import hashlib,pathlib,re,shutil,subprocess,sys
source,out,manifest,verifier=map(pathlib.Path,sys.argv[1:])
entries=[]
for line in manifest.read_text().splitlines():
 line=line.strip()
 if not line or line.startswith('#'): continue
 m=re.fullmatch(r'([0-9a-fA-F]{64})\s+([A-Za-z0-9_.+-]+\.whl)',line)
 if not m: raise SystemExit('invalid approval manifest line')
 sha,name=m.groups()
 if not re.fullmatch(r'cryptography-50\.0\.0-cp311-abi3-linux_i686\.whl',name): raise SystemExit('artifact name/version/ABI is not approved')
 entries.append((name,sha.lower()))
if len(entries)!=1 or len({n for n,_ in entries})!=len(entries): raise SystemExit('manifest must approve exactly one unique artifact')
name,expected=entries[0]; src=source/name
if not src.is_file(): raise SystemExit('approved asset missing')
if hashlib.sha256(src.read_bytes()).hexdigest()!=expected: raise SystemExit('approved asset SHA-256 mismatch')
subprocess.run([str(verifier),str(src),expected],check=True,stdout=subprocess.DEVNULL)
dst=out/name; shutil.copyfile(src,dst)
if hashlib.sha256(dst.read_bytes()).hexdigest()!=expected: raise SystemExit('copied artifact SHA-256 mismatch')
(out/'SHA256SUMS').write_text(f'{expected}  {name}\n')
print('assets=1'); print(f'manifest={out / "SHA256SUMS"}')
PY
echo 'release-assets: PASS (explicitly approved checksummed wheel only; Signal binaries excluded)'
