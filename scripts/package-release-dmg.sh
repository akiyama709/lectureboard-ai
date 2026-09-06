#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail
export LC_ALL=C
export PATH='/usr/bin:/bin:/usr/sbin:/sbin'
umask 077
unset CDPATH

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
expected_product_name='LectureBoard AI'
expected_version='1.0.0'
expected_tag='v1.0.0'
notary_timeout='30m'
maximum_notary_json_bytes=1048576

fail() {
  printf 'Release packaging failed: %s\n' "$1" >&2
  exit 1
}

best_effort_print() {
  /usr/bin/printf "$@" 2>/dev/null || true
  return 0
}

usage() {
  printf 'Usage: %s --app /absolute/LectureBoard\\ AI.app --output-dir /absolute/new/directory --approved-source-dir /absolute/repository\n' \
    "$(basename -- "$0")"
}

normalize_hex() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

is_full_object_id() {
  [[ "$1" =~ ^[0-9A-Fa-f]{40}$|^[0-9A-Fa-f]{64}$ ]]
}

is_uuid() {
  [[ "$1" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]]
}

app_path=''
output_directory=''
approved_source_directory=''
app_seen=0
output_seen=0
source_seen=0
while (( $# > 0 )); do
  case "$1" in
    --app)
      (( $# >= 2 )) || { usage >&2; exit 64; }
      (( app_seen == 0 )) || { usage >&2; exit 64; }
      app_seen=1
      app_path="$2"
      shift 2
      ;;
    --output-dir)
      (( $# >= 2 )) || { usage >&2; exit 64; }
      (( output_seen == 0 )) || { usage >&2; exit 64; }
      output_seen=1
      output_directory="$2"
      shift 2
      ;;
    --approved-source-dir)
      (( $# >= 2 )) || { usage >&2; exit 64; }
      (( source_seen == 0 )) || { usage >&2; exit 64; }
      source_seen=1
      approved_source_directory="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 64
      ;;
  esac
done

[[ "$app_seen" == '1' && "$app_path" == /* ]] || { usage >&2; exit 64; }
[[ "$output_seen" == '1' && "$output_directory" == /* ]] || { usage >&2; exit 64; }
[[ "$source_seen" == '1' && "$approved_source_directory" == /* ]] \
  || { usage >&2; exit 64; }
[[ "$app_path" != '/' && "$output_directory" != '/' && "$approved_source_directory" != '/' ]] \
  || fail 'an input path is too broad'
[[ "${app_path##*/}" == "$expected_product_name.app" ]] \
  || fail 'the input application must have the exact release product name'

team_id="${LECTUREBOARD_DEVELOPMENT_TEAM:-}"
identity_sha1="${LECTUREBOARD_DEVELOPER_ID_SHA1:-}"
release_version="${LECTUREBOARD_RELEASE_VERSION:-}"
build_number="${LECTUREBOARD_RELEASE_BUILD_NUMBER:-}"
approved_commit="${LECTUREBOARD_RELEASE_CI_COMMIT:-}"
approved_tag_object="${LECTUREBOARD_RELEASE_TAG_OBJECT:-}"
notary_profile="${LECTUREBOARD_NOTARYTOOL_PROFILE:-}"
test_mode="${LECTUREBOARD_RELEASE_PACKAGE_TEST_MODE:-}"
fixture_directory="${LECTUREBOARD_RELEASE_PACKAGE_FIXTURE_DIR:-}"

[[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] \
  || fail 'LECTUREBOARD_DEVELOPMENT_TEAM must be a 10-character Apple team identifier'
[[ "$identity_sha1" =~ ^[0-9A-Fa-f]{40}$ ]] \
  || fail 'LECTUREBOARD_DEVELOPER_ID_SHA1 must be a 40-digit SHA-1 fingerprint'
identity_sha1="$(normalize_hex "$identity_sha1")"
[[ "$release_version" == "$expected_version" ]] \
  || fail 'LECTUREBOARD_RELEASE_VERSION must be exactly 1.0.0'
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] \
  || fail 'LECTUREBOARD_RELEASE_BUILD_NUMBER must be a positive integer'
is_full_object_id "$approved_commit" \
  || fail 'LECTUREBOARD_RELEASE_CI_COMMIT must be a full commit object identifier'
approved_commit="$(normalize_hex "$approved_commit")"
is_full_object_id "$approved_tag_object" \
  || fail 'LECTUREBOARD_RELEASE_TAG_OBJECT must be a full annotated-tag object identifier'
approved_tag_object="$(normalize_hex "$approved_tag_object")"
[[ "$notary_profile" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] \
  || fail 'LECTUREBOARD_NOTARYTOOL_PROFILE is malformed'

for forbidden_secret_variable in \
  LECTUREBOARD_NOTARYTOOL_APPLE_ID \
  LECTUREBOARD_NOTARYTOOL_PASSWORD \
  LECTUREBOARD_NOTARYTOOL_KEY \
  LECTUREBOARD_NOTARYTOOL_KEY_ID \
  LECTUREBOARD_NOTARYTOOL_ISSUER; do
  [[ -z "${!forbidden_secret_variable:-}" ]] \
    || fail 'raw notarization credentials are not accepted; use only the named Keychain profile'
done

case "$test_mode" in
  '')
    [[ -z "$fixture_directory" ]] || fail 'fixture input requires explicit fixture mode'
    for inherited_fixture_variable in \
      LECTUREBOARD_RELEASE_PREFLIGHT_TEST_MODE \
      LECTUREBOARD_RELEASE_PREFLIGHT_FIXTURE_DIR \
      LECTUREBOARD_RELEASE_BUILD_TEST_MODE \
      LECTUREBOARD_RELEASE_BUILD_FIXTURE_DIR \
      LECTUREBOARD_RELEASE_CODE_TEST_MODE \
      LECTUREBOARD_RELEASE_CODE_FIXTURE_DIR; do
      [[ -z "${!inherited_fixture_variable:-}" ]] \
        || fail 'production release packaging forbids inherited fixture-mode inputs'
    done
    for dangerous_environment_variable in \
      BASH_ENV ENV CDPATH GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR \
      GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_EXEC_PATH \
      GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 \
      GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_NOSYSTEM \
      XCODE_XCCONFIG_FILE TOOLCHAINS \
      SWIFT_EXEC SWIFT_DRIVER_SWIFT_FRONTEND_EXEC CC CXX LD CPATH \
      C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH LIBRARY_PATH SDKROOT \
      DEVELOPER_DIR DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH \
      DYLD_FALLBACK_LIBRARY_PATH DYLD_FALLBACK_FRAMEWORK_PATH \
      DYLD_INSERT_LIBRARIES TAR_OPTIONS COPYFILE_DISABLE COPY_EXTENDED_ATTRIBUTES; do
      [[ -z "${!dangerous_environment_variable:-}" ]] \
        || fail 'production release packaging forbids inherited build or Git control variables'
    done
    ;;
  fixture-v1)
    [[ "$fixture_directory" == /* && -d "$fixture_directory" ]] \
      || fail 'fixture-v1 requires an absolute fixture directory'
    ;;
  *) fail 'unsupported release-package test mode' ;;
esac

read_fixture_scalar() {
  local name="$1"
  local label="$2"
  local path="$fixture_directory/$name"
  local line_count value

  [[ -f "$path" && ! -L "$path" ]] || fail "a required $label fixture is missing"
  line_count="$(awk 'END { print NR + 0 }' "$path")"
  [[ "$line_count" == '1' ]] || fail "$label fixture must contain exactly one line"
  IFS= read -r value <"$path" || true
  [[ -n "$value" ]] || fail "$label fixture must not be empty"
  printf '%s\n' "$value"
}

fixture_gate() {
  local name="$1"
  local label="$2"
  local reason="$3"
  local status

  status="$(read_fixture_scalar "$name" "$label")"
  [[ "$status" == '0' ]] || fail "$reason"
}

fixture_notary_result() {
  local prefix="$1"
  local label="$2"
  local submission_id submission_status log_id log_status status_code issue_count log_digest
  local submit_bytes log_bytes submitted_sha logged_sha

  submit_bytes="$(read_fixture_scalar "$prefix-submit-bytes.txt" "$label submission response size")"
  submission_id="$(read_fixture_scalar "$prefix-submit-id.txt" "$label submission identifier")"
  submission_status="$(read_fixture_scalar "$prefix-submit-result.txt" "$label submission result")"
  log_bytes="$(read_fixture_scalar "$prefix-log-bytes.txt" "$label log size")"
  log_id="$(read_fixture_scalar "$prefix-log-job-id.txt" "$label log identifier")"
  log_status="$(read_fixture_scalar "$prefix-log-result.txt" "$label log result")"
  status_code="$(read_fixture_scalar "$prefix-log-status-code.txt" "$label log status code")"
  issue_count="$(read_fixture_scalar "$prefix-log-issue-count.txt" "$label log issue count")"
  submitted_sha="$(read_fixture_scalar "$prefix-submitted-sha256.txt" "$label submitted-byte digest")"
  logged_sha="$(read_fixture_scalar "$prefix-log-archive-sha256.txt" "$label log archive digest")"
  log_digest="$(read_fixture_scalar "$prefix-log-digest.txt" "$label log digest")"

  [[ "$submit_bytes" =~ ^[1-9][0-9]*$ && "$submit_bytes" -le "$maximum_notary_json_bytes" ]] \
    || fail "$label submission response is empty or exceeds the bounded size"
  is_uuid "$submission_id" || fail "$label submission identifier is malformed"
  [[ "$submission_status" == 'Accepted' ]] || fail "$label notarization was not Accepted"
  [[ "$log_bytes" =~ ^[1-9][0-9]*$ && "$log_bytes" -le "$maximum_notary_json_bytes" ]] \
    || fail "$label notarization log is empty or exceeds the bounded size"
  [[ "$(normalize_hex "$log_id")" == "$(normalize_hex "$submission_id")" ]] \
    || fail "$label notarization log does not match the submission"
  [[ "$log_status" == 'Accepted' && "$status_code" == '0' ]] \
    || fail "$label notarization log did not confirm Accepted status"
  [[ "$issue_count" == '0' ]] || fail "$label notarization log contains issues"
  [[ "$submitted_sha" =~ ^[0-9A-Fa-f]{64}$ \
    && "$logged_sha" =~ ^[0-9A-Fa-f]{64}$ \
    && "$(normalize_hex "$logged_sha")" == "$(normalize_hex "$submitted_sha")" ]] \
    || fail "$label notarization log is not bound to the submitted bytes"
  [[ "$log_digest" =~ ^[0-9A-Fa-f]{64}$ ]] || fail "$label notarization log digest is malformed"
}

if [[ "$test_mode" == 'fixture-v1' ]]; then
  fixture_gate exact-tag-object-status.txt 'exact annotated tag object status' \
    'the approved annotated tag object changed'
  fixture_gate source-attribute-status.txt 'source attribute status' \
    'the approved source has unbounded Git attributes'
  fixture_gate source-link-status.txt 'source link and submodule status' \
    'the approved source contains a symbolic link or submodule'
  fixture_gate isolated-source-manifest-status.txt 'isolated source manifest status' \
    'the isolated release tree differs from the approved commit'
  fixture_gate approved-source-status.txt 'approved source status' \
    'the approved source or commit state changed'
  fixture_gate input-builder-layout-status.txt 'builder output layout status' \
    'the input application is not from an exact completed builder output'
  fixture_gate input-app-manifest-status.txt 'input application manifest status' \
    'the input application manifest could not be bounded'
  fixture_gate input-dsym-manifest-status.txt 'input dSYM manifest status' \
    'the input dSYM manifest could not be bounded'
  fixture_gate input-debug-identity-status.txt 'input debug identity status' \
    'the input dSYM UUID does not match the application'
  fixture_gate input-app-provenance-status.txt 'input application provenance status' \
    'the signed input application is not bound to the approved commit and tag object'
  fixture_gate input-app-verifier-status.txt 'input application verifier status' \
    'the input application did not pass release-code verification'
  fixture_gate app-copy-status.txt 'application copy status' \
    'the application could not be copied into the isolated package stage'
  fixture_gate copied-app-tree-status.txt 'copied application tree status' \
    'the isolated application copy differs from the verified input'
  fixture_gate copied-app-verifier-status.txt 'copied application verifier status' \
    'the isolated application copy did not pass release-code verification'
  fixture_gate app-zip-status.txt 'application ZIP status' \
    'the application notarization ZIP could not be created'
  fixture_gate app-submit-command-status.txt 'application submission command status' \
    'the application notarization submission did not complete'
  fixture_gate app-log-command-status.txt 'application log command status' \
    'the application notarization log could not be retrieved'
  fixture_notary_result app 'application'
  fixture_gate app-staple-status.txt 'application staple status' \
    'the application notarization ticket could not be stapled'
  fixture_gate app-stapler-validation-status.txt 'application staple validation status' \
    'the stapled application ticket did not validate'
  fixture_gate stapled-app-verifier-status.txt 'stapled application verifier status' \
    'the stapled application did not pass release-code verification'
  fixture_gate dmg-payload-copy-status.txt 'DMG payload copy status' \
    'the stapled application could not be copied into the DMG payload'
  fixture_gate dmg-payload-tree-status.txt 'DMG payload application status' \
    'the DMG payload application differs from the stapled application'
  fixture_gate dmg-payload-structure-status.txt 'DMG payload structure status' \
    'the DMG payload does not contain exactly the approved application and Applications link'
  fixture_gate dmg-create-status.txt 'DMG creation status' \
    'the unsigned disk image could not be created'
  fixture_gate unsigned-dmg-mount-status.txt 'unsigned DMG mount status' \
    'the unsigned disk image could not be mounted read-only'
  fixture_gate unsigned-dmg-structure-status.txt 'unsigned DMG structure status' \
    'the unsigned disk image contents are not the exact approved payload'
  fixture_gate unsigned-dmg-detach-status.txt 'unsigned DMG detach status' \
    'the unsigned disk image could not be detached cleanly'
  fixture_gate dmg-sign-status.txt 'DMG signature status' \
    'the disk image could not be signed with the approved Developer ID identity'
  fixture_gate signed-dmg-verifier-status.txt 'signed DMG verifier status' \
    'the signed disk image did not pass release-code verification'
  fixture_gate dmg-submit-command-status.txt 'DMG submission command status' \
    'the disk image notarization submission did not complete'
  fixture_gate dmg-log-command-status.txt 'DMG log command status' \
    'the disk image notarization log could not be retrieved'
  fixture_notary_result dmg 'disk image'
  fixture_gate dmg-staple-status.txt 'DMG staple status' \
    'the disk image notarization ticket could not be stapled'
  fixture_gate dmg-stapler-validation-status.txt 'DMG staple validation status' \
    'the stapled disk image ticket did not validate'
  fixture_gate final-dmg-verifier-status.txt 'final DMG verifier status' \
    'the final stapled disk image did not pass release-code verification'
  fixture_gate final-dmg-mount-status.txt 'final DMG mount status' \
    'the final disk image could not be mounted read-only'
  fixture_gate final-dmg-structure-status.txt 'final DMG structure status' \
    'the final disk image contents are not the exact approved payload'
  fixture_gate embedded-app-stapler-validation-status.txt 'embedded app staple validation status' \
    'the application embedded in the final disk image lacks a valid stapled ticket'
  fixture_gate embedded-app-verifier-status.txt 'embedded app verifier status' \
    'the application embedded in the final disk image failed release-code verification'
  fixture_gate embedded-app-tree-status.txt 'embedded application tree status' \
    'the application embedded in the final disk image differs from the approved stapled application'
  fixture_gate final-dmg-detach-status.txt 'final DMG detach status' \
    'the final disk image could not be detached cleanly'
  fixture_gate output-copy-status.txt 'output copy status' \
    'the final disk image or notarization evidence could not be staged for output'
  fixture_gate output-copy-digest-status.txt 'output copy digest status' \
    'the staged output bytes differ from the final stapled disk image or notarization logs'

  fixture_final_sha="$(read_fixture_scalar final-dmg-sha256.txt 'final DMG SHA-256')"
  fixture_final_size="$(read_fixture_scalar final-dmg-size.txt 'final DMG size')"
  [[ "$fixture_final_sha" =~ ^[0-9A-Fa-f]{64}$ ]] \
    || fail 'the final disk image SHA-256 is malformed'
  [[ "$fixture_final_size" =~ ^[1-9][0-9]*$ ]] \
    || fail 'the final disk image size is malformed'
  fixture_gate final-ref-status.txt 'final release-ref status' \
    'the approved source or commit state changed before output handoff'
  fixture_gate output-handoff-status.txt 'output handoff status' \
    'the verified release-package output could not be handed off exclusively'
  fixture_gate output-postcondition-status.txt 'output postcondition status' \
    'the exclusive release-package output handoff postcondition did not hold'
  fixture_gate output-final-verifier-status.txt 'output final verifier status' \
    'the handed-off disk image failed final release-code verification'
  fixture_gate output-final-stapler-status.txt 'output final staple validation status' \
    'the handed-off disk image ticket did not validate'
  fixture_gate output-final-digest-status.txt 'output final digest status' \
    'the handed-off disk image differs from the verified final disk image'
  fixture_gate output-exact-set-status.txt 'output exact-set status' \
    'the handed-off output root contains an unexpected entry'
  fixture_gate output-evidence-exact-set-status.txt 'notarization evidence exact-set status' \
    'the handed-off notarization-evidence directory contains an unexpected entry'
  fixture_gate output-marker-cleanup-status.txt 'output marker cleanup status' \
    'the incomplete-output marker could not be removed'
  fixture_gate output-marker-absence-status.txt 'output marker absence status' \
    'the incomplete-output marker still exists or is a symbolic link'

  # A simulated cleanup failure is deliberately ignored here. Production
  # performs every required cleanup before marker release; any EXIT cleanup is
  # only a last-resort best-effort action and cannot revoke completed output.
  read_fixture_scalar best-effort-exit-cleanup-status.txt \
    'best-effort EXIT cleanup status' >/dev/null
  best_effort_print \
    'Release-package fixture simulation passed; no signing, notarization, disk image, or artifact was produced.\n'
  exit 0
fi

current_user="$(/usr/bin/id -un)" || fail 'the release-package user could not be identified'
trusted_home="$(/usr/bin/id -P "$current_user" | /usr/bin/awk -F: 'NF >= 9 { print $9 }')" \
  || fail 'the release-package home directory could not be identified'
[[ "$trusted_home" == /* && -d "$trusted_home" && ! -L "$trusted_home" ]] \
  || fail 'the release-package home directory is invalid'
sanitized_environment=(
  /usr/bin/env -i
  PATH=/usr/bin:/bin:/usr/sbin:/sbin
  LC_ALL=C
  HOME="$trusted_home"
  USER="$current_user"
  LOGNAME="$current_user"
  TMPDIR=/private/tmp
)
sanitized_git_environment=(
  /usr/bin/env -i
  PATH=/usr/bin:/bin:/usr/sbin:/sbin
  LC_ALL=C
  GIT_CONFIG_NOSYSTEM=1
  GIT_CONFIG_GLOBAL=/dev/null
  GIT_CONFIG_SYSTEM=/dev/null
  GIT_NO_REPLACE_OBJECTS=1
  GIT_ATTR_NOSYSTEM=1
)
run_clean() {
  "${sanitized_environment[@]}" "$@"
}

for required_tool in \
  /usr/bin/git /usr/bin/tar /usr/bin/mktemp /usr/bin/find /usr/bin/ditto \
  /usr/bin/codesign /usr/bin/shasum /usr/bin/stat /usr/bin/plutil \
  /usr/bin/hdiutil /usr/bin/xcrun /usr/bin/clang /usr/bin/cmp \
  /usr/bin/readlink /usr/bin/awk /usr/bin/grep /bin/mkdir /bin/ln /bin/cp \
  /bin/chmod /bin/realpath /usr/bin/env; do
  [[ -x "$required_tool" ]] || fail 'a required release-packaging tool is unavailable'
done
"${sanitized_environment[@]}" /usr/bin/xcrun --find notarytool >/dev/null 2>&1 \
  || fail 'notarytool is unavailable in the active Xcode toolchain'
"${sanitized_environment[@]}" /usr/bin/xcrun --find stapler >/dev/null 2>&1 \
  || fail 'stapler is unavailable in the active Xcode toolchain'

[[ -d "$app_path" && ! -L "$app_path" ]] \
  || fail 'the input application must be an existing non-symbolic-link bundle'
canonical_app_path="$(/bin/realpath "$app_path")" \
  || fail 'the input application could not be resolved'
[[ "$canonical_app_path" == "$app_path" ]] \
  || fail 'the input application path must be canonical'
canonical_input_builder_root="$(/usr/bin/dirname -- "$canonical_app_path")"

[[ -d "$approved_source_directory" && ! -L "$approved_source_directory" ]] \
  || fail 'the approved source directory must be an existing non-symbolic-link directory'
canonical_source_directory="$(/bin/realpath "$approved_source_directory")" \
  || fail 'the approved source directory could not be resolved'
[[ "$canonical_source_directory" == "$approved_source_directory" ]] \
  || fail 'the approved source directory path must be canonical'
git_safe() {
  "${sanitized_git_environment[@]}" /usr/bin/git --no-replace-objects \
    -c core.fsmonitor=false -c core.untrackedCache=false \
    -c core.hooksPath=/dev/null -c core.attributesFile=/dev/null \
    -c tar.umask=0000 "$@"
}

source_top_level="$(git_safe -C "$canonical_source_directory" rev-parse --show-toplevel 2>/dev/null)" \
  || fail 'the approved source directory is not a Git worktree'
[[ "$source_top_level" == "$canonical_source_directory" ]] \
  || fail 'the approved source directory must be the Git worktree root'

[[ ! -e "$output_directory" && ! -L "$output_directory" ]] \
  || fail 'the output directory must not already exist'
output_parent="${output_directory%/*}"
output_basename="${output_directory##*/}"
[[ -n "$output_parent" && -n "$output_basename" ]] \
  || fail 'the output directory path is malformed'
[[ -d "$output_parent" && ! -L "$output_parent" ]] \
  || fail 'the output parent must be an existing non-symbolic-link directory'
canonical_output_parent="$(/bin/realpath "$output_parent")" \
  || fail 'the output parent could not be resolved'
[[ "$output_directory" == "$canonical_output_parent/$output_basename" ]] \
  || fail 'the output directory must use a canonical absolute parent path'
[[ "$output_basename" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
  || fail 'the output directory name is malformed'
case "$canonical_output_parent/" in
  "$canonical_source_directory/"*) fail 'release-package output must be outside the approved source worktree' ;;
  "$canonical_input_builder_root/"*) fail 'release-package output must be outside the completed builder output' ;;
esac

temporary_parent='/private/tmp'
[[ -d "$temporary_parent" && ! -L "$temporary_parent" ]] \
  || fail 'the temporary parent is unavailable or symbolic'
temporary_parent="$(/bin/realpath "$temporary_parent")" \
  || fail 'the temporary parent could not be resolved'
temporary_root=''
output_stage=''
mounted_device=''
mounted_target=''
cleanup() {
  if [[ -n "$mounted_target" ]]; then
    if [[ -n "$mounted_device" ]]; then
      run_clean /usr/bin/hdiutil detach "$mounted_device" -force >/dev/null 2>&1 || true
    else
      run_clean /usr/bin/hdiutil detach "$mounted_target" -force >/dev/null 2>&1 || true
    fi
  fi
  if [[ -n "$temporary_root" && -d "$temporary_root" ]]; then
    case "$temporary_root" in
      "$temporary_parent"/lectureboard-release-package.*)
        run_clean /usr/bin/find "$temporary_root" -depth -delete || true
        ;;
    esac
  fi
  if [[ -n "$output_stage" && -d "$output_stage" ]]; then
    case "$output_stage" in
      "$canonical_output_parent"/.lectureboard-release-package-output.*)
        run_clean /usr/bin/find "$output_stage" -depth -delete || true
        ;;
    esac
  fi
  return 0
}
trap cleanup EXIT

assert_approved_source_state() {
  local current_head current_tag current_tag_object current_tag_type current_origin_main current_status
  local link_count submodule_count attributes_mode info_attributes absolute_git_directory
  local attribute_entries attribute_path
  local local_config_override_count

  current_status="$(git_safe -C "$canonical_source_directory" status --porcelain=v1 --untracked-files=all)" \
    || fail 'the approved source worktree status could not be read'
  [[ -z "$current_status" ]] || fail 'the approved source worktree is not clean'
  current_head="$(git_safe -C "$canonical_source_directory" rev-parse --verify HEAD^{commit})" \
    || fail 'the approved source HEAD could not be resolved'
  current_tag="$(git_safe -C "$canonical_source_directory" rev-parse --verify "refs/tags/$expected_tag^{}" 2>/dev/null)" \
    || fail 'the approved release tag could not be resolved'
  current_tag_object="$(git_safe -C "$canonical_source_directory" rev-parse --verify "refs/tags/$expected_tag" 2>/dev/null)" \
    || fail 'the approved release tag object could not be resolved'
  current_tag_type="$(git_safe -C "$canonical_source_directory" cat-file -t "refs/tags/$expected_tag" 2>/dev/null)" \
    || fail 'the approved release tag type could not be read'
  current_origin_main="$(git_safe -C "$canonical_source_directory" rev-parse --verify refs/remotes/origin/main^{commit} 2>/dev/null)" \
    || fail 'the approved origin/main tracking commit could not be resolved'
  [[ "$current_tag_type" == 'tag' \
    && "$(normalize_hex "$current_head")" == "$approved_commit" \
    && "$(normalize_hex "$current_tag")" == "$approved_commit" \
    && "$(normalize_hex "$current_origin_main")" == "$approved_commit" \
    && "$(normalize_hex "$current_tag_object")" == "$approved_tag_object" ]] \
    || fail 'the approved source or commit state changed'

  local_config_override_count="$(git_safe -C "$canonical_source_directory" \
    config --local --no-includes --list \
    | run_clean /usr/bin/awk -F= \
      '$1 ~ /^(include\.|includeif\.|core\.attributesfile$|core\.fsmonitor$|core\.hookspath$)/ { count += 1 } END { print count + 0 }')" \
    || fail 'the local Git configuration could not be audited'
  [[ "$local_config_override_count" == '0' ]] \
    || fail 'the approved source contains an unsafe local Git configuration override'
  absolute_git_directory="$(git_safe -C "$canonical_source_directory" rev-parse --absolute-git-dir)" \
    || fail 'the approved source Git directory could not be resolved'
  [[ "$absolute_git_directory" == /* && -d "$absolute_git_directory" && ! -L "$absolute_git_directory" ]] \
    || fail 'the approved source Git directory is invalid'
  info_attributes="$(git_safe -C "$canonical_source_directory" rev-parse \
    --path-format=absolute --git-path info/attributes)" \
    || fail 'the approved source info-attributes path could not be resolved'
  [[ ! -e "$info_attributes" && ! -L "$info_attributes" ]] \
    || fail 'the approved source has unbounded Git info attributes'
  attribute_entries="$(run_clean /usr/bin/mktemp /private/tmp/lectureboard-attribute-paths.XXXXXX)" \
    || fail 'the approved source attribute-path list could not be created'
  git_safe -C "$canonical_source_directory" ls-tree -r -z --name-only "$approved_commit" \
    >"$attribute_entries" || fail 'the approved source attribute paths could not be audited'
  attributes_mode="$({
    count=0
    while IFS= read -r -d '' attribute_path; do
      case "$attribute_path" in
        .gitattributes|*/.gitattributes) count=$((count + 1)) ;;
      esac
    done <"$attribute_entries"
    printf '%s\n' "$count"
  })"
  run_clean /bin/unlink "$attribute_entries"
  [[ "$attributes_mode" == '0' ]] \
    || fail 'the approved source contains tracked .gitattributes files'
  link_count="$(git_safe -C "$canonical_source_directory" ls-tree -r "$approved_commit" \
    | run_clean /usr/bin/awk '$1 == "120000" { count += 1 } END { print count + 0 }')"
  submodule_count="$(git_safe -C "$canonical_source_directory" ls-tree -r "$approved_commit" \
    | run_clean /usr/bin/awk '$1 == "160000" { count += 1 } END { print count + 0 }')"
  [[ "$link_count" == '0' && "$submodule_count" == '0' ]] \
    || fail 'the approved source contains a symbolic link or submodule'
}

write_approved_export_manifest() {
  local output="$1" entries entry metadata path mode object_type object_id digest
  local stage
  [[ "$output" == /* && "$output" != '/' && ! -e "$output" && ! -L "$output" ]] \
    || fail 'the approved export manifest output is unsafe'
  entries="$(run_clean /usr/bin/mktemp "$temporary_root/approved-ls-tree.XXXXXX")" \
    || fail 'the approved tree-entry list could not be created'
  stage="$(run_clean /usr/bin/mktemp "$temporary_root/approved-export-manifest.XXXXXX")" \
    || { run_clean /bin/unlink "$entries"; fail 'the approved export manifest could not be staged'; }
  git_safe -C "$canonical_source_directory" ls-tree -r -t -z "$approved_commit" >"$entries" \
    || fail 'the approved commit tree could not be enumerated'
  if ! (
    while IFS= read -r -d '' entry; do
      [[ "$entry" == *$'\t'* ]] || exit 81
      metadata="${entry%%$'\t'*}"
      path="${entry#*$'\t'}"
      [[ "$path" != *$'\n'* && "$path" != *$'\t'* && "$path" != *'|'* \
        && "$path" != /* && "$path" != '../'* && "$path" != *'/../'* ]] || exit 82
      set -- $metadata
      [[ "$#" == 3 ]] || exit 83
      mode="$1"; object_type="$2"; object_id="$3"
      if [[ "$mode" == '040000' && "$object_type" == 'tree' \
        && "$object_id" =~ ^[0-9a-f]{40}$|^[0-9a-f]{64}$ ]]; then
        printf 'directory|040000|%s\n' "$path"
      elif [[ ( "$mode" == '100644' || "$mode" == '100755' ) \
        && "$object_type" == 'blob' \
        && "$object_id" =~ ^[0-9a-f]{40}$|^[0-9a-f]{64}$ ]]; then
        digest="$(git_safe -C "$canonical_source_directory" cat-file blob "$object_id" \
          | run_clean /usr/bin/shasum -a 256 | run_clean /usr/bin/awk '{ print $1 }')" \
          || exit 84
        [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || exit 85
        printf 'file|%s|%s|%s\n' "$mode" "$path" "$digest"
      else
        exit 86
      fi
    done <"$entries"
  ) | run_clean /usr/bin/sort >"$stage"; then
    fail 'the approved commit tree contains an unsafe or unsupported entry'
  fi
  [[ -s "$stage" ]] || fail 'the approved export manifest is empty'
  run_clean /bin/mv "$stage" "$output" \
    || fail 'the approved export manifest could not be committed'
  run_clean /bin/unlink "$entries"
}

stage_approved_control() {
  local relative="$1" source="$2" destination="$3" record mode type object_id path
  local approved_digest staged_digest
  [[ -f "$source" && ! -L "$source" && ! -e "$destination" && ! -L "$destination" ]] \
    || fail 'a bootstrap release control path is unsafe'
  record="$(git_safe -C "$canonical_source_directory" ls-tree "$approved_commit" -- "$relative")" \
    || fail 'a bootstrap release control could not be resolved'
  [[ "$record" == *$'\t'* ]] || fail 'a bootstrap release control is absent from the approved commit'
  set -- ${record%%$'\t'*}
  [[ "$#" == 3 ]] || fail 'a bootstrap release control record is malformed'
  mode="$1"; type="$2"; object_id="$3"; path="${record#*$'\t'}"
  [[ "$mode" == '100755' && "$type" == 'blob' && "$path" == "$relative" \
    && "$object_id" =~ ^[0-9a-f]{40}$|^[0-9a-f]{64}$ ]] \
    || fail 'a bootstrap release control is not an approved executable blob'
  approved_digest="$(git_safe -C "$canonical_source_directory" cat-file blob "$object_id" \
    | run_clean /usr/bin/shasum -a 256 | run_clean /usr/bin/awk '{ print $1 }')" \
    || fail 'a bootstrap release control digest could not be read'
  run_clean /bin/cp "$source" "$destination" \
    || fail 'a bootstrap release control could not be staged'
  staged_digest="$(run_clean /usr/bin/shasum -a 256 "$destination" \
    | run_clean /usr/bin/awk '{ print $1 }')" \
    || fail 'a staged bootstrap release control digest could not be read'
  [[ "$approved_digest" =~ ^[0-9a-f]{64}$ && "$staged_digest" == "$approved_digest" ]] \
    || fail 'a bootstrap release control differs from the approved commit'
}

temporary_root="$(/usr/bin/mktemp -d "$temporary_parent/lectureboard-release-package.XXXXXX")" \
  || fail 'the isolated release-package directory could not be created'
case "$temporary_root" in
  "$temporary_parent"/lectureboard-release-package.*) ;;
  *) fail 'the isolated release-package directory is unsafe' ;;
esac

assert_approved_source_state
approved_export_manifest="$temporary_root/approved-export-manifest.txt"
write_approved_export_manifest "$approved_export_manifest"
bootstrap_evidence_tools="$temporary_root/release-package-evidence-tools.sh"
stage_approved_control scripts/release-package-evidence-tools.sh \
  "$script_directory/release-package-evidence-tools.sh" "$bootstrap_evidence_tools"
approved_source_root="$temporary_root/approved-source"
run_clean /bin/mkdir "$approved_source_root"
if ! git_safe -C "$canonical_source_directory" archive --format=tar "$approved_commit" \
  | run_clean /usr/bin/tar -xf - -C "$approved_source_root"; then
  fail 'the approved release commit could not be isolated'
fi
"${sanitized_environment[@]}" /bin/bash -p "$bootstrap_evidence_tools" \
  verify-tree-export --manifest "$approved_export_manifest" --root "$approved_source_root" \
  || fail 'the isolated release tree differs from the approved commit'
committed_packager="$approved_source_root/scripts/package-release-dmg.sh"
committed_verifier="$approved_source_root/scripts/verify-release-code.sh"
committed_rename_source="$approved_source_root/scripts/release-exclusive-rename.c"
committed_artifact_tools="$approved_source_root/scripts/release-artifact-tools.sh"
committed_evidence_tools="$approved_source_root/scripts/release-package-evidence-tools.sh"
[[ -f "$committed_packager" && -x "$committed_verifier" && -f "$committed_rename_source" \
  && -f "$committed_artifact_tools" && -f "$committed_evidence_tools" ]] \
  || fail 'the approved release commit lacks a required packaging control'
run_clean /usr/bin/cmp -s "$script_directory/package-release-dmg.sh" "$committed_packager" \
  || fail 'the running package script differs from the approved release commit'

rename_helper="$temporary_root/release-exclusive-rename"
"${sanitized_environment[@]}" /usr/bin/clang -std=c17 -Wall -Wextra -Werror -O2 \
  "$committed_rename_source" -o "$rename_helper" \
  || fail 'the approved exclusive-output helper could not be compiled'

verify_release_code() {
  local kind="$1"
  local target="$2"

  "${sanitized_environment[@]}" \
    LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
    LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
    LECTUREBOARD_RELEASE_VERSION="$release_version" \
    LECTUREBOARD_RELEASE_BUILD_NUMBER="$build_number" \
    LECTUREBOARD_RELEASE_CI_COMMIT="$approved_commit" \
    LECTUREBOARD_RELEASE_TAG_OBJECT="$approved_tag_object" \
      /bin/bash -p "$committed_verifier" --kind "$kind" --path "$target"
}

attach_disk_image() {
  local image="$1"
  local mount_point="$2"
  local attach_plist="$3"
  local label="$4"
  local observed_device

  run_clean /bin/mkdir "$mount_point"
  mounted_target="$mount_point"
  if ! "${sanitized_environment[@]}" /usr/bin/hdiutil attach \
    -readonly -nobrowse -noautoopen -owners off \
    -mountpoint "$mount_point" -plist "$image" >"$attach_plist" 2>/dev/null; then
    fail "$label disk image could not be mounted read-only"
  fi
  observed_device="$("${sanitized_environment[@]}" /bin/bash -p "$committed_evidence_tools" \
    attach-plist --plist "$attach_plist" --mountpoint "$mount_point")" \
    || fail "$label mount property list is invalid"
  mounted_device="$observed_device"
}

check_mounted_payload() {
  local mount_point="$1"
  local label="$2"
  local top_level_count unexpected_count link_target

  [[ -d "$mount_point/$expected_product_name.app" \
    && ! -L "$mount_point/$expected_product_name.app" ]] \
    || fail "$label does not contain the exact application bundle"
  [[ -L "$mount_point/Applications" ]] \
    || fail "$label does not contain the Applications symbolic link"
  link_target="$(/usr/bin/readlink "$mount_point/Applications")" \
    || fail "$label Applications link could not be read"
  [[ "$link_target" == '/Applications' ]] \
    || fail "$label Applications link has the wrong target"
  top_level_count="$(run_clean /usr/bin/find "$mount_point" -mindepth 1 -maxdepth 1 -print | run_clean /usr/bin/awk 'END { print NR + 0 }')"
  unexpected_count="$({ run_clean /usr/bin/find "$mount_point" -mindepth 1 -maxdepth 1 \
    ! -name "$expected_product_name.app" ! -name Applications -print; } \
    | run_clean /usr/bin/awk 'END { print NR + 0 }')"
  [[ "$top_level_count" == '2' && "$unexpected_count" == '0' ]] \
    || fail "$label contains unapproved top-level content"
}

detach_disk_image() {
  local label="$1"
  local detach_target

  if [[ -n "$mounted_device" ]]; then
    detach_target="$mounted_device"
  else
    detach_target="$mounted_target"
  fi
  run_clean /usr/bin/hdiutil detach "$detach_target" >/dev/null 2>&1 \
    || fail "$label disk image could not be detached cleanly"
  mounted_device=''
  mounted_target=''
}

input_builder_root="$(/usr/bin/dirname -- "$canonical_app_path")"
input_builder_dsym="$input_builder_root/$expected_product_name.app.dSYM"
input_entry_count="$(run_clean /usr/bin/find "$input_builder_root" -mindepth 1 -maxdepth 1 -print \
  | run_clean /usr/bin/awk 'END { print NR + 0 }')"
[[ "$input_entry_count" == '2' && -d "$input_builder_dsym" && ! -L "$input_builder_dsym" \
  && ! -e "$input_builder_root/.lectureboard-release-incomplete" ]] \
  || fail 'the input application is not from an exact completed builder output'
input_app_manifest="$temporary_root/input-app-tree.txt"
"${sanitized_environment[@]}" /bin/bash -p "$committed_artifact_tools" tree-manifest \
  --root "$canonical_app_path" --output "$input_app_manifest" \
  || fail 'the input application manifest could not be bounded'
input_dsym_manifest="$temporary_root/input-dsym-tree.txt"
"${sanitized_environment[@]}" /bin/bash -p "$committed_artifact_tools" tree-manifest \
  --root "$input_builder_dsym" --output "$input_dsym_manifest" \
  || fail 'the input dSYM manifest could not be bounded'
input_app_manifest_sha="$(run_clean /usr/bin/shasum -a 256 "$input_app_manifest" \
  | run_clean /usr/bin/awk '{ print $1 }')" \
  || fail 'the input application manifest digest could not be computed'
input_dsym_manifest_sha="$(run_clean /usr/bin/shasum -a 256 "$input_dsym_manifest" \
  | run_clean /usr/bin/awk '{ print $1 }')" \
  || fail 'the input dSYM manifest digest could not be computed'
input_app_uuid="$("${sanitized_environment[@]}" /bin/bash -p "$committed_artifact_tools" \
  arm64-uuid --path "$canonical_app_path/Contents/MacOS/$expected_product_name")" \
  || fail 'the input application UUID could not be bounded'
input_dsym_uuid="$("${sanitized_environment[@]}" /bin/bash -p "$committed_artifact_tools" \
  arm64-uuid --path "$input_builder_dsym")" \
  || fail 'the input dSYM UUID could not be bounded'
[[ "$input_app_uuid" == "$input_dsym_uuid" ]] \
  || fail 'the input dSYM UUID does not match the application'
verify_release_code app "$canonical_app_path" >/dev/null \
  || fail 'the signed input application is not bound to the approved commit and tag object'

staged_app="$temporary_root/$expected_product_name.app"
"${sanitized_environment[@]}" /usr/bin/ditto --noqtn "$canonical_app_path" "$staged_app" \
  || fail 'the application could not be copied into the isolated package stage'
copied_app_manifest="$temporary_root/copied-app-tree.txt"
"${sanitized_environment[@]}" /bin/bash -p "$committed_artifact_tools" tree-manifest \
  --root "$staged_app" --output "$copied_app_manifest" \
  || fail 'the isolated application copy could not be bounded'
run_clean /usr/bin/cmp -s "$input_app_manifest" "$copied_app_manifest" \
  || fail 'the isolated application copy differs from the verified input'
verify_release_code app "$staged_app" >/dev/null \
  || fail 'the isolated application copy did not pass release-code verification'

app_zip="$temporary_root/LectureBoard-AI-1.0.0-build-$build_number.zip"
"${sanitized_environment[@]}" /usr/bin/ditto -c -k --keepParent "$staged_app" "$app_zip" \
  || fail 'the application notarization ZIP could not be created'
[[ -f "$app_zip" && ! -L "$app_zip" ]] \
  || fail 'the application notarization ZIP is missing'
app_submitted_sha="$(run_clean /usr/bin/shasum -a 256 "$app_zip" | run_clean /usr/bin/awk '{ print $1 }')" \
  || fail 'the application notarization ZIP digest could not be computed'
app_submit_json="$temporary_root/app-notary-submit.json"
if ! "${sanitized_environment[@]}" /usr/bin/xcrun notarytool submit "$app_zip" \
  --keychain-profile "$notary_profile" \
  --wait --timeout "$notary_timeout" --no-progress --output-format json \
  >"$app_submit_json" 2>/dev/null; then
  fail 'the application notarization submission did not complete'
fi
app_submission_id="$("${sanitized_environment[@]}" /bin/bash -p "$committed_evidence_tools" \
  notary-submit --json "$app_submit_json")" \
  || fail 'application notarization submission response was invalid'
app_submit_digest="$(run_clean /usr/bin/shasum -a 256 "$app_submit_json" \
  | run_clean /usr/bin/awk '{ print $1 }')" \
  || fail 'application submission response digest could not be computed'
app_log="$temporary_root/app-notary-log.json"
"${sanitized_environment[@]}" /usr/bin/xcrun notarytool log "$app_submission_id" "$app_log" \
  --keychain-profile "$notary_profile" >/dev/null 2>&1 \
  || fail 'the application notarization log could not be retrieved'
app_log_digest="$("${sanitized_environment[@]}" /bin/bash -p "$committed_evidence_tools" \
  notary-log --json "$app_log" --id "$app_submission_id" --sha256 "$app_submitted_sha")" \
  || fail 'application notarization log was invalid'

"${sanitized_environment[@]}" /usr/bin/xcrun stapler staple "$staged_app" >/dev/null 2>&1 \
  || fail 'the application notarization ticket could not be stapled'
"${sanitized_environment[@]}" /usr/bin/xcrun stapler validate "$staged_app" >/dev/null 2>&1 \
  || fail 'the stapled application ticket did not validate'
verify_release_code app "$staged_app" >/dev/null \
  || fail 'the stapled application did not pass release-code verification'
stapled_app_manifest="$temporary_root/stapled-app-tree.txt"
"${sanitized_environment[@]}" /bin/bash -p "$committed_artifact_tools" tree-manifest \
  --root "$staged_app" --output "$stapled_app_manifest" \
  || fail 'the stapled application manifest could not be bounded'

dmg_payload="$temporary_root/dmg-payload"
run_clean /bin/mkdir "$dmg_payload"
"${sanitized_environment[@]}" /usr/bin/ditto --noqtn "$staged_app" "$dmg_payload/$expected_product_name.app" \
  || fail 'the stapled application could not be copied into the DMG payload'
dmg_payload_manifest="$temporary_root/dmg-payload-app-tree.txt"
"${sanitized_environment[@]}" /bin/bash -p "$committed_artifact_tools" tree-manifest \
  --root "$dmg_payload/$expected_product_name.app" --output "$dmg_payload_manifest" \
  || fail 'the DMG payload application could not be bounded'
run_clean /usr/bin/cmp -s "$stapled_app_manifest" "$dmg_payload_manifest" \
  || fail 'the DMG payload application differs from the stapled application'
run_clean /bin/ln -s /Applications "$dmg_payload/Applications" \
  || fail 'the DMG Applications link could not be created'
payload_count="$(run_clean /usr/bin/find "$dmg_payload" -mindepth 1 -maxdepth 1 -print | run_clean /usr/bin/awk 'END { print NR + 0 }')"
[[ "$payload_count" == '2' \
  && -d "$dmg_payload/$expected_product_name.app" \
  && -L "$dmg_payload/Applications" \
  && "$(/usr/bin/readlink "$dmg_payload/Applications")" == '/Applications' ]] \
  || fail 'the DMG payload does not contain exactly the approved application and Applications link'

dmg_name="LectureBoard-AI-1.0.0-build-$build_number.dmg"
final_dmg="$temporary_root/$dmg_name"
"${sanitized_environment[@]}" /usr/bin/hdiutil create \
  -srcfolder "$dmg_payload" \
  -volname 'LectureBoard AI 1.0.0' \
  -fs 'HFS+' -format UDZO -imagekey zlib-level=9 \
  "$final_dmg" >/dev/null 2>&1 \
  || fail 'the unsigned disk image could not be created'
[[ -f "$final_dmg" && ! -L "$final_dmg" ]] \
  || fail 'the unsigned disk image is missing'

unsigned_mount="$temporary_root/unsigned-mount"
unsigned_attach_plist="$temporary_root/unsigned-attach.plist"
attach_disk_image "$final_dmg" "$unsigned_mount" "$unsigned_attach_plist" 'unsigned'
check_mounted_payload "$unsigned_mount" 'the unsigned disk image'
detach_disk_image 'the unsigned'

"${sanitized_environment[@]}" /usr/bin/codesign --force --sign "$identity_sha1" --timestamp "$final_dmg" >/dev/null 2>&1 \
  || fail 'the disk image could not be signed with the approved Developer ID identity'
verify_release_code dmg "$final_dmg" >/dev/null \
  || fail 'the signed disk image did not pass release-code verification'

dmg_submitted_sha="$(run_clean /usr/bin/shasum -a 256 "$final_dmg" | run_clean /usr/bin/awk '{ print $1 }')" \
  || fail 'the signed disk image submission digest could not be computed'
dmg_submit_json="$temporary_root/dmg-notary-submit.json"
if ! "${sanitized_environment[@]}" /usr/bin/xcrun notarytool submit "$final_dmg" \
  --keychain-profile "$notary_profile" \
  --wait --timeout "$notary_timeout" --no-progress --output-format json \
  >"$dmg_submit_json" 2>/dev/null; then
  fail 'the disk image notarization submission did not complete'
fi
dmg_submission_id="$("${sanitized_environment[@]}" /bin/bash -p "$committed_evidence_tools" \
  notary-submit --json "$dmg_submit_json")" \
  || fail 'disk image notarization submission response was invalid'
dmg_submit_digest="$(run_clean /usr/bin/shasum -a 256 "$dmg_submit_json" \
  | run_clean /usr/bin/awk '{ print $1 }')" \
  || fail 'disk-image submission response digest could not be computed'
dmg_log="$temporary_root/dmg-notary-log.json"
"${sanitized_environment[@]}" /usr/bin/xcrun notarytool log "$dmg_submission_id" "$dmg_log" \
  --keychain-profile "$notary_profile" >/dev/null 2>&1 \
  || fail 'the disk image notarization log could not be retrieved'
dmg_log_digest="$("${sanitized_environment[@]}" /bin/bash -p "$committed_evidence_tools" \
  notary-log --json "$dmg_log" --id "$dmg_submission_id" --sha256 "$dmg_submitted_sha")" \
  || fail 'disk image notarization log was invalid'

"${sanitized_environment[@]}" /usr/bin/xcrun stapler staple "$final_dmg" >/dev/null 2>&1 \
  || fail 'the disk image notarization ticket could not be stapled'
"${sanitized_environment[@]}" /usr/bin/xcrun stapler validate "$final_dmg" >/dev/null 2>&1 \
  || fail 'the stapled disk image ticket did not validate'
verify_release_code dmg "$final_dmg" >/dev/null \
  || fail 'the final stapled disk image did not pass release-code verification'

final_mount="$temporary_root/final-mount"
final_attach_plist="$temporary_root/final-attach.plist"
attach_disk_image "$final_dmg" "$final_mount" "$final_attach_plist" 'final'
check_mounted_payload "$final_mount" 'the final disk image'
embedded_app="$final_mount/$expected_product_name.app"
"${sanitized_environment[@]}" /usr/bin/xcrun stapler validate "$embedded_app" >/dev/null 2>&1 \
  || fail 'the application embedded in the final disk image lacks a valid stapled ticket'
verify_release_code app "$embedded_app" >/dev/null \
  || fail 'the application embedded in the final disk image failed release-code verification'
embedded_app_manifest="$temporary_root/embedded-app-tree.txt"
"${sanitized_environment[@]}" /bin/bash -p "$committed_artifact_tools" tree-manifest \
  --root "$embedded_app" --output "$embedded_app_manifest" \
  || fail 'the embedded application manifest could not be bounded'
run_clean /usr/bin/cmp -s "$stapled_app_manifest" "$embedded_app_manifest" \
  || fail 'the application embedded in the final disk image differs from the approved stapled application'
detach_disk_image 'the final'

# These are the first values labelled as the final release DMG digest and size.
# They are intentionally computed only after DMG stapling, validation, remount,
# and embedded-application verification have all succeeded.
final_dmg_sha="$(run_clean /usr/bin/shasum -a 256 "$final_dmg" | run_clean /usr/bin/awk '{ print $1 }')" \
  || fail 'the final disk image SHA-256 could not be computed'
final_dmg_size="$(run_clean /usr/bin/stat -f '%z' "$final_dmg")" \
  || fail 'the final disk image size could not be read'
[[ "$final_dmg_sha" =~ ^[0-9a-f]{64}$ && "$final_dmg_size" =~ ^[1-9][0-9]*$ ]] \
  || fail 'the final disk image digest or size is malformed'

output_stage="$(/usr/bin/mktemp -d "$canonical_output_parent/.lectureboard-release-package-output.XXXXXX")" \
  || fail 'the release-package output stage could not be created'
case "$output_stage" in
  "$canonical_output_parent"/.lectureboard-release-package-output.*) ;;
  *) fail 'the release-package output stage is unsafe' ;;
esac
output_parent_identity="$(run_clean /usr/bin/stat -f '%d %i' "$canonical_output_parent")" \
  || fail 'the release-package output-parent identity could not be captured'
output_stage_identity="$(run_clean /usr/bin/stat -f '%d %i' "$output_stage")" \
  || fail 'the release-package output-stage identity could not be captured'
[[ "$output_parent_identity" =~ ^[0-9]+\ [0-9]+$ \
  && "$output_stage_identity" =~ ^[0-9]+\ [0-9]+$ ]] \
  || fail 'a release-package handoff identity is malformed'
evidence_directory="$output_stage/notarization-evidence"
run_clean /bin/mkdir "$evidence_directory"
run_clean /bin/cp "$final_dmg" "$output_stage/$dmg_name" \
  || fail 'the final disk image could not be staged for output'
run_clean /bin/cp "$app_submit_json" "$evidence_directory/app-submit.json" \
  || fail 'the application submission response could not be staged for output'
run_clean /bin/cp "$app_log" "$evidence_directory/app-log.json" \
  || fail 'the application notarization log could not be staged for output'
run_clean /bin/cp "$dmg_submit_json" "$evidence_directory/dmg-submit.json" \
  || fail 'the disk-image submission response could not be staged for output'
run_clean /bin/cp "$dmg_log" "$evidence_directory/dmg-log.json" \
  || fail 'the disk-image notarization log could not be staged for output'

output_dmg_sha="$(run_clean /usr/bin/shasum -a 256 "$output_stage/$dmg_name" | run_clean /usr/bin/awk '{ print $1 }')"
output_dmg_size="$(run_clean /usr/bin/stat -f '%z' "$output_stage/$dmg_name")"
output_app_log_digest="$(run_clean /usr/bin/shasum -a 256 "$evidence_directory/app-log.json" | run_clean /usr/bin/awk '{ print $1 }')"
output_dmg_log_digest="$(run_clean /usr/bin/shasum -a 256 "$evidence_directory/dmg-log.json" | run_clean /usr/bin/awk '{ print $1 }')"
output_app_submit_digest="$(run_clean /usr/bin/shasum -a 256 "$evidence_directory/app-submit.json" | run_clean /usr/bin/awk '{ print $1 }')"
output_dmg_submit_digest="$(run_clean /usr/bin/shasum -a 256 "$evidence_directory/dmg-submit.json" | run_clean /usr/bin/awk '{ print $1 }')"
[[ "$output_dmg_sha" == "$final_dmg_sha" \
  && "$output_dmg_size" == "$final_dmg_size" \
  && "$output_app_submit_digest" == "$app_submit_digest" \
  && "$output_dmg_submit_digest" == "$dmg_submit_digest" \
  && "$output_app_log_digest" == "$app_log_digest" \
  && "$output_dmg_log_digest" == "$dmg_log_digest" ]] \
  || fail 'the staged output bytes differ from the final stapled disk image or notarization logs'

evidence_record="$output_stage/release-package-evidence.txt"
{
  printf 'format-version=1\n'
  printf 'release-version=%s\n' "$release_version"
  printf 'release-build=%s\n' "$build_number"
  printf 'release-commit=%s\n' "$approved_commit"
  printf 'release-tag-object=%s\n' "$approved_tag_object"
  printf 'team-id=%s\n' "$team_id"
  printf 'developer-id-sha1=%s\n' "$identity_sha1"
  printf 'input-app-tree-manifest-sha256=%s\n' "$input_app_manifest_sha"
  printf 'input-dsym-tree-manifest-sha256=%s\n' "$input_dsym_manifest_sha"
  printf 'input-arm64-uuid=%s\n' "$input_app_uuid"
  printf 'app-notary-submission-id=%s\n' "$app_submission_id"
  printf 'app-notary-log-sha256=%s\n' "$app_log_digest"
  printf 'dmg-notary-submission-id=%s\n' "$dmg_submission_id"
  printf 'dmg-notary-log-sha256=%s\n' "$dmg_log_digest"
  printf 'final-dmg-name=%s\n' "$dmg_name"
  printf 'final-dmg-sha256=%s\n' "$final_dmg_sha"
  printf 'final-dmg-size-bytes=%s\n' "$final_dmg_size"
} >"$evidence_record"

incomplete_marker="$output_stage/.lectureboard-release-incomplete"
printf 'Release package is incomplete until all post-handoff checks pass.\n' \
  >"$incomplete_marker"

run_clean /bin/chmod 755 "$output_stage" "$evidence_directory"
run_clean /bin/chmod 644 \
  "$output_stage/$dmg_name" \
  "$evidence_directory/app-submit.json" \
  "$evidence_directory/app-log.json" \
  "$evidence_directory/dmg-submit.json" \
  "$evidence_directory/dmg-log.json" \
  "$evidence_record" "$incomplete_marker"

verify_output_exact_set() {
  local root="$1" marker_expected="$2" list entry total=0 dmg=0 evidence=0 logs=0 marker=0
  [[ -d "$root" && ! -L "$root" ]] || return 1
  list="$(run_clean /usr/bin/mktemp "$temporary_root/output-entries.XXXXXX")" || return 1
  run_clean /usr/bin/find "$root" -mindepth 1 -maxdepth 1 -print0 >"$list" || return 1
  while IFS= read -r -d '' entry; do
    total=$((total + 1))
    case "${entry##*/}" in
      "$dmg_name") [[ -f "$entry" && ! -L "$entry" ]] || return 1; dmg=$((dmg + 1)) ;;
      release-package-evidence.txt) [[ -f "$entry" && ! -L "$entry" ]] || return 1; evidence=$((evidence + 1)) ;;
      notarization-evidence) [[ -d "$entry" && ! -L "$entry" ]] || return 1; logs=$((logs + 1)) ;;
      .lectureboard-release-incomplete) [[ -f "$entry" && ! -L "$entry" ]] || return 1; marker=$((marker + 1)) ;;
      *) return 1 ;;
    esac
  done <"$list"
  run_clean /bin/unlink "$list"
  [[ "$dmg" == 1 && "$evidence" == 1 && "$logs" == 1 ]] || return 1
  if [[ "$marker_expected" == yes ]]; then
    [[ "$total" == 4 && "$marker" == 1 ]]
  else
    [[ "$total" == 3 && "$marker" == 0 ]]
  fi
}

