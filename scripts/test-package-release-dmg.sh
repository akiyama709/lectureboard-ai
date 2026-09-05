#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail
export LC_ALL=C

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
packager="$script_directory/package-release-dmg.sh"
evidence_tools="$script_directory/release-package-evidence-tools.sh"
temporary_parent="${TMPDIR:-/tmp}"
temporary_parent="${temporary_parent%/}"
fixture_root="$(mktemp -d "$temporary_parent/lectureboard-release-package-tests.XXXXXX")"

cleanup() {
  case "$fixture_root" in
    "$temporary_parent"/lectureboard-release-package-tests.*)
      find "$fixture_root" -depth -delete
      ;;
  esac
}
trap cleanup EXIT

/bin/bash -p -n "$packager" "$0"
/bin/bash -p -n "$evidence_tools"

approved_commit='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
tag_object='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
team_id='TESTTEAM01'
identity_sha1='1111111111111111111111111111111111111111'
app_submission_id='11111111-2222-3333-4444-555555555555'
dmg_submission_id='aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
fixture_digest='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
forbidden_log="$fixture_root/forbidden-tools.log"
shim_directory="$fixture_root/shims"
mkdir -p "$shim_directory"

for forbidden_tool in \
  git xcodegen xcodebuild codesign security xcrun notarytool stapler hdiutil \
  gh curl wget nc ditto spctl productbuild productsign; do
  {
    printf '%s\n' \
      '#!/bin/bash' \
      'set -euo pipefail' \
      'printf "%s\\n" "${0##*/}" >>"${LECTUREBOARD_RELEASE_PACKAGE_FORBIDDEN_LOG:?}"' \
      'exit 97'
  } >"$shim_directory/$forbidden_tool"
  chmod 755 "$shim_directory/$forbidden_tool"
done

write_fixture() {
  local destination="$1"
  local status_file

  mkdir -p "$destination"
  for status_file in \
    exact-tag-object-status.txt \
    source-attribute-status.txt \
    source-link-status.txt \
    isolated-source-manifest-status.txt \
    approved-source-status.txt \
    input-builder-layout-status.txt \
    input-app-manifest-status.txt \
    input-dsym-manifest-status.txt \
    input-debug-identity-status.txt \
    input-app-provenance-status.txt \
    input-app-verifier-status.txt \
    app-copy-status.txt \
    copied-app-tree-status.txt \
    copied-app-verifier-status.txt \
    app-zip-status.txt \
    app-submit-command-status.txt \
    app-log-command-status.txt \
    app-staple-status.txt \
    app-stapler-validation-status.txt \
    stapled-app-verifier-status.txt \
    dmg-payload-copy-status.txt \
    dmg-payload-tree-status.txt \
    dmg-payload-structure-status.txt \
    dmg-create-status.txt \
    unsigned-dmg-mount-status.txt \
    unsigned-dmg-structure-status.txt \
    unsigned-dmg-detach-status.txt \
    dmg-sign-status.txt \
    signed-dmg-verifier-status.txt \
    dmg-submit-command-status.txt \
    dmg-log-command-status.txt \
    dmg-staple-status.txt \
    dmg-stapler-validation-status.txt \
    final-dmg-verifier-status.txt \
    final-dmg-mount-status.txt \
    final-dmg-structure-status.txt \
    embedded-app-stapler-validation-status.txt \
    embedded-app-verifier-status.txt \
    embedded-app-tree-status.txt \
    final-dmg-detach-status.txt \
    output-copy-status.txt \
    output-copy-digest-status.txt \
    final-ref-status.txt \
    output-handoff-status.txt \
    output-postcondition-status.txt \
    output-final-verifier-status.txt \
    output-final-stapler-status.txt \
    output-final-digest-status.txt \
    output-exact-set-status.txt \
    output-evidence-exact-set-status.txt \
    output-marker-cleanup-status.txt \
    output-marker-absence-status.txt \
    best-effort-exit-cleanup-status.txt; do
    printf '0\n' >"$destination/$status_file"
  done
  printf '512\n' >"$destination/app-submit-bytes.txt"
  printf '%s\n' "$app_submission_id" >"$destination/app-submit-id.txt"
  printf 'Accepted\n' >"$destination/app-submit-result.txt"
  printf '2048\n' >"$destination/app-log-bytes.txt"
  printf '%s\n' "$app_submission_id" >"$destination/app-log-job-id.txt"
  printf 'Accepted\n' >"$destination/app-log-result.txt"
  printf '0\n' >"$destination/app-log-status-code.txt"
  printf '0\n' >"$destination/app-log-issue-count.txt"
  printf '%s\n' "$fixture_digest" >"$destination/app-submitted-sha256.txt"
  printf '%s\n' "$fixture_digest" >"$destination/app-log-archive-sha256.txt"
  printf '%s\n' "$fixture_digest" >"$destination/app-log-digest.txt"
  printf '512\n' >"$destination/dmg-submit-bytes.txt"
  printf '%s\n' "$dmg_submission_id" >"$destination/dmg-submit-id.txt"
  printf 'Accepted\n' >"$destination/dmg-submit-result.txt"
  printf '2048\n' >"$destination/dmg-log-bytes.txt"
  printf '%s\n' "$dmg_submission_id" >"$destination/dmg-log-job-id.txt"
  printf 'Accepted\n' >"$destination/dmg-log-result.txt"
  printf '0\n' >"$destination/dmg-log-status-code.txt"
  printf '0\n' >"$destination/dmg-log-issue-count.txt"
  printf '%s\n' "$fixture_digest" >"$destination/dmg-submitted-sha256.txt"
  printf '%s\n' "$fixture_digest" >"$destination/dmg-log-archive-sha256.txt"
  printf '%s\n' "$fixture_digest" >"$destination/dmg-log-digest.txt"
  printf '%s\n' "$fixture_digest" >"$destination/final-dmg-sha256.txt"
  printf '123456\n' >"$destination/final-dmg-size.txt"
  # A nonzero simulated EXIT-cleanup result must not revoke already completed
  # marker release in the fixture success path.
  printf '97\n' >"$destination/best-effort-exit-cleanup-status.txt"
}

