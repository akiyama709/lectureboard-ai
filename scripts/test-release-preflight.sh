#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail
export LC_ALL=C
export PATH='/usr/bin:/bin:/usr/sbin:/sbin'

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
checker="$script_directory/release-preflight.sh"
temporary_parent="${TMPDIR:-/tmp}"
temporary_parent="${temporary_parent%/}"
fixture_root="$(mktemp -d "$temporary_parent/lectureboard-release-preflight-tests.XXXXXX")"

cleanup() {
  case "$fixture_root" in
    "$temporary_parent"/lectureboard-release-preflight-tests.*)
      find "$fixture_root" -depth -delete
      ;;
  esac
}
trap cleanup EXIT

/bin/bash -p -n "$checker" "$0"

head_commit='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
tag_object='cccccccccccccccccccccccccccccccccccccccc'
other_commit='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
identity_sha1='1111111111111111111111111111111111111111'
other_identity_sha1='2222222222222222222222222222222222222222'
team_id='TESTTEAM01'
other_team_id='OTHERTEAM1'
forbidden_log="$fixture_root/forbidden-tools.log"
shim_directory="$fixture_root/shims"
mkdir -p "$shim_directory"

for forbidden_tool in \
  git security xcodegen xcodebuild codesign xcrun notarytool gh curl wget nc; do
  {
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'set -euo pipefail' \
      'printf "%s\n" "${0##*/}" >>"${LECTUREBOARD_PREFLIGHT_FORBIDDEN_LOG:?}"' \
      'exit 97'
  } >"$shim_directory/$forbidden_tool"
  chmod 755 "$shim_directory/$forbidden_tool"
done

write_fixture() {
  local destination="$1"

  mkdir -p "$destination"
  : >"$destination/git-status.txt"
  : >"$destination/generated-project-diff.txt"
  printf '%s\n' '0' >"$destination/extracted-tree-status.txt"
  printf '%s\n' "$head_commit" >"$destination/head-commit.txt"
  printf '%s\n' "$tag_object" >"$destination/tag-object-id.txt"
  printf '%s\n' 'tag' >"$destination/tag-object-type.txt"
  printf '%s\n' "$head_commit" >"$destination/tag-peeled-target.txt"
  printf '%s\n' \
    'https://github.com/akiyama709/lectureboard-ai.git' \
    >"$destination/origin-fetch-url.txt"
  printf '%s\n' \
    'https://github.com/akiyama709/lectureboard-ai.git' \
    >"$destination/origin-push-url.txt"
  printf '%s\n' "$head_commit" >"$destination/origin-main-commit.txt"
  printf '%s\n' "$head_commit" >"$destination/expected-ci-commit.txt"
  printf '%s\n' "$tag_object" >"$destination/expected-release-tag-object.txt"
  printf '%s\n' '0' >"$destination/replacement-ref-count.txt"
  printf '%s\n' '0' >"$destination/local-config-override-count.txt"
  printf '%s\n' '0' >"$destination/info-attributes-status.txt"
  printf '%s\n' '0' >"$destination/gitattributes-count.txt"
  printf '%s\n' '2026-09-02' >"$destination/expected-release-date.txt"
  printf '%s\n' '42' >"$destination/expected-build-number.txt"
  printf '%s\n' "$identity_sha1" >"$destination/expected-identity-sha1.txt"
  printf '%s\n' "$team_id" >"$destination/expected-team-id.txt"
  printf '%s\n' \
    'cff-version: 1.2.0' \
    'title: "LectureBoard AI"' \
    'version: "1.0.0"' \
    'date-released: "2026-09-02"' \
    >"$destination/CITATION.cff"
  printf '%s\n' \
    '# Changelog' \
    '' \
    '## [Unreleased]' \
    '' \
    '## [1.0.0] - 2026-09-02' \
    >"$destination/CHANGELOG.md"
  printf '%s\n' \
    'settings:' \
    '  base:' \
    '    MARKETING_VERSION: 1.0.0' \
    '    CURRENT_PROJECT_VERSION: 42' \
    >"$destination/project.yml"
  printf '%s\n' \
    '/Applications/Xcode.app/Contents/Developer' \
    >"$destination/selected-developer-directory.txt"
  printf '%s\n' '26.6' >"$destination/xcode-version.txt"
  printf '%s\n' '17F113' >"$destination/xcode-build-version.txt"
  printf '%s\n' '2.46.0' >"$destination/xcodegen-version.txt"
  printf '%s\n' '0' >"$destination/reviewed-project-status.txt"
  printf '  1) %s "Developer ID Application: LectureBoard Fixture (%s)"\n' \
    "$identity_sha1" "$team_id" >"$destination/security-identities.txt"
  printf '     1 valid identities found\n' >>"$destination/security-identities.txt"
}