verify_notary_evidence_exact_set() {
  local root="$1" list entry total=0
  [[ -d "$root" && ! -L "$root" ]] || return 1
  list="$(run_clean /usr/bin/mktemp "$temporary_root/notary-entries.XXXXXX")" || return 1
  run_clean /usr/bin/find "$root" -mindepth 1 -maxdepth 1 -print0 >"$list" || return 1
  while IFS= read -r -d '' entry; do
    total=$((total + 1))
    [[ -f "$entry" && ! -L "$entry" ]] || return 1
    case "${entry##*/}" in
      app-submit.json|app-log.json|dmg-submit.json|dmg-log.json) ;;
      *) return 1 ;;
    esac
  done <"$list"
  run_clean /bin/unlink "$list"
  [[ "$total" == 4 ]]
}

verify_output_exact_set "$output_stage" yes \
  || fail 'the staged output root contains an unexpected entry'
verify_notary_evidence_exact_set "$evidence_directory" \
  || fail 'the staged notarization-evidence directory contains an unexpected entry'
output_tree_manifest="$temporary_root/output-tree.txt"
"${sanitized_environment[@]}" /bin/bash -p "$committed_artifact_tools" tree-manifest \
  --root "$output_stage" --output "$output_tree_manifest" \
  || fail 'the staged output tree could not be bounded'

