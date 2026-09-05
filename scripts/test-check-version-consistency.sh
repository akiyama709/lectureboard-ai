#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
checker="$script_directory/check-version-consistency.sh"
temporary_parent="${TMPDIR:-/tmp}"
fixture_root="$(mktemp -d "$temporary_parent/lectureboard-version-consistency.XXXXXX")"

cleanup() {
  find "$fixture_root" -type f -delete
  find "$fixture_root" -depth -type d -empty -delete
}
trap cleanup EXIT

write_fixture() {
  local destination="$1"

  mkdir -p "$destination/scripts"
  cp "$checker" "$destination/scripts/check-version-consistency.sh"
  {
    printf '%s\n' \
      'cff-version: 1.2.0' \
      'title: "LectureBoard AI"' \
      'version: "0.1.0-alpha"' \
      'date-released: "2026-08-29"'
  } >"$destination/CITATION.cff"
  {
    printf '%s\n' \
      '# Changelog' \
      '' \
      '## [Unreleased]' \
      '' \
      '## [0.1.0-alpha] - 2026-08-29'
  } >"$destination/CHANGELOG.md"
  {
    printf '%s\n' \
      'settings:' \
      '  base:' \
      '    MARKETING_VERSION: 0.1.0' \
      '    CURRENT_PROJECT_VERSION: 1'
  } >"$destination/project.yml"
}

assert_rejected() {
  local fixture="$1"
  local label="$2"

  if "$fixture/scripts/check-version-consistency.sh" >/dev/null 2>&1; then
    printf 'Version consistency check accepted %s.\n' "$label" >&2
    exit 1
  fi
}

baseline="$fixture_root/baseline"
write_fixture "$baseline"
"$baseline/scripts/check-version-consistency.sh" >/dev/null

stable_v1="$fixture_root/stable-v1"
write_fixture "$stable_v1"
sed 's/0.1.0-alpha/1.0.0/' "$baseline/CITATION.cff" >"$stable_v1/CITATION.cff"
sed 's/0.1.0-alpha/1.0.0/' "$baseline/CHANGELOG.md" >"$stable_v1/CHANGELOG.md"
sed 's/MARKETING_VERSION: 0.1.0/MARKETING_VERSION: 1.0.0/' \
  "$baseline/project.yml" >"$stable_v1/project.yml"
"$stable_v1/scripts/check-version-consistency.sh" >/dev/null

suffix_core_mismatch="$fixture_root/suffix-core-mismatch"
write_fixture "$suffix_core_mismatch"
sed 's/MARKETING_VERSION: 0.1.0/MARKETING_VERSION: 0.1.1/' \
  "$baseline/project.yml" >"$suffix_core_mismatch/project.yml"
assert_rejected "$suffix_core_mismatch" 'a repository suffix with a mismatched bundle core'

version_mismatch="$fixture_root/cff-changelog-version-mismatch"
write_fixture "$version_mismatch"
sed 's/\[0.1.0-alpha\]/[0.1.1-alpha]/' \
  "$baseline/CHANGELOG.md" >"$version_mismatch/CHANGELOG.md"
assert_rejected "$version_mismatch" 'different CFF and changelog versions'

date_mismatch="$fixture_root/cff-changelog-date-mismatch"
write_fixture "$date_mismatch"
sed 's/2026-08-29/2026-08-30/' \
  "$baseline/CHANGELOG.md" >"$date_mismatch/CHANGELOG.md"
assert_rejected "$date_mismatch" 'different CFF and changelog dates'

malformed_version="$fixture_root/malformed-version"
write_fixture "$malformed_version"
sed 's/0.1.0-alpha/01.0.0-alpha/' \
  "$baseline/CITATION.cff" >"$malformed_version/CITATION.cff"
sed 's/0.1.0-alpha/01.0.0-alpha/' \
  "$baseline/CHANGELOG.md" >"$malformed_version/CHANGELOG.md"
assert_rejected "$malformed_version" 'a malformed repository version'

nonpositive_build="$fixture_root/nonpositive-build"
write_fixture "$nonpositive_build"
sed 's/CURRENT_PROJECT_VERSION: 1/CURRENT_PROJECT_VERSION: 0/' \
  "$baseline/project.yml" >"$nonpositive_build/project.yml"
assert_rejected "$nonpositive_build" 'a nonpositive bundle build number'

duplicate_setting="$fixture_root/duplicate-setting"
write_fixture "$duplicate_setting"
printf '    MARKETING_VERSION: 0.1.0\n' >>"$duplicate_setting/project.yml"
assert_rejected "$duplicate_setting" 'a duplicate project version setting'

duplicate_cff_value="$fixture_root/duplicate-cff-value"
write_fixture "$duplicate_cff_value"
printf 'version: "0.1.0-alpha"\n' >>"$duplicate_cff_value/CITATION.cff"
assert_rejected "$duplicate_cff_value" 'a duplicate CFF version value'

missing_value="$fixture_root/missing-value"
write_fixture "$missing_value"
sed '/date-released:/d' "$baseline/CITATION.cff" >"$missing_value/CITATION.cff"
assert_rejected "$missing_value" 'a missing CFF release date'

malformed_changelog_heading="$fixture_root/malformed-changelog-heading"
write_fixture "$malformed_changelog_heading"
sed 's/ \- 2026-08-29$/ (2026-08-29)/' \
  "$baseline/CHANGELOG.md" >"$malformed_changelog_heading/CHANGELOG.md"
assert_rejected "$malformed_changelog_heading" 'a malformed first released changelog heading'

invalid_calendar_date="$fixture_root/invalid-calendar-date"
write_fixture "$invalid_calendar_date"
sed 's/2026-08-29/2026-02-30/' \
  "$baseline/CITATION.cff" >"$invalid_calendar_date/CITATION.cff"
sed 's/2026-08-29/2026-02-30/' \
  "$baseline/CHANGELOG.md" >"$invalid_calendar_date/CHANGELOG.md"
assert_rejected "$invalid_calendar_date" 'an invalid calendar date'

printf 'Version consistency regression tests passed.\n'
