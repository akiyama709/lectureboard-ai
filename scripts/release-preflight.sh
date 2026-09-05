#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail
export LC_ALL=C
export PATH='/usr/bin:/bin:/usr/sbin:/sbin'
unset CDPATH

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && /bin/pwd -P)"
repository_root="$(cd -- "$script_directory/.." && /bin/pwd -P)"
artifact_tools="$script_directory/release-artifact-tools.sh"

expected_tag='v1.0.0'
expected_version='1.0.0'
expected_origin='https://github.com/akiyama709/lectureboard-ai.git'
expected_developer_directory='/Applications/Xcode.app/Contents/Developer'
expected_xcode_version='26.6'
expected_xcode_build_version='17F113'
expected_xcodegen_version='2.46.0'

fail() {
  printf 'Release preflight failed: %s\n' "$1" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "required preflight input is missing"
}

read_single_line_file() {
  local path="$1"
  local label="$2"
  local line_count value

  require_file "$path"
  line_count="$(awk 'END { print NR + 0 }' "$path")"
  [[ "$line_count" == '1' ]] || fail "$label must contain exactly one line"
  IFS= read -r value <"$path" || true
  [[ -n "$value" ]] || fail "$label must not be empty"
  printf '%s\n' "$value"
}

read_unique_scalar() {
  local path="$1"
  local key="$2"
  local indentation="$3"
  local count line value

  require_file "$path"
  if [[ "$indentation" == 'top-level' ]]; then
    count="$(awk -v key="$key" '
      $0 ~ ("^" key "[[:space:]]*:") { count += 1 }
      END { print count + 0 }
    ' "$path")"
    line="$(awk -v key="$key" '
      $0 ~ ("^" key "[[:space:]]*:") { print; exit }
    ' "$path")"
  else
    count="$(awk -v key="$key" '
      $0 ~ ("^[[:space:]]*" key "[[:space:]]*:") { count += 1 }
      END { print count + 0 }
    ' "$path")"
    line="$(awk -v key="$key" '
      $0 ~ ("^[[:space:]]*" key "[[:space:]]*:") { print; exit }
    ' "$path")"
  fi

  [[ "$count" == '1' ]] || fail "release metadata has a missing or duplicate $key value"

  value="${line#*:}"
  if [[ "$value" =~ ^[[:space:]]*\"([^\"]+)\"[[:space:]]*$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ "$value" =~ ^[[:space:]]*\'([^\']+)\'[[:space:]]*$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ "$value" =~ ^[[:space:]]*([^[:space:]#]+)[[:space:]]*$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    fail "release metadata contains a malformed $key value"
  fi
}

validate_date() {
  local value="$1"
  local year month day max_day

  if [[ ! "$value" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]]; then
    fail 'the release date must use YYYY-MM-DD'
  fi

  year=$((10#${BASH_REMATCH[1]}))
  month=$((10#${BASH_REMATCH[2]}))
  day=$((10#${BASH_REMATCH[3]}))
  case "$month" in
    1 | 3 | 5 | 7 | 8 | 10 | 12) max_day=31 ;;
    4 | 6 | 9 | 11) max_day=30 ;;
    2)
      max_day=28
      if ((year % 400 == 0 || (year % 4 == 0 && year % 100 != 0))); then
        max_day=29
      fi
      ;;
    *) fail 'the release date has an invalid month' ;;
  esac
  ((day >= 1 && day <= max_day)) || fail 'the release date has an invalid day'
}

normalize_hex() {
  printf '%s' "$1" | tr '[:lower:]' '[:upper:]'
}

validate_object_id() {
  local value="$1"
  local label="$2"
  local length="${#value}"

  [[ "$value" =~ ^[0-9A-Fa-f]+$ ]] || fail "$label is malformed"
  [[ "$length" == '40' || "$length" == '64' ]] || fail "$label is malformed"
}

test_mode="${LECTUREBOARD_RELEASE_PREFLIGHT_TEST_MODE:-}"
fixture_directory="${LECTUREBOARD_RELEASE_PREFLIGHT_FIXTURE_DIR:-}"

case "$test_mode" in
  '')
    [[ -z "$fixture_directory" ]] \
      || fail 'fixture input requires explicit test mode'
    for forbidden_environment_variable in \
      BASH_ENV ENV \
      GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR GIT_OBJECT_DIRECTORY \
      GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_EXEC_PATH GIT_CONFIG_COUNT \
      GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM \
      GIT_CONFIG_NOSYSTEM \
      XCODE_XCCONFIG_FILE TOOLCHAINS SWIFT_EXEC SWIFT_DRIVER_SWIFT_FRONTEND_EXEC \
      CC CXX LD CPATH C_INCLUDE_PATH CPLUS_INCLUDE_PATH OBJC_INCLUDE_PATH LIBRARY_PATH \
      SDKROOT DEVELOPER_DIR DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH \
      DYLD_FALLBACK_LIBRARY_PATH DYLD_FALLBACK_FRAMEWORK_PATH DYLD_INSERT_LIBRARIES; do
      [[ -z "${!forbidden_environment_variable:-}" ]] \
        || fail 'production preflight forbids toolchain or repository override inputs'
    done
    metadata_root="$repository_root"
    ;;
  fixture-v1)
    [[ -n "$fixture_directory" ]] || fail 'test mode requires a fixture directory'
    [[ "$fixture_directory" == /* ]] || fail 'the fixture directory must be absolute'
    [[ -d "$fixture_directory" ]] || fail 'the fixture directory does not exist'
    metadata_root="$fixture_directory"
    ;;
  *) fail 'unsupported test mode' ;;
esac

if [[ "$test_mode" == 'fixture-v1' ]]; then
  expected_ci_commit="$(read_single_line_file "$fixture_directory/expected-ci-commit.txt" 'CI commit input')"
  expected_tag_object="$(read_single_line_file "$fixture_directory/expected-release-tag-object.txt" 'release tag-object input')"
  expected_release_date="$(read_single_line_file "$fixture_directory/expected-release-date.txt" 'release date input')"
  expected_build_number="$(read_single_line_file "$fixture_directory/expected-build-number.txt" 'build number input')"
  expected_identity_sha1="$(read_single_line_file "$fixture_directory/expected-identity-sha1.txt" 'identity fingerprint input')"
  expected_team_id="$(read_single_line_file "$fixture_directory/expected-team-id.txt" 'team identifier input')"
else
  expected_ci_commit="${LECTUREBOARD_RELEASE_CI_COMMIT:-}"
  expected_tag_object="${LECTUREBOARD_RELEASE_TAG_OBJECT:-}"
  expected_release_date="${LECTUREBOARD_RELEASE_DATE:-}"
  expected_build_number="${LECTUREBOARD_RELEASE_BUILD_NUMBER:-}"
  expected_identity_sha1="${LECTUREBOARD_DEVELOPER_ID_SHA1:-}"
  expected_team_id="${LECTUREBOARD_DEVELOPMENT_TEAM:-}"

  [[ -n "$expected_ci_commit" ]] || fail 'LECTUREBOARD_RELEASE_CI_COMMIT is required'
  [[ -n "$expected_tag_object" ]] || fail 'LECTUREBOARD_RELEASE_TAG_OBJECT is required'
  [[ -n "$expected_release_date" ]] || fail 'LECTUREBOARD_RELEASE_DATE is required'
  [[ -n "$expected_build_number" ]] || fail 'LECTUREBOARD_RELEASE_BUILD_NUMBER is required'
  [[ -n "$expected_identity_sha1" ]] || fail 'LECTUREBOARD_DEVELOPER_ID_SHA1 is required'
  [[ -n "$expected_team_id" ]] || fail 'LECTUREBOARD_DEVELOPMENT_TEAM is required'
fi

validate_object_id "$expected_ci_commit" 'the CI commit input'
validate_object_id "$expected_tag_object" 'the annotated release-tag object input'
validate_date "$expected_release_date"
[[ "$expected_build_number" =~ ^[1-9][0-9]*$ ]] \
  || fail 'the expected build number must be a positive integer'
[[ "$expected_identity_sha1" =~ ^[0-9A-Fa-f]{40}$ ]] \
  || fail 'the expected Developer ID identity fingerprint must be a SHA-1 value'
[[ "$expected_team_id" =~ ^[A-Z0-9]{10}$ ]] \
  || fail 'the expected Apple team identifier is malformed'
expected_identity_sha1="$(normalize_hex "$expected_identity_sha1")"

current_user="$(/usr/bin/id -un)" || fail 'the preflight user could not be identified'
trusted_home="$(
  /usr/bin/id -P "$current_user" | /usr/bin/awk -F: 'NF >= 9 { print $9 }'
)" || fail 'the preflight home directory could not be identified'
[[ "$trusted_home" == /* && -d "$trusted_home" ]] \
  || fail 'the preflight home directory is invalid'
sanitized_environment=(
  /usr/bin/env -i
  PATH=/usr/bin:/bin:/usr/sbin:/sbin
  LC_ALL=C
  TMPDIR=/private/tmp
  HOME="$trusted_home"
  USER="$current_user"
  LOGNAME="$current_user"
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
git_read_command=(
  "${sanitized_git_environment[@]}"
  /usr/bin/git
  --no-replace-objects
  -c core.fsmonitor=false
  -c core.untrackedCache=false
  -c core.attributesFile=/dev/null
  -c tar.umask=0000
)

if [[ "$test_mode" == 'fixture-v1' ]]; then
  require_file "$fixture_directory/git-status.txt"
  git_status="$(<"$fixture_directory/git-status.txt")"
else
  [[ -x /usr/bin/git ]] || fail 'the system Git executable is unavailable'
  "${git_read_command[@]}" -C "$repository_root" \
    rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || fail 'a Git worktree is required'
  git_status="$("${git_read_command[@]}" -C "$repository_root" \
    status --porcelain=v1 --untracked-files=all)" \
    || fail 'Git status could not be read'
fi

[[ -z "$git_status" ]] || fail 'the worktree contains tracked or untracked changes'

if [[ "$test_mode" == 'fixture-v1' ]]; then
  head_commit="$(read_single_line_file "$fixture_directory/head-commit.txt" 'HEAD fixture')"
  tag_object="$(read_single_line_file "$fixture_directory/tag-object-id.txt" 'tag object fixture')"
  tag_object_type="$(read_single_line_file "$fixture_directory/tag-object-type.txt" 'tag type fixture')"
  tag_peeled_target="$(read_single_line_file "$fixture_directory/tag-peeled-target.txt" 'tag target fixture')"
  origin_fetch_url="$(read_single_line_file "$fixture_directory/origin-fetch-url.txt" 'origin fetch fixture')"
  origin_push_url="$(read_single_line_file "$fixture_directory/origin-push-url.txt" 'origin push fixture')"
  origin_main_commit="$(read_single_line_file "$fixture_directory/origin-main-commit.txt" 'origin/main fixture')"
  replacement_ref_count="$(read_single_line_file "$fixture_directory/replacement-ref-count.txt" 'replacement ref-count fixture')"
  local_config_override_count="$(read_single_line_file "$fixture_directory/local-config-override-count.txt" 'local config override-count fixture')"
  info_attributes_status="$(read_single_line_file "$fixture_directory/info-attributes-status.txt" 'Git info attributes status fixture')"
  gitattributes_count="$(read_single_line_file "$fixture_directory/gitattributes-count.txt" 'gitattributes count fixture')"
else
  head_commit="$("${git_read_command[@]}" -C "$repository_root" rev-parse --verify HEAD^{commit})" \
    || fail 'HEAD could not be resolved'
  tag_object_type="$("${git_read_command[@]}" -C "$repository_root" cat-file -t "refs/tags/$expected_tag" 2>/dev/null)" \
    || fail 'the required annotated release tag is missing'
  tag_object="$("${git_read_command[@]}" -C "$repository_root" rev-parse --verify "refs/tags/$expected_tag" 2>/dev/null)" \
    || fail 'the annotated release-tag object could not be resolved'
  tag_peeled_target="$("${git_read_command[@]}" -C "$repository_root" rev-parse --verify "refs/tags/$expected_tag^{}" 2>/dev/null)" \
    || fail 'the release tag target could not be resolved'
  origin_fetch_url="$("${git_read_command[@]}" -C "$repository_root" remote get-url origin 2>/dev/null)" \
    || fail 'the origin fetch URL could not be read'
  origin_push_url="$("${git_read_command[@]}" -C "$repository_root" remote get-url --push origin 2>/dev/null)" \
    || fail 'the origin push URL could not be read'
  # This reads only the existing local tracking ref. The preflight never fetches
  # and therefore cannot prove that origin/main is fresh on the network.
  origin_main_commit="$("${git_read_command[@]}" -C "$repository_root" rev-parse --verify refs/remotes/origin/main^{commit} 2>/dev/null)" \
    || fail 'the local origin/main tracking commit could not be read'
  replacement_ref_count="$(
    "${git_read_command[@]}" -C "$repository_root" \
      for-each-ref --format='%(refname)' refs/replace/ \
      | /usr/bin/awk 'NF { count += 1 } END { print count + 0 }'
  )" || fail 'Git replacement refs could not be audited'
  local_config_override_count="$(
    "${git_read_command[@]}" -C "$repository_root" \
      config --local --no-includes --list 2>/dev/null \
      | /usr/bin/awk -F= \
        '$1 ~ /^(include\.|includeif\.|core\.attributesfile$|core\.fsmonitor$|core\.hookspath$)/ { count += 1 } END { print count + 0 }'
  )" || fail 'the local Git configuration could not be audited'
  info_attributes_path="$(
    "${git_read_command[@]}" -C "$repository_root" \
      rev-parse --path-format=absolute --git-path info/attributes
  )" || fail 'the repository-local Git attributes path could not be resolved'
  if [[ -e "$info_attributes_path" || -L "$info_attributes_path" ]]; then
    info_attributes_status='1'
  else
    info_attributes_status='0'
  fi
  gitattributes_count="$(
    "${git_read_command[@]}" -C "$repository_root" \
      ls-tree -r --name-only "$head_commit" \
      | /usr/bin/awk '$0 == ".gitattributes" || $0 ~ /\/\.gitattributes$/ { count += 1 } END { print count + 0 }'
  )" || fail 'release Git attributes could not be audited'
fi

validate_object_id "$head_commit" 'HEAD'
validate_object_id "$tag_object" 'the release-tag object'
validate_object_id "$tag_peeled_target" 'the release-tag target'
validate_object_id "$origin_main_commit" 'origin/main'
[[ "$tag_object_type" == 'tag' ]] || fail 'v1.0.0 must be an annotated tag'
[[ "$(normalize_hex "$tag_object")" == "$(normalize_hex "$expected_tag_object")" ]] \
  || fail 'the annotated release-tag object does not match the approved object'
[[ "$(normalize_hex "$tag_peeled_target")" == "$(normalize_hex "$head_commit")" ]] \
  || fail 'the annotated release tag does not peel to HEAD'
[[ "$origin_fetch_url" == "$expected_origin" ]] \
  || fail 'the origin fetch URL does not match the expected repository'
[[ "$origin_push_url" == "$expected_origin" ]] \
  || fail 'the origin push URL does not match the expected repository'
[[ "$(normalize_hex "$origin_main_commit")" == "$(normalize_hex "$head_commit")" ]] \
  || fail 'the local origin/main tracking commit does not match HEAD'
[[ "$(normalize_hex "$expected_ci_commit")" == "$(normalize_hex "$head_commit")" ]] \
  || fail 'the CI commit input does not match HEAD'
[[ "$(normalize_hex "$expected_ci_commit")" == "$(normalize_hex "$origin_main_commit")" ]] \
  || fail 'the CI commit input does not match the local origin/main tracking commit'
[[ "$replacement_ref_count" == '0' ]] \
  || fail 'the release repository contains a Git replacement ref'
[[ "$local_config_override_count" == '0' ]] \
  || fail 'the release repository contains an unsafe local Git configuration override'
[[ "$info_attributes_status" == '0' ]] \
  || fail 'the release repository contains repository-local Git attributes'
[[ "$gitattributes_count" == '0' ]] \
  || fail 'the release commit contains unsupported Git archive attributes'

citation_version="$(read_unique_scalar "$metadata_root/CITATION.cff" version top-level)"
citation_date="$(read_unique_scalar "$metadata_root/CITATION.cff" date-released top-level)"
marketing_version="$(read_unique_scalar "$metadata_root/project.yml" MARKETING_VERSION any)"
build_number="$(read_unique_scalar "$metadata_root/project.yml" CURRENT_PROJECT_VERSION any)"
require_file "$metadata_root/CHANGELOG.md"

unreleased_count="$(awk '
  /^## \[Unreleased\][[:space:]]*$/ { count += 1 }
  END { print count + 0 }
' "$metadata_root/CHANGELOG.md")"
[[ "$unreleased_count" == '1' ]] \
  || fail 'CHANGELOG.md must contain exactly one Unreleased heading'

released_heading="$(awk '
  /^## \[Unreleased\][[:space:]]*$/ { after_unreleased = 1; next }
  after_unreleased && /^## / { print; exit }
' "$metadata_root/CHANGELOG.md")"
if [[ ! "$released_heading" =~ ^##[[:space:]]\[([^]]+)\][[:space:]]-[[:space:]]([0-9]{4}-[0-9]{2}-[0-9]{2})$ ]]; then
  fail 'the first released CHANGELOG.md heading is missing or malformed'
fi
changelog_version="${BASH_REMATCH[1]}"
changelog_date="${BASH_REMATCH[2]}"

duplicate_release_count="$(awk -v version="$expected_version" '
  /^## \[[^]]+\][[:space:]]+-[[:space:]]+[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][[:space:]]*$/ {
    heading = $0
    sub(/^## \[/, "", heading)
    sub(/\].*$/, "", heading)
    if (heading == version) { count += 1 }
  }
  END { print count + 0 }
' "$metadata_root/CHANGELOG.md")"
[[ "$duplicate_release_count" == '1' ]] \
  || fail 'CHANGELOG.md must contain exactly one v1.0.0 release heading'

[[ "$citation_version" == "$expected_version" ]] \
  || fail 'CITATION.cff is not at the required v1.0.0 version'
[[ "$changelog_version" == "$expected_version" ]] \
  || fail 'CHANGELOG.md is not at the required v1.0.0 version'
[[ "$marketing_version" == "$expected_version" ]] \
  || fail 'project.yml is not at the required v1.0.0 bundle version'
validate_date "$citation_date"
validate_date "$changelog_date"
[[ "$citation_date" == "$expected_release_date" ]] \
  || fail 'CITATION.cff does not match the expected release date'
[[ "$changelog_date" == "$expected_release_date" ]] \
  || fail 'CHANGELOG.md does not match the expected release date'
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] \
  || fail 'project.yml has a nonpositive or malformed build number'
[[ "$build_number" == "$expected_build_number" ]] \
  || fail 'project.yml does not match the expected build number'

if [[ "$test_mode" == 'fixture-v1' ]]; then
  selected_developer_directory="$(read_single_line_file "$fixture_directory/selected-developer-directory.txt" 'selected developer directory fixture')"
  xcode_version="$(read_single_line_file "$fixture_directory/xcode-version.txt" 'Xcode version fixture')"
  xcode_build_version="$(read_single_line_file "$fixture_directory/xcode-build-version.txt" 'Xcode build version fixture')"
  xcodegen_version="$(read_single_line_file "$fixture_directory/xcodegen-version.txt" 'XcodeGen version fixture')"
else
  [[ -x /usr/bin/xcode-select ]] || fail 'xcode-select is unavailable'
  [[ -x /usr/bin/plutil ]] || fail 'plutil is unavailable'
  selected_developer_directory="$(/usr/bin/xcode-select -p 2>/dev/null)" \
    || fail 'the selected Xcode developer directory could not be read'
  xcode_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw /Applications/Xcode.app/Contents/version.plist 2>/dev/null)" \
    || fail 'the Xcode version could not be read'
  xcode_build_version="$(/usr/bin/plutil -extract ProductBuildVersion raw /Applications/Xcode.app/Contents/version.plist 2>/dev/null)" \
    || fail 'the Xcode build version could not be read'
  [[ -x /opt/homebrew/bin/xcodegen ]] \
    || fail 'the trusted XcodeGen executable is unavailable'
  xcodegen_version="$(
    "${sanitized_environment[@]}" /opt/homebrew/bin/xcodegen --version 2>/dev/null \
      | /usr/bin/awk '/^Version: / { print $2 }'
  )" || fail 'the XcodeGen version could not be read'
fi

[[ "$selected_developer_directory" == "$expected_developer_directory" ]] \
  || fail 'the selected developer directory is not the expected Xcode application'
[[ "$xcode_version" == "$expected_xcode_version" ]] \
  || fail 'Xcode 26.6 is required'
[[ "$xcode_build_version" == "$expected_xcode_build_version" ]] \
  || fail 'Xcode 26.6 build 17F113 is required'
[[ "$xcodegen_version" == "$expected_xcodegen_version" ]] \
  || fail 'XcodeGen 2.46.0 is required'

if [[ "$test_mode" == 'fixture-v1' ]]; then
  reviewed_project_status="$(read_single_line_file \
    "$fixture_directory/reviewed-project-status.txt" \
    'reviewed Xcode source status fixture')"
else
  [[ -x "$artifact_tools" ]] \
    || fail 'the reviewed release-artifact verifier is unavailable'
  if "${sanitized_environment[@]}" /bin/bash -p "$artifact_tools" \
    verify-reviewed-xcode-source --root "$repository_root"; then
    reviewed_project_status='0'
  else
    reviewed_project_status='1'
  fi
fi
[[ "$reviewed_project_status" == '0' ]] \
  || fail 'the XcodeGen input or checked-in project differs from the exact reviewed source'

if [[ "$test_mode" == 'fixture-v1' ]]; then
  require_file "$fixture_directory/generated-project-diff.txt"
  generated_project_diff="$(<"$fixture_directory/generated-project-diff.txt")"
  extracted_tree_status="$(read_single_line_file \
    "$fixture_directory/extracted-tree-status.txt" \
    'extracted Git-tree status fixture')"
else
  [[ -x /opt/homebrew/bin/xcodegen ]] \
    || fail 'the trusted XcodeGen executable is unavailable'
  [[ -x /usr/bin/mktemp && -x /bin/mkdir && -x /usr/bin/tar && -x /usr/bin/diff ]] \
    || fail 'a required system project-verification tool is unavailable'

  temporary_parent="${TMPDIR:-/tmp}"
  temporary_parent="${temporary_parent%/}"
  temporary_root="$(/usr/bin/mktemp -d "$temporary_parent/lectureboard-release-preflight.XXXXXX")" \
    || fail 'the isolated project-verification directory could not be created'
  case "$temporary_root" in
    "$temporary_parent"/lectureboard-release-preflight.*) ;;
    *) fail 'the isolated project-verification directory is unsafe' ;;
  esac

  cleanup() {
    if [[ -n "${temporary_root:-}" && -d "$temporary_root" ]]; then
      case "$temporary_root" in
        "$temporary_parent"/lectureboard-release-preflight.*)
          /usr/bin/find "$temporary_root" -depth -delete
          ;;
      esac
    fi
  }
  trap cleanup EXIT

  mirror_root="$temporary_root/repository"
  /bin/mkdir "$mirror_root"
  if ! "${git_read_command[@]}" -C "$repository_root" archive --format=tar HEAD \
    | "${sanitized_environment[@]}" /usr/bin/tar -xf - -C "$mirror_root"; then
    fail 'the isolated tracked source mirror could not be created'
  fi
  if "${sanitized_environment[@]}" /bin/bash -p \
    "$mirror_root/scripts/release-artifact-tools.sh" \
    verify-extracted-git-tree --repository "$repository_root" \
    --commit "$expected_ci_commit" --source "$mirror_root"; then
    extracted_tree_status='0'
  else
    extracted_tree_status='1'
  fi
  [[ "$extracted_tree_status" == '0' ]] \
    || fail 'the isolated source differs from the exact approved Git tree'
  if ! "${sanitized_environment[@]}" /bin/bash -p \
    "$mirror_root/scripts/release-artifact-tools.sh" \
    verify-reviewed-xcode-source --root "$mirror_root"; then
    fail 'the isolated XcodeGen input differs from the exact reviewed source'
  fi
  if ! (
    cd "$mirror_root"
    "${sanitized_environment[@]}" /opt/homebrew/bin/xcodegen generate >/dev/null 2>&1
  ); then
    fail 'isolated Xcode project generation failed'
  fi
  if /usr/bin/diff -qr \
    "$repository_root/LectureBoardAI.xcodeproj" \
    "$mirror_root/LectureBoardAI.xcodeproj" >/dev/null 2>&1; then
    generated_project_diff=''
  else
    generated_project_diff='different'
  fi
fi

[[ "$extracted_tree_status" == '0' ]] \
  || fail 'the isolated source differs from the exact approved Git tree'
[[ -z "$generated_project_diff" ]] \
  || fail 'the checked-in Xcode project differs from isolated XcodeGen output'

if [[ "$test_mode" == 'fixture-v1' ]]; then
  require_file "$fixture_directory/security-identities.txt"
  identity_output="$(<"$fixture_directory/security-identities.txt")"
else
  [[ -x /usr/bin/security ]] || fail 'the system security executable is unavailable'
  identity_output="$("${sanitized_environment[@]}" /usr/bin/security find-identity -v -p codesigning 2>/dev/null)" \
    || fail 'code-signing identities could not be read'
fi

developer_identity_count=0
identity_is_malformed=0
identity_matches_expectation=0
identity_pattern='^[[:space:]]*[0-9]+\)[[:space:]]+([0-9A-Fa-f]{40})[[:space:]]+"Developer ID Application: [^"]+ \(([A-Z0-9]{10})\)"[[:space:]]*$'
while IFS= read -r identity_line; do
  case "$identity_line" in
    *'"Developer ID Application:'*)
      developer_identity_count=$((developer_identity_count + 1))
      if [[ "$identity_line" =~ $identity_pattern ]]; then
        found_identity_sha1="$(normalize_hex "${BASH_REMATCH[1]}")"
        found_team_id="${BASH_REMATCH[2]}"
        if [[ "$found_identity_sha1" == "$expected_identity_sha1" \
          && "$found_team_id" == "$expected_team_id" ]]; then
          identity_matches_expectation=1
        fi
      else
        identity_is_malformed=1
      fi
      ;;
  esac
done <<<"$identity_output"

[[ "$developer_identity_count" == '1' ]] \
  || fail 'exactly one Developer ID Application identity is required'
[[ "$identity_is_malformed" == '0' ]] \
  || fail 'the Developer ID Application identity record is malformed'
[[ "$identity_matches_expectation" == '1' ]] \
  || fail 'the Developer ID Application identity does not match the expected fingerprint and team'

if [[ "$test_mode" == 'fixture-v1' ]]; then
  printf 'Release preflight fixture simulation passed; production readiness was not established.\n'
else
  printf 'Release preflight passed for the annotated v1.0.0 source and exact CI commit.\n'
fi
printf 'The origin/main check used the existing local tracking ref; no fetch or remote freshness proof occurred.\n'
printf 'No build, signing, notarization, Apple network, or GitHub mutation was performed.\n'
