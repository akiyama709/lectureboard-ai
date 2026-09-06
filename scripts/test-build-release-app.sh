#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail
export LC_ALL=C
export PATH='/usr/bin:/bin:/usr/sbin:/sbin'

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
builder="$script_directory/build-release-app.sh"
temporary_parent="${TMPDIR:-/tmp}"
temporary_parent="${temporary_parent%/}"
fixture_root="$(mktemp -d "$temporary_parent/lectureboard-release-build-tests.XXXXXX")"

cleanup() {
  case "$fixture_root" in
    "$temporary_parent"/lectureboard-release-build-tests.*)
      find "$fixture_root" -depth -delete
      ;;
  esac
}
trap cleanup EXIT

/bin/bash -p -n "$builder" "$0"

head_commit='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
tag_object='cccccccccccccccccccccccccccccccccccccccc'
team_id='TESTTEAM01'
identity_sha1='1111111111111111111111111111111111111111'
forbidden_log="$fixture_root/forbidden-tools.log"
shim_directory="$fixture_root/shims"
mkdir -p "$shim_directory"

for forbidden_tool in \
  git xcodegen xcodebuild codesign security xcrun notarytool hdiutil gh curl wget nc ditto; do
  {
    printf '%s\n' \
      '#!/usr/bin/env bash' \
      'set -euo pipefail' \
      'printf "%s\n" "${0##*/}" >>"${LECTUREBOARD_RELEASE_BUILD_FORBIDDEN_LOG:?}"' \
      'exit 97'
  } >"$shim_directory/$forbidden_tool"
  chmod 755 "$shim_directory/$forbidden_tool"
done

write_fixture() {
  local destination="$1"
  mkdir -p "$destination"
  printf '%s\n' \
    '0' >"$destination/preflight-status.txt"
  for release_ref_fixture in \
    post-preflight-head.txt \
    post-preflight-tag.txt \
    post-preflight-origin-main.txt \
    pre-handoff-head.txt \
    pre-handoff-tag.txt \
    pre-handoff-origin-main.txt; do
    printf '%s\n' "$head_commit" >"$destination/$release_ref_fixture"
  done
  for tag_object_fixture in \
    post-preflight-tag-object.txt \
    pre-handoff-tag-object.txt; do
    printf '%s\n' "$tag_object" >"$destination/$tag_object_fixture"
  done
  for tag_type_fixture in \
    post-preflight-tag-type.txt \
    pre-handoff-tag-type.txt; do
    printf '%s\n' 'tag' >"$destination/$tag_type_fixture"
  done
  for zero_status_fixture in \
    tracked-link-count.txt \
    replacement-ref-count.txt \
    local-config-override-count.txt \
    info-attributes-status.txt \
    gitattributes-count.txt \
    extracted-link-count.txt \
    extracted-tree-status.txt \
    reviewed-project-status.txt \
    generated-project-status.txt \
    project-reference-status.txt \
    project-support-status.txt \
    package-manifest-status.txt; do
    printf '%s\n' '0' >"$destination/$zero_status_fixture"
  done
  printf '%s\n' \
    '0' >"$destination/archive-status.txt"
  printf '%s\n' \
    '1' >"$destination/app-exists.txt"
  printf '%s\n' \
    'io.github.akiyama709.LectureBoardAI' >"$destination/bundle-identifier.txt"
  printf '%s\n' \
    '1.0.0' >"$destination/marketing-version.txt"
  printf '%s\n' \
    '42' >"$destination/build-number.txt"
  printf '%s\n' \
    'arm64' >"$destination/architecture.txt"
  printf '%s\n' \
    '0' >"$destination/debug-dylib-count.txt"
  printf '%s\n' \
    '0' >"$destination/archive-verifier-status.txt"
  printf '%s\n' \
    '0' >"$destination/copy-status.txt"
  printf '%s\n' \
    '0' >"$destination/copied-verifier-status.txt"
  printf '%s\n' \
    '0' >"$destination/copied-tree-status.txt"
  printf '%s\n' '1' >"$destination/dsym-exists.txt"
  for uuid_fixture in app-uuid.txt dsym-uuid.txt staged-dsym-uuid.txt; do
    printf '%s\n' '01234567-89AB-CDEF-0123-456789ABCDEF' \
      >"$destination/$uuid_fixture"
  done
  for final_status_fixture in \
    handoff-status.txt \
    handoff-postcondition-status.txt \
    output-layout-status.txt \
    final-verifier-status.txt \
    final-tree-status.txt \
    final-output-tree-status.txt \
    marker-cleanup-status.txt \
    marker-absence-status.txt \
    pre-completion-cleanup-status.txt; do
    printf '%s\n' '0' >"$destination/$final_status_fixture"
  done
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
  LECTUREBOARD_RELEASE_BUILD_FORBIDDEN_LOG="$forbidden_log" \
  LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
  LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
  LECTUREBOARD_RELEASE_VERSION='1.0.0' \
  LECTUREBOARD_RELEASE_DATE='2026-09-02' \
  LECTUREBOARD_RELEASE_BUILD_NUMBER='42' \
  LECTUREBOARD_RELEASE_CI_COMMIT="$head_commit" \
  LECTUREBOARD_RELEASE_TAG_OBJECT="$tag_object" \
  LECTUREBOARD_RELEASE_BUILD_TEST_MODE='fixture-v1' \
  LECTUREBOARD_RELEASE_BUILD_FIXTURE_DIR="$fixture" \
    /bin/bash -p "$builder" --output-dir '/fixture/LectureBoard-AI-v1.0.0-build-42' \
      >"$output" 2>&1
}