assert_approved_source_state \
  || fail 'the approved source or commit state changed before output handoff'
[[ ! -e "$output_directory" && ! -L "$output_directory" ]] \
  || fail 'the output directory appeared before exclusive handoff'
"$rename_helper" "$output_stage" "$output_directory" \
  "${output_parent_identity% *}" "${output_parent_identity#* }" \
  "${output_stage_identity% *}" "${output_stage_identity#* }" \
  || fail 'the verified release-package output could not be handed off exclusively'
output_stage=''
[[ -d "$output_directory" && ! -L "$output_directory" \
  && -f "$output_directory/$dmg_name" && ! -L "$output_directory/$dmg_name" \
  && -f "$output_directory/release-package-evidence.txt" \
  && -f "$output_directory/.lectureboard-release-incomplete" ]] \
  || fail 'the exclusive release-package output handoff postcondition did not hold'
verify_output_exact_set "$output_directory" yes \
  || fail 'the handed-off output root contains an unexpected entry'
verify_notary_evidence_exact_set "$output_directory/notarization-evidence" \
  || fail 'the handed-off notarization-evidence directory contains an unexpected entry'
verify_release_code dmg "$output_directory/$dmg_name" >/dev/null \
  || fail 'the handed-off disk image failed final release-code verification'
"${sanitized_environment[@]}" /usr/bin/xcrun stapler validate \
  "$output_directory/$dmg_name" >/dev/null 2>&1 \
  || fail 'the handed-off disk image ticket did not validate'
