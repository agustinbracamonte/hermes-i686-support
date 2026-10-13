#!/usr/bin/env bash
# Build a libsignal JNI artifact in a private staging checkout; never touches Signal data.
set -euo pipefail

: "${LIBSIGNAL_SOURCE:?set LIBSIGNAL_SOURCE to a clean libsignal v0.103.0 checkout}"
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PATCH_DIR=$(cd "$SCRIPT_DIR/../patches" && pwd)
"$SCRIPT_DIR/verify-patched-checkout.sh" "$LIBSIGNAL_SOURCE" v0.103.0 "$PATCH_DIR/libsignal-v0.103.0-i386-protobuf-root.patch" 0effc12567d12d6137e6a97a231b3af7d39feb6745264487692d38c4ed882215
: "${CARGO_BUILD_TARGET:=i686-unknown-linux-gnu}"
: "${CARGO_TARGET_DIR:=${TMPDIR:-/tmp}/hermes-libsignal-cargo-target}"
: "${OUT_DIR:=$PWD/dist/signal-cli-i686}"
: "${JOBS:=1}"

for cmd in cargo rustc sha256sum file readelf; do command -v "$cmd" >/dev/null || { echo "missing command: $cmd" >&2; exit 1; }; done
[[ $(rustc -vV | awk -F': ' '/^host:/{print $2}') == i686-unknown-linux-gnu ]] || { echo 'expected i686 Rust host' >&2; exit 1; }

export CARGO_TARGET_DIR CARGO_BUILD_TARGET
export CARGO_BUILD_JOBS="$JOBS"
export CFLAGS="-msse2 ${CFLAGS:-}"
export CXXFLAGS="-msse2 ${CXXFLAGS:-}"
cd "$LIBSIGNAL_SOURCE"
cargo build --locked --release -p libsignal-jni --target "$CARGO_BUILD_TARGET" -j "$JOBS"
source_so="$CARGO_TARGET_DIR/$CARGO_BUILD_TARGET/release/libsignal_jni.so"
test -f "$source_so"
mkdir -p "$OUT_DIR"
cp -f "$source_so" "$OUT_DIR/libsignal_jni_i386.so"
file "$OUT_DIR/libsignal_jni_i386.so"
readelf -d "$OUT_DIR/libsignal_jni_i386.so" | grep -E 'NEEDED|RPATH|RUNPATH' || true
sha256sum "$OUT_DIR/libsignal_jni_i386.so"
echo 'build-jni: PASS'
