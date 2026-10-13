#!/usr/bin/env bash
# Read-only checks for a staged signal-cli i386 build. Does not touch account data.
set -euo pipefail

: "${JAVA_BIN:=java}"
: "${RUSTC_BIN:=rustc}"
: "${CMAKE_BIN:=cmake}"

for command in "$JAVA_BIN" "$RUSTC_BIN" "$CMAKE_BIN" file readelf sha256sum; do
  command -v "$command" >/dev/null || { echo "missing command: $command" >&2; exit 1; }
done
java_arch=$("$JAVA_BIN" -XshowSettings:properties -version 2>&1 | awk -F'= ' '/^[[:space:]]*os.arch =/{print $2; exit}')
rust_host=$("$RUSTC_BIN" -Vv | awk -F': ' '/^host:/{print $2; exit}')
cmake_version=$("$CMAKE_BIN" --version | awk 'NR==1{print $3}')
printf 'java_arch=%s\nrust_host=%s\ncmake_version=%s\n' "$java_arch" "$rust_host" "$cmake_version"
[[ $java_arch == i386 || $java_arch == i686 || $java_arch == x86 ]] || { echo 'expected an i386 Java runtime' >&2; exit 1; }
[[ $rust_host == i686-unknown-linux-gnu ]] || { echo 'expected Rust host i686-unknown-linux-gnu' >&2; exit 1; }
echo 'signal-cli-preflight: PASS'
