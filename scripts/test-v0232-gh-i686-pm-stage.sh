#!/usr/bin/env bash
# Cross-stage the verified GitHub CLI 2.97.0 archive through Hermes PM via
# loopback. This checks the lock hash, extraction and ELF32 guard without exec.
set -euo pipefail

UPSTREAM=${1:?usage: test-v0232-gh-i686-pm-stage.sh PATCHED_HERMES_V0232_CHECKOUT}
ARCHIVE=${GH_I686_ARCHIVE:?set GH_I686_ARCHIVE to the verified gh 2.97.0 Linux 386 tarball}
PYTHON=${HERMES_PYTHON:-python3}
PIN="ae2a81ccc00e9b7c06301523e5bb09608397149c"
[[ -d "$UPSTREAM/.git" || -f "$UPSTREAM/.git" ]] || { echo 'input is not a Git checkout' >&2; exit 1; }
[[ "$(git -C "$UPSTREAM" rev-parse HEAD)" == "$PIN" ]] || { echo "input must be exact commit $PIN" >&2; exit 1; }
[[ -f "$ARCHIVE" ]] || { echo "archive not found: $ARCHIVE" >&2; exit 1; }
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

HERMES_HOME="$TMP/home" HERMES_RUNTIME_DIR="$TMP/tools" \
    "$PYTHON" - "$UPSTREAM" "$ARCHIVE" <<'PY'
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import hashlib
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
from pm.package import machine_matches_binary, verify_package_entry
from pm.registry import get_package

data = archive.read_bytes()
checksum = hashlib.sha256(data).hexdigest()
lock = Lockfile(paths.lockfile_path())
pin = lock.artifacts("gh", "linux-i686")[0]
if lock.version("gh") != "2.97.0" or pin["sha256"] != checksum:
    raise SystemExit("local archive does not match the pinned gh i686 lock row")

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/gh-2.97.0-i686.tar.gz":
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
    local_lock.set_pin("gh", "2.97.0", {
        "linux-i686": {
            "url": f"http://127.0.0.1:{server.server_port}/gh-2.97.0-i686.tar.gz",
            "sha256": checksum,
        }
    })
    import pm.install as install
    install._lockfile = lambda: local_lock
    store = Path(os.environ["HERMES_RUNTIME_DIR"]).resolve()
    paths.store_root = lambda: store

    entry = stage_only("gh", "linux-i686")
    package = get_package("gh")
    binary = entry / "bin" / "gh"
    if not binary.is_file() or machine_matches_binary(binary, "linux-i686") is not True:
        raise SystemExit("PM staged an invalid i686 gh binary")
    reason = verify_package_entry(package, entry, "linux-i686")
    if reason:
        raise SystemExit(f"PM i686 entry verification failed: {reason}")
    print(f"gh PM cross-stage: PASS ({checksum}, {entry.name}; ELF32 validated, not executed)")
finally:
    server.shutdown()
    server.server_close()
    thread.join(timeout=5)
PY