run_fixture_closed_stdout() {
  local fixture="$1"

  : >"$forbidden_log"
  PATH="$shim_directory:$PATH" \
  LECTUREBOARD_RELEASE_BUILD_FORBIDDEN_LOG="$forbidden_log" \
  LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
  LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
  LECTUREBOARD_RELEASE_VERSION='1.0.0' \
  LECTUREBOARD_RELEASE_DATE='2026-09-02' \
  LECTUREBOARD_RELEASE_BUILD_NUMBER='42' \
  LECTUREBOARD_RELEASE_CI_COMMIT="$head_commit" \
  LECTUREBOARD_RELEASE_TAG_OBJECT="$tag_object" \
  LECTUREBOARD_RELEASE_BUILD_TEST_MODE='fixture-v1' \
  LECTUREBOARD_RELEASE_BUILD_FIXTURE_DIR="$fixture" \
    /bin/bash -p "$builder" --output-dir '/fixture/LectureBoard-AI-v1.0.0-build-42' \
      >&- 2>"$fixture/closed-stdout-error.txt"
}

assert_no_forbidden_tool() {
  local label="$1"
  if [[ -s "$forbidden_log" ]]; then
    printf 'Release-build fixture invoked a forbidden tool for %s.\n' "$label" >&2
    exit 1
  fi
}

assert_rejected() {
  local fixture="$1"
  local label="$2"
  local expected="$3"
  local output="$fixture/output.txt"

  if run_fixture "$fixture" "$output"; then
    printf 'Release-build fixture accepted %s.\n' "$label" >&2
    exit 1
  fi
  assert_no_forbidden_tool "$label"
  if ! grep -Fq "$expected" "$output"; then
    printf 'Release-build fixture lost the bounded reason for %s.\n' "$label" >&2
    exit 1
  fi
}

baseline="$fixture_root/baseline"
write_fixture "$baseline"
run_fixture "$baseline" "$baseline/output.txt"
assert_no_forbidden_tool 'the passing baseline'
grep -Fq 'fixture simulation passed; no archive, signature, or artifact was produced' \
  "$baseline/output.txt"