clone_fixture() {
  local source="$1"
  local destination="$2"
  mkdir -p "$destination"
  cp -R "$source/." "$destination/"
}

run_fixture() {
  local fixture="$1"
  local output="$2"

  : >"$forbidden_log"
  PATH="$shim_directory:$PATH" \
  LECTUREBOARD_RELEASE_PACKAGE_FORBIDDEN_LOG="$forbidden_log" \
  LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
  LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
  LECTUREBOARD_RELEASE_VERSION='1.0.0' \
  LECTUREBOARD_RELEASE_BUILD_NUMBER='42' \
  LECTUREBOARD_RELEASE_CI_COMMIT="$approved_commit" \
  LECTUREBOARD_RELEASE_TAG_OBJECT="$tag_object" \
  LECTUREBOARD_NOTARYTOOL_PROFILE='LectureBoard-v1-Notary' \
  LECTUREBOARD_RELEASE_PACKAGE_TEST_MODE='fixture-v1' \
  LECTUREBOARD_RELEASE_PACKAGE_FIXTURE_DIR="$fixture" \
    /bin/bash -p "$packager" \
      --app '/fixture/LectureBoard AI.app' \
      --output-dir '/fixture/LectureBoard-AI-v1.0.0-build-42' \
      --approved-source-dir '/fixture/approved-source' \
      >"$output" 2>&1
}

assert_no_forbidden_tool() {
  local label="$1"
  if [[ -s "$forbidden_log" ]]; then
    printf 'Release-package fixture invoked a forbidden tool for %s.\n' "$label" >&2
    exit 1
  fi
}

assert_rejected() {
  local fixture="$1"
  local label="$2"
  local expected="$3"
  local output="$fixture/output.txt"

  if run_fixture "$fixture" "$output"; then
    printf 'Release-package fixture accepted %s.\n' "$label" >&2
    exit 1
  fi
  assert_no_forbidden_tool "$label"
  if ! grep -Fq "$expected" "$output"; then
    printf 'Release-package fixture lost the bounded reason for %s.\n' "$label" >&2
    exit 1
  fi
}

baseline="$fixture_root/baseline"
write_fixture "$baseline"
run_fixture "$baseline" "$baseline/output.txt"
assert_no_forbidden_tool 'the passing baseline'
grep -Fq 'fixture simulation passed; no signing, notarization, disk image, or artifact was produced' \
  "$baseline/output.txt"

closed_stdout_error="$fixture_root/closed-stdout-error.txt"
if ! env \
  LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
  LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
  LECTUREBOARD_RELEASE_VERSION='1.0.0' \
  LECTUREBOARD_RELEASE_BUILD_NUMBER='42' \
  LECTUREBOARD_RELEASE_CI_COMMIT="$approved_commit" \
  LECTUREBOARD_RELEASE_TAG_OBJECT="$tag_object" \
  LECTUREBOARD_NOTARYTOOL_PROFILE='LectureBoard-v1-Notary' \
  LECTUREBOARD_RELEASE_PACKAGE_TEST_MODE='fixture-v1' \
  LECTUREBOARD_RELEASE_PACKAGE_FIXTURE_DIR="$baseline" \
    /bin/bash -p "$packager" \
      --app '/fixture/LectureBoard AI.app' \
      --output-dir '/fixture/LectureBoard-AI-v1.0.0-build-42' \
      --approved-source-dir '/fixture/approved-source' \
      1>&- 2>"$closed_stdout_error"; then
  printf 'Closed stdout revoked a completed fixture result.\n' >&2
  exit 1
