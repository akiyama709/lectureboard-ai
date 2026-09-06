#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail
export LC_ALL=C
export PATH='/usr/bin:/bin:/usr/sbin:/sbin'
unset CDPATH

fail() {
  printf 'Release artifact check failed: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf '%s\n' \
    'Usage:' \
    '  release-artifact-tools.sh tree-manifest --root /absolute/tree --output /absolute/new/file' \
    '  release-artifact-tools.sh arm64-uuid --path /absolute/binary-or-dSYM' \
    '  release-artifact-tools.sh parse-arm64-uuid --input /absolute/dwarfdump-output' \
    '  release-artifact-tools.sh macos-min-version --path /absolute/Mach-O' \
    '  release-artifact-tools.sh parse-macos-min-version --input /absolute/vtool-output' \
    '  release-artifact-tools.sh verify-reviewed-xcode-source --root /absolute/source' \
    '  release-artifact-tools.sh verify-extracted-git-tree --repository /absolute/repository --commit FULL_OID --source /absolute/source' \
    '  release-artifact-tools.sh verify-project-containment --path /absolute/project.pbxproj' \
    '  release-artifact-tools.sh verify-xcode-project-support --root /absolute/Project.xcodeproj' \
    '  release-artifact-tools.sh verify-package-manifests --root /absolute/source' \
    '  release-artifact-tools.sh verify-app-code-layout --app /absolute/App.app --main /absolute/App.app/Contents/MacOS/App' \
    '  release-artifact-tools.sh verify-output-layout --root /absolute/output' \
    '  release-artifact-tools.sh verified-output-manifest --root /absolute/output --output /absolute/new/file'
}

