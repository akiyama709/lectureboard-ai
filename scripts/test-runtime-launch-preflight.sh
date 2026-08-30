#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
preflight_script="$script_directory/runtime-launch-preflight.sh"
probe_source="$script_directory/runtime-window-server-probe.swift"
temporary_parent="${TMPDIR:-/tmp}"
temporary_directory="$(mktemp -d "$temporary_parent/lectureboard-runtime-preflight.XXXXXX")"

cleanup() {
  rm -rf -- "$temporary_directory"
}
trap cleanup EXIT

bash -n "$preflight_script"
source "$preflight_script"

env \
  SWIFT_MODULECACHE_PATH="$temporary_directory/swift" \
  CLANG_MODULE_CACHE_PATH="$temporary_directory/clang" \
  xcrun swiftc -typecheck "$probe_source"

if ! runtime_window_server_is_accessible /usr/bin/true; then
  printf 'The runtime launch preflight rejected an accessible WindowServer probe.\n' >&2
  exit 1
fi

if runtime_window_server_is_accessible /usr/bin/false; then
  printf 'The runtime launch preflight accepted an inaccessible WindowServer probe.\n' >&2
  exit 1
fi

probe_cache_root="$temporary_directory/lectureboard-runtime-window-server-probe-cache"
mkdir -p "$probe_cache_root"
direct_status=0
env \
  SWIFT_MODULECACHE_PATH="$probe_cache_root/swift" \
  CLANG_MODULE_CACHE_PATH="$probe_cache_root/clang" \
  xcrun swift "$probe_source" >/dev/null 2>&1 || direct_status=$?

wrapper_status=0
TMPDIR="$temporary_directory" runtime_window_server_is_accessible || wrapper_status=$?

if (( direct_status != wrapper_status )); then
  printf \
    'The default runtime preflight did not preserve the probe status (%d != %d).\n' \
    "$wrapper_status" \
    "$direct_status" >&2
  exit 1
fi

printf 'Runtime launch preflight tests passed.\n'
