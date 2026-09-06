#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/.." && pwd)"
runtime_script="$script_directory/build-local-runtime.sh"
signing_requirement_script="$script_directory/runtime-signing-requirement.sh"

/bin/bash -p -n "$runtime_script" "$signing_requirement_script"
source "$signing_requirement_script"

accepted_quoted_requirement='# designated => identifier "io.github.akiyama709.LectureBoardAI" and anchor apple generic and certificate leaf[subject.OU] = "TESTTEAM01"'
accepted_unquoted_requirement='# designated => identifier "io.github.akiyama709.LectureBoardAI" and anchor apple generic and certificate leaf[subject.OU] = TESTTEAM01'
accepted_parenthesized_requirement='# designated => identifier "io.github.akiyama709.LectureBoardAI" and anchor apple generic and (certificate leaf[subject.OU] = TESTTEAM01)'
missing_team_binding_requirement='# designated => identifier "io.github.akiyama709.LectureBoardAI" and anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */'
wrong_team_requirement='# designated => identifier "io.github.akiyama709.LectureBoardAI" and anchor apple generic and certificate leaf[subject.OU] = OTHERTEAM1'
misplaced_team_requirement='# designated => identifier "TESTTEAM01.io.github.example" and anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] /* exists */'
team_prefix_requirement='# designated => identifier "io.github.akiyama709.LectureBoardAI" and anchor apple generic and certificate leaf[subject.OU] = TESTTEAM01EXTRA'
disjunctive_team_requirement='# designated => identifier "io.github.akiyama709.LectureBoardAI" and anchor apple generic and (certificate leaf[subject.OU] = "TESTTEAM01" or certificate leaf[subject.OU] = "OTHERTEAM1")'
disjunctive_non_ou_requirement='# designated => identifier "io.github.akiyama709.LectureBoardAI" and anchor apple generic and (certificate leaf[subject.OU] = "TESTTEAM01" OR anchor trusted)'
negated_team_requirement='# designated => identifier "io.github.akiyama709.LectureBoardAI" and anchor apple generic and not (certificate leaf[subject.OU] = "TESTTEAM01")'
symbolic_negated_team_requirement='# designated => identifier "io.github.akiyama709.LectureBoardAI" and anchor apple generic and !(certificate leaf[subject.OU] = "TESTTEAM01")'
quoted_fake_team_requirement='# designated => identifier "io.github.akiyama709.LectureBoardAI" and anchor apple generic and info[Foo] = "(certificate leaf[subject.OU] = TESTTEAM01)"'
commented_fake_team_requirement='# designated => identifier "io.github.akiyama709.LectureBoardAI" and anchor apple generic and certificate leaf[field.1.2.3] /* certificate leaf[subject.OU] = TESTTEAM01 */ exists'

if ! runtime_requirement_is_team_bound "$accepted_quoted_requirement" 'TESTTEAM01'; then
  printf 'The signing policy rejected a quoted team-bound requirement.\n' >&2
  exit 1
fi

if ! runtime_requirement_is_team_bound "$accepted_unquoted_requirement" 'TESTTEAM01'; then
  printf 'The signing policy rejected an unquoted team-bound requirement.\n' >&2
  exit 1
fi

if ! runtime_requirement_is_team_bound "$accepted_parenthesized_requirement" 'TESTTEAM01'; then
  printf 'The signing policy rejected a parenthesized team-bound requirement.\n' >&2
  exit 1
fi

if runtime_requirement_is_team_bound "$missing_team_binding_requirement" 'TESTTEAM01'; then
  printf 'The signing policy accepted a requirement without a team binding.\n' >&2
  exit 1
fi

if runtime_requirement_is_team_bound "$wrong_team_requirement" 'TESTTEAM01'; then
  printf 'The signing policy accepted a requirement bound to another team.\n' >&2
  exit 1
fi

if runtime_requirement_is_team_bound "$misplaced_team_requirement" 'TESTTEAM01'; then
  printf 'The signing policy accepted a team identifier outside the leaf OU constraint.\n' >&2
  exit 1
