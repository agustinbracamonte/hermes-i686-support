#!/usr/bin/env bash
# Shared guard/checkpoint helpers for the v0.23.2 i686 source builds.

v0232_die() {
  printf 'v0.23.2 i686 build: ERROR: %s\n' "$*" >&2
  exit 1
}

v0232_log() {
  printf 'v0.23.2 i686 build: %s\n' "$*"
}

v0232_need() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || v0232_die "missing required tool: $tool"
  done
}

v0232_sha256() {
  sha256sum "$1" | awk '{print $1}'
}

v0232_elf_identity() {
  local path=$1
  [[ -r "$path" ]] || return 1
  readelf -h "$path" 2>/dev/null | awk '
    /Class:/ { class=$2 }
    /Data:/ { data=$0 }
    /Machine:/ { machine=$0 }
    END {
      if (class == "ELF32" && data ~ /little endian/ && machine ~ /Intel 80386/) {
        print "ELF32 little-endian Intel 80386"
        exit 0
      }
      exit 1
    }
  '
}

v0232_assert_i686_elf() {
  local path=$1 identity
  identity=$(v0232_elf_identity "$path") || v0232_die "$path is not ELF32 little-endian EM_386"
  v0232_log "verified $path: $identity"
}

v0232_assert_i686_process() {
  local executable class machine
  executable="/proc/$$/exe"
  [[ -e "$executable" ]] || v0232_die "cannot identify this build shell through $executable"
  readelf -h "$executable" >/dev/null 2>&1 || v0232_die "cannot read the build shell ELF header"
  class=$(readelf -h "$executable" | awk '/Class:/ { print $2; exit }')
  machine=$(readelf -h "$executable" | awk '/Machine:/ { sub(/^[[:space:]]*Machine:[[:space:]]*/, ""); print; exit }')
  [[ "$class" == ELF32 && "$machine" == 'Intel 80386' ]] || \
    v0232_die "build must run in an i686 userspace process (saw $class $machine; kernel uname is intentionally ignored)"
}

v0232_assert_i686_compiler() {
  local cc=$1 target
  target=$("$cc" -dumpmachine 2>/dev/null) || v0232_die "$cc cannot report its target triple"
  [[ "$target" =~ ^i[3-6]86(-|$) ]] || v0232_die "$cc targets '$target', not Linux i686"
}

v0232_fingerprint() {
  printf '%s\n' "$*" | sha256sum | awk '{print $1}'
}

v0232_checkpoint() {
  local state=$1 step=$2 fingerprint=$3 expected=$4 marker current
  shift 4
  marker="$state/$step.sha256"
  if [[ -f "$marker" ]]; then
    current=$(<"$marker")
    [[ "$current" == "$fingerprint" ]] || \
      v0232_die "checkpoint '$step' does not match this source/toolchain/configuration; use a new build root"
    [[ -e "$expected" ]] || v0232_die "checkpoint '$step' exists but its output is missing: $expected"
    v0232_log "checkpoint: $step already complete"
    return 0
  fi

  v0232_log "starting checkpoint: $step"
  "$@"
  [[ -e "$expected" ]] || v0232_die "step '$step' completed without expected output: $expected"
  printf '%s\n' "$fingerprint" >"$marker.tmp"
  mv -f -- "$marker.tmp" "$marker"
  v0232_log "checkpoint saved: $step"
}

v0232_build_lock() {
  local state=$1
  exec 9>"$state/build.lock"
  flock -n 9 || v0232_die "another build is using this checkpoint directory"
}

v0232_require_serial() {
  [[ "${JOBS:-1}" == 1 ]] || v0232_die "serial builds only; set JOBS=1 or leave it unset"
}