clone_fixture() {
  local source="$1"
  local destination="$2"

  mkdir -p "$destination"
  cp -R "$source/." "$destination/"
}

run_fixture() {
  local fixture="$1"
  local output_path="$2"

  : >"$forbidden_log"
  PATH="$shim_directory:$PATH" \
  LECTUREBOARD_PREFLIGHT_FORBIDDEN_LOG="$forbidden_log" \
  LECTUREBOARD_RELEASE_PREFLIGHT_TEST_MODE='fixture-v1' \
  LECTUREBOARD_RELEASE_PREFLIGHT_FIXTURE_DIR="$fixture" \
    /bin/bash -p "$checker" >"$output_path" 2>&1
}

assert_no_forbidden_tool() {
  local label="$1"

  if [[ -s "$forbidden_log" ]]; then
    printf 'Release preflight fixture invoked a forbidden real-tool path for %s.\n' \
      "$label" >&2
    exit 1
  fi
}

assert_rejected() {
  local fixture="$1"
  local label="$2"
  local expected_message="$3"
  local output_path="$fixture/preflight-output.txt"

  if run_fixture "$fixture" "$output_path"; then
    printf 'Release preflight accepted %s.\n' "$label" >&2
    exit 1
  fi
  assert_no_forbidden_tool "$label"
  if ! grep -Fq "$expected_message" "$output_path"; then
    printf 'Release preflight did not report the bounded reason for %s.\n' \
      "$label" >&2
    exit 1
  fi
}

baseline="$fixture_root/baseline"
write_fixture "$baseline"
run_fixture "$baseline" "$baseline/preflight-output.txt"
assert_no_forbidden_tool 'the passing baseline'
grep -Fq 'fixture simulation passed; production readiness was not established.' \
  "$baseline/preflight-output.txt"
grep -Fq 'No build, signing, notarization, Apple network, or GitHub mutation was performed.' \
  "$baseline/preflight-output.txt"

dirty_tracked="$fixture_root/dirty-tracked"
clone_fixture "$baseline" "$dirty_tracked"
printf '%s\n' ' M tracked-file' >"$dirty_tracked/git-status.txt"
assert_rejected \
  "$dirty_tracked" 'a dirty tracked file' \
  'the worktree contains tracked or untracked changes'

dirty_untracked="$fixture_root/dirty-untracked"
clone_fixture "$baseline" "$dirty_untracked"
printf '%s\n' '?? untracked-file' >"$dirty_untracked/git-status.txt"
assert_rejected \
  "$dirty_untracked" 'an untracked file' \
  'the worktree contains tracked or untracked changes'

lightweight_tag="$fixture_root/lightweight-tag"
clone_fixture "$baseline" "$lightweight_tag"
printf '%s\n' 'commit' >"$lightweight_tag/tag-object-type.txt"
assert_rejected \
  "$lightweight_tag" 'a lightweight v1.0.0 tag' \
  'v1.0.0 must be an annotated tag'

wrong_tag_target="$fixture_root/wrong-tag-target"
clone_fixture "$baseline" "$wrong_tag_target"
printf '%s\n' "$other_commit" >"$wrong_tag_target/tag-peeled-target.txt"
assert_rejected \
  "$wrong_tag_target" 'an annotated tag targeting another commit' \
  'the annotated release tag does not peel to HEAD'

wrong_tag_object="$fixture_root/wrong-tag-object"
clone_fixture "$baseline" "$wrong_tag_object"
printf '%s\n' "$other_commit" >"$wrong_tag_object/tag-object-id.txt"
assert_rejected \
  "$wrong_tag_object" 'an unapproved annotated tag object' \
  'annotated release-tag object does not match the approved object'

replacement_ref="$fixture_root/replacement-ref"
clone_fixture "$baseline" "$replacement_ref"
printf '1\n' >"$replacement_ref/replacement-ref-count.txt"
assert_rejected \
  "$replacement_ref" 'a Git replacement ref' \
  'release repository contains a Git replacement ref'

unsafe_local_config="$fixture_root/unsafe-local-config"
clone_fixture "$baseline" "$unsafe_local_config"
printf '1\n' >"$unsafe_local_config/local-config-override-count.txt"
assert_rejected \
  "$unsafe_local_config" 'an unsafe local Git config override' \
  'unsafe local Git configuration override'

info_attributes="$fixture_root/info-attributes"
clone_fixture "$baseline" "$info_attributes"
printf '1\n' >"$info_attributes/info-attributes-status.txt"
assert_rejected \
  "$info_attributes" 'repository-local Git attributes' \
  'repository-local Git attributes'

