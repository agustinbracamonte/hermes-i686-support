#!/usr/bin/env bash
# Fail-closed privacy and artifact audit. Reports paths/categories only, never matched values.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
python3 - "$ROOT" <<'PY'
import pathlib,re,subprocess,sys
root=pathlib.Path(sys.argv[1])
pats={
 'private_path':r'/(?:home|Users)/[^/\s]+|C:\\Users\\',
 'email':r'(?<![\w.-])[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}(?![\w.-])',
 'phone':r'(?<!\w)\+?[0-9][0-9 ()-]{7,}[0-9](?!\w)',
 'private_key':r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
 'github_token':r'\bgh[pousr]_[A-Za-z0-9_]{20,}\b',
 'slack_token':r'\bxox[baprs]-[A-Za-z0-9-]{10,}\b',
 'aws_key':r'\b(?:AKIA|ASIA)[A-Z0-9]{16}\b',
 'credential_uri':r'(?i)\b(?:https?|ssh)://[^\s/@:]+:[^\s/@]+@',
 'credential_assignment':r'''(?im)^\s*(?:export\s+)?(?:[A-Z][A-Z0-9_]*(?:API_KEY|BOT_TOKEN|ACCESS_KEY|SECRET|TOKEN|PASSWORD)|api[_-]?key|token|password|secret|cookie)\s*[:=]\s*["']?[^\s"']{8,}''',
}
compiled={k:re.compile(v) for k,v in pats.items()}; flags=[]
def scan(scope,path,data):
 try: text=data.decode('utf-8')
 except UnicodeDecodeError:
  flags.append((scope,str(path),'binary_file')); return
 hits=[k for k,p in compiled.items() if p.search(text)]
 if hits: flags.append((scope,str(path),','.join(hits)))
# Scan every filesystem file, including ignored and untracked; Git internals are scanned below.
for p in root.rglob('*'):
 if '.git' in p.parts or not p.is_file(): continue
 try:
  if p.stat().st_size>20_000_000: flags.append(('worktree',str(p.relative_to(root)),'oversize_unreviewed')); continue
  scan('worktree',p.relative_to(root),p.read_bytes())
 except OSError: flags.append(('worktree',str(p.relative_to(root)),'unreadable'))
# Scan all commits' identities AND full messages. Do not print any metadata or matched text.
refs=subprocess.check_output(['git','-C',str(root),'for-each-ref','--format=%(refname)'],text=True).splitlines()
commits=set()
for ref in refs: commits.update(subprocess.check_output(['git','-C',str(root),'rev-list',ref],text=True).splitlines())
commits.update(subprocess.check_output(['git','-C',str(root),'rev-list','HEAD'],text=True).splitlines())
for c in sorted(commits):
 meta=subprocess.check_output(['git','-C',str(root),'show','-s','--format=%an%n%ae%n%cn%n%ce%n%B',c])
 scan('commit:'+c[:12],'metadata+message',meta)
# Scan every reachable blob exactly once by object enumeration.
for line in subprocess.check_output(['git','-C',str(root),'rev-list','--objects','--all'],text=True).splitlines():
 oid,*path=line.split(' ',1)
 try: data=subprocess.check_output(['git','-C',str(root),'cat-file','blob',oid],stderr=subprocess.DEVNULL)
 except subprocess.CalledProcessError: continue
 scan('history',path[0] if path else oid[:12],data)
# Include dangling blobs; never reveal contents.
fsck=subprocess.run(['git','-C',str(root),'fsck','--no-reflogs','--unreachable'],text=True,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL)
for line in fsck.stdout.splitlines():
 parts=line.split()
 if len(parts)>=3 and parts[1]=='commit':
  oid=parts[2]
  try: scan('unreachable-commit:'+oid[:12],'metadata+message',subprocess.check_output(['git','-C',str(root),'show','-s','--format=%an%n%ae%n%cn%n%ce%n%B',oid]))
  except subprocess.CalledProcessError: pass
 elif len(parts)>=3 and parts[1]=='blob':
  oid=parts[2]
  try: scan('unreachable-history',oid[:12],subprocess.check_output(['git','-C',str(root),'cat-file','blob',oid]))
  except subprocess.CalledProcessError: pass
if flags:
 for scope,path,cats in flags: print(f'FLAG scope={scope} path={path} categories={cats}')
 print(f'publication-audit: FAIL flags={len(flags)}'); raise SystemExit(1)
print('publication-audit: PASS (filesystem, all refs, commit metadata/messages, reachable and dangling blobs)')
PY
