#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail
export LC_ALL=C
export PATH='/usr/bin:/bin:/usr/sbin:/sbin'
unset CDPATH
umask 022

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && /bin/pwd -P)"
repository_root="$(cd -- "$script_directory/.." && /bin/pwd -P)"
preflight="$script_directory/release-preflight.sh"
expected_bundle_identifier='io.github.akiyama709.LectureBoardAI'
expected_product_name='LectureBoard AI'
expected_version='1.0.0'
expected_tag='v1.0.0'
expected_deployment_target='26.0'

fail() {
  printf 'Release app build failed: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf 'Usage: %s --output-dir /absolute/new/directory\n' "$(/usr/bin/basename -- "$0")"
}

require_single_line_fixture() {
  local path="$fixture_directory/$1"
  local label="$2"
  local line_count value

  [[ -f "$path" ]] || fail "a required $label fixture is missing"
  line_count="$(/usr/bin/awk 'END { print NR + 0 }' "$path")"
  [[ "$line_count" == '1' ]] || fail "$label fixture must contain exactly one line"
  IFS= read -r value <"$path" || true
  [[ -n "$value" ]] || fail "$label fixture must not be empty"
  printf '%s\n' "$value"
}

normalize_hex() {
  printf '%s' "$1" | /usr/bin/tr '[:lower:]' '[:upper:]'
}