archive_attributes="$fixture_root/archive-attributes"
clone_fixture "$baseline" "$archive_attributes"
printf '1\n' >"$archive_attributes/gitattributes-count.txt"
assert_rejected \
  "$archive_attributes" 'release archive attributes' \
  'release commit contains unsupported Git archive attributes'

wrong_fetch_origin="$fixture_root/wrong-fetch-origin"
clone_fixture "$baseline" "$wrong_fetch_origin"
printf '%s\n' 'https://github.com/example/other.git' \
  >"$wrong_fetch_origin/origin-fetch-url.txt"
assert_rejected \
  "$wrong_fetch_origin" 'an unexpected origin fetch URL' \
  'the origin fetch URL does not match the expected repository'

wrong_push_origin="$fixture_root/wrong-push-origin"
clone_fixture "$baseline" "$wrong_push_origin"
printf '%s\n' 'https://github.com/example/other.git' \
  >"$wrong_push_origin/origin-push-url.txt"
assert_rejected \
  "$wrong_push_origin" 'an unexpected origin push URL' \
  'the origin push URL does not match the expected repository'

wrong_origin_main="$fixture_root/wrong-origin-main"
clone_fixture "$baseline" "$wrong_origin_main"
printf '%s\n' "$other_commit" >"$wrong_origin_main/origin-main-commit.txt"
assert_rejected \
  "$wrong_origin_main" 'a local origin/main commit different from HEAD' \
  'the local origin/main tracking commit does not match HEAD'

wrong_ci_commit="$fixture_root/wrong-ci-commit"
clone_fixture "$baseline" "$wrong_ci_commit"
printf '%s\n' "$other_commit" >"$wrong_ci_commit/expected-ci-commit.txt"
assert_rejected \
  "$wrong_ci_commit" 'a CI commit different from HEAD' \
  'the CI commit input does not match HEAD'

wrong_version="$fixture_root/wrong-version"
clone_fixture "$baseline" "$wrong_version"
sed 's/version: "1.0.0"/version: "1.0.1"/' \
  "$baseline/CITATION.cff" >"$wrong_version/CITATION.cff"
assert_rejected \
  "$wrong_version" 'mismatched v1 release metadata' \
  'CITATION.cff is not at the required v1.0.0 version'

wrong_date="$fixture_root/wrong-date"
clone_fixture "$baseline" "$wrong_date"
sed 's/2026-09-02/2026-09-03/' \
  "$baseline/CHANGELOG.md" >"$wrong_date/CHANGELOG.md"
assert_rejected \
  "$wrong_date" 'mismatched release dates' \
  'CHANGELOG.md does not match the expected release date'

wrong_build="$fixture_root/wrong-build"
clone_fixture "$baseline" "$wrong_build"
sed 's/CURRENT_PROJECT_VERSION: 42/CURRENT_PROJECT_VERSION: 43/' \
  "$baseline/project.yml" >"$wrong_build/project.yml"
assert_rejected \
  "$wrong_build" 'a mismatched bundle build number' \
  'project.yml does not match the expected build number'

wrong_xcode="$fixture_root/wrong-xcode"
clone_fixture "$baseline" "$wrong_xcode"
printf '%s\n' '26.5' >"$wrong_xcode/xcode-version.txt"
assert_rejected "$wrong_xcode" 'Xcode other than 26.6' 'Xcode 26.6 is required'

wrong_xcode_build="$fixture_root/wrong-xcode-build"
clone_fixture "$baseline" "$wrong_xcode_build"
printf '%s\n' '17F114' >"$wrong_xcode_build/xcode-build-version.txt"
assert_rejected \
  "$wrong_xcode_build" 'an unexpected Xcode 26.6 build' \
  'Xcode 26.6 build 17F113 is required'

wrong_xcodegen="$fixture_root/wrong-xcodegen"
clone_fixture "$baseline" "$wrong_xcodegen"
printf '%s\n' '2.45.0' >"$wrong_xcodegen/xcodegen-version.txt"
assert_rejected \
  "$wrong_xcodegen" 'XcodeGen other than 2.46.0' \
  'XcodeGen 2.46.0 is required'

wrong_reviewed_project="$fixture_root/wrong-reviewed-project"
clone_fixture "$baseline" "$wrong_reviewed_project"
printf '%s\n' '1' >"$wrong_reviewed_project/reviewed-project-status.txt"
assert_rejected \
  "$wrong_reviewed_project" 'an unreviewed XcodeGen input' \
  'differs from the exact reviewed source'

wrong_generated_project="$fixture_root/generated-project-diff"
clone_fixture "$baseline" "$wrong_generated_project"
printf '%s\n' 'different' >"$wrong_generated_project/generated-project-diff.txt"
assert_rejected \
  "$wrong_generated_project" 'a stale checked-in Xcode project' \
  'the checked-in Xcode project differs from isolated XcodeGen output'

