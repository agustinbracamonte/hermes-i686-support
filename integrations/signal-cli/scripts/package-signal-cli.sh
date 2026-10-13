#!/usr/bin/env bash
# Inject an i386 JNI resource into a copied libsignal client JAR and build signal-cli in staging.
set -euo pipefail

: "${SIGNAL_CLI_SOURCE:?set SIGNAL_CLI_SOURCE to a clean signal-cli v0.14.9 checkout}"
: "${UPSTREAM_LIBSIGNAL_JAR:?set UPSTREAM_LIBSIGNAL_JAR}"
: "${JNI_SO:?set JNI_SO to the output of build-jni.sh}"
: "${OUT_DIR:=$PWD/dist/signal-cli-i686}"
: "${JAVA_HOME:?set JAVA_HOME to a private i386 Java 21 runtime}"

for cmd in zip jar sha256sum file; do command -v "$cmd" >/dev/null || { echo "missing command: $cmd" >&2; exit 1; }; done
[[ -x $JAVA_HOME/bin/java ]] || { echo 'JAVA_HOME must contain Java' >&2; exit 1; }
[[ -d $SIGNAL_CLI_SOURCE/.git ]] || { echo 'SIGNAL_CLI_SOURCE must be a source checkout' >&2; exit 1; }
[[ $(git -C "$SIGNAL_CLI_SOURCE" describe --tags --always | sed 's/-dirty$//') == v0.14.9 ]] || { echo 'expected signal-cli tag v0.14.9' >&2; exit 1; }
file "$JNI_SO" | grep -Fq 'ELF 32-bit'
file "$JNI_SO" | grep -Fq 'Intel 80386'
mkdir -p "$OUT_DIR" "$OUT_DIR/resource"
cp -f "$UPSTREAM_LIBSIGNAL_JAR" "$OUT_DIR/libsignal-client-0.103.0-i386.jar"
cp -f "$JNI_SO" "$OUT_DIR/resource/libsignal_jni_x86.so"
cp -f "$JNI_SO" "$OUT_DIR/resource/libsignal_jni_i386.so"
(
  cd "$OUT_DIR/resource"
  zip -q -u ../libsignal-client-0.103.0-i386.jar libsignal_jni_x86.so libsignal_jni_i386.so
)
rm -rf "$OUT_DIR/resource"
jar tf "$OUT_DIR/libsignal-client-0.103.0-i386.jar" | grep -Eq 'libsignal_jni_(x86|i386)\.so'
cd "$SIGNAL_CLI_SOURCE"
JAVA_HOME="$JAVA_HOME" ./gradlew :lib:jar fatJar -Plibsignal_client_path="$OUT_DIR/libsignal-client-0.103.0-i386.jar"
cp -f build/libs/signal-cli-fat-0.14.9.jar "$OUT_DIR/signal-cli-i386.jar"
sha256sum "$OUT_DIR/libsignal-client-0.103.0-i386.jar" "$OUT_DIR/signal-cli-i386.jar"
echo 'package-signal-cli: PASS (run verify-artifacts.sh; perform native-load test separately)'
