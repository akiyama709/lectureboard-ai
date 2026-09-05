#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail
export LC_ALL=C
export PATH='/usr/bin:/bin:/usr/sbin:/sbin'

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
checker="$script_directory/verify-release-code.sh"
temporary_parent="${TMPDIR:-/tmp}"
temporary_parent="${temporary_parent%/}"
fixture_root="$(mktemp -d "$temporary_parent/lectureboard-release-code-tests.XXXXXX")"
trap 'find "$fixture_root" -depth -delete' EXIT

team_id='TESTTEAM01'
identity_sha1='1111111111111111111111111111111111111111'
other_identity_sha1='2222222222222222222222222222222222222222'
head_commit='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
tag_object='cccccccccccccccccccccccccccccccccccccccc'

write_app_fixture() {
  local destination="$1"
  mkdir -p "$destination"
  printf '0\n' >"$destination/strict-verification-status.txt"
  printf '%s\n' \
    'Executable=/fixture/LectureBoard AI.app/Contents/MacOS/LectureBoard AI' \
    'Identifier=io.github.akiyama709.LectureBoardAI' \
    'CodeDirectory v=20500 size=1 flags=0x10000(runtime) hashes=1+7 location=embedded' \
    'Signature size=9000' \
    'Authority=Developer ID Application: Fixture (TESTTEAM01)' \
    'Authority=Developer ID Certification Authority' \
    'Authority=Apple Root CA' \
    'Timestamp=Sep 2, 2026 at 1:00:00 AM' \
    'TeamIdentifier=TESTTEAM01' \
    'CDHash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa' \
    >"$destination/signature-details.txt"
  printf '%s\n' \
    '# designated => identifier "io.github.akiyama709.LectureBoardAI" and anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] /* exists */ and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */ and certificate leaf[subject.OU] = "TESTTEAM01"' \
    >"$destination/requirement-details.txt"
  printf '%s\n' "$identity_sha1" >"$destination/leaf-certificate-sha1.txt"
  printf '%s\n' 'io.github.akiyama709.LectureBoardAI' >"$destination/bundle-identifier.txt"
  printf '%s\n' '1.0.0' >"$destination/marketing-version.txt"
  printf '%s\n' '42' >"$destination/build-number.txt"
  printf '%s\n' 'arm64' >"$destination/architecture.txt"
  printf '0\n' >"$destination/code-layout-status.txt"
  printf '26.0\n' >"$destination/minimum-os-version.txt"
  printf '%s\n' "$head_commit" >"$destination/embedded-commit.txt"
  printf '%s\n' "$tag_object" >"$destination/embedded-tag-object.txt"
  cp "$script_directory/../LectureBoardAI/Config/LectureBoardAI.entitlements" \
    "$destination/entitlements.plist"
}

clone_fixture() {
  mkdir -p "$2"
  cp -R "$1/." "$2/"
}

run_app() {
  local fixture="$1"
  LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
  LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
  LECTUREBOARD_RELEASE_VERSION='1.0.0' \
  LECTUREBOARD_RELEASE_BUILD_NUMBER='42' \
  LECTUREBOARD_RELEASE_CI_COMMIT="$head_commit" \
  LECTUREBOARD_RELEASE_TAG_OBJECT="$tag_object" \
  LECTUREBOARD_RELEASE_CODE_TEST_MODE='fixture-v1' \
  LECTUREBOARD_RELEASE_CODE_FIXTURE_DIR="$fixture" \
    /bin/bash -p "$checker" --kind app --path '/fixture/LectureBoard AI.app'
}

run_dmg() {
  local fixture="$1"
  LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
  LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
  LECTUREBOARD_RELEASE_CODE_TEST_MODE='fixture-v1' \
  LECTUREBOARD_RELEASE_CODE_FIXTURE_DIR="$fixture" \
    /bin/bash -p "$checker" --kind dmg --path '/fixture/LectureBoard-AI-1.0.0.dmg'
}