fi

case_index=0
while IFS='|' read -r status_file label reason; do
  [[ -n "$status_file" ]] || continue
  case_index=$((case_index + 1))
  fixture="$fixture_root/status-$case_index"
  clone_fixture "$baseline" "$fixture"
  printf '1\n' >"$fixture/$status_file"
  assert_rejected "$fixture" "$label" "$reason"
done <<'STATUS_CASES'
exact-tag-object-status.txt|a changed annotated tag object|approved annotated tag object changed
source-attribute-status.txt|unbounded source attributes|approved source has unbounded Git attributes
source-link-status.txt|a source link or submodule|approved source contains a symbolic link or submodule
isolated-source-manifest-status.txt|an altered isolated export|isolated release tree differs from the approved commit
approved-source-status.txt|a changed approved source|approved source or commit state changed
input-builder-layout-status.txt|an incomplete builder output|input application is not from an exact completed builder output
input-app-manifest-status.txt|an unbounded input app|input application manifest could not be bounded
input-dsym-manifest-status.txt|an unbounded input dSYM|input dSYM manifest could not be bounded
input-debug-identity-status.txt|a mismatched input dSYM|input dSYM UUID does not match the application
input-app-provenance-status.txt|an app from a different commit|signed input application is not bound to the approved commit and tag object
input-app-verifier-status.txt|an invalid input application|input application did not pass release-code verification
app-copy-status.txt|an application copy failure|application could not be copied into the isolated package stage
copied-app-tree-status.txt|changed copied application bytes|isolated application copy differs from the verified input
copied-app-verifier-status.txt|an invalid copied application|isolated application copy did not pass release-code verification
app-zip-status.txt|an application ZIP failure|application notarization ZIP could not be created
app-submit-command-status.txt|an application submission failure|application notarization submission did not complete
app-log-command-status.txt|an application log retrieval failure|application notarization log could not be retrieved
app-staple-status.txt|an application staple failure|application notarization ticket could not be stapled
app-stapler-validation-status.txt|an invalid application ticket|stapled application ticket did not validate
stapled-app-verifier-status.txt|an invalid stapled application|stapled application did not pass release-code verification
dmg-payload-copy-status.txt|a DMG payload copy failure|stapled application could not be copied into the DMG payload
dmg-payload-tree-status.txt|a changed DMG payload application|DMG payload application differs from the stapled application
dmg-payload-structure-status.txt|an extra DMG payload item|DMG payload does not contain exactly the approved application and Applications link
dmg-create-status.txt|a DMG creation failure|unsigned disk image could not be created
unsigned-dmg-mount-status.txt|an unsigned DMG mount failure|unsigned disk image could not be mounted read-only
unsigned-dmg-structure-status.txt|an invalid unsigned DMG structure|unsigned disk image contents are not the exact approved payload
unsigned-dmg-detach-status.txt|an unsigned DMG detach failure|unsigned disk image could not be detached cleanly
dmg-sign-status.txt|a DMG signing failure|disk image could not be signed with the approved Developer ID identity
signed-dmg-verifier-status.txt|an invalid signed DMG|signed disk image did not pass release-code verification
dmg-submit-command-status.txt|a DMG submission failure|disk image notarization submission did not complete
dmg-log-command-status.txt|a DMG log retrieval failure|disk image notarization log could not be retrieved
dmg-staple-status.txt|a DMG staple failure|disk image notarization ticket could not be stapled
dmg-stapler-validation-status.txt|an invalid DMG ticket|stapled disk image ticket did not validate
final-dmg-verifier-status.txt|an invalid final DMG|final stapled disk image did not pass release-code verification
final-dmg-mount-status.txt|a final DMG mount failure|final disk image could not be mounted read-only
final-dmg-structure-status.txt|an invalid final DMG structure|final disk image contents are not the exact approved payload
embedded-app-stapler-validation-status.txt|an unstapled embedded application|embedded in the final disk image lacks a valid stapled ticket
embedded-app-verifier-status.txt|an invalid embedded application|embedded in the final disk image failed release-code verification
embedded-app-tree-status.txt|changed embedded application bytes|embedded in the final disk image differs from the approved stapled application
final-dmg-detach-status.txt|a final DMG detach failure|final disk image could not be detached cleanly
output-copy-status.txt|an output copy failure|final disk image or notarization evidence could not be staged for output
output-copy-digest-status.txt|changed output bytes|staged output bytes differ from the final stapled disk image or notarization logs
final-ref-status.txt|a final source-ref change|approved source or commit state changed before output handoff
output-handoff-status.txt|an output handoff failure|verified release-package output could not be handed off exclusively
output-postcondition-status.txt|an output handoff postcondition failure|exclusive release-package output handoff postcondition did not hold
output-final-verifier-status.txt|an invalid handed-off DMG|handed-off disk image failed final release-code verification
output-final-stapler-status.txt|an unstapled handed-off DMG|handed-off disk image ticket did not validate
output-final-digest-status.txt|changed handed-off DMG bytes|handed-off disk image differs from the verified final disk image
output-exact-set-status.txt|an unexpected handed-off output item|handed-off output root contains an unexpected entry
output-evidence-exact-set-status.txt|an unexpected notarization evidence item|handed-off notarization-evidence directory contains an unexpected entry
output-marker-cleanup-status.txt|an incomplete marker cleanup failure|incomplete-output marker could not be removed
output-marker-absence-status.txt|a remaining incomplete marker|incomplete-output marker still exists or is a symbolic link
STATUS_CASES