if ! run_fixture_closed_stdout "$baseline"; then
  printf 'Release-build success became a failure when stdout was closed.\n' >&2
  exit 1
fi
trap_clear_line="$(grep -nF '  trap - EXIT' "$builder" | tail -1 | cut -d: -f1)"
marker_unlink_line="$(grep -nF '  if /bin/unlink "$handed_off_marker"; then' "$builder" | cut -d: -f1)"
if [[ -z "$trap_clear_line" || -z "$marker_unlink_line" \
  || "$trap_clear_line" -ge "$marker_unlink_line" ]]; then
  printf 'Release-build completion does not disable cleanup before marker removal.\n' >&2
  exit 1
fi

preflight_failure="$fixture_root/preflight-failure"
clone_fixture "$baseline" "$preflight_failure"
printf '1\n' >"$preflight_failure/preflight-status.txt"
assert_rejected \
  "$preflight_failure" 'a failed production preflight' \
  'the production release preflight did not pass'

archive_failure="$fixture_root/archive-failure"
clone_fixture "$baseline" "$archive_failure"
printf '1\n' >"$archive_failure/archive-status.txt"
assert_rejected \
  "$archive_failure" 'a failed signed archive' \
  'the signed Release archive did not complete'

missing_app="$fixture_root/missing-app"
clone_fixture "$baseline" "$missing_app"
printf '0\n' >"$missing_app/app-exists.txt"
assert_rejected \
  "$missing_app" 'a missing archive application' \
  'did not contain the expected application'

wrong_bundle="$fixture_root/wrong-bundle"
clone_fixture "$baseline" "$wrong_bundle"
printf 'io.github.example.Other\n' >"$wrong_bundle/bundle-identifier.txt"
assert_rejected \
  "$wrong_bundle" 'another bundle identifier' \
  'has the wrong bundle identifier'

wrong_version="$fixture_root/wrong-version"
clone_fixture "$baseline" "$wrong_version"
printf '1.0.1\n' >"$wrong_version/marketing-version.txt"
assert_rejected \
  "$wrong_version" 'another marketing version' \
  'has the wrong marketing version'

wrong_build="$fixture_root/wrong-build"
clone_fixture "$baseline" "$wrong_build"
printf '43\n' >"$wrong_build/build-number.txt"
assert_rejected \
  "$wrong_build" 'another build number' \
  'has the wrong build number'

wrong_architecture="$fixture_root/wrong-architecture"
clone_fixture "$baseline" "$wrong_architecture"
printf 'x86_64 arm64\n' >"$wrong_architecture/architecture.txt"
assert_rejected \
  "$wrong_architecture" 'an unapproved architecture set' \
  'must contain exactly arm64 code'

debug_dylib="$fixture_root/debug-dylib"
clone_fixture "$baseline" "$debug_dylib"
printf '1\n' >"$debug_dylib/debug-dylib-count.txt"
assert_rejected \
  "$debug_dylib" 'a debug dylib' \
  'contains a debug dylib'

archive_verifier="$fixture_root/archive-verifier"
clone_fixture "$baseline" "$archive_verifier"
printf '1\n' >"$archive_verifier/archive-verifier-status.txt"
assert_rejected \
  "$archive_verifier" 'an archive signature-verification failure' \
  'did not pass release-code verification'

copy_failure="$fixture_root/copy-failure"
clone_fixture "$baseline" "$copy_failure"
printf '1\n' >"$copy_failure/copy-status.txt"
assert_rejected \
  "$copy_failure" 'an app staging failure' \
  'could not be staged'

copied_verifier="$fixture_root/copied-verifier"
clone_fixture "$baseline" "$copied_verifier"
printf '1\n' >"$copied_verifier/copied-verifier-status.txt"
assert_rejected \
  "$copied_verifier" 'a copied signature-verification failure' \
  'staged application did not pass release-code verification'

