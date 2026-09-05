#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/.." && pwd)"
project_file="$repository_root/project.yml"
entitlements_relative_path="LectureBoardAI/Config/LectureBoardAI.entitlements"
entitlements_file="$repository_root/$entitlements_relative_path"

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

require_exact_line() {
  local path="$1"
  local expected_line="$2"
  local count

  count="$(grep -Fxc -- "$expected_line" "$path" || true)"
  [[ "$count" == "1" ]] || fail "Expected exactly one project setting: $expected_line"
}

[[ -f "$project_file" ]] || fail "Missing project definition: project.yml"
[[ -f "$entitlements_file" ]] || fail "Missing entitlement allowlist: $entitlements_relative_path"
command -v plutil >/dev/null 2>&1 || fail "plutil is required to check the permission contract."

require_exact_line \
  "$project_file" \
  "        CODE_SIGN_ENTITLEMENTS: $entitlements_relative_path"
require_exact_line \
  "$project_file" \
  '        INFOPLIST_KEY_NSAppleEventsUsageDescription: "LectureBoard AI uses Automation only after you explicitly start a managed PowerPoint slide show, to read its current slide identity and perform a brief reversible role check."'

plutil -lint "$entitlements_file" >/dev/null \
  || fail "The entitlement allowlist is not a valid property list."

require_true_entitlement() {
  local entitlement_key="$1"
  local key_line=$'\t<key>'"$entitlement_key"'</key>'
  local value_line
  local key_count

  key_count="$(grep -Fxc -- "$key_line" "$entitlements_file" || true)"
  [[ "$key_count" == "1" ]] || fail "Missing or duplicate entitlement: $entitlement_key"
  value_line="$(awk -v key="$key_line" '$0 == key { getline; print; exit }' "$entitlements_file")"
  [[ "$value_line" == $'\t<true/>' ]] \
    || fail "The entitlement must be true: $entitlement_key"
}

require_true_entitlement "com.apple.security.automation.apple-events"
require_true_entitlement "com.apple.security.device.audio-input"

entitlement_key_count="$(grep -Ec '^[[:space:]]*<key>[^<]+</key>[[:space:]]*$' "$entitlements_file")"
[[ "$entitlement_key_count" == "2" ]] \
  || fail "The entitlement allowlist must contain exactly the two approved keys."

printf 'Permission and hardened-runtime entitlement contract passed.\n'
