#!/usr/bin/env bash
# Build the pinned cryptography wheel in an isolated workspace only.
set -euo pipefail
: "${PYTHON_BIN:=python3}"; : "${WORKDIR:=$PWD/.work/cryptography-i686}"
: "${CRYPTOGRAPHY_VERSION:=50.0.0}"; : "${CRYPTOGRAPHY_SDIST_SHA256:?set CRYPTOGRAPHY_SDIST_SHA256}"
: "${OPENSSL_VERSION:=3.5.7}"; : "${OPENSSL_SHA256:?set OPENSSL_SHA256}"; : "${JOBS:=1}"
: "${RUST_VERSION:=1.97.1}"; : "${CMAKE_VERSION:=3.22.6}"; : "${MATURIN_VERSION:=1.14.1}"
: "${GCC_VERSION:=10.2.1}"; : "${MAKE_VERSION:=4.3}"; : "${PERL_VERSION:=5.32.1}"
[[ $CRYPTOGRAPHY_VERSION == 50.0.0 && $OPENSSL_VERSION == 3.5.7 ]] || { echo 'unsupported release version pins' >&2; exit 1; }
for cmd in curl tar make gcc perl sha256sum rustup rustc cargo "$PYTHON_BIN"; do command -v "$cmd" >/dev/null || { echo "missing command: $cmd" >&2; exit 1; }; done
bits=$("$PYTHON_BIN" -c 'import struct;print(struct.calcsize("P")*8)'); [[ $bits == 32 ]] || { echo "Python must be 32-bit (found $bits)" >&2; exit 1; }
pyversion=$("$PYTHON_BIN" -c 'import platform,sys; print(f"{platform.python_implementation()} {sys.version_info.major}.{sys.version_info.minor}")')
[[ $pyversion == 'CPython 3.11' ]] || { echo "Python must be CPython 3.11 (found $pyversion)" >&2; exit 1; }
export RUSTUP_TOOLCHAIN=stable-i686-unknown-linux-gnu
rust_host=$(rustc -vV | awk -F': ' '/^host:/{print $2}')
[[ $rust_host == i686-unknown-linux-gnu ]] || { echo "Rust host must be i686-unknown-linux-gnu (found $rust_host)" >&2; exit 1; }
rust_version=$(rustc --version | awk '{print $2}'); [[ $rust_version == "$RUST_VERSION" ]] || { echo "Rust must be $RUST_VERSION (found $rust_version)" >&2; exit 1; }
cmake_version=$(cmake --version 2>/dev/null | awk 'NR==1 {print $3}'); [[ $cmake_version == "$CMAKE_VERSION" ]] || { echo "CMake must be $CMAKE_VERSION (found ${cmake_version:-missing})" >&2; exit 1; }
gcc_version=$(gcc -dumpfullversion -dumpversion); [[ $gcc_version == "$GCC_VERSION" ]] || { echo "GCC must be $GCC_VERSION (found $gcc_version)" >&2; exit 1; }
make_version=$(make --version | awk 'NR==1 {print $3}'); [[ $make_version == "$MAKE_VERSION" ]] || { echo "GNU Make must be $MAKE_VERSION (found $make_version)" >&2; exit 1; }
perl_version=$(perl -e 'printf "%vd", $^V'); [[ $perl_version == "$PERL_VERSION" ]] || { echo "Perl must be $PERL_VERSION (found $perl_version)" >&2; exit 1; }
mkdir -p "$WORKDIR"/{downloads,src,prefix,dist,cargo-target}; cd "$WORKDIR"
download() { local url=$1 out=$2 sha=$3; if [[ ! -f $out ]]; then curl --fail --location --retry 3 --output "$out.tmp" "$url"; mv "$out.tmp" "$out"; fi; printf '%s  %s\n' "$sha" "$out" | sha256sum -c -; }
download "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz" "downloads/openssl-${OPENSSL_VERSION}.tar.gz" "$OPENSSL_SHA256"
download "https://files.pythonhosted.org/packages/de/41/6cbdcf9142d00fe82836fbb51e503e58088575cf7a0fe1dbff6695bf0840/cryptography-${CRYPTOGRAPHY_VERSION}.tar.gz" "downloads/cryptography-${CRYPTOGRAPHY_VERSION}.tar.gz" "$CRYPTOGRAPHY_SDIST_SHA256"
if [[ ! -x prefix/openssl/bin/openssl ]]; then
 tar -xzf "downloads/openssl-${OPENSSL_VERSION}.tar.gz" -C src
 # Exact OpenSSL Configure flags: linux-x86 -m32 -fPIC; static libraries only; disable tests and legacy protocols.
 (cd "src/openssl-${OPENSSL_VERSION}" && ./Configure linux-x86 -m32 -fPIC --prefix="$WORKDIR/prefix/openssl" no-shared no-tests no-ssl3 no-weak-ssl-ciphers && make -j"$JOBS" && make install_sw)
fi
export OPENSSL_DIR="$WORKDIR/prefix/openssl" OPENSSL_STATIC=1
export CC=gcc CXX=g++ CFLAGS='-m32 -fPIC' CXXFLAGS='-m32 -fPIC' CARGO_TARGET_I686_UNKNOWN_LINUX_GNU_LINKER=gcc
export CARGO_BUILD_TARGET=i686-unknown-linux-gnu CARGO_BUILD_JOBS="$JOBS" CARGO_TARGET_DIR="$WORKDIR/cargo-target"
[[ -d venv ]] || "$PYTHON_BIN" -m venv venv
venv/bin/python -m pip install --disable-pip-version-check "pip==25.0.1" "setuptools==78.1.0" "wheel==0.45.1" "maturin==${MATURIN_VERSION}"
PATH="$WORKDIR/venv/bin:$PATH" venv/bin/python -m pip wheel --no-deps --no-binary cryptography --no-build-isolation --wheel-dir dist "downloads/cryptography-${CRYPTOGRAPHY_VERSION}.tar.gz"
shopt -s nullglob; wheels=(dist/cryptography-*.whl); (( ${#wheels[@]} == 1 )) || { echo 'expected exactly one cryptography wheel' >&2; exit 1; }
echo "built=${wheels[0]}"; echo 'build: PASS'
