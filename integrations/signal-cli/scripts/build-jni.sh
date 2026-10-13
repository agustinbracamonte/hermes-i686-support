#!/usr/bin/env bash
# Build a libsignal JNI artifact in a private staging checkout; never touches Signal data.
set -euo pipefail

: "${LIBSIGNAL_SOURCE:?set LIBSIGNAL_SOURCE to a clean libsignal v0.103.0 checkout}"
: "${CARGO_BUILD_TARGET:=i686-unknown-linux-gnu}"
: "${CARGO_TARGET_DIR:=$LIBSIGNAL_SOURCE/target-i686}"
: "${OUT_DIR:=$PWD/dist/signal-cli-i686}"
: "${JOBS:=1}"

for cmd in cargo rustc sha256sum file readelf; do command -v "$cmd" >/dev/null || { echo "missing command: $cmd" >&2; exit 1; }; done
[[ -d $LIBSIGNAL_SOURCE/.git ]] || { echo 'LIBSIGNAL_SOURCE must be a source checkout' >&2; exit 1; }
[[ $(git -C "$LIBSIGNAL_SOURCE" describe --tags --always | sed 's/-dirty$//') == v0.103.0 ]] || { echo 'expected libsignal tag v0.103.0' >&2; exit 1; }
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