handed_off_sha="$(run_clean /usr/bin/shasum -a 256 "$output_directory/$dmg_name" | run_clean /usr/bin/awk '{ print $1 }')"
handed_off_size="$(run_clean /usr/bin/stat -f '%z' "$output_directory/$dmg_name")"
[[ "$handed_off_sha" == "$final_dmg_sha" && "$handed_off_size" == "$final_dmg_size" ]] \
  || fail 'the handed-off disk image differs from the verified final disk image'
final_output_manifest="$temporary_root/final-output-tree.txt"
"${sanitized_environment[@]}" /bin/bash -p "$committed_artifact_tools" tree-manifest \
  --root "$output_directory" --output "$final_output_manifest" \
  || fail 'the handed-off output tree could not be bounded'
run_clean /usr/bin/cmp -s "$output_tree_manifest" "$final_output_manifest" \
  || fail 'the handed-off output tree differs from the verified output stage'
handoff_dmg_sha="$(run_clean /usr/bin/shasum -a 256 "$output_directory/$dmg_name" | run_clean /usr/bin/awk '{ print $1 }')"
handoff_dmg_size="$(run_clean /usr/bin/stat -f '%z' "$output_directory/$dmg_name")"
[[ "$handoff_dmg_sha" == "$final_dmg_sha" && "$handoff_dmg_size" == "$final_dmg_size" ]] \
  || fail 'the exclusive handoff changed the final disk image bytes'

