#!/usr/bin/env bash

runtime_window_server_is_accessible() {
  if (( $# > 0 )); then
    "$1" >/dev/null 2>&1
    return
  fi

  local preflight_directory
  preflight_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
  local probe_source="$preflight_directory/runtime-window-server-probe.swift"
  local probe_cache_root="${TMPDIR:-/tmp}/lectureboard-runtime-window-server-probe-cache"

  [[ -f "$probe_source" ]] || return 1
  command -v xcrun >/dev/null 2>&1 || return 1
  mkdir -p -- "$probe_cache_root" || return 1
  env \
    SWIFT_MODULECACHE_PATH="$probe_cache_root/swift" \
    CLANG_MODULE_CACHE_PATH="$probe_cache_root/clang" \
    xcrun swift "$probe_source" >/dev/null 2>&1
}
