#!/usr/bin/env bash
# Cross-stage the already verified official @pnpm/wasm archive through Hermes PM.
# Uses loopback, so PM hashes and installs the supplied archive without a second download.
set -euo pipefail

UPSTREAM=${1:?usage: test-v0232-pnpm-wasm-pm-stage.sh PATCHED_HERMES_V0232_CHECKOUT}
ARCHIVE=${PNPM_WASM_ARCHIVE:?set PNPM_WASM_ARCHIVE to the verified @pnpm/wasm 12.15.0 archive}
PYTHON=${HERMES_PYTHON:-python3}
PIN="ae2a81ccc00e9b7c06301523e5bb09608397149c"
[[ -d "$UPSTREAM/.git" || -f "$UPSTREAM/.git" ]] || { echo 'input is not a Git checkout' >&2; exit 1; }
[[ "$(git -C "$UPSTREAM" rev-parse HEAD)" == "$PIN" ]] || { echo "input must be exact commit $PIN" >&2; exit 1; }
[[ -f "$ARCHIVE" ]] || { echo "archive not found: $ARCHIVE" >&2; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT
HERMES_HOME="$TMP/home" HERMES_RUNTIME_DIR="$TMP/tools" \
  "$PYTHON" - "$UPSTREAM" "$ARCHIVE" <<'PY'
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
import json
import os
from pathlib import Path
import re
import sys
from threading import Thread

source = Path(sys.argv[1]).resolve()
archive = Path(sys.argv[2]).resolve()
sys.path.insert(0, str(source))
os.chdir(source)

from pm import paths
from pm.install import stage_only
from pm.lock import Lockfile
from pm.package import verify_package_entry
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
    print(f"pnpm WASM PM cross-stage: PASS ({checksum}; {entry.name}; ELF scan passed; no pnpm/Node execution)")
finally:
    server.shutdown()
    server.server_close()
    thread.join(timeout=5)
PY
