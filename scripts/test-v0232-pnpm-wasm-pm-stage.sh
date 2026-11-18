#!/usr/bin/env bash
# Cross-stage the already verified official @pnpm/wasm archive through Hermes PM.
# Uses loopback, so PM hashes and installs the supplied archive without a second download.
set -euo pipefail

usage() {
  cat <<'HELP'
Usage: test-v0232-pnpm-wasm-pm-stage.sh PATCHED_HERMES_V0232_CHECKOUT [--node-bin PATH --node-store PATH] [--require-ia32]

Cross-stages the already-verified pnpm WASM archive through PM. With --node-bin,
also executes the staged pnpm launchers and an offline local-file install via
the Node executable resolved from an explicit, isolated --node-store containing
that Node. The supplied node store is read-only; pnpm is staged in a private
temporary directory owned by this script. Node must be v26.12.1.
--require-ia32 additionally requires process.arch=ia32 for native staging tests.
Set PNPM_WASM_ARCHIVE to the verified archive; this script does not download it.
HELP
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi
if (($# == 0)); then
  usage >&2
  exit 2
fi
UPSTREAM=$1
shift
PYTHON=${HERMES_PYTHON:-python3}
PNPM_NODE_BIN=${PNPM_NODE_BIN:-}
PNPM_REQUIRE_IA32=0
PNPM_NODE_STORE=${PNPM_NODE_STORE:-}
while (($#)); do
  case "$1" in
    --node-bin)
      [[ $# -ge 2 && -n "$2" ]] || { echo '--node-bin requires a path' >&2; exit 2; }
      PNPM_NODE_BIN=$2
      shift 2
      ;;
    --node-store)
      [[ $# -ge 2 && -n "$2" ]] || { echo '--node-store requires a path' >&2; exit 2; }
      PNPM_NODE_STORE=$2
      shift 2
      ;;
    --require-ia32)
      PNPM_REQUIRE_IA32=1
      shift
      ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
if (( PNPM_REQUIRE_IA32 )) && [[ -z "$PNPM_NODE_BIN" ]]; then
  echo '--require-ia32 requires --node-bin or PNPM_NODE_BIN' >&2
  exit 2
fi
if [[ -n "$PNPM_NODE_BIN" && -z "$PNPM_NODE_STORE" ]]; then
  echo 'Node execution requires an explicit isolated --node-store' >&2
  exit 2
fi
if [[ -n "$PNPM_NODE_STORE" && -z "$PNPM_NODE_BIN" ]]; then
  echo '--node-store requires --node-bin or PNPM_NODE_BIN' >&2
  exit 2
fi
if [[ -n "$PNPM_NODE_STORE" && "$PNPM_NODE_STORE" != /* ]]; then
  echo '--node-store must be an absolute path' >&2
  exit 2
fi
ARCHIVE=${PNPM_WASM_ARCHIVE:?set PNPM_WASM_ARCHIVE to the verified @pnpm/wasm 12.15.0 archive}
PIN="ae2a81ccc00e9b7c06301523e5bb09608397149c"
[[ -d "$UPSTREAM/.git" || -f "$UPSTREAM/.git" ]] || { echo 'input is not a Git checkout' >&2; exit 1; }
[[ "$(git -C "$UPSTREAM" rev-parse HEAD)" == "$PIN" ]] || { echo "input must be exact commit $PIN" >&2; exit 1; }
[[ -f "$ARCHIVE" ]] || { echo "archive not found: $ARCHIVE" >&2; exit 1; }

NODE_STORE_REAL=
if [[ -n "$PNPM_NODE_STORE" ]]; then
  NODE_STORE_REAL=$(realpath -e -- "$PNPM_NODE_STORE") || {
    echo 'could not resolve --node-store' >&2
    exit 2
  }
  [[ -d "$NODE_STORE_REAL" ]] || { echo '--node-store is not a directory' >&2; exit 2; }
  case "$NODE_STORE_REAL" in
    /usr|/usr/*|/bin|/bin/*|/sbin|/sbin/*)
      echo '--node-store must not be a system runtime directory' >&2
      exit 2
      ;;
  esac
fi

# Ignore caller-controlled TMPDIR so it cannot redirect staging into the
# supplied Node store. Also skip a candidate base nested inside that store.
TMP_BASE=
for candidate in /tmp /var/tmp; do
  candidate_real=$(realpath -e -- "$candidate") || continue
  [[ -d "$candidate_real" && -w "$candidate_real" ]] || continue
  if [[ -n "$NODE_STORE_REAL" && ( "$NODE_STORE_REAL" == / || \
        "$candidate_real" == "$NODE_STORE_REAL" || \
        "$candidate_real" == "$NODE_STORE_REAL/"* ) ]]; then
    continue
  fi
  TMP_BASE=$candidate_real
  break
done
[[ -n "$TMP_BASE" ]] || { echo 'no safe temporary directory outside --node-store' >&2; exit 2; }
TMP=$(mktemp -d "$TMP_BASE/hermes-pnpm-stage.XXXXXX")
trap 'rm -rf -- "$TMP"' EXIT
HERMES_HOME="$TMP/home" HERMES_RUNTIME_DIR="$TMP/tools" \
  PNPM_NODE_BIN="$PNPM_NODE_BIN" PNPM_NODE_STORE="$PNPM_NODE_STORE" \
  PNPM_REQUIRE_IA32="$PNPM_REQUIRE_IA32" \
  "$PYTHON" - "$UPSTREAM" "$ARCHIVE" <<'PY'
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import subprocess
from threading import Thread

source = Path(sys.argv[1]).resolve()
archive = Path(sys.argv[2]).resolve()
sys.path.insert(0, str(source))
os.chdir(source)

from pm import paths
from pm.install import stage_only
from pm.lock import Lockfile
from pm.package import machine_matches_binary, verify_package_entry
from pm.registry import get_package

data = archive.read_bytes()
checksum = hashlib.sha256(data).hexdigest()
lock = Lockfile(paths.lockfile_path())
if lock.version("pnpm") != "12.15.0":
    raise SystemExit("patched source lock does not pin pnpm 12.15.0")
pin = lock.artifacts("pnpm", "linux-i686")[0]
if pin["sha256"] != checksum or pin["url"] != "https://registry.npmjs.org/@pnpm/wasm/-/wasm-12.15.0.tgz":
    raise SystemExit("local archive does not match the pinned pnpm WASM lock row")

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/pnpm-wasm-12.15.0.tgz":
            self.send_error(404)
            return
        bounds = self.headers.get("Range")
        body = data
        status = 200
        if bounds:
            match = re.fullmatch(r"bytes=(\d+)-(\d+)", bounds)
            if not match:
                self.send_error(416)
                return
            start, end = map(int, match.groups())
            if start > end or end >= len(data):
                self.send_error(416)
                return
            body = data[start:end + 1]
            status = 206
        self.send_response(status)
        if status == 206:
            self.send_header("Content-Range", f"bytes {start}-{end}/{len(data)}")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def log_message(self, *_args):
        pass

server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
thread = Thread(target=server.serve_forever, daemon=True)
thread.start()
try:
    local_lock = Lockfile(paths.lockfile_path())
    local_lock.set_pin("pnpm", "12.15.0", {
        "linux-i686": {
            "url": f"http://127.0.0.1:{server.server_port}/pnpm-wasm-12.15.0.tgz",
            "sha256": checksum,
        }
    })
    import pm.install as install
    install._lockfile = lambda: local_lock
    store = Path(os.environ["HERMES_RUNTIME_DIR"]).resolve()
    paths.store_root = lambda: store

    entry = stage_only("pnpm", "linux-i686")
    package = get_package("pnpm")
    reason = verify_package_entry(package, entry, "linux-i686")
    if reason:
        raise SystemExit(f"PM i686 entry verification failed: {reason}")
    for name in ("pnpm", "pn", "pnpx", "pnx"):
        wrapper = package.binary(entry, "linux-i686").parent / name
        if not wrapper.is_file() or not os.access(wrapper, os.X_OK):
            raise SystemExit(f"PM staged an invalid {name} WASM launcher")
    manifest = json.loads((entry / "package" / "package.json").read_text())
    wasm = entry / "package" / "dist" / "pnpm.wasm"
    if manifest.get("name") != "@pnpm/wasm" or manifest.get("version") != "12.15.0":
        raise SystemExit("PM staged the wrong pnpm WASM package")
    if wasm.stat().st_size != 44_951_421 or wasm.read_bytes()[:4] != b"\x00asm":
        raise SystemExit("PM staged an invalid pnpm WASM module")
    print(f"pnpm WASM PM cross-stage: PASS ({checksum}; {entry.name}; ELF scan passed)")

    node_value = os.environ.get("PNPM_NODE_BIN", "")
    require_ia32 = os.environ.get("PNPM_REQUIRE_IA32") == "1"
    if not node_value:
        if require_ia32:
            raise SystemExit("--require-ia32 needs a Node binary")
        print("pnpm WASM staged launcher execution: NOT RUN (no PM-managed Node supplied)")
        raise SystemExit(0)

    node = Path(node_value)
    if not node.is_absolute():
        raise SystemExit("PM-managed Node path must be absolute")
    try:
        node = node.resolve(strict=True)
    except OSError as exc:
        raise SystemExit(f"could not resolve PM-managed Node: {exc}")
    try:
        node_store = Path(os.environ["PNPM_NODE_STORE"]).resolve(strict=True)
    except OSError as exc:
        raise SystemExit(f"could not resolve --node-store: {exc}")
    if not node_store.is_dir():
        raise SystemExit("Node store is not a directory")
    system_roots = {Path(root).resolve() for root in ("/", "/usr", "/bin", "/sbin")}
    if any(node_store == root or root in node_store.parents for root in system_roots):
        raise SystemExit("Node store must be an isolated non-system runtime store")
    try:
        node.relative_to(node_store)
    except ValueError:
        raise SystemExit("Node executable must resolve inside the read-only --node-store")
    if not node.is_file() or not os.access(node, os.X_OK):
        raise SystemExit("PM-managed Node is not an executable file")
    if node.name != "node":
        raise SystemExit("PM-managed Node path must name the node executable")
    if require_ia32 and machine_matches_binary(node, "linux-i686") is not True:
        raise SystemExit("--require-ia32 but PM-managed Node is not ELF32/EM_386")

    runtime_test = Path(os.environ["HERMES_HOME"]).parent / "pnpm-runtime-test"
    test_home = runtime_test / "home"
    runtime_test.mkdir(parents=True)
    test_home.mkdir(parents=True)
    env = {
        "HOME": str(test_home),
        "PATH": f"{node.parent}:/usr/bin:/bin",
        "COREPACK_ENABLE_NETWORK": "0",
        "CI": "1",
        "NPM_CONFIG_USERCONFIG": "/dev/null",
        "NPM_CONFIG_GLOBALCONFIG": "/dev/null",
        "NO_COLOR": "1",
        "FORCE_COLOR": "0",
    }
    selected_node = subprocess.run(
        ["/bin/sh", "-c", "command -v node"], check=True, capture_output=True, text=True, env=env
    ).stdout.strip()
    if Path(selected_node).resolve() != node:
        raise SystemExit(f"controlled PATH selected {selected_node}, expected PM-managed Node {node}")

    try:
        node_version = subprocess.run(
            [str(node), "--version"], check=True, capture_output=True, text=True, env=env
        ).stdout.strip()
        node_arch = subprocess.run(
            [str(node), "-p", "process.arch"], check=True, capture_output=True, text=True, env=env
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError) as exc:
        raise SystemExit(f"could not run PM-managed Node preflight: {exc}")
    if node_version != "v26.12.1":
        raise SystemExit(f"PM-managed Node must be v26.12.1; found {node_version}")
    if require_ia32 and node_arch != "ia32":
        raise SystemExit(f"--require-ia32 but PM-managed Node reports process.arch={node_arch}")

    wrapper = package.binary(entry, "linux-i686").parent / "pnpm"
    version_result = subprocess.run(
        [str(wrapper), "--version"], check=True, capture_output=True, text=True, env=env
    ).stdout.strip()
    if version_result != "12.15.0":
        raise SystemExit(f"staged pnpm launcher returned {version_result}, expected 12.15.0")

    dependency = runtime_test / "dependency"
    app = runtime_test / "app"
    dependency.mkdir()
    app.mkdir()
    (dependency / "package.json").write_text(
        json.dumps({"name": "hermes-i686-offline-fixture", "version": "1.0.0", "main": "index.js"}),
        encoding="utf-8",
    )
    (dependency / "index.js").write_text("module.exports = 'offline-ok'\n", encoding="utf-8")
    (app / "package.json").write_text(
        json.dumps({
            "name": "hermes-i686-pnpm-launcher-smoke",
            "version": "1.0.0",
            "private": True,
            "dependencies": {"hermes-i686-offline-fixture": "file:../dependency"},
        }),
        encoding="utf-8",
    )
    subprocess.run(
        [str(wrapper), "install", "--offline", "--ignore-scripts"],
        cwd=app,
        check=True,
        env=env,
    )
    loaded = subprocess.run(
        [str(node), "-e", "process.stdout.write(require('hermes-i686-offline-fixture'))"],
        cwd=app,
        check=True,
        capture_output=True,
        text=True,
        env=env,
    ).stdout
    if loaded != "offline-ok":
        raise SystemExit("staged pnpm launcher did not install the local offline dependency")
    print(f"pnpm WASM staged launcher execution: PASS (pnpm={version_result}; node={node_version}; arch={node_arch}; controlled PATH selected PM store Node; offline file install passed)")
finally:
    server.shutdown()
    server.server_close()
    thread.join(timeout=5)
PY