require_absolute_nonroot() {
  [[ "$1" == /* && "$1" != '/' ]] || fail "$2 must be an absolute non-root path"
}

parse_arm64_uuid_file() {
  local input_path="$1"
  local line_count uuid

  [[ -f "$input_path" && ! -L "$input_path" ]] \
    || fail 'the UUID input must be a regular non-symbolic-link file'
  line_count="$(/usr/bin/awk 'NF { count += 1 } END { print count + 0 }' "$input_path")"
  [[ "$line_count" == '1' ]] \
    || fail 'a release binary must contain exactly one UUID record'
  uuid="$(
    /usr/bin/awk \
      '$1 == "UUID:" && $3 == "(arm64)" && NF >= 4 { print toupper($2) }' \
      "$input_path"
  )"
  [[ "$uuid" =~ ^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$ ]] \
    || fail 'a release binary did not expose one valid arm64 UUID'
  printf '%s\n' "$uuid"
}

parse_macos_min_version_file() {
  local input_path="$1"
  local platform_count minos_count minos

  [[ -f "$input_path" && ! -L "$input_path" ]] \
    || fail 'the build-version input must be a regular non-symbolic-link file'
  platform_count="$(
    /usr/bin/awk '$1 == "platform" && $2 == "MACOS" { count += 1 } END { print count + 0 }' \
      "$input_path"
  )"
  minos_count="$(
    /usr/bin/awk '$1 == "minos" { count += 1 } END { print count + 0 }' "$input_path"
  )"
  [[ "$platform_count" == '1' && "$minos_count" == '1' ]] \
    || fail 'the executable must contain exactly one macOS build-version record'
  minos="$(/usr/bin/awk '$1 == "minos" { print $2 }' "$input_path")"
  [[ "$minos" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]] \
    || fail 'the macOS minimum version is malformed'
  printf '%s\n' "$minos"
}

write_tree_manifest() {
  local tree_root="$1"
  local manifest_path="$2"
  local excluded_relative_path="${3:-}"
  local relative_path mode digest link_target manifest_stage unsorted_stage entry_list
  local owner group flags acl_count acl_summary acl_records
  local xattr_list xattr_records xattr_name xattr_digest xattr_summary

  [[ -d "$tree_root" && ! -L "$tree_root" ]] \
    || fail 'the manifest root must be a non-symbolic-link directory'
  [[ ! -e "$manifest_path" && ! -L "$manifest_path" ]] \
    || fail 'the manifest output must not already exist'
  [[ -d "$(/usr/bin/dirname -- "$manifest_path")" ]] \
    || fail 'the manifest output parent does not exist'
  manifest_stage="$(/usr/bin/mktemp "$(/usr/bin/dirname -- "$manifest_path")/.lectureboard-tree.XXXXXX")" \
    || fail 'the manifest staging file could not be created'
  unsorted_stage="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lectureboard-tree-unsorted.XXXXXX")" \
    || fail 'the unsorted manifest staging file could not be created'
  entry_list="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lectureboard-tree-entries.XXXXXX")" \
    || fail 'the manifest entry list could not be created'
  xattr_list="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lectureboard-xattrs.XXXXXX")" \
    || fail 'the extended-attribute list could not be created'
  xattr_records="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lectureboard-xattr-records.XXXXXX")" \
    || fail 'the extended-attribute record could not be created'
  acl_records="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lectureboard-acl-records.XXXXXX")" \
    || fail 'the ACL record could not be created'
  cleanup_manifest() {
    if [[ -n "${manifest_stage:-}" && -f "$manifest_stage" ]]; then
      /bin/unlink "$manifest_stage" || :
    fi
    if [[ -n "${unsorted_stage:-}" && -f "$unsorted_stage" ]]; then
      /bin/unlink "$unsorted_stage" || :
    fi
    if [[ -n "${entry_list:-}" && -f "$entry_list" ]]; then
      /bin/unlink "$entry_list" || :
    fi
    [[ -f "${xattr_list:-}" ]] && { /bin/unlink "$xattr_list" || :; }
    [[ -f "${xattr_records:-}" ]] && { /bin/unlink "$xattr_records" || :; }
    [[ -f "${acl_records:-}" ]] && { /bin/unlink "$acl_records" || :; }
  }
  trap cleanup_manifest EXIT

  if ! (cd "$tree_root" && /usr/bin/find . -print0 >"$entry_list"); then
    fail 'the application tree could not be enumerated completely'
  fi

  if ! (
    cd "$tree_root" || exit 89
    while IFS= read -r -d '' relative_path; do
      if [[ -n "$excluded_relative_path" && "$relative_path" == "$excluded_relative_path" ]]; then
        continue
      fi
      [[ "$relative_path" != *$'\n'* && "$relative_path" != *'|'* ]] || exit 90
      mode="$(/usr/bin/stat -f '%Lp' "$relative_path")" || exit 91
      owner="$(/usr/bin/stat -f '%u' "$relative_path")" || exit 96
      group="$(/usr/bin/stat -f '%g' "$relative_path")" || exit 97
      flags="$(/usr/bin/stat -f '%Sf' "$relative_path")" || exit 98
      /bin/ls -lde "$relative_path" >"$acl_records" || exit 99
      acl_count="$(/usr/bin/awk 'NR > 1 { count += 1 } END { print count + 0 }' "$acl_records")" \
        || exit 106
      if [[ "$acl_count" == '0' ]]; then
        acl_summary='-'
      else
        acl_summary="$(/usr/bin/tail -n +2 "$acl_records" | /usr/bin/shasum -a 256 | /usr/bin/awk '{ print $1 }')" \
          || exit 105
      fi
      : >"$xattr_list" || exit 107
      : >"$xattr_records" || exit 108
      /usr/bin/xattr "$relative_path" >"$xattr_list" || exit 100
      /usr/bin/sort -o "$xattr_list" "$xattr_list" || exit 101
      while IFS= read -r xattr_name; do
        [[ -n "$xattr_name" && "$xattr_name" != -* \
          && "$xattr_name" != *$'\n'* && "$xattr_name" != *'|'* ]] || exit 102
        xattr_digest="$(
          /usr/bin/xattr -p "$xattr_name" "$relative_path" \
            | /usr/bin/shasum -a 256 | /usr/bin/awk '{ print $1 }'
        )" || exit 103
        printf '%s=%s\n' "$xattr_name" "$xattr_digest" >>"$xattr_records" \
          || exit 109
      done <"$xattr_list"
      if [[ -s "$xattr_records" ]]; then
        xattr_summary="$(/usr/bin/shasum -a 256 "$xattr_records" | /usr/bin/awk '{ print $1 }')" \
          || exit 104
      else
        xattr_summary='-'
      fi
      if [[ -L "$relative_path" ]]; then
        link_target="$(/usr/bin/readlink "$relative_path")" || exit 92
        [[ "$link_target" != *$'\n'* && "$link_target" != *'|'* ]] || exit 95
        printf 'link|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
          "$owner" "$group" "$mode" "$flags" "$acl_count" "$acl_summary" "$xattr_summary" \
          "$relative_path" "$link_target" || exit 110
      elif [[ -d "$relative_path" ]]; then
        printf 'directory|%s|%s|%s|%s|%s|%s|%s|%s\n' \
          "$owner" "$group" "$mode" "$flags" "$acl_count" "$acl_summary" "$xattr_summary" \
          "$relative_path" || exit 111
      elif [[ -f "$relative_path" ]]; then
        digest="$(/usr/bin/shasum -a 256 "$relative_path" | /usr/bin/awk '{ print $1 }')" \
          || exit 93
        printf 'file|%s|%s|%s|%s|%s|%s|%s|%s|%s\n' \
          "$owner" "$group" "$mode" "$flags" "$acl_count" "$acl_summary" "$xattr_summary" \
          "$relative_path" "$digest" || exit 112
      else
        exit 94
      fi
    done <"$entry_list"
  ) >"$unsorted_stage"; then
    fail 'the application tree could not be represented safely'
  fi
  /usr/bin/sort "$unsorted_stage" >"$manifest_stage" \
    || fail 'the application tree manifest could not be sorted completely'
  /bin/unlink "$unsorted_stage"
  unsorted_stage=''
  /bin/unlink "$entry_list"
  entry_list=''
  /bin/unlink "$xattr_list"
  xattr_list=''
  /bin/unlink "$xattr_records"
  xattr_records=''
  /bin/unlink "$acl_records"
  acl_records=''
  /bin/ln "$manifest_stage" "$manifest_path" \
    || fail 'the completed tree manifest could not be committed exclusively'
  /bin/unlink "$manifest_stage" || :
  manifest_stage=''
  trap - EXIT
}

verify_reviewed_xcode_source() {
  local source_root="$1"
  local project_spec project_file project_spec_digest project_file_digest
  local expected_project_spec_digest='00764473ec28961c2c687a1afdd670c47a665b97e9c6062bd02bc0dfbe3c15fa'
  local expected_project_file_digest='65f3984165596fb6e160c0551d4adfd27bcecccf1d5ef8898867368d671ad9ca'

  [[ -d "$source_root" && ! -L "$source_root" ]] \
    || fail 'the reviewed Xcode source root must be a non-symbolic-link directory'
  project_spec="$source_root/project.yml"
  project_file="$source_root/LectureBoardAI.xcodeproj/project.pbxproj"
  [[ -f "$project_spec" && ! -L "$project_spec" ]] \
    || fail 'the reviewed XcodeGen project specification is missing or symbolic'
  [[ -f "$project_file" && ! -L "$project_file" ]] \
    || fail 'the reviewed Xcode project file is missing or symbolic'
  project_spec_digest="$(
    /usr/bin/shasum -a 256 "$project_spec" | /usr/bin/awk '{ print $1 }'
  )" || fail 'the XcodeGen project-specification digest could not be read'
  project_file_digest="$(
    /usr/bin/shasum -a 256 "$project_file" | /usr/bin/awk '{ print $1 }'
  )" || fail 'the Xcode project digest could not be read'
  [[ "$project_spec_digest" == "$expected_project_spec_digest" ]] \
    || fail 'project.yml differs from the reviewed command-free v1 source specification'
  [[ "$project_file_digest" == "$expected_project_file_digest" ]] \
    || fail 'the checked-in Xcode project differs from the exact reviewed v1 project'
}

verify_extracted_git_tree() {
  local repository_path="$1"
  local commit_id="$2"
  local source_root="$3"
  local tree_records expected_stage actual_stage record metadata relative_path
  local mode object_type object_id metadata_tail object_digest actual_mode
  local git_command

  [[ -d "$repository_path" && ! -L "$repository_path" ]] \
    || fail 'the Git-tree repository must be a non-symbolic-link directory'
  [[ "$commit_id" =~ ^[0-9A-Fa-f]{40}$|^[0-9A-Fa-f]{64}$ ]] \
    || fail 'the Git-tree commit identifier must be full length'
  [[ -d "$source_root" && ! -L "$source_root" ]] \
    || fail 'the extracted Git-tree source must be a non-symbolic-link directory'

  git_command=(
    /usr/bin/env -i
    PATH=/usr/bin:/bin:/usr/sbin:/sbin
    LC_ALL=C
    TMPDIR=/private/tmp
    GIT_CONFIG_NOSYSTEM=1
    GIT_CONFIG_GLOBAL=/dev/null
    GIT_CONFIG_SYSTEM=/dev/null
    GIT_NO_REPLACE_OBJECTS=1
    GIT_ATTR_NOSYSTEM=1
    /usr/bin/git
    --no-replace-objects
    -c core.fsmonitor=false
    -c core.untrackedCache=false
    -c core.attributesFile=/dev/null
  )
  tree_records="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lectureboard-git-tree.XXXXXX")" \
    || fail 'the Git tree-record file could not be created'
  expected_stage="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lectureboard-git-expected.XXXXXX")" \
    || fail 'the expected Git-tree manifest could not be created'
  actual_stage="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lectureboard-git-actual.XXXXXX")" \
    || fail 'the extracted Git-tree manifest could not be created'
  cleanup_git_tree() {
    [[ -f "${tree_records:-}" ]] && /bin/unlink "$tree_records"
    [[ -f "${expected_stage:-}" ]] && /bin/unlink "$expected_stage"
    [[ -f "${actual_stage:-}" ]] && /bin/unlink "$actual_stage"
  }
  trap cleanup_git_tree EXIT

  "${git_command[@]}" -C "$repository_path" \
    ls-tree -r -z --full-tree "$commit_id" >"$tree_records" \
    || fail 'the approved Git tree could not be enumerated completely'
  if ! (
    while IFS= read -r -d '' record; do
      [[ "$record" == *$'\t'* ]] || exit 120
      metadata="${record%%$'\t'*}"
      relative_path="${record#*$'\t'}"
      mode="${metadata%% *}"
      metadata_tail="${metadata#* }"
      object_type="${metadata_tail%% *}"
      object_id="${metadata_tail#* }"
      [[ "$metadata" != "$metadata_tail" && "$metadata_tail" != "$object_id" ]] \
        || exit 121
      [[ "$mode" == '100644' || "$mode" == '100755' ]] || exit 122
      [[ "$object_type" == 'blob' ]] || exit 123
      [[ "$object_id" =~ ^[0-9A-Fa-f]{40}$|^[0-9A-Fa-f]{64}$ ]] || exit 124
      [[ -n "$relative_path" && "$relative_path" != /* \
        && "$relative_path" != *$'\n'* && "$relative_path" != *$'\t'* \
        && "$relative_path" != *'|'* && "$relative_path" != '..' \
        && "$relative_path" != ../* && "$relative_path" != */../* \
        && "$relative_path" != */.. ]] || exit 125
      object_digest="$(
        "${git_command[@]}" -C "$repository_path" cat-file blob "$object_id" \
          | /usr/bin/shasum -a 256 | /usr/bin/awk '{ print $1 }'
      )" || exit 126
      printf 'file|%s|%s|%s\n' "$mode" "$relative_path" "$object_digest" \
        || exit 127
    done <"$tree_records"
  ) | /usr/bin/sort >"$expected_stage"; then
    fail 'the approved Git tree could not be represented safely'
  fi

  if ! (
    cd "$source_root" || exit 128
    /usr/bin/find . -mindepth 1 ! -type d -print0 \
      | while IFS= read -r -d '' relative_path; do
        [[ -f "$relative_path" && ! -L "$relative_path" ]] || exit 129
        relative_path="${relative_path#./}"
        [[ -n "$relative_path" && "$relative_path" != /* \
          && "$relative_path" != *$'\n'* && "$relative_path" != *$'\t'* \
          && "$relative_path" != *'|'* && "$relative_path" != '..' \
          && "$relative_path" != ../* && "$relative_path" != */../* \
          && "$relative_path" != */.. ]] || exit 130
        actual_mode="$(/usr/bin/stat -f '%Lp' "$relative_path")" || exit 131
        case "$actual_mode" in
          644) mode='100644' ;;
          755) mode='100755' ;;
          *) exit 132 ;;
        esac
        object_digest="$(
          /usr/bin/shasum -a 256 "$relative_path" | /usr/bin/awk '{ print $1 }'
        )" || exit 133
        printf 'file|%s|%s|%s\n' "$mode" "$relative_path" "$object_digest" \
          || exit 134
      done
  ) | /usr/bin/sort >"$actual_stage"; then
    fail 'the extracted Git tree could not be represented safely'
  fi
  /usr/bin/cmp -s "$expected_stage" "$actual_stage" \
    || fail 'the extracted source differs from the exact approved Git tree'
  /bin/unlink "$tree_records"
  tree_records=''
  /bin/unlink "$expected_stage"
  expected_stage=''
  /bin/unlink "$actual_stage"
  actual_stage=''
  trap - EXIT
}