expect_failure() {
  local fixture="$1"
  local label="$2"
  local expected="$3"
  local output="$fixture/output.txt"
  if run_app "$fixture" >"$output" 2>&1; then
    printf 'Release-code verification accepted %s.\n' "$label" >&2
    exit 1
  fi
  grep -Fq "$expected" "$output" \
    || { printf 'Release-code verification lost the bounded reason for %s.\n' "$label" >&2; exit 1; }
}

baseline="$fixture_root/baseline"
write_app_fixture "$baseline"
run_app "$baseline" | grep -Fq 'fixture simulation passed; production verification was not established'

adhoc="$fixture_root/adhoc"
clone_fixture "$baseline" "$adhoc"
printf 'Signature=adhoc\nTeamIdentifier=TESTTEAM01\nCDHash=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\n' \
  >"$adhoc/signature-details.txt"
expect_failure "$adhoc" 'an ad hoc signature' 'ad hoc signatures are not release signatures'

wrong_team="$fixture_root/wrong-team"
clone_fixture "$baseline" "$wrong_team"
sed 's/TeamIdentifier=TESTTEAM01/TeamIdentifier=OTHERTEAM1/' \
  "$baseline/signature-details.txt" >"$wrong_team/signature-details.txt"
expect_failure "$wrong_team" 'another signing team' 'signature team does not match'

wrong_certificate="$fixture_root/wrong-certificate"
clone_fixture "$baseline" "$wrong_certificate"
printf '%s\n' "$other_identity_sha1" >"$wrong_certificate/leaf-certificate-sha1.txt"
expect_failure "$wrong_certificate" 'another certificate' 'does not match the approved fingerprint'

missing_runtime="$fixture_root/missing-runtime"
clone_fixture "$baseline" "$missing_runtime"
sed 's/ flags=0x10000(runtime)/ flags=0x0(none)/' \
  "$baseline/signature-details.txt" >"$missing_runtime/signature-details.txt"
expect_failure "$missing_runtime" 'a missing hardened-runtime flag' 'hardened-runtime'

missing_timestamp="$fixture_root/missing-timestamp"
clone_fixture "$baseline" "$missing_timestamp"
sed '/^Timestamp=/d' "$baseline/signature-details.txt" >"$missing_timestamp/signature-details.txt"
expect_failure "$missing_timestamp" 'a missing secure timestamp' 'secure signing timestamp'

unsafe_requirement="$fixture_root/unsafe-requirement"
clone_fixture "$baseline" "$unsafe_requirement"
sed 's/ and certificate leaf\[subject.OU\]/ or certificate leaf[subject.OU]/' \
  "$baseline/requirement-details.txt" >"$unsafe_requirement/requirement-details.txt"
expect_failure "$unsafe_requirement" 'a disjunctive team requirement' 'not exclusively bound'

missing_oid="$fixture_root/missing-oid"
clone_fixture "$baseline" "$missing_oid"
sed 's/1.2.840.113635.100.6.1.13/1.2.3.4/' \
  "$baseline/requirement-details.txt" >"$missing_oid/requirement-details.txt"
expect_failure "$missing_oid" 'a non-Developer-ID leaf requirement' 'Application leaf requirement is missing'

debug_entitlement="$fixture_root/debug-entitlement"
clone_fixture "$baseline" "$debug_entitlement"
sed -i '' '/<\/dict>/i\
  <key>com.apple.security.get-task-allow</key>\
  <true/>\
' "$debug_entitlement/entitlements.plist"
expect_failure "$debug_entitlement" 'a debug entitlement' 'exact two-key allowlist'

wrong_version="$fixture_root/wrong-version"
clone_fixture "$baseline" "$wrong_version"
printf '1.0.1\n' >"$wrong_version/marketing-version.txt"
expect_failure "$wrong_version" 'another bundle version' 'marketing version does not match'

