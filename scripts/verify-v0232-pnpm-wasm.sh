#!/usr/bin/env bash
# Verify the official pnpm 12.15.0 WASM distribution without native executables.
set -euo pipefail

readonly PNPM_VERSION=12.15.0
readonly WRAPPER_URL=https://registry.npmjs.org/pnpm/-/pnpm-12.15.0.tgz
readonly WRAPPER_SHA256=f5173f6127cc505cdb36ec17719fe54a8511c6fd8560c7ceb4bf7c73e3b4458b
readonly WASM_URL=https://registry.npmjs.org/@pnpm/wasm/-/wasm-12.15.0.tgz
readonly WASM_SHA256=172c9d9a2b8b82b00a67323ffa6d34c32f8706279661329ea460432b95c9da1f
readonly WASM_SHA512_HEX=bb157ad53ed29f7e12015524cd97f4c58356d0e730e7d3821d844d758da93a6e3113767eaf6a6d5ce7765d3896401399f2a83230bb3af45e191dc51a92f151d9
readonly WASM_NPM_INTEGRITY=uxV61T7Sn34SAVUkzZf0xYNW0Ocw59OCHYRNdY2pOm4xE3Z+r2ptXOd2XTiWQBOZ8qgyMLs69F4ZHcUakvFR2Q==

NODE_BIN=${NODE_BIN:-node}
REQUIRE_IA32=0
case "${1:-}" in
  --help|-h)
    cat <<'HELP'
Usage: verify-v0232-pnpm-wasm.sh [--require-ia32]

Checks the official pnpm 12.15.0 npm wrapper and @pnpm/wasm package by pinned
SHA-256/SHA-512. Proves the regular `pnpm` npm package tries to download a
native executable with networking disabled, then runs @pnpm/wasm using NODE_BIN
and performs a local-file, offline install with an empty HOME and npm config.

Set NODE_BIN to the Node executable under test. --require-ia32 makes the check
fail unless process.arch is ia32; without it, the runtime architecture is
reported as evidence and is not inferred from the kernel name.

Optional cached inputs: PNPM_WRAPPER_ARCHIVE, PNPM_WASM_ARCHIVE.
HELP
    exit 0
    ;;
  --require-ia32) REQUIRE_IA32=1 ;;
  "") ;;
  *) printf 'pnpm WASM verification: ERROR: unknown argument: %s\n' "$1" >&2; exit 2 ;;
esac

for tool in awk basename base64 cp curl dirname env find grep mktemp openssl python3 sed sha256sum sha512sum tar; do
  command -v "$tool" >/dev/null 2>&1 || { printf 'pnpm WASM verification: ERROR: missing tool: %s\n' "$tool" >&2; exit 1; }