fi

if runtime_requirement_is_team_bound "$team_prefix_requirement" 'TESTTEAM01'; then
  printf 'The signing policy accepted a longer leaf OU value with the expected prefix.\n' >&2
  exit 1
fi

if runtime_requirement_is_team_bound "$disjunctive_team_requirement" 'TESTTEAM01'; then
  printf 'The signing policy accepted a requirement that also permits another team.\n' >&2
  exit 1
fi

if runtime_requirement_is_team_bound "$disjunctive_non_ou_requirement" 'TESTTEAM01'; then
  printf 'The signing policy accepted a disjunctive team requirement.\n' >&2
  exit 1
fi

if runtime_requirement_is_team_bound "$negated_team_requirement" 'TESTTEAM01'; then
  printf 'The signing policy accepted a negated team requirement.\n' >&2
  exit 1
fi

if runtime_requirement_is_team_bound "$symbolic_negated_team_requirement" 'TESTTEAM01'; then
  printf 'The signing policy accepted a symbolically negated team requirement.\n' >&2
  exit 1
fi

if runtime_requirement_is_team_bound "$quoted_fake_team_requirement" 'TESTTEAM01'; then
  printf 'The signing policy accepted a team predicate embedded in a quoted value.\n' >&2
  exit 1
fi

if runtime_requirement_is_team_bound "$commented_fake_team_requirement" 'TESTTEAM01'; then
  printf 'The signing policy accepted a team predicate embedded in a comment.\n' >&2
  exit 1
fi

config_output="$(
  env \
    -u LECTUREBOARD_CODE_SIGN_IDENTITY \
    -u LECTUREBOARD_DEVELOPMENT_TEAM \
    "$runtime_script" --print-config
)"

expect_config_line() {
  local expected_line="$1"
  if ! grep -Fxq "$expected_line" <<<"$config_output"; then
    printf 'Missing runtime-build configuration line: %s\n' "$expected_line" >&2
    exit 1
  fi
}

expect_config_line "REPOSITORY_ROOT=$repository_root"
expect_config_line "DERIVED_DATA_PATH=$repository_root/DerivedData/RuntimeBuild"
expect_config_line \
  "GENERATED_PROJECT_PATH=$repository_root/DerivedData/RuntimeBuild/GeneratedProject/LectureBoardAI.xcodeproj"
expect_config_line \
  "LOCAL_PACKAGE_LINK=$repository_root/DerivedData/RuntimeBuild/GeneratedProject/Packages"
expect_config_line "LOCAL_PACKAGE_TARGET=$repository_root/Packages"
expect_config_line \
  "INFO_PLIST_PATH=$repository_root/LectureBoardAI/Config/Info.plist"
expect_config_line \
  "GENERATED_INFO_PLIST_LINK=$repository_root/DerivedData/RuntimeBuild/GeneratedProject/LectureBoardAI/Config/Info.plist"
expect_config_line \
  "ENTITLEMENTS_PATH=$repository_root/LectureBoardAI/Config/LectureBoardAI.entitlements"
expect_config_line \
  "GENERATED_ENTITLEMENTS_LINK=$repository_root/DerivedData/RuntimeBuild/GeneratedProject/LectureBoardAI/Config/LectureBoardAI.entitlements"
expect_config_line \
  "APP_PATH=$repository_root/DerivedData/RuntimeBuild/Build/Products/Debug/LectureBoard AI.app"
expect_config_line 'BUNDLE_IDENTIFIER=io.github.akiyama709.LectureBoardAI'
expect_config_line 'ARCHITECTURE=arm64'
expect_config_line 'CONFIGURATION=Debug'
expect_config_line 'DEBUG_DYLIB=disabled'
expect_config_line 'LOCALIZATIONS=en,ja'
expect_config_line 'SIGNING_MODE=ad-hoc'
expect_config_line 'SIGNATURE_TYPE=ad hoc'
expect_config_line 'DESIGNATED_REQUIREMENT_KIND=per-build cdhash'
expect_config_line \
  'SCREEN_RECORDING_PERMISSION=may require authorization again after rebuild'