verify_project_containment() {
  local project_path="$1"
  local violation_count

  [[ -f "$project_path" && ! -L "$project_path" ]] \
    || fail 'the Xcode project file must be a regular non-symbolic-link file'
  violation_count="$(
    /usr/bin/awk '
      function trim(value) {
        sub(/^[[:space:]]+/, "", value)
        sub(/[[:space:]]+$/, "", value)
        if (value ~ /^".*"$/) {
          sub(/^"/, "", value)
          sub(/"$/, "", value)
        }
        return value
      }
      function escapes(value) {
        return value ~ /^\// || value == ".." || value ~ /^\.\.\// ||
          value ~ /\/\.\.\// || value ~ /\/\.\.$/
      }
      {
        line = $0
        if (line ~ /PBXShellScriptBuildPhase/ || line ~ /PBXBuildRule/ ||
            line ~ /PBXLegacyTarget/ || line ~ /PBXExternalBuildToolExecution/ ||
            line ~ /XCRemoteSwiftPackageReference/ ||
            line ~ /baseConfigurationReference/ || line ~ /text\.xcconfig/) {
          violations += 1
        }
        if (line ~ /^[[:space:]]*(SWIFT_EXEC|SWIFT_DRIVER_SWIFT_FRONTEND_EXEC|CC|CXX|LD|LIBTOOL|TOOLCHAINS)[[:space:]]*=/) {
          violations += 1
        }
        if (line ~ /sourceTree[[:space:]]*=[[:space:]]*"<absolute>"/) {
          violations += 1
        }
        if (match(line, /path[[:space:]]*=[[:space:]]*[^;]+;/)) {
          value = substr(line, RSTART, RLENGTH)
          sub(/^path[[:space:]]*=[[:space:]]*/, "", value)
          sub(/;$/, "", value)
          value = trim(value)
          if (escapes(value)) { violations += 1 }
        }
        if (line ~ /\$\((SRCROOT|PROJECT_DIR|SOURCE_ROOT)\)[^";]*\/\.\.(\/|[";[:space:]]|$)/ ||
            line ~ /\$\{(SRCROOT|PROJECT_DIR|SOURCE_ROOT)\}[^";]*\/\.\.(\/|[";[:space:]]|$)/) {
          violations += 1
        }
        if (line ~ /\$\((HOME|USER_HOME|PROJECT_TEMP_DIR|TEMP_DIR)\)/ ||
            line ~ /\$\{(HOME|USER_HOME|PROJECT_TEMP_DIR|TEMP_DIR)\}/) {
          violations += 1
        }
        if (line ~ /\$\((SRCROOT|PROJECT_DIR|SOURCE_ROOT|HOME|USER_HOME)[^)]*:/ ||
            line ~ /\$\{(SRCROOT|PROJECT_DIR|SOURCE_ROOT|HOME|USER_HOME)[^}]*:/) {
          violations += 1
        }
        if (line ~ /(^|[\/"=[:space:]])\.\.([\/";[:space:]]|$)/) {
          violations += 1
        }
        if (match(line, /=[[:space:]]*[^;]+;/)) {
          assignment = substr(line, RSTART, RLENGTH)
          sub(/^=[[:space:]]*/, "", assignment)
          sub(/;$/, "", assignment)
          assignment = trim(assignment)
          if (assignment ~ /^\// || assignment ~ /^~\//) { violations += 1 }
        }
      }
      END { print violations + 0 }
    ' "$project_path"
  )" || fail 'the Xcode project containment scan failed'
  [[ "$violation_count" == '0' ]] \
    || fail 'the Xcode project contains a source or build path outside the release tree'
}