required_cleanup_before_completion() {
  [[ -z "$mounted_device" && -z "$mounted_target" && -z "$output_stage" ]] \
    || return 1
  [[ -n "$temporary_root" && -d "$temporary_root" && ! -L "$temporary_root" ]] \
    || return 1
  case "$temporary_root" in
    "$temporary_parent"/lectureboard-release-package.*) ;;
    *) return 1 ;;
  esac
  run_clean /usr/bin/find "$temporary_root" -depth -delete || return 1
  [[ ! -e "$temporary_root" && ! -L "$temporary_root" ]] || return 1
  temporary_root=''
}

release_completion_marker() {
  local marker="$1"
  [[ -f "$marker" && ! -L "$marker" ]] || return 1
  run_clean /bin/unlink "$marker" || return 1
  [[ ! -e "$marker" && ! -L "$marker" ]]
}

required_cleanup_before_completion \
  || fail 'required release-package cleanup did not complete before marker release'
# Required cleanup is complete, so no EXIT action is permitted to change the
# success status after the marker is released. Error-path cleanup above remains
# explicitly best effort.
trap - EXIT
release_completion_marker "$output_directory/.lectureboard-release-incomplete" \
  || fail 'the incomplete-output marker could not be released and confirmed absent'

best_effort_print 'Verified notarized release DMG: %s\n' "$output_directory/$dmg_name"
best_effort_print 'Release commit: %s\n' "$approved_commit"
best_effort_print 'Release tag object: %s\n' "$approved_tag_object"
best_effort_print 'Final DMG SHA-256: %s\n' "$final_dmg_sha"
best_effort_print 'Final DMG size: %s bytes\n' "$final_dmg_size"
best_effort_print 'Application notarization submission: %s\n' "$app_submission_id"
best_effort_print 'Disk-image notarization submission: %s\n' "$dmg_submission_id"
best_effort_print 'Publication status: not published by this script\n'
exit 0