expect_config_line 'DISTRIBUTION_STATUS=not distribution signed or notarized'

stable_config_output="$(
  LECTUREBOARD_CODE_SIGN_IDENTITY='Apple Development: Script Regression Test' \
  LECTUREBOARD_DEVELOPMENT_TEAM='TESTTEAM01' \
    "$runtime_script" --print-config
)"

for expected_line in \
  'SIGNING_MODE=developer-identity' \
  'SIGNATURE_TYPE=explicit developer identity' \
  'SIGNING_CREDENTIALS=explicit identity and team provided' \
  'DESIGNATED_REQUIREMENT_KIND=Apple certificate-bound requirement' \
  'SCREEN_RECORDING_PERMISSION=eligible for stable matching across rebuilds with the same identity and team' \
  'DISTRIBUTION_STATUS=not notarized by this script'; do
  if ! grep -Fxq "$expected_line" <<<"$stable_config_output"; then
    printf 'Missing stable-signing configuration line: %s\n' "$expected_line" >&2
    exit 1
  fi
done

if grep -Fq 'Apple Development: Script Regression Test' <<<"$stable_config_output" \
  || grep -Fq 'TESTTEAM01' <<<"$stable_config_output"; then
  printf 'Stable-signing configuration exposed an identity or team value.\n' >&2
  exit 1
fi

if LECTUREBOARD_CODE_SIGN_IDENTITY='Apple Development: Script Regression Test' \
  env -u LECTUREBOARD_DEVELOPMENT_TEAM \
  "$runtime_script" --print-config >/dev/null 2>&1; then
  printf 'The runtime-build script accepted a signing identity without a team.\n' >&2
  exit 1
fi

if LECTUREBOARD_DEVELOPMENT_TEAM='TESTTEAM01' \
  env -u LECTUREBOARD_CODE_SIGN_IDENTITY \
  "$runtime_script" --print-config >/dev/null 2>&1; then
  printf 'The runtime-build script accepted a team without a signing identity.\n' >&2
  exit 1
fi

if LECTUREBOARD_CODE_SIGN_IDENTITY='-' \
  LECTUREBOARD_DEVELOPMENT_TEAM='TESTTEAM01' \
  "$runtime_script" --print-config >/dev/null 2>&1; then
  printf 'The runtime-build script accepted ad hoc signing in the stable-signing path.\n' >&2
  exit 1
fi

if LECTUREBOARD_CODE_SIGN_IDENTITY='Apple Development: Script Regression Test' \
  LECTUREBOARD_DEVELOPMENT_TEAM='invalid' \
  "$runtime_script" --print-config >/dev/null 2>&1; then
  printf 'The runtime-build script accepted an invalid Apple team identifier.\n' >&2
  exit 1
fi

if "$runtime_script" --unsupported >/dev/null 2>&1; then
  printf 'The runtime-build script accepted an unsupported argument.\n' >&2
  exit 1
fi

if "$runtime_script" --print-config unexpected >/dev/null 2>&1; then
  printf 'The runtime-build script accepted multiple arguments.\n' >&2
  exit 1
fi

for required_info_plist_boundary in \
  '[[ ! -f "$info_plist_file" || -L "$info_plist_file" ]]' \
  'plutil -lint "$info_plist_file"' \
  'actual_info_plist_target="$(readlink "$generated_info_plist_link")"' \
  'ln -s "$info_plist_file" "$generated_info_plist_link"'; do
  if ! grep -Fq "$required_info_plist_boundary" "$runtime_script"; then
    printf 'The runtime-build script lost an Info.plist boundary: %s\n' \
      "$required_info_plist_boundary" >&2
    exit 1
  fi
done

printf 'Runtime-build script configuration tests passed.\n'