wrong_extracted_tree="$fixture_root/wrong-extracted-tree"
clone_fixture "$baseline" "$wrong_extracted_tree"
printf '%s\n' '1' >"$wrong_extracted_tree/extracted-tree-status.txt"
assert_rejected \
  "$wrong_extracted_tree" 'an archive changed by Git attributes' \
  'isolated source differs from the exact approved Git tree'

zero_identity="$fixture_root/zero-identity"
clone_fixture "$baseline" "$zero_identity"
printf '%s\n' '     0 valid identities found' \
  >"$zero_identity/security-identities.txt"
assert_rejected \
  "$zero_identity" 'zero Developer ID Application identities' \
  'exactly one Developer ID Application identity is required'

multiple_identities="$fixture_root/multiple-identities"
clone_fixture "$baseline" "$multiple_identities"
{
  printf '  1) %s "Developer ID Application: LectureBoard Fixture (%s)"\n' \
    "$identity_sha1" "$team_id"
  printf '  2) %s "Developer ID Application: Other Fixture (%s)"\n' \
    "$other_identity_sha1" "$team_id"
  printf '%s\n' '     2 valid identities found'
} >"$multiple_identities/security-identities.txt"
assert_rejected \
  "$multiple_identities" 'multiple Developer ID Application identities' \
  'exactly one Developer ID Application identity is required'

ad_hoc_identity="$fixture_root/ad-hoc-identity"
clone_fixture "$baseline" "$ad_hoc_identity"
printf '  1) %s "-"\n' "$identity_sha1" \
  >"$ad_hoc_identity/security-identities.txt"
assert_rejected \
  "$ad_hoc_identity" 'an ad hoc identity' \
  'exactly one Developer ID Application identity is required'

development_identity="$fixture_root/apple-development-identity"
clone_fixture "$baseline" "$development_identity"
printf '  1) %s "Apple Development: LectureBoard Fixture (%s)"\n' \
  "$identity_sha1" "$team_id" >"$development_identity/security-identities.txt"
assert_rejected \
  "$development_identity" 'an Apple Development identity' \
  'exactly one Developer ID Application identity is required'

wrong_fingerprint="$fixture_root/wrong-fingerprint"
clone_fixture "$baseline" "$wrong_fingerprint"
printf '  1) %s "Developer ID Application: LectureBoard Fixture (%s)"\n' \
  "$other_identity_sha1" "$team_id" >"$wrong_fingerprint/security-identities.txt"
assert_rejected \
  "$wrong_fingerprint" 'a Developer ID identity with another fingerprint' \
  'does not match the expected fingerprint and team'

wrong_team="$fixture_root/wrong-team"
clone_fixture "$baseline" "$wrong_team"
printf '  1) %s "Developer ID Application: LectureBoard Fixture (%s)"\n' \
  "$identity_sha1" "$other_team_id" >"$wrong_team/security-identities.txt"
assert_rejected \
  "$wrong_team" 'a Developer ID identity for another team' \
  'does not match the expected fingerprint and team'

malformed_identity="$fixture_root/malformed-identity"
clone_fixture "$baseline" "$malformed_identity"
printf '%s\n' \
  '  1) SHORT "Developer ID Application: LectureBoard Fixture (TESTTEAM01)"' \
  >"$malformed_identity/security-identities.txt"
assert_rejected \
  "$malformed_identity" 'a malformed Developer ID identity record' \
  'the Developer ID Application identity record is malformed'

for dangerous_environment in \
  'GIT_DIR=/private/tmp/untrusted-git-dir' \
  'GIT_CONFIG_COUNT=1' \
  'XCODE_XCCONFIG_FILE=/private/tmp/untrusted.xcconfig'; do
  dangerous_name="${dangerous_environment%%=*}"
  dangerous_value="${dangerous_environment#*=}"
  dangerous_output="$fixture_root/dangerous-${dangerous_name}.txt"
  if /usr/bin/env "$dangerous_name=$dangerous_value" \
    /bin/bash -p "$checker" >"$dangerous_output" 2>&1; then
    printf 'Release preflight accepted dangerous environment %s.\n' \
      "$dangerous_name" >&2
    exit 1
  fi
  /usr/bin/grep -Fq 'forbids toolchain or repository override inputs' \
    "$dangerous_output" \
    || { printf 'Dangerous preflight rejection lost its bounded reason.\n' >&2; exit 1; }
done

if grep -Eq '(/usr/bin/xcodebuild|/usr/bin/codesign|notarytool[[:space:]]+submit|gh[[:space:]]+release)' \
  "$checker"; then
  printf 'Release preflight contains a build, signing, notary, or GitHub mutation command.\n' >&2
  exit 1
fi

printf 'Release preflight regression tests passed.\n'