malformed_app_id="$fixture_root/malformed-app-id"
clone_fixture "$baseline" "$malformed_app_id"
printf 'not-a-uuid\n' >"$malformed_app_id/app-submit-id.txt"
assert_rejected "$malformed_app_id" 'a malformed application submission identifier' \
  'application submission identifier is malformed'

rejected_app="$fixture_root/rejected-app"
clone_fixture "$baseline" "$rejected_app"
printf 'Invalid\n' >"$rejected_app/app-submit-result.txt"
assert_rejected "$rejected_app" 'a rejected application notarization' \
  'application notarization was not Accepted'

mismatched_app_log="$fixture_root/mismatched-app-log"
clone_fixture "$baseline" "$mismatched_app_log"
printf '%s\n' "$dmg_submission_id" >"$mismatched_app_log/app-log-job-id.txt"
assert_rejected "$mismatched_app_log" 'an unrelated application notarization log' \
  'application notarization log does not match the submission'

oversized_app_response="$fixture_root/oversized-app-response"
clone_fixture "$baseline" "$oversized_app_response"
printf '1048577\n' >"$oversized_app_response/app-submit-bytes.txt"
assert_rejected "$oversized_app_response" 'an oversized application response' \
  'application submission response is empty or exceeds the bounded size'

oversized_dmg_log="$fixture_root/oversized-dmg-log"
clone_fixture "$baseline" "$oversized_dmg_log"
printf '1048577\n' >"$oversized_dmg_log/dmg-log-bytes.txt"
assert_rejected "$oversized_dmg_log" 'an oversized DMG log' \
  'disk image notarization log is empty or exceeds the bounded size'

unbound_app_log="$fixture_root/unbound-app-log"
clone_fixture "$baseline" "$unbound_app_log"
printf 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\n' \
  >"$unbound_app_log/app-log-archive-sha256.txt"
assert_rejected "$unbound_app_log" 'an application log for other bytes' \
  'application notarization log is not bound to the submitted bytes'

unbound_dmg_log="$fixture_root/unbound-dmg-log"
clone_fixture "$baseline" "$unbound_dmg_log"
printf 'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\n' \
  >"$unbound_dmg_log/dmg-log-archive-sha256.txt"
assert_rejected "$unbound_dmg_log" 'a DMG log for other bytes' \
  'disk image notarization log is not bound to the submitted bytes'

app_issues="$fixture_root/app-issues"
clone_fixture "$baseline" "$app_issues"
printf '1\n' >"$app_issues/app-log-issue-count.txt"
assert_rejected "$app_issues" 'an application log with issues' \
  'application notarization log contains issues'

rejected_dmg="$fixture_root/rejected-dmg"
clone_fixture "$baseline" "$rejected_dmg"
printf 'Rejected\n' >"$rejected_dmg/dmg-log-result.txt"
assert_rejected "$rejected_dmg" 'a rejected DMG notarization log' \
  'disk image notarization log did not confirm Accepted status'

dmg_issues="$fixture_root/dmg-issues"
clone_fixture "$baseline" "$dmg_issues"
printf '2\n' >"$dmg_issues/dmg-log-issue-count.txt"
assert_rejected "$dmg_issues" 'a DMG log with issues' \
  'disk image notarization log contains issues'

malformed_log_digest="$fixture_root/malformed-log-digest"
clone_fixture "$baseline" "$malformed_log_digest"
printf 'short\n' >"$malformed_log_digest/dmg-log-digest.txt"
assert_rejected "$malformed_log_digest" 'a malformed notary-log digest' \
  'disk image notarization log digest is malformed'

malformed_final_digest="$fixture_root/malformed-final-digest"
clone_fixture "$baseline" "$malformed_final_digest"
printf 'short\n' >"$malformed_final_digest/final-dmg-sha256.txt"
assert_rejected "$malformed_final_digest" 'a malformed final DMG digest' \
  'final disk image SHA-256 is malformed'