copied_tree="$fixture_root/copied-tree"
clone_fixture "$baseline" "$copied_tree"
printf '1\n' >"$copied_tree/copied-tree-status.txt"
assert_rejected \
  "$copied_tree" 'changed copied application bytes' \
  'differs from the verified archive application'

for bounded_failure in \
  'tracked-link-count.txt|1|a tracked symbolic link or submodule' \
  'replacement-ref-count.txt|1|contains a Git replacement ref' \
  'local-config-override-count.txt|1|unsafe local Git configuration override' \
  'info-attributes-status.txt|1|repository-local Git attributes' \
  'gitattributes-count.txt|1|contains unsupported Git archive attributes' \
  'extracted-link-count.txt|1|isolated release source contains a symbolic link' \
  'extracted-tree-status.txt|1|approved source differs from the exact Git tree' \
  'reviewed-project-status.txt|1|approved XcodeGen input differs from the exact reviewed source' \
  'generated-project-status.txt|1|differs from isolated XcodeGen output' \
  'project-reference-status.txt|1|contains an external source reference' \
  'project-support-status.txt|1|support files differ from the reviewed release set' \
  'package-manifest-status.txt|1|unsupported Swift package manifest' \
  'dsym-exists.txt|0|did not contain the required dSYM' \
  'handoff-status.txt|1|release output could not be handed off' \
  'handoff-postcondition-status.txt|1|exclusive output handoff postcondition did not hold' \
  'output-layout-status.txt|1|does not have the exact expected layout' \
  'final-verifier-status.txt|1|did not pass final release-code verification' \
  'final-tree-status.txt|1|handed-off application differs from the verified archive' \
  'final-output-tree-status.txt|1|completed release output differs from the staged release output' \
  'pre-completion-cleanup-status.txt|1|temporary state could not be removed before completion' \
  'marker-cleanup-status.txt|1|incomplete-output marker could not be removed' \
  'marker-absence-status.txt|1|incomplete-output marker still exists or is a symbolic link'; do
  fixture_name="${bounded_failure%%|*}"
  remaining="${bounded_failure#*|}"
  fixture_value="${remaining%%|*}"
  expected_message="${remaining#*|}"
  failure_directory="$fixture_root/failure-${fixture_name%.txt}"
  clone_fixture "$baseline" "$failure_directory"
  printf '%s\n' "$fixture_value" >"$failure_directory/$fixture_name"
  assert_rejected "$failure_directory" "$fixture_name=$fixture_value" "$expected_message"
done

wrong_dsym_uuid="$fixture_root/wrong-dsym-uuid"
clone_fixture "$baseline" "$wrong_dsym_uuid"
printf '%s\n' '11111111-1111-1111-1111-111111111111' \
  >"$wrong_dsym_uuid/staged-dsym-uuid.txt"
assert_rejected \
  "$wrong_dsym_uuid" 'a staged dSYM UUID mismatch' \
  'application and dSYM UUIDs do not match'

malformed_uuid="$fixture_root/malformed-uuid"
clone_fixture "$baseline" "$malformed_uuid"
printf '%s\n' 'not-a-uuid' >"$malformed_uuid/app-uuid.txt"
assert_rejected \
  "$malformed_uuid" 'a malformed application UUID' \
  'release UUID observation is malformed'

malformed_commit="$fixture_root/malformed-commit"
clone_fixture "$baseline" "$malformed_commit"
printf 'not-a-commit\n' >"$malformed_commit/post-preflight-head.txt"
assert_rejected \
  "$malformed_commit" 'a malformed observed release ref' \
  'fixture release-ref observation is malformed'

changed_commit="$fixture_root/changed-commit"
clone_fixture "$baseline" "$changed_commit"
printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n' \
  >"$changed_commit/pre-handoff-head.txt"
assert_rejected \
  "$changed_commit" 'a changed HEAD before handoff' \
  'a release ref changed after production preflight'

