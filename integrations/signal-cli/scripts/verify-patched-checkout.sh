#!/usr/bin/env bash
# Verify a checkout is exactly its pinned upstream tag plus one authorized patch.
set -euo pipefail
repo=${1:?usage: verify-patched-checkout.sh REPO TAG PATCH SHA256}
tag=${2:?missing pinned tag}
patch_file=${3:?missing authorized patch}
expected_sha=${4:?missing patch SHA-256}
[[ -d $repo/.git && -f $patch_file ]] || { echo 'checkout or patch missing' >&2; exit 1; }
actual_sha=$(sha256sum "$patch_file" | awk '{print $1}')
[[ $actual_sha == "$expected_sha" ]] || { echo 'authorized patch digest mismatch' >&2; exit 1; }
tag_commit=$(git -C "$repo" rev-parse --verify "$tag^{commit}") || { echo 'pinned upstream tag missing' >&2; exit 1; }
head=$(git -C "$repo" rev-parse HEAD)
[[ $head == "$tag_commit" ]] || { echo 'checkout HEAD is not the exact pinned tag commit' >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git -C "$repo" archive "$head" | tar -xf - -C "$tmp"
git -C "$tmp" apply --check "$patch_file" || { echo 'authorized patch does not apply cleanly to pinned tag' >&2; exit 1; }
git -C "$tmp" apply "$patch_file"
# Exact byte-for-byte worktree comparison also rejects extra edits, staged changes and ignored/untracked files.
python3 - "$tmp" "$repo" <<'PY'
import pathlib,stat,sys
expected,actual=map(pathlib.Path,sys.argv[1:])
def entries(root):
 out={}
 for p in root.rglob('*'):
  rel=p.relative_to(root)
  if '.git' in rel.parts: continue
  if p.is_symlink(): out[rel.as_posix()]=('link',p.readlink().as_posix())
  elif p.is_file(): out[rel.as_posix()]=('file',stat.S_IMODE(p.stat().st_mode),p.read_bytes())
 return out
a,b=entries(expected),entries(actual)
if a.keys()!=b.keys(): raise SystemExit('source worktree file set differs from authorized patch result')
if any(a[p]!=b[p] for p in a): raise SystemExit('source worktree contains changes beyond authorized patch result')
PY
echo 'source-provenance: PASS (exact pinned tag plus authorized patch only)'