zero_final_size="$fixture_root/zero-final-size"
clone_fixture "$baseline" "$zero_final_size"
printf '0\n' >"$zero_final_size/final-dmg-size.txt"
assert_rejected "$zero_final_size" 'a zero-byte final DMG' \
  'final disk image size is malformed'

missing_fixture="$fixture_root/missing-fixture"
clone_fixture "$baseline" "$missing_fixture"
rm "$missing_fixture/app-log-status-code.txt"
assert_rejected "$missing_fixture" 'a missing bounded fixture input' \
  'required application log status code fixture is missing'

if LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
  LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
  LECTUREBOARD_RELEASE_VERSION='1.0.0' \
  LECTUREBOARD_RELEASE_BUILD_NUMBER='42' \
  LECTUREBOARD_RELEASE_CI_COMMIT="$approved_commit" \
  LECTUREBOARD_RELEASE_TAG_OBJECT="$tag_object" \
  LECTUREBOARD_NOTARYTOOL_PROFILE='LectureBoard-v1-Notary' \
  LECTUREBOARD_RELEASE_PACKAGE_TEST_MODE='fixture-v1' \
  LECTUREBOARD_RELEASE_PACKAGE_FIXTURE_DIR="$baseline" \
    /bin/bash -p "$packager" \
      --app relative.app \
      --output-dir '/fixture/output' \
      --approved-source-dir '/fixture/source' >/dev/null 2>&1; then
  printf 'Release-package script accepted a relative application path.\n' >&2
  exit 1
fi

for inherited_fixture_variable in \
  LECTUREBOARD_RELEASE_PREFLIGHT_TEST_MODE \
  LECTUREBOARD_RELEASE_PREFLIGHT_FIXTURE_DIR \
  LECTUREBOARD_RELEASE_BUILD_TEST_MODE \
  LECTUREBOARD_RELEASE_BUILD_FIXTURE_DIR \
  LECTUREBOARD_RELEASE_CODE_TEST_MODE \
  LECTUREBOARD_RELEASE_CODE_FIXTURE_DIR; do
  nested_output="$fixture_root/nested-$inherited_fixture_variable.txt"
  : >"$forbidden_log"
  if env \
    PATH="$shim_directory:$PATH" \
    LECTUREBOARD_RELEASE_PACKAGE_FORBIDDEN_LOG="$forbidden_log" \
    LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
    LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
    LECTUREBOARD_RELEASE_VERSION='1.0.0' \
    LECTUREBOARD_RELEASE_BUILD_NUMBER='42' \
    LECTUREBOARD_RELEASE_CI_COMMIT="$approved_commit" \
  LECTUREBOARD_RELEASE_TAG_OBJECT="$tag_object" \
    LECTUREBOARD_NOTARYTOOL_PROFILE='LectureBoard-v1-Notary' \
    "$inherited_fixture_variable=fixture-v1" \
      /bin/bash -p "$packager" \
        --app '/fixture/LectureBoard AI.app' \
        --output-dir '/fixture/output' \
        --approved-source-dir '/fixture/source' >"$nested_output" 2>&1; then
    printf 'Production release packaging accepted inherited fixture input %s.\n' \
      "$inherited_fixture_variable" >&2
    exit 1
  fi
  assert_no_forbidden_tool "$inherited_fixture_variable"
  grep -Fq 'production release packaging forbids inherited fixture-mode inputs' \
    "$nested_output" \
    || { printf 'Inherited fixture rejection lost its bounded reason.\n' >&2; exit 1; }
done

for dangerous_environment_variable in ENV GIT_CONFIG_COUNT TAR_OPTIONS; do
  dangerous_output="$fixture_root/dangerous-$dangerous_environment_variable.txt"
  if env \
    LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
    LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
    LECTUREBOARD_RELEASE_VERSION='1.0.0' \
    LECTUREBOARD_RELEASE_BUILD_NUMBER='42' \
    LECTUREBOARD_RELEASE_CI_COMMIT="$approved_commit" \
    LECTUREBOARD_RELEASE_TAG_OBJECT="$tag_object" \
    LECTUREBOARD_NOTARYTOOL_PROFILE='LectureBoard-v1-Notary' \
    "$dangerous_environment_variable=untrusted" \
      /bin/bash -p "$packager" \
        --app '/fixture/LectureBoard AI.app' \
        --output-dir '/fixture/output' \
        --approved-source-dir '/fixture/source' >"$dangerous_output" 2>&1; then
    printf 'Production release packaging accepted dangerous environment input %s.\n' \
      "$dangerous_environment_variable" >&2
    exit 1
  fi
  grep -Fq 'production release packaging forbids inherited build or Git control variables' \
    "$dangerous_output" \
    || { printf 'Dangerous environment rejection lost its bounded reason.\n' >&2; exit 1; }