verify_xcode_project_support() {
  local project_root="$1"
  local file_list relative_path file_count=0 scheme_digest workspace_digest
  local expected_scheme_digest='ecb715700c98ed2c99882c999a678f200fd0b616ed63335d32a61f3b5a498c47'
  local expected_workspace_digest='7f3b00b5c3fdb45242d7b87e1e5c4e25d1fa8129a16c94295ecc4e8ea2235c5f'

  [[ -d "$project_root" && ! -L "$project_root" && "$project_root" == *.xcodeproj ]] \
    || fail 'the Xcode project root must be a non-symbolic-link xcodeproj directory'
  file_list="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lectureboard-xcode-project.XXXXXX")" \
    || fail 'the Xcode project file list could not be created'
  cleanup_xcode_project() {
    [[ -f "${file_list:-}" ]] && /bin/unlink "$file_list"
  }
  trap cleanup_xcode_project EXIT
  (cd "$project_root" && /usr/bin/find . -type f -print0 >"$file_list") \
    || fail 'the Xcode project files could not be enumerated completely'
  while IFS= read -r -d '' relative_path; do
    file_count=$((file_count + 1))
    case "$relative_path" in
      './project.pbxproj'|'./project.xcworkspace/contents.xcworkspacedata'|'./xcshareddata/xcschemes/LectureBoardAI.xcscheme') ;;
      *) fail 'the Xcode project contains an unreviewed support file' ;;
    esac
  done <"$file_list"
  [[ "$file_count" == '3' ]] || fail 'the Xcode project support-file set is incomplete'
  scheme_digest="$(
    /usr/bin/shasum -a 256 "$project_root/xcshareddata/xcschemes/LectureBoardAI.xcscheme" \
      | /usr/bin/awk '{ print $1 }'
  )" || fail 'the shared scheme digest could not be read'
  workspace_digest="$(
    /usr/bin/shasum -a 256 "$project_root/project.xcworkspace/contents.xcworkspacedata" \
      | /usr/bin/awk '{ print $1 }'
  )" || fail 'the project workspace digest could not be read'
  [[ "$scheme_digest" == "$expected_scheme_digest" ]] \
    || fail 'the shared release scheme differs from the reviewed action-free scheme'
  [[ "$workspace_digest" == "$expected_workspace_digest" ]] \
    || fail 'the project workspace differs from the reviewed self-contained workspace'
  /bin/unlink "$file_list"
  file_list=''
  trap - EXIT
}

