#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/.." && pwd)"
project_file="$repository_root/project.yml"
info_plist_relative_path="LectureBoardAI/Config/Info.plist"
info_plist_file="$repository_root/$info_plist_relative_path"
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
[[ -f "$info_plist_file" ]] || fail "Missing application property list: $info_plist_relative_path"
[[ -f "$entitlements_file" ]] || fail "Missing entitlement allowlist: $entitlements_relative_path"
command -v plutil >/dev/null 2>&1 || fail "plutil is required to check the permission contract."

require_exact_line \
  "$project_file" \
  "        GENERATE_INFOPLIST_FILE: NO"
require_exact_line \
  "$project_file" \
  "        INFOPLIST_FILE: $info_plist_relative_path"
require_exact_line \
  "$project_file" \
  "        CODE_SIGN_ENTITLEMENTS: $entitlements_relative_path"
require_exact_line \
  "$project_file" \
  '        LECTUREBOARD_RELEASE_COMMIT: UNBOUND'
require_exact_line \
  "$project_file" \
  '        LECTUREBOARD_RELEASE_TAG: UNBOUND'
require_exact_line \
  "$project_file" \
  '        LECTUREBOARD_RELEASE_TAG_OBJECT: UNBOUND'

plutil -lint "$info_plist_file" >/dev/null \
  || fail "The application property list is not valid."
plutil -lint "$entitlements_file" >/dev/null \
  || fail "The entitlement allowlist is not a valid property list."

require_plist_string() {
  local key="$1"
  local expected="$2"
  local actual

  actual="$(plutil -extract "$key" raw -o - "$info_plist_file" 2>/dev/null)" \
    || fail "Missing application property-list key: $key"
  [[ "$actual" == "$expected" ]] \
    || fail "Unexpected application property-list value: $key"
}

if plutil -extract NSAppleEventsUsageDescription raw -o - "$info_plist_file" >/dev/null 2>&1; then
  fail "NSAppleEventsUsageDescription must be absent from the visual-only application."
fi
require_plist_string \
  "NSMicrophoneUsageDescription" \
  "LectureBoard AI uses the microphone to transcribe the lecturer and identify material that may be useful to place on the board."
require_plist_string \
  "NSScreenCaptureUsageDescription" \
  "LectureBoard AI observes the selected PowerPoint window to identify slide content and unused space."
require_plist_string \
  "NSSpeechRecognitionUsageDescription" \
  "LectureBoard AI uses speech recognition to create grounded lecture-board annotations."
require_plist_string "LectureBoardReleaseCommit" '$(LECTUREBOARD_RELEASE_COMMIT)'
require_plist_string "LectureBoardReleaseTag" '$(LECTUREBOARD_RELEASE_TAG)'
require_plist_string "LectureBoardReleaseTagObject" '$(LECTUREBOARD_RELEASE_TAG_OBJECT)'

[[ "$(plutil -extract NSHighResolutionCapable raw -o - "$info_plist_file" 2>/dev/null)" == "true" ]] \
  || fail "NSHighResolutionCapable must be true."

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

require_true_entitlement "com.apple.security.device.audio-input"

if grep -Fq '<key>com.apple.security.automation.apple-events</key>' \
  "$entitlements_file"; then
  fail "The Apple Events entitlement must be absent from the visual-only application."
fi

entitlement_key_count="$(grep -Ec '^[[:space:]]*<key>[^<]+</key>[[:space:]]*$' "$entitlements_file")"
[[ "$entitlement_key_count" == "1" ]] \
  || fail "The entitlement allowlist must contain exactly the approved audio-input key."

printf 'Permission and hardened-runtime entitlement contract passed.\n'