done
grep -Fq 'DYLD_INSERT_LIBRARIES' "$packager" \
  || { printf 'Production packager lost its DYLD injection rejection.\n' >&2; exit 1; }

for raw_credential_variable in \
  LECTUREBOARD_NOTARYTOOL_APPLE_ID \
  LECTUREBOARD_NOTARYTOOL_PASSWORD \
  LECTUREBOARD_NOTARYTOOL_KEY \
  LECTUREBOARD_NOTARYTOOL_KEY_ID \
  LECTUREBOARD_NOTARYTOOL_ISSUER; do
  credential_output="$fixture_root/credential-$raw_credential_variable.txt"
  if env \
    LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
    LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
    LECTUREBOARD_RELEASE_VERSION='1.0.0' \
    LECTUREBOARD_RELEASE_BUILD_NUMBER='42' \
    LECTUREBOARD_RELEASE_CI_COMMIT="$approved_commit" \
  LECTUREBOARD_RELEASE_TAG_OBJECT="$tag_object" \
    LECTUREBOARD_NOTARYTOOL_PROFILE='LectureBoard-v1-Notary' \
    LECTUREBOARD_RELEASE_PACKAGE_TEST_MODE='fixture-v1' \
    LECTUREBOARD_RELEASE_PACKAGE_FIXTURE_DIR="$baseline" \
    "$raw_credential_variable=secret" \
      /bin/bash -p "$packager" \
        --app '/fixture/LectureBoard AI.app' \
        --output-dir '/fixture/output' \
        --approved-source-dir '/fixture/source' >"$credential_output" 2>&1; then
    printf 'Release-package script accepted raw credential input %s.\n' \
      "$raw_credential_variable" >&2
    exit 1
  fi
  grep -Fq 'raw notarization credentials are not accepted' "$credential_output" \
    || { printf 'Raw credential rejection lost its bounded reason.\n' >&2; exit 1; }
done

invalid_profile_output="$fixture_root/invalid-profile.txt"
if LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
  LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
  LECTUREBOARD_RELEASE_VERSION='1.0.0' \
  LECTUREBOARD_RELEASE_BUILD_NUMBER='42' \
  LECTUREBOARD_RELEASE_CI_COMMIT="$approved_commit" \
  LECTUREBOARD_RELEASE_TAG_OBJECT="$tag_object" \
  LECTUREBOARD_NOTARYTOOL_PROFILE='-unsafe-profile' \
  LECTUREBOARD_RELEASE_PACKAGE_TEST_MODE='fixture-v1' \
  LECTUREBOARD_RELEASE_PACKAGE_FIXTURE_DIR="$baseline" \
    /bin/bash -p "$packager" \
      --app '/fixture/LectureBoard AI.app' \
      --output-dir '/fixture/output' \
      --approved-source-dir '/fixture/source' >"$invalid_profile_output" 2>&1; then
  printf 'Release-package script accepted a malformed Keychain profile name.\n' >&2
  exit 1
fi
grep -Fq 'LECTUREBOARD_NOTARYTOOL_PROFILE is malformed' "$invalid_profile_output"

invalid_tag_object_output="$fixture_root/invalid-tag-object.txt"
if LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
  LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
  LECTUREBOARD_RELEASE_VERSION='1.0.0' \
  LECTUREBOARD_RELEASE_BUILD_NUMBER='42' \
  LECTUREBOARD_RELEASE_CI_COMMIT="$approved_commit" \
  LECTUREBOARD_RELEASE_TAG_OBJECT='not-a-full-object-id' \
  LECTUREBOARD_NOTARYTOOL_PROFILE='LectureBoard-v1-Notary' \
  LECTUREBOARD_RELEASE_PACKAGE_TEST_MODE='fixture-v1' \
  LECTUREBOARD_RELEASE_PACKAGE_FIXTURE_DIR="$baseline" \
    /bin/bash -p "$packager" \
      --app '/fixture/LectureBoard AI.app' \
      --output-dir '/fixture/output' \
      --approved-source-dir '/fixture/source' >"$invalid_tag_object_output" 2>&1; then
  printf 'Release-package script accepted a malformed annotated-tag object.\n' >&2
  exit 1
fi
grep -Fq 'LECTUREBOARD_RELEASE_TAG_OBJECT must be a full annotated-tag object identifier' \
  "$invalid_tag_object_output"

for forbidden_credential_flag in --apple-id --password '--key ' --key-id --issuer; do
  if grep -Fq -- "$forbidden_credential_flag" "$packager"; then
    printf 'Release-package script contains forbidden raw credential flag %s.\n' \
      "$forbidden_credential_flag" >&2
    exit 1
  fi
done

