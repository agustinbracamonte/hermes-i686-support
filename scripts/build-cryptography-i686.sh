#!/usr/bin/env bash
# Build a pinned cryptography wheel for an i686 Python in an isolated workspace.
# It never installs into an existing Hermes environment.
set -euo pipefail

: "${PYTHON_BIN:=python3}"
: "${WORKDIR:=$PWD/.work/cryptography-i686}"
: "${CRYPTOGRAPHY_VERSION:=50.0.0}"
: "${CRYPTOGRAPHY_SDIST_SHA256:?set CRYPTOGRAPHY_SDIST_SHA256}"
: "${OPENSSL_VERSION:=3.5.7}"
: "${OPENSSL_SHA256:?set OPENSSL_SHA256}"
: "${JOBS:=1}"

for cmd in curl tar make gcc perl sha256sum "$PYTHON_BIN"; do command -v "$cmd" >/dev/null || { echo "missing command: $cmd" >&2; exit 1; }; done
bits=$("$PYTHON_BIN" -c 'import struct; print(struct.calcsize("P") * 8)')
[[ $bits == 32 ]] || { echo "refusing: PYTHON_BIN is ${bits}-bit, not 32-bit" >&2; exit 1; }
command -v rustup >/dev/null || { echo 'missing rustup' >&2; exit 1; }

mkdir -p "$WORKDIR"/{downloads,src,prefix,dist,cargo-target}
cd "$WORKDIR"
download() { local url=$1 out=$2 sha=$3; if [[ ! -f $out ]]; then curl --fail --location --retry 3 --output "$out.tmp" "$url"; mv "$out.tmp" "$out"; fi; printf '%s  %s\n' "$sha" "$out" | sha256sum -c -; }
download "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" "downloads/openssl-${OPENSSL_VERSION}.tar.gz" "$OPENSSL_SHA256"
download "https://files.pythonhosted.org/packages/source/c/cryptography/cryptography-${CRYPTOGRAPHY_VERSION}.tar.gz" "downloads/cryptography-${CRYPTOGRAPHY_VERSION}.tar.gz" "$CRYPTOGRAPHY_SDIST_SHA256"

if [[ ! -x prefix/openssl/bin/openssl ]]; then
  rm -rf "src/openssl-${OPENSSL_VERSION}"
  tar -xzf "downloads/openssl-${OPENSSL_VERSION}.tar.gz" -C src
  (cd "src/openssl-${OPENSSL_VERSION}" && ./Configure linux-x86 --prefix="$WORKDIR/prefix/openssl" no-shared && make -j"$JOBS" && make install_sw)
fi

export RUSTUP_TOOLCHAIN=stable-i686-unknown-linux-gnu
export OPENSSL_DIR="$WORKDIR/prefix/openssl" OPENSSL_STATIC=1
export CC=gcc CXX=g++ CFLAGS='-m32 -fPIC' CXXFLAGS='-m32 -fPIC'
export CARGO_TARGET_I686_UNKNOWN_LINUX_GNU_LINKER=gcc
export CARGO_BUILD_TARGET=i686-unknown-linux-gnu CARGO_BUILD_JOBS="$JOBS"
export CARGO_TARGET_DIR="$WORKDIR/cargo-target"

if [[ ! -d venv ]]; then "$PYTHON_BIN" -m venv venv; fi
# The build venv must provide both the Python package and executable on PATH.
venv/bin/python -m pip install --upgrade pip setuptools wheel maturin
PATH="$WORKDIR/venv/bin:$PATH" venv/bin/python -m pip wheel --no-deps --no-binary cryptography --no-build-isolation --wheel-dir dist "downloads/cryptography-${CRYPTOGRAPHY_VERSION}.tar.gz"
find dist -maxdepth 1 -type f -name 'cryptography-*.whl' -print
echo 'build: PASS'