verify_package_manifests() {
  local source_root="$1"
  local manifest_list manifest_path relative_path manifest_count=0 manifest_digest
  local expected_manifest='./Packages/LectureBoardCore/Package.swift'
  local expected_digest='d7b523fb8484c88210599e9a36eafccbab5aaa2d507b4b9a938371290ad4d98e'

  [[ -d "$source_root" && ! -L "$source_root" ]] \
    || fail 'the package-manifest root must be a non-symbolic-link directory'
  manifest_list="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lectureboard-package-manifests.XXXXXX")" \
    || fail 'the package-manifest list could not be created'
  cleanup_packages() {
    [[ -f "${manifest_list:-}" ]] && /bin/unlink "$manifest_list"
  }
  trap cleanup_packages EXIT
  (cd "$source_root" && /usr/bin/find . -type f -name 'Package*.swift' -print0 >"$manifest_list") \
    || fail 'the package manifests could not be enumerated completely'
  while IFS= read -r -d '' manifest_path; do
    manifest_count=$((manifest_count + 1))
    relative_path="$manifest_path"
    [[ "$relative_path" == "$expected_manifest" ]] \
      || fail 'v1.0.0 allows only the reviewed LectureBoardCore package manifest path'
    manifest_digest="$(
      /usr/bin/shasum -a 256 "$source_root/${relative_path#./}" \
        | /usr/bin/awk '{ print $1 }'
    )" || fail 'the package manifest digest could not be read'
    [[ "$manifest_digest" == "$expected_digest" ]] \
      || fail 'the LectureBoardCore package manifest differs from the reviewed v1 content'
  done <"$manifest_list"
  [[ "$manifest_count" == '1' ]] \
    || fail 'the exact reviewed LectureBoardCore package manifest is required'
  /bin/unlink "$manifest_list"
  manifest_list=''
  trap - EXIT
}

