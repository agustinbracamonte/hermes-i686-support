#!/usr/bin/env bash
# Build real ELF32 runtimes in an ephemeral Debian 11 i386 chroot on GitHub-hosted CI.
# This intentionally refuses all local/self-hosted environments, including the B10.
set -euo pipefail

readonly DEBIAN_SNAPSHOT=20260912T092708Z
readonly CLANG_VERSION='1:19.1.7-3~deb11u1'
readonly CLANG_SHA256=d52c7089346ebc4616d3e9e3bbee6eb0848455a9abb777746fdd32812ce981d3

die() {
  printf 'v0.23.2 i686 hosted build: ERROR: %s\n' "$*" >&2
  exit 1
}

[[ "$(printenv GITHUB_ACTIONS 2>/dev/null || true)" == true ]] || die 'only GitHub Actions is allowed'
[[ "$(printenv RUNNER_ENVIRONMENT 2>/dev/null || true)" == github-hosted ]] || die 'self-hosted runners are not allowed'
[[ "$(printenv RUNNER_ARCH 2>/dev/null || true)" == X64 ]] || die 'requires an ephemeral GitHub-hosted X64 runner'
[[ "$(uname -m)" == x86_64 ]] || die 'expected an x86_64 Linux kernel with IA32 compatibility'
[[ $# == 2 ]] || die 'usage: ci-v0232-i686-runtime-build.sh SOURCE_ROOT BUILD_ROOT'

SOURCE_ROOT=$(cd "$1" && pwd)
BUILD_ROOT=$(mkdir -p "$2" && cd "$2" && pwd)
[[ "$SOURCE_ROOT" != *" "* && "$BUILD_ROOT" != *" "* ]] || die 'workspace paths must not contain spaces'
[[ -f "$SOURCE_ROOT/scripts/build-cpython-v0232-i686.sh" ]] || die 'source checkout is incomplete'

readonly WORK_ROOT="$(dirname "$BUILD_ROOT")/v0232-i686-hosted"
readonly ROOTFS="$WORK_ROOT/rootfs"
mkdir -p "$WORK_ROOT"

command -v sudo >/dev/null 2>&1 || die 'sudo is required on the GitHub-hosted runner'
command -v debootstrap >/dev/null 2>&1 || {
  sudo apt-get update
  sudo apt-get install -y --no-install-recommends debootstrap debian-archive-keyring
}

[[ ! -e "$ROOTFS" ]] || die "refusing to reuse an existing rootfs: $ROOTFS"
mkdir -p "$ROOTFS"
sudo debootstrap --arch=i386 --variant=minbase --include=ca-certificates,debian-archive-keyring \
  bullseye "$ROOTFS" "https://snapshot.debian.org/archive/debian/$DEBIAN_SNAPSHOT"
sudo rm -f "$ROOTFS/etc/resolv.conf"
sudo cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

sudo tee "$ROOTFS/etc/apt/sources.list" >/dev/null <<EOF
deb [check-valid-until=no] https://snapshot.debian.org/archive/debian/$DEBIAN_SNAPSHOT bullseye main
deb [check-valid-until=no] https://archive.debian.org/debian-security bullseye-security main
EOF

sudo mkdir -p "$ROOTFS/work/source" "$ROOTFS/work/build"
cleanup() {
  sudo umount -R "$ROOTFS/sys" 2>/dev/null || true
  sudo umount -R "$ROOTFS/dev" 2>/dev/null || true
  sudo umount "$ROOTFS/proc" 2>/dev/null || true
  sudo umount "$ROOTFS/work/build" 2>/dev/null || true
  sudo umount "$ROOTFS/work/source" 2>/dev/null || true
}
trap cleanup EXIT

sudo mount --bind "$SOURCE_ROOT" "$ROOTFS/work/source"
sudo mount -o remount,bind,ro "$ROOTFS/work/source"
sudo mount --bind "$BUILD_ROOT" "$ROOTFS/work/build"
sudo mount -t proc proc "$ROOTFS/proc"
sudo mount --rbind /dev "$ROOTFS/dev"
sudo mount --make-rslave "$ROOTFS/dev"
sudo mount --rbind /sys "$ROOTFS/sys"
sudo mount --make-rslave "$ROOTFS/sys"

sudo chroot "$ROOTFS" /usr/bin/env "CLANG_VERSION=$CLANG_VERSION" "CLANG_SHA256=$CLANG_SHA256" \
  /bin/bash -euo pipefail -s <<'CHROOT'
export DEBIAN_FRONTEND=noninteractive
export LC_ALL=C

test "$(dpkg --print-architecture)" = i386
apt-get -o Acquire::Check-Valid-Until=false update
apt-get -o Acquire::Check-Valid-Until=false --yes --no-install-recommends --download-only install \
  build-essential ca-certificates clang-19="$CLANG_VERSION" curl git openssl pkg-config python3 tar \
  libbz2-dev libexpat1-dev libffi-dev libgdbm-compat-dev libgdbm-dev liblzma-dev \
  libncursesw5-dev libreadline-dev libsqlite3-dev libssl-dev uuid-dev \
  xz-utils zlib1g-dev

clang_deb=/var/cache/apt/archives/clang-19_19.1.7-3~deb11u1_i386.deb
test -f "$clang_deb"
actual_clang_sha=$(sha256sum "$clang_deb" | awk '{print $1}')
test "$actual_clang_sha" = "$CLANG_SHA256"
apt-get -o Acquire::Check-Valid-Until=false --yes --no-install-recommends --no-download install \
  build-essential ca-certificates clang-19="$CLANG_VERSION" curl git openssl pkg-config python3 tar \
  libbz2-dev libexpat1-dev libffi-dev libgdbm-compat-dev libgdbm-dev liblzma-dev \
  libncursesw5-dev libreadline-dev libsqlite3-dev libssl-dev uuid-dev \
  xz-utils zlib1g-dev

clang_package_version=$(dpkg-query -W -f='${Version}' clang-19)
test "$clang_package_version" = "$CLANG_VERSION"
libc_version=$(dpkg-query -W -f='${Version}' libc6)
dpkg --compare-versions "$libc_version" ge 2.29
clang_elf=$(readlink -f "$(command -v clang-19)")
readelf -h "$clang_elf" | awk '
  /Class:/ { class=$2 }
  /Data:/ { data=$0 }
  /Machine:/ { machine=$0 }
  END { if (class != "ELF32" || data !~ /little endian/ || machine !~ /Intel 80386/) exit 1 }
'
clang_target=$(clang-19 -dumpmachine)
case "$clang_target" in
  i[3-6]86*-linux*) ;;
  *) printf 'unexpected Clang target: %s\n' "$clang_target" >&2; exit 1 ;;