# The fixture-only package simulator cannot stand in for the parsers used after
# real notarytool and hdiutil invocations. Exercise those same side-effect-free
# parser commands directly with actual JSON/property-list documents.
parser_root="$fixture_root/parser"
mkdir -p "$parser_root"
submit_json="$parser_root/submit.json"
printf '{"id":"%s","status":"Accepted","message":"Processing complete"}\n' \
  "$app_submission_id" >"$submit_json"
parsed_submit="$(/bin/bash -p "$evidence_tools" notary-submit --json "$submit_json")" \
  || { printf 'Valid notary submission JSON was rejected.\n' >&2; exit 1; }
[[ "$parsed_submit" == "$app_submission_id" ]] \
  || { printf 'Valid notary submission JSON returned the wrong identifier.\n' >&2; exit 1; }

log_json="$parser_root/log.json"
printf '{"jobId":"%s","status":"Accepted","statusCode":0,"sha256":"%s","issues":[]}\n' \
  "$app_submission_id" "$fixture_digest" >"$log_json"
parsed_log_digest="$(/bin/bash -p "$evidence_tools" notary-log --json "$log_json" \
  --id "$app_submission_id" --sha256 "$fixture_digest")" \
  || { printf 'Valid notary log JSON was rejected.\n' >&2; exit 1; }
[[ "$parsed_log_digest" =~ ^[0-9a-f]{64}$ ]] \
  || { printf 'Valid notary log JSON returned a malformed digest.\n' >&2; exit 1; }

attach_plist="$parser_root/attach.plist"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>system-entities</key><array><dict><key>dev-entry</key><string>/dev/disk42s1</string><key>mount-point</key><string>/private/tmp/LectureBoardMount</string></dict></array></dict></plist>\n' \
  >"$attach_plist"
parsed_device="$(/bin/bash -p "$evidence_tools" attach-plist --plist "$attach_plist" \
  --mountpoint /private/tmp/LectureBoardMount)" \
  || { printf 'Valid attach property list was rejected.\n' >&2; exit 1; }
[[ "$parsed_device" == '/dev/disk42s1' ]] \
  || { printf 'Valid attach property list returned the wrong device.\n' >&2; exit 1; }

bad_submit="$parser_root/bad-submit.json"
printf '{"id":7,"status":"Accepted"}\n' >"$bad_submit"
if /bin/bash -p "$evidence_tools" notary-submit --json "$bad_submit" >/dev/null 2>&1; then
  printf 'Notary submission parser accepted a non-string identifier.\n' >&2
  exit 1
fi
bad_log="$parser_root/bad-log.json"
printf '{"jobId":"%s","status":"Accepted","statusCode":"0","sha256":"%s","issues":[]}\n' \
  "$app_submission_id" "$fixture_digest" >"$bad_log"
if /bin/bash -p "$evidence_tools" notary-log --json "$bad_log" \
    --id "$app_submission_id" --sha256 "$fixture_digest" >/dev/null 2>&1; then
  printf 'Notary log parser accepted a string status code.\n' >&2
  exit 1
fi
duplicate_attach="$parser_root/duplicate-attach.plist"
printf '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0"><dict><key>system-entities</key><array><dict><key>dev-entry</key><string>/dev/disk42s1</string><key>mount-point</key><string>/private/tmp/LectureBoardMount</string></dict><dict><key>dev-entry</key><string>/dev/disk43s1</string><key>mount-point</key><string>/private/tmp/LectureBoardMount</string></dict></array></dict></plist>\n' \
  >"$duplicate_attach"
if /bin/bash -p "$evidence_tools" attach-plist --plist "$duplicate_attach" \
    --mountpoint /private/tmp/LectureBoardMount >/dev/null 2>&1; then
  printf 'Attach parser accepted two matching mounted volumes.\n' >&2
  exit 1
fi

export_root="$parser_root/export-root"
mkdir -p "$export_root/subdirectory"
printf 'approved content\n' >"$export_root/subdirectory/content.txt"
printf '#!/bin/bash\nexit 0\n' >"$export_root/run.sh"
chmod 755 "$export_root/run.sh"
content_sha="$(/usr/bin/shasum -a 256 "$export_root/subdirectory/content.txt" | /usr/bin/awk '{ print $1 }')"
script_sha="$(/usr/bin/shasum -a 256 "$export_root/run.sh" | /usr/bin/awk '{ print $1 }')"
export_manifest="$parser_root/export-manifest.txt"
{
  printf 'directory|040000|subdirectory\n'
  printf 'file|100644|subdirectory/content.txt|%s\n' "$content_sha"
  printf 'file|100755|run.sh|%s\n' "$script_sha"
} | /usr/bin/sort >"$export_manifest"
/bin/bash -p "$evidence_tools" verify-tree-export \
  --manifest "$export_manifest" --root "$export_root"