wrong_architecture="$fixture_root/wrong-architecture"
clone_fixture "$baseline" "$wrong_architecture"
printf 'x86_64 arm64\n' >"$wrong_architecture/architecture.txt"
expect_failure "$wrong_architecture" 'an unapproved architecture set' 'exactly arm64'

wrong_minimum_os="$fixture_root/wrong-minimum-os"
clone_fixture "$baseline" "$wrong_minimum_os"
printf '25.0\n' >"$wrong_minimum_os/minimum-os-version.txt"
expect_failure \
  "$wrong_minimum_os" 'an unapproved minimum macOS version' \
  'minimum macOS version must be exactly 26.0'

wrong_embedded_commit="$fixture_root/wrong-embedded-commit"
clone_fixture "$baseline" "$wrong_embedded_commit"
printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n' \
  >"$wrong_embedded_commit/embedded-commit.txt"
expect_failure \
  "$wrong_embedded_commit" 'an app built from another commit' \
  'not bound to the approved release commit'

wrong_embedded_tag="$fixture_root/wrong-embedded-tag"
clone_fixture "$baseline" "$wrong_embedded_tag"
printf 'dddddddddddddddddddddddddddddddddddddddd\n' \
  >"$wrong_embedded_tag/embedded-tag-object.txt"
expect_failure \
  "$wrong_embedded_tag" 'an app built for another annotated tag object' \
  'not bound to the approved annotated tag object'

invalid_code_layout="$fixture_root/invalid-code-layout"
clone_fixture "$baseline" "$invalid_code_layout"
printf '1\n' >"$invalid_code_layout/code-layout-status.txt"
expect_failure \
  "$invalid_code_layout" 'an invalid executable-code layout' \
  'contains an invalid or undeclared executable-code layout'

strict_failure="$fixture_root/strict-failure"
clone_fixture "$baseline" "$strict_failure"
printf '1\n' >"$strict_failure/strict-verification-status.txt"
expect_failure "$strict_failure" 'a strict signature failure' 'strict complete-code signature'

dmg_baseline="$fixture_root/dmg-baseline"
clone_fixture "$baseline" "$dmg_baseline"
: >"$dmg_baseline/entitlements.plist"
run_dmg "$dmg_baseline" \
  | grep -Fq 'fixture simulation passed; production verification was not established'

dmg_empty_plist="$fixture_root/dmg-empty-plist"
clone_fixture "$dmg_baseline" "$dmg_empty_plist"
printf '%s\n' \
  '<?xml version="1.0" encoding="UTF-8"?>' \
  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
  '<plist version="1.0">' \
  '<dict/>' \
  '</plist>' >"$dmg_empty_plist/entitlements.plist"
run_dmg "$dmg_empty_plist" \
  | grep -Fq 'fixture simulation passed; production verification was not established'

dmg_malformed_entitlement="$fixture_root/dmg-malformed-entitlement"
clone_fixture "$dmg_baseline" "$dmg_malformed_entitlement"
printf '%s\n' '<plist><array></plist>' \
  >"$dmg_malformed_entitlement/entitlements.plist"
if run_dmg "$dmg_malformed_entitlement" \
  >"$dmg_malformed_entitlement/output.txt" 2>&1; then
  printf 'Release-code verification accepted malformed disk-image entitlements.\n' >&2
  exit 1
fi
grep -Fq 'disk image entitlement property list is malformed' \
  "$dmg_malformed_entitlement/output.txt"

dmg_entitlement="$fixture_root/dmg-entitlement"
clone_fixture "$baseline" "$dmg_entitlement"
if run_dmg "$dmg_entitlement" >"$dmg_entitlement/output.txt" 2>&1; then
  printf 'Release-code verification accepted disk-image entitlements.\n' >&2
  exit 1
fi
grep -Fq 'disk image signature has unexpected entitlements' \
  "$dmg_entitlement/output.txt"

printf 'Release-code verification fixture tests passed.\n'