esac
git config --global --add safe.directory /work/source
mkdir -p /work/build/v0232-i686/results
printf 'clang_package_version=%s\nclang_package_sha256=%s\ndebian_snapshot=%s\nlibc6=%s\nclang_target=%s\n' \
  "$clang_package_version" "$actual_clang_sha" 20260912T092708Z "$libc_version" "$clang_target" \
  >/work/build/v0232-i686/results/system-packages.txt
dpkg-query -W -f='${binary:Package}=${Version}\n' \
  build-essential binutils clang-19 gcc g++ libc6 make \
  >>/work/build/v0232-i686/results/system-packages.txt

cd /work/source
export HERMES_I686_BUILD_ROOT=/work/build/v0232-i686
bash scripts/build-cpython-v0232-i686.sh --preflight-only
bash scripts/build-cpython-v0232-i686.sh
CC=clang-19 CXX=clang++-19 bash scripts/build-node-v0232-i686.sh --preflight-only
CC=clang-19 CXX=clang++-19 bash scripts/build-node-v0232-i686.sh
NODE_BIN=/work/build/v0232-i686/prefix/node-26.12.1/bin/node \
  bash scripts/verify-v0232-pnpm-wasm.sh --require-ia32
CHROOT

for manifest in \
  "$BUILD_ROOT/v0232-i686/results/system-packages.txt" \
  "$BUILD_ROOT/v0232-i686/results/cpython-3.14.9.txt" \
  "$BUILD_ROOT/v0232-i686/results/node-26.12.1.txt"; do
  [[ -s "$manifest" ]] || die "missing build evidence: $manifest"
  cat "$manifest"
done

if [[ -n "$(printenv GITHUB_STEP_SUMMARY 2>/dev/null || true)" ]]; then
  {
    printf '# Hermes v0.23.2 native i686 runtime build\n\n'
    printf 'Built serially in a disposable Debian 11 i386 chroot on a GitHub-hosted x86_64 runner. No build binaries were uploaded. This does not validate B10 memory headroom or Púlsar staging behavior.\n\n'
    for manifest in \
      "$BUILD_ROOT/v0232-i686/results/system-packages.txt" \
      "$BUILD_ROOT/v0232-i686/results/cpython-3.14.9.txt" \
      "$BUILD_ROOT/v0232-i686/results/node-26.12.1.txt"; do
      printf '~~~text\n'
      cat "$manifest"
      printf '~~~\n\n'
    done
    printf 'The pnpm WASM verification ran against Node with process.arch=ia32 and completed its offline local-file install.\n'
  } >>"$(printenv GITHUB_STEP_SUMMARY)"
fi

cleanup
trap - EXIT
sudo rm -rf -- "$ROOTFS"
printf 'v0.23.2 i686 hosted runtime build: PASS\n'
