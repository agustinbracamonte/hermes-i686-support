#!/usr/bin/env bash
# Inspect staged artifacts only; never run signal-cli or read its data directory.
set -euo pipefail

JNI_SO=${1:?Usage: verify-artifacts.sh JNI_SO SIGNAL_CLI_JAR LIBSIGNAL_JAR}
SIGNAL_CLI_JAR=${2:?Usage: verify-artifacts.sh JNI_SO SIGNAL_CLI_JAR LIBSIGNAL_JAR}
LIBSIGNAL_JAR=${3:?Usage: verify-artifacts.sh JNI_SO SIGNAL_CLI_JAR LIBSIGNAL_JAR}
for f in "$JNI_SO" "$SIGNAL_CLI_JAR" "$LIBSIGNAL_JAR"; do test -f "$f" || { echo "missing: $f" >&2; exit 1; }; done
file "$JNI_SO" | grep -Fq 'ELF 32-bit'
file "$JNI_SO" | grep -Fq 'Intel 80386'
readelf -d "$JNI_SO" | grep -Fq 'libc.so.6'
for jar in "$SIGNAL_CLI_JAR" "$LIBSIGNAL_JAR"; do
  jar tf "$jar" | grep -Eq '(^|/)libsignal_jni_(i386|x86)\.so$'
done
sha256sum "$JNI_SO" "$SIGNAL_CLI_JAR" "$LIBSIGNAL_JAR"
echo 'signal-cli-artifacts: PASS'