verify_app_code_layout() {
  local app_path="$1"
  local main_path="$2"
  local candidate_path candidate_kind entry_list

  [[ -d "$app_path" && ! -L "$app_path" && "$app_path" == *.app ]] \
    || fail 'the code-layout target must be a non-symbolic-link application bundle'
  [[ "$(/usr/bin/dirname -- "$main_path")" == "$app_path/Contents/MacOS" ]] \
    || fail 'the declared main executable is outside the application executable directory'
  [[ -f "$main_path" && -x "$main_path" && ! -L "$main_path" ]] \
    || fail 'the declared main executable is missing, symbolic, or not executable'
  entry_list="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lectureboard-code-layout.XXXXXX")" \
    || fail 'the application code-layout list could not be created'
  cleanup_code_layout() {
    [[ -f "${entry_list:-}" ]] && /bin/unlink "$entry_list"
  }
  trap cleanup_code_layout EXIT
  /usr/bin/find "$app_path" -print0 >"$entry_list" \
    || fail 'the application code layout could not be enumerated completely'
  while IFS= read -r -d '' candidate_path; do
    if [[ -L "$candidate_path" ]]; then
      fail 'v1.0.0 does not allow symbolic links inside the application bundle'
    fi
    if [[ -d "$candidate_path" && "$candidate_path" != "$app_path" ]]; then
      case "$candidate_path" in
        *.app|*.bundle|*.framework|*.xpc|*.appex|*.plugin)
          fail 'v1.0.0 does not allow nested application or code bundles'
          ;;
      esac
    fi
    [[ -f "$candidate_path" ]] || continue
    if [[ "$candidate_path" != "$main_path" && -x "$candidate_path" ]]; then
      fail 'v1.0.0 does not allow an undeclared executable file'
    fi
    if [[ "$candidate_path" != "$main_path" ]]; then
      candidate_kind="$(/usr/bin/file -b -- "$candidate_path" 2>/dev/null)" \
        || fail 'an application file type could not be inspected'
      case "$candidate_kind" in
        Mach-O*) fail 'v1.0.0 does not allow undeclared Mach-O code' ;;
      esac
    fi
  done <"$entry_list"
  /bin/unlink "$entry_list"
  entry_list=''
  trap - EXIT
}