changed_export="$parser_root/changed-export"
cp -R "$export_root" "$changed_export"
printf 'changed content\n' >"$changed_export/subdirectory/content.txt"
if /bin/bash -p "$evidence_tools" verify-tree-export \
    --manifest "$export_manifest" --root "$changed_export" >/dev/null 2>&1; then
  printf 'Export verifier accepted changed blob bytes.\n' >&2
  exit 1
fi
mode_export="$parser_root/mode-export"
cp -R "$export_root" "$mode_export"
chmod 644 "$mode_export/run.sh"
if /bin/bash -p "$evidence_tools" verify-tree-export \
    --manifest "$export_manifest" --root "$mode_export" >/dev/null 2>&1; then
  printf 'Export verifier accepted a changed Git executable mode.\n' >&2
  exit 1
fi
extra_export="$parser_root/extra-export"
cp -R "$export_root" "$extra_export"
printf 'extra\n' >"$extra_export/unapproved.txt"
if /bin/bash -p "$evidence_tools" verify-tree-export \
    --manifest "$export_manifest" --root "$extra_export" >/dev/null 2>&1; then
  printf 'Export verifier accepted an unapproved path.\n' >&2
  exit 1
fi
link_export="$parser_root/link-export"
cp -R "$export_root" "$link_export"
ln -s missing-target "$link_export/dangling-link"
if /bin/bash -p "$evidence_tools" verify-tree-export \
    --manifest "$export_manifest" --root "$link_export" >/dev/null 2>&1; then
  printf 'Export verifier accepted a symbolic-link entry.\n' >&2
  exit 1
fi

absent_marker="$parser_root/absent-marker"
/bin/bash -p "$evidence_tools" require-absent --path "$absent_marker"
ln -s missing-target "$absent_marker"
if /bin/bash -p "$evidence_tools" require-absent --path "$absent_marker" >/dev/null 2>&1; then
  printf 'Absence verifier accepted a dangling symbolic link.\n' >&2
  exit 1
fi

for required_contract in \
  '#!/bin/bash' \
  'LECTUREBOARD_RELEASE_TAG_OBJECT' \
  'GIT_NO_REPLACE_OBJECTS=1' \
  '/usr/bin/git --no-replace-objects' \
  'GIT_CONFIG_GLOBAL=/dev/null' \
  'GIT_CONFIG_SYSTEM=/dev/null' \
  'GIT_ATTR_NOSYSTEM=1' \
  '/usr/bin/env -i' \
  'TMPDIR=/private/tmp' \
  '--keychain-profile "$notary_profile"' \
  '--wait --timeout "$notary_timeout" --no-progress --output-format json' \
  '/usr/bin/ditto -c -k --keepParent' \
  '/usr/bin/xcrun stapler staple' \
  '/usr/bin/xcrun stapler validate' \
  '/usr/bin/hdiutil create' \
  '/usr/bin/hdiutil attach' \
  '/usr/bin/codesign --force --sign "$identity_sha1" --timestamp' \
  'verify_release_code app' \
  'verify_release_code dmg' \
  'committed_verifier="$approved_source_root/scripts/verify-release-code.sh"' \
  'committed_packager="$approved_source_root/scripts/package-release-dmg.sh"' \
  'committed_artifact_tools="$approved_source_root/scripts/release-artifact-tools.sh"' \
  'committed_evidence_tools="$approved_source_root/scripts/release-package-evidence-tools.sh"' \
  'input-app-tree-manifest-sha256=' \
  'input-dsym-tree-manifest-sha256=' \
  'input-arm64-uuid=' \
  'verify-tree-export --manifest "$approved_export_manifest" --root "$approved_source_root"' \
  'release_completion_marker' \
  '[[ ! -e "$marker" && ! -L "$marker" ]]' \
  'required_cleanup_before_completion' \
  'trap - EXIT' \
  'best_effort_print' \
  '.lectureboard-release-incomplete' \
  'Publication status: not published by this script'; do
  grep -Fq -- "$required_contract" "$packager" \
    || { printf 'Release-package script lost required contract: %s\n' "$required_contract" >&2; exit 1; }
done

if grep -Fq 'diff -qr' "$packager"; then
  printf 'Release-package script still uses metadata-incomplete diff -qr comparison.\n' >&2
  exit 1
fi
if grep -Fq '#!/usr/bin/env bash' "$packager" "$evidence_tools"; then
  printf 'A production release-package script still uses PATH-selected bash.\n' >&2
  exit 1
fi

if grep -Eq '(^|[[:space:]])(gh|curl|wget)[[:space:]]' "$packager"; then
  printf 'Release-package script contains a publication or general network command.\n' >&2
  exit 1
fi

printf 'Release-package fixture tests passed.\n'