changed_tag_object="$fixture_root/changed-tag-object"
clone_fixture "$baseline" "$changed_tag_object"
printf 'dddddddddddddddddddddddddddddddddddddddd\n' \
  >"$changed_tag_object/pre-handoff-tag-object.txt"
assert_rejected \
  "$changed_tag_object" 'a changed annotated tag object before handoff' \
  'annotated release-tag object changed after production preflight'

lightweight_after_preflight="$fixture_root/lightweight-after-preflight"
clone_fixture "$baseline" "$lightweight_after_preflight"
printf 'commit\n' >"$lightweight_after_preflight/pre-handoff-tag-type.txt"
assert_rejected \
  "$lightweight_after_preflight" 'a lightweight release tag after preflight' \
  'release tag is no longer an annotated tag'

if LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
  LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
  LECTUREBOARD_RELEASE_VERSION='1.0.0' \
  LECTUREBOARD_RELEASE_DATE='2026-09-02' \
  LECTUREBOARD_RELEASE_BUILD_NUMBER='42' \
  LECTUREBOARD_RELEASE_CI_COMMIT="$head_commit" \
  LECTUREBOARD_RELEASE_TAG_OBJECT="$tag_object" \
  LECTUREBOARD_RELEASE_BUILD_TEST_MODE='fixture-v1' \
  LECTUREBOARD_RELEASE_BUILD_FIXTURE_DIR="$baseline" \
    /bin/bash -p "$builder" --output-dir relative/path >/dev/null 2>&1; then
  printf 'Release-build script accepted a relative output directory.\n' >&2
  exit 1
fi

for nested_fixture_variable in \
  LECTUREBOARD_RELEASE_PREFLIGHT_TEST_MODE \
  LECTUREBOARD_RELEASE_PREFLIGHT_FIXTURE_DIR \
  LECTUREBOARD_RELEASE_CODE_TEST_MODE \
  LECTUREBOARD_RELEASE_CODE_FIXTURE_DIR; do
  nested_output="$fixture_root/nested-${nested_fixture_variable}.txt"
  if env \
    LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
    LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
    LECTUREBOARD_RELEASE_VERSION='1.0.0' \
    LECTUREBOARD_RELEASE_DATE='2026-09-02' \
    LECTUREBOARD_RELEASE_BUILD_NUMBER='42' \
    LECTUREBOARD_RELEASE_CI_COMMIT="$head_commit" \
    LECTUREBOARD_RELEASE_TAG_OBJECT="$tag_object" \
    "$nested_fixture_variable=fixture-v1" \
      /bin/bash -p "$builder" \
        --output-dir '/fixture/LectureBoard-AI-v1.0.0-build-42' \
        >"$nested_output" 2>&1; then
    printf 'Production release build accepted nested fixture variable %s.\n' \
      "$nested_fixture_variable" >&2
    exit 1
  fi
  grep -Fq 'production release build forbids nested fixture-mode inputs' \
    "$nested_output" \
    || { printf 'Nested fixture rejection lost its bounded reason.\n' >&2; exit 1; }
done

if LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
  LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
  LECTUREBOARD_RELEASE_VERSION='1.0.0' \
  LECTUREBOARD_RELEASE_DATE='2026-09-02' \
  LECTUREBOARD_RELEASE_BUILD_NUMBER='42' \
  LECTUREBOARD_RELEASE_CI_COMMIT="$head_commit" \
  LECTUREBOARD_RELEASE_TAG_OBJECT="$tag_object" \
  LECTUREBOARD_RELEASE_BUILD_TEST_MODE='fixture-v1' \
  LECTUREBOARD_RELEASE_BUILD_FIXTURE_DIR="$baseline" \
    /bin/bash -p "$builder" --output-dir / >/dev/null 2>&1; then
  printf 'Release-build script accepted the filesystem root as output.\n' >&2
  exit 1
fi

