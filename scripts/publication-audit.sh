#!/usr/bin/env bash
# Safe, local pre-publication scanner. It emits paths/categories, never matched text.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import pathlib,re,subprocess,sys
root=pathlib.Path(sys.argv[1])
patterns={
  'private_path': r'/(?:home|Users)/[^/\s]+|C:\\Users\\',
  'email': r'(?<![\w.-])[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}(?![\w.-])',
  'phone': r'(?<!\w)\+?[0-9][0-9 ()-]{7,}[0-9](?!\w)',
  'private_key': r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
  'github_token': r'\bgh[pousr]_[A-Za-z0-9_]{20,}\b',
  'credential_assignment': r'(?im)^\s*(?:api[_-]?key|token|password|secret|cookie)\s*[:=]\s*["\']?[^\s"\']{12,}',
}
compiled={name:re.compile(expr,re.I if name=='private_path' else 0) for name,expr in patterns.items()}
def cats(text): return [name for name,pattern in compiled.items() if pattern.search(text)]
flags = 0
def report(scope,path,text):
    global flags
    found=cats(text)
    if found:
        flags += 1
        print(f'FLAG scope={scope} path={path} categories={",".join(found)}')
for path in root.rglob('*'):
    if '.git' in path.parts or not path.is_file() or path.stat().st_size > 1_000_000: continue
    report('worktree', path.relative_to(root), path.read_text(encoding='utf-8',errors='replace'))
commits=subprocess.check_output(['git','-C',str(root),'rev-list','--all'],text=True).splitlines()
for commit in commits:
    meta=subprocess.check_output(['git','-C',str(root),'show','-s','--format=%an%n%ae%n%cn%n%ce',commit],text=True)
    report(f'commit-metadata:{commit[:12]}','metadata',meta)
    for name in subprocess.check_output(['git','-C',str(root),'ls-tree','-r','--name-only',commit],text=True).splitlines():
        try: data=subprocess.check_output(['git','-C',str(root),'show',f'{commit}:{name}'],text=True,stderr=subprocess.DEVNULL)
        except subprocess.CalledProcessError: continue
        report(f'commit:{commit[:12]}',name,data)
if flags:
    print(f'publication-audit: FAIL flags={flags}')
    raise SystemExit(1)
print('publication-audit: PASS')
PY
