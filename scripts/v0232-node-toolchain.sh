#!/usr/bin/env bash
# Compiler-family checks for the pinned Node 26 Linux build requirements.

v0232_node_compiler_info() {
  local compiler=$1 first_line family version target
  command -v "$compiler" >/dev/null 2>&1 || v0232_die "missing compiler: $compiler"
  first_line=$("$compiler" --version 2>/dev/null | sed -n '1p') || v0232_die "$compiler cannot report its version"
  [[ -n "$first_line" ]] || v0232_die "$compiler returned an empty version line"

  if [[ "$first_line" == *[Cc][Ll][Aa][Nn][Gg]* ]]; then
    family=clang
    version=$(printf '%s\n' "$first_line" | sed -nE 's/.*[Cc]lang version ([0-9]+(\.[0-9]+){1,2}).*/\1/p')
    [[ -n "$version" ]] || v0232_die "cannot parse Clang version from: $first_line"
  else
    family=gcc
    version=$("$compiler" -dumpfullversion -dumpversion 2>/dev/null) || v0232_die "$compiler cannot report a GCC version"
    [[ "$version" =~ ^[0-9]+(\.[0-9]+){1,2}$ ]] || v0232_die "invalid GCC version from $compiler: $version"
  fi

  target=$("$compiler" -dumpmachine 2>/dev/null) || v0232_die "$compiler cannot report its target triple"
  [[ "$target" =~ ^i[3-6]86(-|$) && "$target" == *linux* ]] || \
    v0232_die "$compiler targets '$target', not Linux i686"
  printf '%s %s %s\n' "$family" "$version" "$target"
}

v0232_node_version_at_least() {
  local minimum=$1 actual=$2 first
  first=$(printf '%s\n' "$minimum" "$actual" | sort -V | head -n 1)
  [[ "$first" == "$minimum" ]]
}

v0232_node_check_compiler_pair() {
  local cc=$1 cxx=$2 cc_info cxx_info cc_family cc_version cc_target cxx_family cxx_version cxx_target minimum label
  cc_info=$(v0232_node_compiler_info "$cc") || return 1
  cxx_info=$(v0232_node_compiler_info "$cxx") || return 1
  read -r cc_family cc_version cc_target <<<"$cc_info"
  read -r cxx_family cxx_version cxx_target <<<"$cxx_info"
  [[ "$cc_family" == "$cxx_family" ]] || v0232_die "C/C++ compiler families differ ($cc_family vs $cxx_family)"
  [[ "$cc_target" == "$cxx_target" ]] || v0232_die "C/C++ compiler targets differ ($cc_target vs $cxx_target)"
  [[ "$cc_version" == "$cxx_version" ]] || v0232_die "C/C++ compiler versions differ ($cc_version vs $cxx_version)"

  if [[ "$cc_family" == clang ]]; then
    minimum=19.1
    label='Clang >=19.1'
  else
    minimum=13.2
    label='GCC >=13.2'
  fi
  v0232_node_version_at_least "$minimum" "$cc_version" || \
    v0232_die "Node 26 upstream requires $label (found $cc_version)"
  printf '%s %s %s\n' "$cc_family" "$cc_version" "$cc_target"
}