for forbidden_environment_case in \
  'GIT_DIR=/private/tmp/untrusted-git-dir' \
  'TAR_OPTIONS=--warning=all' \
  'XCODE_XCCONFIG_FILE=/private/tmp/untrusted.xcconfig'; do
  forbidden_name="${forbidden_environment_case%%=*}"
  forbidden_value="${forbidden_environment_case#*=}"
  forbidden_output="$fixture_root/forbidden-${forbidden_name}.txt"
  if /usr/bin/env \
    LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
    LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
    LECTUREBOARD_RELEASE_VERSION='1.0.0' \
    LECTUREBOARD_RELEASE_DATE='2026-09-02' \
    LECTUREBOARD_RELEASE_BUILD_NUMBER='42' \
    LECTUREBOARD_RELEASE_CI_COMMIT="$head_commit" \
    LECTUREBOARD_RELEASE_TAG_OBJECT="$tag_object" \
    "$forbidden_name=$forbidden_value" \
      /bin/bash -p "$builder" \
        --output-dir '/fixture/LectureBoard-AI-v1.0.0-build-42' \
        >"$forbidden_output" 2>&1; then
    printf 'Production release build accepted dangerous environment %s.\n' \
      "$forbidden_name" >&2
    exit 1
  fi
  /usr/bin/grep -Fq 'forbids toolchain or repository override inputs' \
    "$forbidden_output" \
    || { printf 'Dangerous environment rejection lost its bounded reason.\n' >&2; exit 1; }
done

if grep -Eq 'CODE_SIGN_IDENTITY=(-|Apple Development)|CODE_SIGNING_ALLOWED=NO|allowProvisioningUpdates' \
  "$builder"; then
  printf 'Release-build script contains a signing fallback or automatic-provisioning path.\n' >&2
  exit 1
fi

for required_setting in \
  'CODE_SIGN_STYLE=Manual' \
  'CODE_SIGNING_REQUIRED=YES' \
  'CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO' \
  'ENABLE_HARDENED_RUNTIME=YES' \
  'ENABLE_DEBUG_DYLIB=NO' \
  'ARCHS=arm64' \
  '-disableAutomaticPackageResolution' \
  '-skipPackageUpdates' \
  'OTHER_CODE_SIGN_FLAGS=--timestamp' \
  'LECTUREBOARD_RELEASE_COMMIT=' \
  'LECTUREBOARD_RELEASE_TAG=' \
  'LECTUREBOARD_RELEASE_TAG_OBJECT='; do
  grep -Fq -- "$required_setting" "$builder" \
    || { printf 'Release-build script lost required setting: %s\n' "$required_setting" >&2; exit 1; }
done

/usr/bin/grep -Fq -- '-i' "$builder" \
  || { printf 'Release-build child calls no longer use an environment allowlist.\n' >&2; exit 1; }

grep -Fq 'committed_verifier="$source_root/scripts/verify-release-code.sh"' "$builder" \
  || { printf 'Release build does not pin its verifier to the approved commit.\n' >&2; exit 1; }
if grep -Fq '"$script_directory/verify-release-code.sh" --kind' "$builder"; then
  printf 'Release build can invoke a mutable worktree verifier after preflight.\n' >&2
  exit 1
fi
grep -Fq 'release-exclusive-rename.c' "$builder" \
  || { printf 'Release build lost the exclusive output-handoff helper.\n' >&2; exit 1; }
grep -Fq 'release-artifact-tools.sh' "$builder" \
  || { printf 'Release build lost the tested artifact helper.\n' >&2; exit 1; }
grep -Fq 'GIT_NO_REPLACE_OBJECTS=1' "$builder" \
  || { printf 'Release build no longer disables Git replacement objects.\n' >&2; exit 1; }
grep -Fq 'GIT_ATTR_NOSYSTEM=1' "$builder" \
  || { printf 'Release build no longer disables system Git attributes.\n' >&2; exit 1; }

printf 'Release app build fixture tests passed.\n'