done
if [[ "$NODE_BIN" == */* ]]; then
  [[ -x "$NODE_BIN" ]] || { printf 'pnpm WASM verification: ERROR: Node not executable: %s\n' "$NODE_BIN" >&2; exit 1; }
  NODE_BIN="$(cd "$(dirname "$NODE_BIN")" && pwd)/$(basename "$NODE_BIN")"
else
  NODE_BIN=$(command -v "$NODE_BIN" 2>/dev/null || true)
  [[ -n "$NODE_BIN" && -x "$NODE_BIN" ]] || { printf 'pnpm WASM verification: ERROR: Node not executable: %s\n' "${NODE_BIN:-node}" >&2; exit 1; }
fi

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/home" "$work/wrapper" "$work/wasm" "$work/app" "$work/dep"

fetch_or_copy() {
  local override=$1 url=$2 destination=$3 expected=$4
  if [[ -n "$override" ]]; then
    [[ -f "$override" ]] || { printf 'pnpm WASM verification: ERROR: archive not found: %s\n' "$override" >&2; exit 1; }
    cp -- "$override" "$destination"
  else
    curl --fail --location --retry 3 --retry-delay 2 "$url" -o "$destination"
  fi
  local actual
  actual=$(sha256sum "$destination" | awk '{print $1}')
  [[ "$actual" == "$expected" ]] || { printf 'pnpm WASM verification: ERROR: SHA-256 mismatch for %s: %s\n' "$url" "$actual" >&2; exit 1; }
}

fetch_or_copy "${PNPM_WRAPPER_ARCHIVE:-}" "$WRAPPER_URL" "$work/pnpm-12.15.0.tgz" "$WRAPPER_SHA256"
fetch_or_copy "${PNPM_WASM_ARCHIVE:-}" "$WASM_URL" "$work/pnpm-wasm-12.15.0.tgz" "$WASM_SHA256"
[[ "$(sha512sum "$work/pnpm-wasm-12.15.0.tgz" | awk '{print $1}')" == "$WASM_SHA512_HEX" ]] || {
  printf 'pnpm WASM verification: ERROR: SHA-512 mismatch for @pnpm/wasm\n' >&2; exit 1;
}
[[ "$(openssl dgst -sha512 -binary "$work/pnpm-wasm-12.15.0.tgz" | base64 -w0)" == "$WASM_NPM_INTEGRITY" ]] || {
  printf 'pnpm WASM verification: ERROR: npm registry integrity mismatch for @pnpm/wasm\n' >&2; exit 1;
}
tar -xzf "$work/pnpm-12.15.0.tgz" -C "$work/wrapper"
tar -xzf "$work/pnpm-wasm-12.15.0.tgz" -C "$work/wasm"

python3 - "$work/wasm/package" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
manifest = json.loads((root / "package.json").read_text())
assert manifest["name"] == "@pnpm/wasm", manifest
assert manifest["version"] == "12.15.0", manifest
assert manifest["engines"]["node"] == ">=22.13", manifest
assert manifest["bin"]["pnpm"] == "dist/pnpm.mjs", manifest
wasm = root / "dist/pnpm.wasm"
assert wasm.is_file() and wasm.stat().st_size == 44_951_421, wasm
assert wasm.read_bytes()[:4] == b"\0asm", wasm
native = []
for path in root.rglob("*"):
    if not path.is_file():
        continue
    if path.suffix == ".node":
        native.append(str(path.relative_to(root)))
        continue
    try:
        head = path.open("rb").read(4)
    except OSError:
        continue
    if head.startswith(b"\x7fELF") or head == b"MZ\x90\x00" or head in (b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf"):
        native.append(str(path.relative_to(root)))
assert not native, f"native executable/module found: {native}"
print(f"package=@pnpm/wasm@{manifest['version']}; wasm_bytes={wasm.stat().st_size}; native_files=0")
PY

node_version=$(env -i HOME="$work/home" PATH="$(dirname "$NODE_BIN"):/usr/bin:/bin" "$NODE_BIN" --version)
node_arch=$(env -i HOME="$work/home" PATH="$(dirname "$NODE_BIN"):/usr/bin:/bin" "$NODE_BIN" -p 'process.arch')
node_major=$(printf '%s\n' "$node_version" | sed -E 's/^v([0-9]+)\..*/\1/')
node_minor=$(printf '%s\n' "$node_version" | sed -E 's/^v[0-9]+\.([0-9]+)\..*/\1/')
(( node_major > 22 || (node_major == 22 && node_minor >= 13) )) || {
  printf 'pnpm WASM verification: ERROR: Node >=22.13 required (found %s)\n' "$node_version" >&2; exit 1;
}
if (( REQUIRE_IA32 )); then
  [[ "$node_arch" == ia32 ]] || { printf 'pnpm WASM verification: ERROR: --require-ia32 but process.arch=%s\n' "$node_arch" >&2; exit 1; }
fi

set +e
(cd "$work" && env -i HOME="$work/home" PATH="$(dirname "$NODE_BIN"):/usr/bin:/bin" COREPACK_ENABLE_NETWORK=0 NPM_CONFIG_USERCONFIG=/dev/null NPM_CONFIG_GLOBALCONFIG=/dev/null \
  "$NODE_BIN" "$work/wrapper/package/bin/pnpm.mjs" --version) >"$work/wrapper-output.txt" 2>&1
wrapper_status=$?
set -e
[[ "$wrapper_status" -eq 1 ]] || { cat "$work/wrapper-output.txt" >&2; printf 'pnpm WASM verification: ERROR: standard npm wrapper unexpectedly exited %s\n' "$wrapper_status" >&2; exit 1; }
grep -Fq 'Network access is disabled by the environment, so the pnpm binary cannot be downloaded.' "$work/wrapper-output.txt" || {
  cat "$work/wrapper-output.txt" >&2; printf 'pnpm WASM verification: ERROR: standard wrapper did not fail at its native-binary download gate\n' >&2; exit 1;
}

wasm_cli="$work/wasm/package/dist/pnpm.mjs"
wasm_version=$(cd "$work" && env -i HOME="$work/home" PATH="$(dirname "$NODE_BIN"):/usr/bin:/bin" NPM_CONFIG_USERCONFIG=/dev/null NPM_CONFIG_GLOBALCONFIG=/dev/null "$NODE_BIN" "$wasm_cli" --version)
[[ "$wasm_version" == "$PNPM_VERSION" ]] || { printf 'pnpm WASM verification: ERROR: WASM CLI reported %s\n' "$wasm_version" >&2; exit 1; }

cat >"$work/dep/package.json" <<'JSON'
{"name":"hermes-i686-offline-fixture","version":"1.0.0","main":"index.js"}
JSON
cat >"$work/dep/index.js" <<'JS'
module.exports = 'offline-ok'
JS
cat >"$work/app/package.json" <<'JSON'
{"name":"hermes-i686-pnpm-wasm-smoke","version":"1.0.0","private":true,"dependencies":{"hermes-i686-offline-fixture":"file:../dep"}}
JSON
(cd "$work/app" && env -i HOME="$work/home" PATH="$(dirname "$NODE_BIN"):/usr/bin:/bin" CI=1 COREPACK_ENABLE_NETWORK=0 NPM_CONFIG_USERCONFIG=/dev/null NPM_CONFIG_GLOBALCONFIG=/dev/null NO_COLOR=1 FORCE_COLOR=0 \
  "$NODE_BIN" "$wasm_cli" install --offline --ignore-scripts)
loaded=$(cd "$work/app" && env -i HOME="$work/home" PATH="$(dirname "$NODE_BIN"):/usr/bin:/bin" "$NODE_BIN" -e "process.stdout.write(require('hermes-i686-offline-fixture'))")
[[ "$loaded" == offline-ok ]] || { printf 'pnpm WASM verification: ERROR: local offline package did not load\n' >&2; exit 1; }

printf 'pnpm WASM verification: PASS\n'
printf 'node=%s arch=%s\n' "$node_version" "$node_arch"
printf 'regular_pnpm_npm_package=wrapper_requires_native_binary (network-disabled negative passed)\n'
printf 'pnpm_wasm=%s; sha256=%s; npm_integrity=sha512-%s\n' "$wasm_version" "$WASM_SHA256" "$WASM_NPM_INTEGRITY"
printf 'offline_file_dependency_install=PASS; additional_native_executable=none\n'