verify_output_layout() {
  local output_root="$1"
  local entry_list entry_path app_count=0 dsym_count=0 marker_count=0 total_count=0

  [[ -d "$output_root" && ! -L "$output_root" ]] \
    || fail 'the release output root must be a non-symbolic-link directory'
  entry_list="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lectureboard-output-layout.XXXXXX")" \
    || fail 'the release output-layout list could not be created'
  cleanup_output_layout() {
    [[ -f "${entry_list:-}" ]] && /bin/unlink "$entry_list"
  }
  trap cleanup_output_layout EXIT
  /usr/bin/find "$output_root" -mindepth 1 -maxdepth 1 -print0 >"$entry_list" \
    || fail 'the release output root could not be enumerated completely'
  while IFS= read -r -d '' entry_path; do
    total_count=$((total_count + 1))
    case "${entry_path##*/}" in
      'LectureBoard AI.app')
        [[ -d "$entry_path" && ! -L "$entry_path" ]] || fail 'the output application entry is invalid'
        app_count=$((app_count + 1))
        ;;
      'LectureBoard AI.app.dSYM')
        [[ -d "$entry_path" && ! -L "$entry_path" ]] || fail 'the output dSYM entry is invalid'
        dsym_count=$((dsym_count + 1))
        ;;
      '.lectureboard-release-incomplete')
        [[ -f "$entry_path" && ! -L "$entry_path" ]] || fail 'the incomplete-output marker is invalid'
        marker_count=$((marker_count + 1))
        ;;
      *) fail 'the release output root contains an unexpected entry' ;;
    esac
  done <"$entry_list"
  [[ "$total_count" == '3' && "$app_count" == '1' && "$dsym_count" == '1' \
    && "$marker_count" == '1' ]] \
    || fail 'the release output root does not contain the exact expected entries'
  /bin/unlink "$entry_list"
  entry_list=''
  trap - EXIT
}

command_name="${1:-}"
[[ -n "$command_name" ]] || { usage >&2; exit 64; }
shift