output_directory=''
output_seen=0
while (( $# > 0 )); do
  case "$1" in
    --output-dir)
      (( $# >= 2 )) || { usage >&2; exit 64; }
      (( output_seen == 0 )) || { usage >&2; exit 64; }
      output_seen=1
      output_directory="$2"
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

[[ "$output_seen" == '1' && "$output_directory" == /* ]] \
  || { usage >&2; exit 64; }
[[ "$output_directory" != '/' ]] || fail 'the output directory is too broad'

team_id="${LECTUREBOARD_DEVELOPMENT_TEAM:-}"
identity_sha1="${LECTUREBOARD_DEVELOPER_ID_SHA1:-}"
release_version="${LECTUREBOARD_RELEASE_VERSION:-}"
release_date="${LECTUREBOARD_RELEASE_DATE:-}"
build_number="${LECTUREBOARD_RELEASE_BUILD_NUMBER:-}"
approved_commit="${LECTUREBOARD_RELEASE_CI_COMMIT:-}"
approved_tag_object="${LECTUREBOARD_RELEASE_TAG_OBJECT:-}"
test_mode="${LECTUREBOARD_RELEASE_BUILD_TEST_MODE:-}"
fixture_directory="${LECTUREBOARD_RELEASE_BUILD_FIXTURE_DIR:-}"

[[ "$team_id" =~ ^[A-Z0-9]{10}$ ]] \
  || fail 'LECTUREBOARD_DEVELOPMENT_TEAM must be a 10-character Apple team identifier'
[[ "$identity_sha1" =~ ^[0-9A-Fa-f]{40}$ ]] \
  || fail 'LECTUREBOARD_DEVELOPER_ID_SHA1 must be a 40-digit SHA-1 fingerprint'
identity_sha1="$(normalize_hex "$identity_sha1")"
[[ "$release_version" == "$expected_version" ]] \
  || fail 'LECTUREBOARD_RELEASE_VERSION must be exactly 1.0.0'
[[ "$release_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] \
  || fail 'LECTUREBOARD_RELEASE_DATE must use YYYY-MM-DD'
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] \
  || fail 'LECTUREBOARD_RELEASE_BUILD_NUMBER must be a positive integer'
[[ "$approved_commit" =~ ^[0-9A-Fa-f]{40}$|^[0-9A-Fa-f]{64}$ ]] \
  || fail 'LECTUREBOARD_RELEASE_CI_COMMIT must be a full commit object identifier'
approved_commit="$(normalize_hex "$approved_commit")"
[[ "$approved_tag_object" =~ ^[0-9A-Fa-f]{40}$|^[0-9A-Fa-f]{64}$ ]] \
  || fail 'LECTUREBOARD_RELEASE_TAG_OBJECT must be a full annotated-tag object identifier'
approved_tag_object="$(normalize_hex "$approved_tag_object")"

case "$test_mode" in
  '')
    [[ -z "$fixture_directory" ]] || fail 'fixture input requires explicit test mode'
    for forbidden_fixture_variable in \
      LECTUREBOARD_RELEASE_PREFLIGHT_TEST_MODE \
      LECTUREBOARD_RELEASE_PREFLIGHT_FIXTURE_DIR \
      LECTUREBOARD_RELEASE_CODE_TEST_MODE \
      LECTUREBOARD_RELEASE_CODE_FIXTURE_DIR; do
      [[ -z "${!forbidden_fixture_variable:-}" ]] \
        || fail 'production release build forbids nested fixture-mode inputs'
    done
    for forbidden_environment_variable in \
      BASH_ENV ENV \
      GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_EXEC_PATH GIT_CONFIG_COUNT \
      GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM \
      GIT_CONFIG_NOSYSTEM \
      XCODE_XCCONFIG_FILE TOOLCHAINS SWIFT_EXEC SWIFT_DRIVER_SWIFT_FRONTEND_EXEC \
      CC CXX LD CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH LIBRARY_PATH \
      SDKROOT DEVELOPER_DIR DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH \
      DYLD_FALLBACK_LIBRARY_PATH DYLD_FALLBACK_FRAMEWORK_PATH DYLD_INSERT_LIBRARIES \
      TAR_OPTIONS COPYFILE_DISABLE COPY_EXTENDED_ATTRIBUTES; do
      [[ -z "${!forbidden_environment_variable:-}" ]] \
        || fail 'production release build forbids toolchain or repository override inputs'
    done
    ;;
  fixture-v1)
    [[ "$fixture_directory" == /* && -d "$fixture_directory" ]] \
      || fail 'fixture-v1 requires an absolute fixture directory'
    ;;
  *) fail 'unsupported release-build test mode' ;;
esac

temporary_parent='/private/tmp'
temporary_root=''
output_stage=''
cleanup() {
  if [[ -n "$temporary_root" && -d "$temporary_root" ]]; then
    case "$temporary_root" in
      "$temporary_parent"/lectureboard-release-build.*)
        /usr/bin/find "$temporary_root" -depth -delete
        ;;
    esac
  fi
  if [[ -n "$output_stage" && -d "$output_stage" ]]; then
    case "$output_stage" in
      */.lectureboard-release-output.*)
        /usr/bin/find "$output_stage" -depth -delete
        ;;
    esac
  fi
}
trap cleanup EXIT

current_user="$(/usr/bin/id -un)" || fail 'the release-build user could not be identified'
trusted_home="$(
  /usr/bin/id -P "$current_user" | /usr/bin/awk -F: 'NF >= 9 { print $9 }'
)" || fail 'the release-build home directory could not be identified'
[[ "$trusted_home" == /* && -d "$trusted_home" ]] \
  || fail 'the release-build home directory is invalid'

sanitized_environment=(
  /usr/bin/env
  -i
  PATH=/usr/bin:/bin:/usr/sbin:/sbin
  LC_ALL=C
  TMPDIR=/private/tmp
  HOME="$trusted_home"
  USER="$current_user"
  LOGNAME="$current_user"
)

sanitized_git_environment=(
  /usr/bin/env
  -i
  PATH=/usr/bin:/bin:/usr/sbin:/sbin
  LC_ALL=C
  GIT_CONFIG_NOSYSTEM=1
  GIT_CONFIG_GLOBAL=/dev/null
  GIT_CONFIG_SYSTEM=/dev/null
  GIT_NO_REPLACE_OBJECTS=1
  GIT_ATTR_NOSYSTEM=1
)
git_read_command=(
  "${sanitized_git_environment[@]}"
  /usr/bin/git
  --no-replace-objects
  -c core.fsmonitor=false
  -c core.untrackedCache=false
  -c core.attributesFile=/dev/null
  -c tar.umask=0000
)

assert_current_release_refs_match() {
  local current_head current_tag_object current_tag_type current_tag_target current_origin_main

  current_head="$(
    "${git_read_command[@]}" -C "$repository_root" rev-parse --verify HEAD^{commit}
  )" \
    || fail 'HEAD could not be resolved after release preflight'
  current_tag_target="$(
    "${git_read_command[@]}" -C "$repository_root" rev-parse --verify "refs/tags/$expected_tag^{}"
  )" || fail 'the release tag could not be resolved after release preflight'
  current_tag_object="$(
    "${git_read_command[@]}" -C "$repository_root" rev-parse --verify "refs/tags/$expected_tag"
  )" || fail 'the annotated release-tag object could not be resolved after release preflight'
  current_tag_type="$(
    "${git_read_command[@]}" -C "$repository_root" cat-file -t "refs/tags/$expected_tag"
  )" || fail 'the release-tag object type could not be resolved after release preflight'
  current_origin_main="$(
    "${git_read_command[@]}" -C "$repository_root" rev-parse --verify refs/remotes/origin/main^{commit}
  )" || fail 'origin/main could not be resolved after release preflight'

  [[ "$(normalize_hex "$current_head")" == "$approved_commit" ]] \
    || fail 'HEAD changed after release preflight'
  [[ "$(normalize_hex "$current_tag_target")" == "$approved_commit" ]] \
    || fail 'the release tag changed after release preflight'
  [[ "$current_tag_type" == 'tag' ]] \
    || fail 'the release tag is no longer an annotated tag'
  [[ "$(normalize_hex "$current_tag_object")" == "$approved_tag_object" ]] \
    || fail 'the annotated release-tag object changed after release preflight'
  [[ "$(normalize_hex "$current_origin_main")" == "$approved_commit" ]] \
    || fail 'origin/main changed after release preflight'
}

if [[ "$test_mode" == 'fixture-v1' ]]; then
  preflight_status="$(require_single_line_fixture preflight-status.txt 'preflight status')"
else
  [[ -x "$preflight" ]] || fail 'the release preflight is unavailable'
  if "${sanitized_environment[@]}" \
    LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
    LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
    LECTUREBOARD_RELEASE_VERSION="$release_version" \
    LECTUREBOARD_RELEASE_DATE="$release_date" \
    LECTUREBOARD_RELEASE_BUILD_NUMBER="$build_number" \
    LECTUREBOARD_RELEASE_CI_COMMIT="$approved_commit" \
    LECTUREBOARD_RELEASE_TAG_OBJECT="$approved_tag_object" \
      /bin/bash -p "$preflight"; then
    preflight_status='0'
  else
    preflight_status='1'
  fi
fi
[[ "$preflight_status" == '0' ]] || fail 'the production release preflight did not pass'

if [[ "$test_mode" == 'fixture-v1' ]]; then
  post_preflight_head="$(require_single_line_fixture post-preflight-head.txt 'post-preflight HEAD')"
  post_preflight_tag="$(require_single_line_fixture post-preflight-tag.txt 'post-preflight tag')"
  post_preflight_tag_object="$(require_single_line_fixture post-preflight-tag-object.txt 'post-preflight tag object')"
  post_preflight_tag_type="$(require_single_line_fixture post-preflight-tag-type.txt 'post-preflight tag type')"
  post_preflight_origin_main="$(require_single_line_fixture post-preflight-origin-main.txt 'post-preflight origin/main')"
  pre_handoff_head="$(require_single_line_fixture pre-handoff-head.txt 'pre-handoff HEAD')"
  pre_handoff_tag="$(require_single_line_fixture pre-handoff-tag.txt 'pre-handoff tag')"
  pre_handoff_tag_object="$(require_single_line_fixture pre-handoff-tag-object.txt 'pre-handoff tag object')"
  pre_handoff_tag_type="$(require_single_line_fixture pre-handoff-tag-type.txt 'pre-handoff tag type')"
  pre_handoff_origin_main="$(require_single_line_fixture pre-handoff-origin-main.txt 'pre-handoff origin/main')"
  tracked_link_count="$(require_single_line_fixture tracked-link-count.txt 'tracked link count')"
  replacement_ref_count="$(require_single_line_fixture replacement-ref-count.txt 'replacement ref count')"
  local_config_override_count="$(require_single_line_fixture local-config-override-count.txt 'local Git config override count')"
  info_attributes_status="$(require_single_line_fixture info-attributes-status.txt 'Git info attributes status')"
  gitattributes_count="$(require_single_line_fixture gitattributes-count.txt 'gitattributes count')"
  extracted_link_count="$(require_single_line_fixture extracted-link-count.txt 'extracted link count')"
  extracted_tree_status="$(require_single_line_fixture extracted-tree-status.txt 'extracted Git-tree status')"
  reviewed_project_status="$(require_single_line_fixture reviewed-project-status.txt 'reviewed Xcode source status')"
  generated_project_status="$(require_single_line_fixture generated-project-status.txt 'generated-project status')"
  project_reference_status="$(require_single_line_fixture project-reference-status.txt 'project-reference status')"
  project_support_status="$(require_single_line_fixture project-support-status.txt 'project-support status')"
  package_manifest_status="$(require_single_line_fixture package-manifest-status.txt 'package-manifest status')"
  archive_status="$(require_single_line_fixture archive-status.txt 'archive status')"
  app_exists="$(require_single_line_fixture app-exists.txt 'archive app existence')"
  bundle_identifier="$(require_single_line_fixture bundle-identifier.txt 'bundle identifier')"
  archive_version="$(require_single_line_fixture marketing-version.txt 'marketing version')"
  archive_build_number="$(require_single_line_fixture build-number.txt 'build number')"
  architecture="$(require_single_line_fixture architecture.txt 'architecture')"
  debug_dylib_count="$(require_single_line_fixture debug-dylib-count.txt 'debug dylib count')"
  archive_verifier_status="$(require_single_line_fixture archive-verifier-status.txt 'archive verifier status')"
  copy_status="$(require_single_line_fixture copy-status.txt 'copy status')"
  copied_verifier_status="$(require_single_line_fixture copied-verifier-status.txt 'copied verifier status')"
  copied_tree_status="$(require_single_line_fixture copied-tree-status.txt 'copied tree status')"
  dsym_exists="$(require_single_line_fixture dsym-exists.txt 'dSYM existence')"
  app_uuid="$(require_single_line_fixture app-uuid.txt 'application UUID')"
  dsym_uuid="$(require_single_line_fixture dsym-uuid.txt 'dSYM UUID')"
  staged_dsym_uuid="$(require_single_line_fixture staged-dsym-uuid.txt 'staged dSYM UUID')"
  handoff_status="$(require_single_line_fixture handoff-status.txt 'handoff status')"
  handoff_postcondition_status="$(require_single_line_fixture handoff-postcondition-status.txt 'handoff postcondition status')"
  output_layout_status="$(require_single_line_fixture output-layout-status.txt 'output-layout status')"
  final_verifier_status="$(require_single_line_fixture final-verifier-status.txt 'final verifier status')"
  final_tree_status="$(require_single_line_fixture final-tree-status.txt 'final tree status')"
  final_output_tree_status="$(require_single_line_fixture final-output-tree-status.txt 'final output-tree status')"
  marker_cleanup_status="$(require_single_line_fixture marker-cleanup-status.txt 'handoff marker cleanup status')"
  marker_absence_status="$(require_single_line_fixture marker-absence-status.txt 'handoff marker absence status')"
  pre_completion_cleanup_status="$(require_single_line_fixture pre-completion-cleanup-status.txt 'pre-completion cleanup status')"
else
  assert_current_release_refs_match
  for required_tool in \
    /usr/bin/git /usr/bin/tar /usr/bin/mktemp /usr/bin/find /usr/bin/xcodebuild \
    /usr/bin/plutil /usr/bin/lipo /usr/bin/ditto /usr/bin/diff /usr/bin/env \
    /usr/bin/clang /usr/bin/cmp /usr/bin/dwarfdump /usr/bin/file /usr/bin/shasum \
    /usr/bin/stat /usr/bin/sort /usr/bin/readlink /bin/unlink /bin/mkdir \
    /bin/realpath /opt/homebrew/bin/xcodegen; do
    [[ -x "$required_tool" ]] || fail 'a required release-build tool is unavailable'
  done
  privileged_bash='/bin/bash'
  [[ -x "$privileged_bash" ]] || fail 'privileged Bash is unavailable'

  [[ ! -e "$output_directory" && ! -L "$output_directory" ]] \
    || fail 'the output directory must not already exist'
  output_parent="$(/usr/bin/dirname -- "$output_directory")"
  output_basename="$(/usr/bin/basename -- "$output_directory")"
  [[ -d "$output_parent" && ! -L "$output_parent" ]] \
    || fail 'the output parent must be an existing non-symbolic-link directory'
  canonical_parent="$(/bin/realpath "$output_parent")" \
    || fail 'the output parent could not be resolved'
  [[ "$output_directory" == "$canonical_parent/$output_basename" ]] \
    || fail 'the output directory must use a canonical absolute parent path'
  [[ "$output_basename" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
    || fail 'the output directory name is malformed'
  case "$canonical_parent/" in
    "$repository_root/"*) fail 'the release output must be outside the source repository' ;;
  esac

  replacement_ref_count="$(
    "${git_read_command[@]}" -C "$repository_root" \
      for-each-ref --format='%(refname)' refs/replace/ \
      | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }'
  )" || fail 'Git replacement refs could not be audited'
  [[ "$replacement_ref_count" == '0' ]] \
    || fail 'the release repository contains a Git replacement ref'
  local_config_override_count="$(
    "${git_read_command[@]}" -C "$repository_root" config --local --no-includes --list \
      2>/dev/null \
      | /usr/bin/awk -F= \
        '$1 ~ /^(include\.|includeif\.|core\.attributesfile$|core\.fsmonitor$|core\.hookspath$)/ { count += 1 } END { print count + 0 }'
  )" || fail 'the local Git configuration could not be audited'
  [[ "$local_config_override_count" == '0' ]] \
    || fail 'the release repository contains an unsafe local Git configuration override'
  info_attributes_path="$(
    "${git_read_command[@]}" -C "$repository_root" \
      rev-parse --path-format=absolute --git-path info/attributes
  )" || fail 'the repository-local Git attributes path could not be resolved'
  if [[ -e "$info_attributes_path" || -L "$info_attributes_path" ]]; then
    info_attributes_status='1'
  else
    info_attributes_status='0'
  fi
  [[ "$info_attributes_status" == '0' ]] \
    || fail 'the release repository contains repository-local Git attributes'
  tracked_link_count="$(
    "${git_read_command[@]}" -C "$repository_root" ls-tree -r "$approved_commit" \
      | /usr/bin/awk '$1 == "120000" || $1 == "160000" { count += 1 } END { print count + 0 }'
  )" || fail 'the approved commit tree modes could not be audited'
  [[ "$tracked_link_count" == '0' ]] \
    || fail 'the approved release commit contains a tracked symbolic link or submodule'
  gitattributes_count="$(
    "${git_read_command[@]}" -C "$repository_root" \
      ls-tree -r --name-only "$approved_commit" \
      | /usr/bin/awk '$0 == ".gitattributes" || $0 ~ /\/\.gitattributes$/ { count += 1 } END { print count + 0 }'
  )" || fail 'the approved release attributes could not be audited'
  [[ "$gitattributes_count" == '0' ]] \
    || fail 'the approved release commit contains unsupported Git archive attributes'

  temporary_root="$(/usr/bin/mktemp -d "$temporary_parent/lectureboard-release-build.XXXXXX")" \
    || fail 'the isolated release-build directory could not be created'
  case "$temporary_root" in
    "$temporary_parent"/lectureboard-release-build.*) ;;
    *) fail 'the isolated release-build directory is unsafe' ;;
  esac

  source_root="$temporary_root/source"
  archive_path="$temporary_root/LectureBoardAI.xcarchive"
  derived_data_path="$temporary_root/DerivedData"
  /bin/mkdir "$source_root"
  if ! "${git_read_command[@]}" -C "$repository_root" \
    archive --format=tar "$approved_commit" \
    | "${sanitized_environment[@]}" /usr/bin/tar -xf - -C "$source_root"; then
    fail 'the approved release commit could not be isolated'
  fi
  extracted_link_count="$(
    /usr/bin/find "$source_root" -type l -print | /usr/bin/awk 'END { print NR + 0 }'
  )"
  [[ "$extracted_link_count" == '0' ]] \
    || fail 'the isolated release source contains a symbolic link'
  artifact_tools="$source_root/scripts/release-artifact-tools.sh"
  if [[ -x "$artifact_tools" ]] \
    && "${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" \
      verify-extracted-git-tree --repository "$repository_root" \
      --commit "$approved_commit" --source "$source_root"; then
    extracted_tree_status='0'
  else
    extracted_tree_status='1'
  fi
  [[ "$extracted_tree_status" == '0' ]] \
    || fail 'the isolated source differs from the exact approved Git tree'
  if [[ -x "$artifact_tools" ]] \
    && "${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" \
      verify-reviewed-xcode-source --root "$source_root"; then
    reviewed_project_status='0'
  else
    reviewed_project_status='1'
  fi
  [[ "$reviewed_project_status" == '0' ]] \
    || fail 'the isolated XcodeGen input differs from the exact reviewed source'
  generated_source_root="$temporary_root/generated-source"
  "${sanitized_environment[@]}" /usr/bin/ditto --noqtn "$source_root" "$generated_source_root" \
    || fail 'the generated-project comparison source could not be copied'
  if ! (
    cd "$generated_source_root"
    "${sanitized_environment[@]}" /opt/homebrew/bin/xcodegen generate >/dev/null
  ); then
    fail 'isolated release project generation failed'
  fi
  if /usr/bin/diff -qr \
    "$source_root/LectureBoardAI.xcodeproj" \
    "$generated_source_root/LectureBoardAI.xcodeproj" >/dev/null 2>&1; then
    generated_project_status='0'
  else
    generated_project_status='1'
  fi
  [[ "$generated_project_status" == '0' ]] \
    || fail 'the approved checked-in project differs from isolated XcodeGen output'
  if [[ -f "$artifact_tools" ]] \
    && "${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" \
      verify-project-containment \
      --path "$source_root/LectureBoardAI.xcodeproj/project.pbxproj"; then
    project_reference_status='0'
  else
    project_reference_status='1'
  fi
  [[ "$project_reference_status" == '0' ]] \
    || fail 'the approved Xcode project contains an external source reference'
  if "${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" \
    verify-xcode-project-support --root "$source_root/LectureBoardAI.xcodeproj"; then
    project_support_status='0'
  else
    project_support_status='1'
  fi
  [[ "$project_support_status" == '0' ]] \
    || fail 'the approved Xcode project support files differ from the reviewed release set'
  if "${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" \
    verify-package-manifests --root "$source_root"; then
    package_manifest_status='0'
  else
    package_manifest_status='1'
  fi
  [[ "$package_manifest_status" == '0' ]] \
    || fail 'the approved source contains an unsupported Swift package manifest'
  rename_helper_source="$source_root/scripts/release-exclusive-rename.c"
  rename_helper="$temporary_root/release-exclusive-rename"
  committed_verifier="$source_root/scripts/verify-release-code.sh"
  committed_requirement_policy="$source_root/scripts/runtime-signing-requirement.sh"
  [[ -f "$rename_helper_source" ]] \
    || fail 'the approved release commit lacks the exclusive-handoff helper'
  [[ -x "$committed_verifier" && -f "$committed_requirement_policy" \
    && -f "$artifact_tools" ]] \
    || fail 'the approved release commit lacks its release-code verifier'
  "${sanitized_environment[@]}" /usr/bin/clang \
    -std=c17 -Wall -Wextra -Werror -O2 \
    "$rename_helper_source" -o "$rename_helper" \
    || fail 'the exclusive-handoff helper could not be compiled'

  if "${sanitized_environment[@]}" /usr/bin/xcodebuild \
    -project "$source_root/LectureBoardAI.xcodeproj" \
    -scheme LectureBoardAI \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -archivePath "$archive_path" \
    -derivedDataPath "$derived_data_path" \
    -disableAutomaticPackageResolution \
    -skipPackageUpdates \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    "CODE_SIGN_IDENTITY=$identity_sha1" \
    "DEVELOPMENT_TEAM=$team_id" \
    "INFOPLIST_KEY_LectureBoardReleaseCommit=$approved_commit" \
    "INFOPLIST_KEY_LectureBoardReleaseTagObject=$approved_tag_object" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    ENABLE_HARDENED_RUNTIME=YES \
    ENABLE_DEBUG_DYLIB=NO \
    ARCHS=arm64 \
    ONLY_ACTIVE_ARCH=NO \
    SKIP_INSTALL=NO \
    DEBUG_INFORMATION_FORMAT=dwarf-with-dsym \
    "MACOSX_DEPLOYMENT_TARGET=$expected_deployment_target" \
    'OTHER_CODE_SIGN_FLAGS=--timestamp' \
    clean archive; then
    archive_status='0'
  else
    archive_status='1'
  fi

  archived_app="$archive_path/Products/Applications/$expected_product_name.app"
  if [[ -d "$archived_app" && ! -L "$archived_app" ]]; then
    app_exists='1'
  else
    app_exists='0'
  fi
  [[ "$app_exists" == '1' ]] || fail 'the signed archive did not contain the expected application'

  info_plist="$archived_app/Contents/Info.plist"
  [[ -f "$info_plist" ]] || fail 'the archived application Info.plist is missing'
  bundle_identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$info_plist" 2>/dev/null)" \
    || fail 'the archived bundle identifier could not be read'
  archive_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$info_plist" 2>/dev/null)" \
    || fail 'the archived marketing version could not be read'
  archive_build_number="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$info_plist" 2>/dev/null)" \
    || fail 'the archived build number could not be read'
  executable_name="$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$info_plist" 2>/dev/null)" \
    || fail 'the archived executable name could not be read'
  executable_path="$archived_app/Contents/MacOS/$executable_name"
  [[ -f "$executable_path" ]] || fail 'the archived executable is missing'
  architecture="$(/usr/bin/lipo -archs "$executable_path" 2>/dev/null)" \
    || fail 'the archived executable architecture could not be read'
  [[ -x "$executable_path" ]] || fail 'the archived main executable is not executable'
  debug_dylib_count="$({ /usr/bin/find "$archived_app/Contents/MacOS" -type f -name '*.debug.dylib' -print; } | /usr/bin/awk 'END { print NR + 0 }')"

  if "${sanitized_environment[@]}" \
    LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
    LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
    LECTUREBOARD_RELEASE_VERSION="$release_version" \
    LECTUREBOARD_RELEASE_BUILD_NUMBER="$build_number" \
    LECTUREBOARD_RELEASE_CI_COMMIT="$approved_commit" \
    LECTUREBOARD_RELEASE_TAG_OBJECT="$approved_tag_object" \
      /bin/bash -p "$committed_verifier" --kind app --path "$archived_app"; then
    archive_verifier_status='0'
  else
    archive_verifier_status='1'
  fi

  archive_tree_manifest="$temporary_root/archive-app-tree.txt"
  "${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" tree-manifest \
    --root "$archived_app" --output "$archive_tree_manifest" \
    || fail 'the archived application tree could not be bounded'

  output_stage="$(/usr/bin/mktemp -d "$canonical_parent/.lectureboard-release-output.XXXXXX")" \
    || fail 'the atomic output stage could not be created'
  case "$output_stage" in
    "$canonical_parent"/.lectureboard-release-output.*) ;;
    *) fail 'the atomic output stage is unsafe' ;;
  esac
  staged_app="$output_stage/$expected_product_name.app"
  if "${sanitized_environment[@]}" /usr/bin/ditto --noqtn "$archived_app" "$staged_app"; then
    copy_status='0'
  else
    copy_status='1'
  fi

  if "${sanitized_environment[@]}" \
    LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
    LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
    LECTUREBOARD_RELEASE_VERSION="$release_version" \
    LECTUREBOARD_RELEASE_BUILD_NUMBER="$build_number" \
    LECTUREBOARD_RELEASE_CI_COMMIT="$approved_commit" \
    LECTUREBOARD_RELEASE_TAG_OBJECT="$approved_tag_object" \
      /bin/bash -p "$committed_verifier" --kind app --path "$staged_app"; then
    copied_verifier_status='0'
  else
    copied_verifier_status='1'
  fi
  staged_tree_manifest="$temporary_root/staged-app-tree.txt"
  if "${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" tree-manifest \
      --root "$staged_app" --output "$staged_tree_manifest" \
    && /usr/bin/cmp -s "$archive_tree_manifest" "$staged_tree_manifest"; then
    copied_tree_status='0'
  else
    copied_tree_status='1'
  fi

  archived_dsym="$archive_path/dSYMs/$expected_product_name.app.dSYM"
  if [[ -d "$archived_dsym" ]]; then
    dsym_exists='1'
    app_uuid="$("${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" arm64-uuid --path "$executable_path")"
    dsym_uuid="$("${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" arm64-uuid --path "$archived_dsym")"
    archive_dsym_manifest="$temporary_root/archive-dsym-tree.txt"
    "${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" tree-manifest \
      --root "$archived_dsym" --output "$archive_dsym_manifest" \
      || fail 'the archived dSYM tree could not be bounded'
    "${sanitized_environment[@]}" /usr/bin/ditto --noqtn "$archived_dsym" \
      "$output_stage/$expected_product_name.app.dSYM" \
      || fail 'the release dSYM could not be staged'
    staged_dsym_uuid="$(
      "${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" arm64-uuid \
        --path "$output_stage/$expected_product_name.app.dSYM"
    )"
    staged_dsym_manifest="$temporary_root/staged-dsym-tree.txt"
    "${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" tree-manifest \
      --root "$output_stage/$expected_product_name.app.dSYM" \
      --output "$staged_dsym_manifest" \
      || fail 'the staged dSYM tree could not be bounded'
    /usr/bin/cmp -s "$archive_dsym_manifest" "$staged_dsym_manifest" \
      || fail 'the staged dSYM differs from the archived dSYM'
  else
    dsym_exists='0'
    app_uuid='missing'
    dsym_uuid='missing'
    staged_dsym_uuid='missing'
  fi
fi

if [[ "$test_mode" == 'fixture-v1' ]]; then
  for observed_commit in \
    "$post_preflight_head" \
    "$post_preflight_tag" \
    "$post_preflight_origin_main" \
    "$pre_handoff_head" \
    "$pre_handoff_tag" \
    "$pre_handoff_origin_main"; do
    [[ "$observed_commit" =~ ^[0-9A-Fa-f]{40}$|^[0-9A-Fa-f]{64}$ ]] \
      || fail 'a fixture release-ref observation is malformed'
    [[ "$(normalize_hex "$observed_commit")" == "$approved_commit" ]] \
      || fail 'a release ref changed after production preflight'
  done
  for observed_tag_object in \
    "$post_preflight_tag_object" \
    "$pre_handoff_tag_object"; do
    [[ "$observed_tag_object" =~ ^[0-9A-Fa-f]{40}$|^[0-9A-Fa-f]{64}$ ]] \
      || fail 'a fixture release-tag object observation is malformed'
    [[ "$(normalize_hex "$observed_tag_object")" == "$approved_tag_object" ]] \
      || fail 'the annotated release-tag object changed after production preflight'
  done
  [[ "$post_preflight_tag_type" == 'tag' && "$pre_handoff_tag_type" == 'tag' ]] \
    || fail 'the release tag is no longer an annotated tag'
fi
[[ "$tracked_link_count" == '0' ]] \
  || fail 'the approved release commit contains a tracked symbolic link or submodule'
[[ "$replacement_ref_count" == '0' ]] \
  || fail 'the release repository contains a Git replacement ref'
[[ "$local_config_override_count" == '0' ]] \
  || fail 'the release repository contains an unsafe local Git configuration override'
[[ "$info_attributes_status" == '0' ]] \
  || fail 'the release repository contains repository-local Git attributes'
[[ "$gitattributes_count" == '0' ]] \
  || fail 'the approved release commit contains unsupported Git archive attributes'
[[ "$extracted_link_count" == '0' ]] \
  || fail 'the isolated release source contains a symbolic link'
[[ "$extracted_tree_status" == '0' ]] \
  || fail 'the approved source differs from the exact Git tree'
[[ "$reviewed_project_status" == '0' ]] \
  || fail 'the approved XcodeGen input differs from the exact reviewed source'
[[ "$generated_project_status" == '0' ]] \
  || fail 'the approved checked-in project differs from isolated XcodeGen output'
[[ "$project_reference_status" == '0' ]] \
  || fail 'the approved Xcode project contains an external source reference'
[[ "$project_support_status" == '0' ]] \
  || fail 'the approved Xcode project support files differ from the reviewed release set'
[[ "$package_manifest_status" == '0' ]] \
  || fail 'the approved source contains an unsupported Swift package manifest'
[[ "$archive_status" == '0' ]] || fail 'the signed Release archive did not complete'
[[ "$app_exists" == '1' ]] || fail 'the signed archive did not contain the expected application'
[[ "$bundle_identifier" == "$expected_bundle_identifier" ]] \
  || fail 'the archived application has the wrong bundle identifier'
[[ "$archive_version" == "$release_version" ]] \
  || fail 'the archived application has the wrong marketing version'
[[ "$archive_build_number" == "$build_number" ]] \
  || fail 'the archived application has the wrong build number'
[[ "$architecture" == 'arm64' ]] \
  || fail 'the archived application must contain exactly arm64 code'
[[ "$debug_dylib_count" == '0' ]] \
  || fail 'the archived application contains a debug dylib'
[[ "$archive_verifier_status" == '0' ]] \
  || fail 'the archived application did not pass release-code verification'
[[ "$copy_status" == '0' ]] || fail 'the release application could not be staged'
[[ "$copied_verifier_status" == '0' ]] \
  || fail 'the staged application did not pass release-code verification'
[[ "$copied_tree_status" == '0' ]] \
  || fail 'the staged application differs from the verified archive application'
[[ "$dsym_exists" == '1' ]] || fail 'the signed archive did not contain the required dSYM'
for observed_uuid in "$app_uuid" "$dsym_uuid" "$staged_dsym_uuid"; do
  [[ "$observed_uuid" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] \
    || fail 'a release UUID observation is malformed'
done
[[ "$(normalize_hex "$app_uuid")" == "$(normalize_hex "$dsym_uuid")" \
  && "$(normalize_hex "$app_uuid")" == "$(normalize_hex "$staged_dsym_uuid")" ]] \
  || fail 'the application and dSYM UUIDs do not match'

if [[ "$test_mode" == 'fixture-v1' ]]; then
  [[ "$handoff_status" == '0' ]] || fail 'the verified release output could not be handed off'
  [[ "$handoff_postcondition_status" == '0' ]] \
    || fail 'the exclusive output handoff postcondition did not hold'
  [[ "$output_layout_status" == '0' ]] \
    || fail 'the handed-off release output does not have the exact expected layout'
  [[ "$final_verifier_status" == '0' ]] \
    || fail 'the handed-off application did not pass final release-code verification'
  [[ "$final_tree_status" == '0' ]] \
    || fail 'the handed-off application differs from the verified archive application'
  [[ "$final_output_tree_status" == '0' ]] \
    || fail 'the completed release output differs from the staged release output'
  [[ "$pre_completion_cleanup_status" == '0' ]] \
    || fail 'release-build temporary state could not be removed before completion'
  [[ "$marker_cleanup_status" == '0' ]] \
    || fail 'the incomplete-output marker could not be removed'
  [[ "$marker_absence_status" == '0' ]] \
    || fail 'the incomplete-output marker still exists or is a symbolic link'
  printf 'Release app build fixture simulation passed; no archive, signature, or artifact was produced.\n' || :
else
  assert_current_release_refs_match
  /bin/chmod 755 "$output_stage"
  staged_output_manifest="$temporary_root/staged-output-tree.txt"
  "${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" tree-manifest \
    --root "$output_stage" --output "$staged_output_manifest" \
    || fail 'the staged release output tree could not be bounded'
  incomplete_marker="$output_stage/.lectureboard-release-incomplete"
  printf 'Release output is incomplete until all post-handoff checks pass.\n' \
    >"$incomplete_marker"
  if "$rename_helper" "$output_stage" "$output_directory"; then
    handoff_status='0'
  else
    handoff_status='1'
  fi
  [[ "$handoff_status" == '0' ]] \
    || fail 'the verified release output could not be handed off'
  output_stage=''

  handed_off_app="$output_directory/$expected_product_name.app"
  handed_off_dsym="$output_directory/$expected_product_name.app.dSYM"
  handed_off_marker="$output_directory/.lectureboard-release-incomplete"
  if [[ -d "$output_directory" && ! -L "$output_directory" \
    && -d "$handed_off_app" && ! -L "$handed_off_app" \
    && -d "$handed_off_dsym" && ! -L "$handed_off_dsym" \
    && -f "$handed_off_marker" && ! -L "$handed_off_marker" ]]; then
    handoff_postcondition_status='0'
  else
    handoff_postcondition_status='1'
  fi
  [[ "$handoff_postcondition_status" == '0' ]] \
    || fail 'the exclusive output handoff postcondition did not hold'
  if "${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" \
    verify-output-layout --root "$output_directory"; then
    output_layout_status='0'
  else
    output_layout_status='1'
  fi
  [[ "$output_layout_status" == '0' ]] \
    || fail 'the handed-off release output does not have the exact expected layout'

  if "${sanitized_environment[@]}" \
    LECTUREBOARD_DEVELOPMENT_TEAM="$team_id" \
    LECTUREBOARD_DEVELOPER_ID_SHA1="$identity_sha1" \
    LECTUREBOARD_RELEASE_VERSION="$release_version" \
    LECTUREBOARD_RELEASE_BUILD_NUMBER="$build_number" \
    LECTUREBOARD_RELEASE_CI_COMMIT="$approved_commit" \
    LECTUREBOARD_RELEASE_TAG_OBJECT="$approved_tag_object" \
      /bin/bash -p "$committed_verifier" --kind app --path "$handed_off_app"; then
    final_verifier_status='0'
  else
    final_verifier_status='1'
  fi
  [[ "$final_verifier_status" == '0' ]] \
    || fail 'the handed-off application did not pass final release-code verification'

  final_tree_manifest="$temporary_root/final-app-tree.txt"
  if "${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" tree-manifest \
      --root "$handed_off_app" --output "$final_tree_manifest" \
    && /usr/bin/cmp -s "$archive_tree_manifest" "$final_tree_manifest"; then
    final_tree_status='0'
  else
    final_tree_status='1'
  fi
  [[ "$final_tree_status" == '0' ]] \
    || fail 'the handed-off application differs from the verified archive application'
  final_dsym_uuid="$(
    "${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" arm64-uuid \
      --path "$handed_off_dsym"
  )"
  [[ "$(normalize_hex "$final_dsym_uuid")" == "$(normalize_hex "$app_uuid")" ]] \
    || fail 'the handed-off dSYM UUID does not match the application'
  final_dsym_manifest="$temporary_root/final-dsym-tree.txt"
  "${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" tree-manifest \
    --root "$handed_off_dsym" --output "$final_dsym_manifest" \
    || fail 'the handed-off dSYM tree could not be bounded'
  /usr/bin/cmp -s "$archive_dsym_manifest" "$final_dsym_manifest" \
    || fail 'the handed-off dSYM differs from the archived dSYM'

  final_output_manifest="$temporary_root/final-output-tree.txt"
  if "${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" verified-output-manifest \
      --root "$output_directory" --output "$final_output_manifest" \
    && /usr/bin/cmp -s "$staged_output_manifest" "$final_output_manifest"; then
    final_output_tree_status='0'
  else
    final_output_tree_status='1'
  fi
  [[ "$final_output_tree_status" == '0' ]] \
    || fail 'the completed release output differs from the staged release output'
  if [[ -n "$temporary_root" && -d "$temporary_root" ]] \
    && /usr/bin/find "$temporary_root" -depth -delete; then
    temporary_root=''
    pre_completion_cleanup_status='0'
  else
    pre_completion_cleanup_status='1'
  fi
  [[ "$pre_completion_cleanup_status" == '0' ]] \
    || fail 'release-build temporary state could not be removed before completion'
  [[ -z "$output_stage" ]] \
    || fail 'release-build staging state remained before completion'
  trap - EXIT
  if /bin/unlink "$handed_off_marker"; then
    marker_cleanup_status='0'
  else
    marker_cleanup_status='1'
  fi
  [[ "$marker_cleanup_status" == '0' ]] \
    || fail 'the incomplete-output marker could not be removed'
  if [[ ! -e "$handed_off_marker" && ! -L "$handed_off_marker" ]]; then
    marker_absence_status='0'
  else
    marker_absence_status='1'
  fi
  [[ "$marker_absence_status" == '0' ]] \
    || fail 'the incomplete-output marker still exists or is a symbolic link'
  printf 'Verified Developer ID application output: %s\n' "$handed_off_app" || :
  printf 'Release commit: %s\n' "$approved_commit" || :
  printf 'Notarization status: not submitted by this script\n' || :
  printf 'Distribution status: signed application only; not yet a release artifact\n' || :
fi
