#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
CI_SCRIPT="$ROOT/scripts/ci-v0232-ffmpeg-i686.sh"
WORKFLOW="$ROOT/.github/workflows/v0232-ffmpeg-i686.yml"
TMP=$(mktemp -d)
trap 'rm -rf -- "$TMP"' EXIT

bash -n "$CI_SCRIPT"
bash -n "$ROOT/scripts/build-v0232-ffmpeg-i686.sh"
bash -n "$ROOT/scripts/verify-v0232-ffmpeg-i686.sh"
help=$("$CI_SCRIPT" --help)
[[ "$help" == *'Debian 11 i386'* && "$help" == *'never uploads artifacts'* ]]

if env GITHUB_ACTIONS=false RUNNER_ENVIRONMENT=self-hosted RUNNER_ARCH=X64 \
  RUNNER_TEMP="$TMP" "$CI_SCRIPT" "$ROOT" "$TMP/build" >"$TMP/local.log" 2>&1; then
  printf 'FFmpeg CI helper unexpectedly accepted a non-GitHub Actions environment\n' >&2
  exit 1
fi
grep -Fq 'only GitHub Actions is allowed' "$TMP/local.log"
[[ ! -e "$TMP/build" ]]

grep -Fq 'name: v0.23.2 FFmpeg i686 build and smoke' "$WORKFLOW"
grep -Fq 'branches:' "$WORKFLOW"
grep -Fq -- '- codex/v0232-ffmpeg-ci' "$WORKFLOW"
grep -Fq 'runs-on: ubuntu-24.04' "$WORKFLOW"
grep -Fq 'timeout-minutes: 360' "$WORKFLOW"
grep -Fq 'permissions: {}' "$WORKFLOW"
grep -Fq "github.repository == 'agustinbracamonte/hermes-i686-support'" "$WORKFLOW"
grep -Fq 'GITHUB_SHA' "$WORKFLOW"
grep -Fq 'ci-v0232-ffmpeg-i686.sh' "$WORKFLOW"
if grep -Eiq 'upload-artifact|create-release|gh release|secrets\.|cache@|larger runner|self-hosted' "$WORKFLOW"; then
  printf 'workflow must not publish artifacts, use secrets/caches, or use billed larger/self-hosted runners\n' >&2
  exit 1
fi

grep -Fq 'snapshot.debian.org/archive/debian/$DEBIAN_SNAPSHOT' "$CI_SCRIPT"
grep -Fq 'results/ffmpeg-9.0.1/ci-packages.txt' "$CI_SCRIPT"
if grep -Fq 'results/ci-packages.txt' "$CI_SCRIPT"; then
  printf 'CI dependency manifest must use the same versioned result root as the builder\n' >&2
  exit 1
fi
grep -Fq 'sudo mount -o remount,bind,ro "$ROOTFS/work/source"' "$CI_SCRIPT"
if grep -Fq 'sudo mount --remount' "$CI_SCRIPT"; then
  printf 'hosted chroot bind remount must use mount -o syntax\n' >&2
  exit 1
fi
grep -Fq 'make -j1' "$ROOT/scripts/build-v0232-ffmpeg-i686.sh"
grep -Fq 'QEMU' "$ROOT/scripts/verify-v0232-ffmpeg-i686.sh"
grep -Fq 'verify-v0232-ffmpeg-i686.sh --runtime' "$CI_SCRIPT"
grep -Fq 'sudo rm -rf -- "$BUILD_ROOT"' "$CI_SCRIPT"
grep -Fq 'No artifact upload, release, cache, or package publication is configured.' "$CI_SCRIPT"

printf 'v0.23.2 FFmpeg hosted i686 CI guards: PASS\n'