case "$command_name" in
  tree-manifest)
    [[ "$#" == '4' && "$1" == '--root' && "$3" == '--output' ]] \
      || { usage >&2; exit 64; }
    require_absolute_nonroot "$2" 'the manifest root'
    require_absolute_nonroot "$4" 'the manifest output'
    write_tree_manifest "$2" "$4"
    ;;
  arm64-uuid)
    [[ "$#" == '2' && "$1" == '--path' ]] || { usage >&2; exit 64; }
    require_absolute_nonroot "$2" 'the UUID target'
    [[ -e "$2" && ! -L "$2" ]] || fail 'the UUID target does not exist or is symbolic'
    uuid_stage="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lectureboard-uuid.XXXXXX")" \
      || fail 'the UUID staging file could not be created'
    cleanup_uuid() {
      [[ -f "${uuid_stage:-}" ]] && /bin/unlink "$uuid_stage"
    }
    trap cleanup_uuid EXIT
    /usr/bin/dwarfdump --uuid "$2" >"$uuid_stage" 2>/dev/null \
      || fail 'a release UUID could not be read'
    parse_arm64_uuid_file "$uuid_stage"
    ;;
  parse-arm64-uuid)
    [[ "$#" == '2' && "$1" == '--input' ]] || { usage >&2; exit 64; }
    require_absolute_nonroot "$2" 'the UUID input'
    parse_arm64_uuid_file "$2"
    ;;
  macos-min-version)
    [[ "$#" == '2' && "$1" == '--path' ]] || { usage >&2; exit 64; }
    require_absolute_nonroot "$2" 'the build-version target'
    [[ -f "$2" && ! -L "$2" ]] \
      || fail 'the build-version target must be a regular non-symbolic-link file'
    build_version_stage="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/lectureboard-build-version.XXXXXX")" \
      || fail 'the build-version staging file could not be created'
    cleanup_build_version() {
      [[ -f "${build_version_stage:-}" ]] && /bin/unlink "$build_version_stage"
    }
    trap cleanup_build_version EXIT
    /usr/bin/vtool -arch arm64 -show-build "$2" >"$build_version_stage" 2>/dev/null \
      || fail 'the executable build-version record could not be read'
    parse_macos_min_version_file "$build_version_stage"
    ;;
  parse-macos-min-version)
    [[ "$#" == '2' && "$1" == '--input' ]] || { usage >&2; exit 64; }
    require_absolute_nonroot "$2" 'the build-version input'
    parse_macos_min_version_file "$2"
    ;;
  verify-reviewed-xcode-source)
    [[ "$#" == '2' && "$1" == '--root' ]] || { usage >&2; exit 64; }
    require_absolute_nonroot "$2" 'the reviewed Xcode source root'
    verify_reviewed_xcode_source "$2"
    ;;
  verify-extracted-git-tree)
    [[ "$#" == '6' && "$1" == '--repository' && "$3" == '--commit' \
      && "$5" == '--source' ]] || { usage >&2; exit 64; }
    require_absolute_nonroot "$2" 'the Git-tree repository'
    require_absolute_nonroot "$6" 'the extracted Git-tree source'
    verify_extracted_git_tree "$2" "$4" "$6"
    ;;
  verify-project-containment)
    [[ "$#" == '2' && "$1" == '--path' ]] || { usage >&2; exit 64; }
    require_absolute_nonroot "$2" 'the Xcode project path'
    verify_project_containment "$2"
    ;;
  verify-xcode-project-support)
    [[ "$#" == '2' && "$1" == '--root' ]] || { usage >&2; exit 64; }
    require_absolute_nonroot "$2" 'the Xcode project root'
    verify_xcode_project_support "$2"
    ;;
  verify-package-manifests)
    [[ "$#" == '2' && "$1" == '--root' ]] || { usage >&2; exit 64; }
    require_absolute_nonroot "$2" 'the package-manifest root'
    verify_package_manifests "$2"
    ;;
  verify-app-code-layout)
    [[ "$#" == '4' && "$1" == '--app' && "$3" == '--main' ]] \
      || { usage >&2; exit 64; }
    require_absolute_nonroot "$2" 'the application path'
    require_absolute_nonroot "$4" 'the main executable path'
    verify_app_code_layout "$2" "$4"
    ;;
  verify-output-layout)
    [[ "$#" == '2' && "$1" == '--root' ]] || { usage >&2; exit 64; }
    require_absolute_nonroot "$2" 'the release output root'
    verify_output_layout "$2"
    ;;
  verified-output-manifest)
    [[ "$#" == '4' && "$1" == '--root' && "$3" == '--output' ]] \
      || { usage >&2; exit 64; }
    require_absolute_nonroot "$2" 'the release output root'
    require_absolute_nonroot "$4" 'the release output manifest'
    verify_output_layout "$2"
    write_tree_manifest "$2" "$4" './.lectureboard-release-incomplete'
    ;;
  *) usage >&2; exit 64 ;;
esac
