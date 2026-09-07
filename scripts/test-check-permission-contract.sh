#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/.." && pwd)"
fixture_parent="$(mktemp -d "${TMPDIR:-/tmp}/lectureboard-permission-contract.XXXXXX")"
trap 'rm -rf "$fixture_parent"' EXIT

make_fixture() {
  local destination="$1"

  mkdir -p "$destination/scripts" "$destination/LectureBoardAI/Config"
  cp "$repository_root/scripts/check-permission-contract.sh" "$destination/scripts/"
  cp "$repository_root/project.yml" "$destination/project.yml"
  cp "$repository_root/LectureBoardAI/Config/Info.plist" \
    "$destination/LectureBoardAI/Config/Info.plist"
  cp "$repository_root/LectureBoardAI/Config/LectureBoardAI.entitlements" \
    "$destination/LectureBoardAI/Config/LectureBoardAI.entitlements"
}

expect_failure() {
  local fixture="$1"
  local label="$2"

  if "$fixture/scripts/check-permission-contract.sh" >/dev/null 2>&1; then
    printf 'Permission-contract check accepted %s.\n' "$label" >&2
    exit 1
  fi
}

valid_fixture="$fixture_parent/valid"
make_fixture "$valid_fixture"
"$valid_fixture/scripts/check-permission-contract.sh" >/dev/null

added_description="$fixture_parent/added-apple-events-description"
make_fixture "$added_description"
plutil -insert NSAppleEventsUsageDescription -string "Unexpected Automation request" \
  "$added_description/LectureBoardAI/Config/Info.plist"
expect_failure "$added_description" "an Apple Events usage description"

for provenance_key in \
  LectureBoardReleaseCommit \
  LectureBoardReleaseTag \
  LectureBoardReleaseTagObject; do
  missing_provenance="$fixture_parent/missing-$provenance_key"
  make_fixture "$missing_provenance"
  plutil -remove "$provenance_key" \
    "$missing_provenance/LectureBoardAI/Config/Info.plist"
  expect_failure "$missing_provenance" "a missing signed Info.plist provenance key: $provenance_key"
done

wrong_info_path="$fixture_parent/wrong-info-path"
make_fixture "$wrong_info_path"
sed -i '' \
  's#INFOPLIST_FILE: LectureBoardAI/Config/Info.plist#INFOPLIST_FILE: wrong.plist#' \
  "$wrong_info_path/project.yml"
expect_failure "$wrong_info_path" "an unexpected application property-list path"

wrong_entitlement_path="$fixture_parent/wrong-entitlement-path"
make_fixture "$wrong_entitlement_path"
sed -i '' \
  's#CODE_SIGN_ENTITLEMENTS: LectureBoardAI/Config/LectureBoardAI.entitlements#CODE_SIGN_ENTITLEMENTS: wrong.entitlements#' \
  "$wrong_entitlement_path/project.yml"
expect_failure "$wrong_entitlement_path" "an unexpected code-signing entitlement path"

added_automation="$fixture_parent/added-automation"
make_fixture "$added_automation"
sed -i '' '/<\/dict>/i\
  <key>com.apple.security.automation.apple-events</key>\
  <true/>\
' "$added_automation/LectureBoardAI/Config/LectureBoardAI.entitlements"
expect_failure "$added_automation" "an Apple Events entitlement"

missing_audio="$fixture_parent/missing-audio"
make_fixture "$missing_audio"
sed -i '' '/com.apple.security.device.audio-input/{N;d;}' \
  "$missing_audio/LectureBoardAI/Config/LectureBoardAI.entitlements"
expect_failure "$missing_audio" "a missing audio-input entitlement"

disabled_audio="$fixture_parent/disabled-audio"
make_fixture "$disabled_audio"
sed -i '' '/com.apple.security.device.audio-input/{n;s#<true/>#<false/>#;}' \
  "$disabled_audio/LectureBoardAI/Config/LectureBoardAI.entitlements"
expect_failure "$disabled_audio" "a disabled audio-input entitlement"

extra_entitlement="$fixture_parent/extra-entitlement"
make_fixture "$extra_entitlement"
sed -i '' '/<\/dict>/i\
  <key>com.apple.security.get-task-allow</key>\
  <true/>\
' "$extra_entitlement/LectureBoardAI/Config/LectureBoardAI.entitlements"
expect_failure "$extra_entitlement" "an entitlement outside the exact allowlist"

printf 'Permission-contract checker fixture tests passed.\n'
