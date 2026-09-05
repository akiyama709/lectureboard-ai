#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

fail() {
  printf 'Version consistency check failed: %s\n' "$1" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "required file is missing: $1"
}

read_unique_scalar() {
  local path="$1"
  local key="$2"
  local indentation="$3"
  local count line value

  if [[ "$indentation" == "top-level" ]]; then
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

  [[ "$count" == "1" ]] || fail "$path must contain exactly one $key setting (found $count)"

  value="${line#*:}"
  if [[ "$value" =~ ^[[:space:]]*\"([^\"]+)\"[[:space:]]*$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ "$value" =~ ^[[:space:]]*\'([^\']+)\'[[:space:]]*$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  elif [[ "$value" =~ ^[[:space:]]*([^[:space:]#]+)[[:space:]]*$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  else
    fail "$path contains a malformed $key value"
  fi
}

validate_semver() {
  local version="$1"
  local semver_pattern

  semver_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-((0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(\.(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?(\+([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?$'
  if [[ ! "$version" =~ $semver_pattern ]]; then
    fail "repository version is not valid SemVer: $version"
  fi

  semver_core="${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
}

validate_date() {
  local value="$1"
  local year month day max_day

  if [[ ! "$value" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})$ ]]; then
    fail "release date must use YYYY-MM-DD: $value"
  fi

  year=$((10#${BASH_REMATCH[1]}))
  month=$((10#${BASH_REMATCH[2]}))
  day=$((10#${BASH_REMATCH[3]}))
  case "$month" in
    1|3|5|7|8|10|12) max_day=31 ;;
    4|6|9|11) max_day=30 ;;
    2)
      max_day=28
      if (( year % 400 == 0 || (year % 4 == 0 && year % 100 != 0) )); then
        max_day=29
      fi
      ;;
    *) fail "release date has an invalid month: $value" ;;
  esac
  (( day >= 1 && day <= max_day )) || fail "release date has an invalid day: $value"
}

require_file CITATION.cff
require_file CHANGELOG.md
require_file project.yml

cff_version="$(read_unique_scalar CITATION.cff version top-level)"
cff_date="$(read_unique_scalar CITATION.cff date-released top-level)"
marketing_version="$(read_unique_scalar project.yml MARKETING_VERSION any)"
build_number="$(read_unique_scalar project.yml CURRENT_PROJECT_VERSION any)"

unreleased_count="$(awk '
  /^## \[Unreleased\][[:space:]]*$/ { count += 1 }
  END { print count + 0 }
' CHANGELOG.md)"
[[ "$unreleased_count" == "1" ]] \
  || fail "CHANGELOG.md must contain exactly one Unreleased heading (found $unreleased_count)"

released_heading="$(awk '
  /^## \[Unreleased\][[:space:]]*$/ { after_unreleased = 1; next }
  after_unreleased && /^## / { print; exit }
' CHANGELOG.md)"
[[ -n "$released_heading" ]] || fail "CHANGELOG.md has no released heading after Unreleased"
if [[ ! "$released_heading" =~ ^##[[:space:]]\[([^]]+)\][[:space:]]-[[:space:]]([0-9]{4}-[0-9]{2}-[0-9]{2})$ ]]; then
  fail "first released CHANGELOG.md heading is malformed: $released_heading"
fi
changelog_version="${BASH_REMATCH[1]}"
changelog_date="${BASH_REMATCH[2]}"

duplicate_release_count="$(awk -v version="$changelog_version" '
  /^## \[[^]]+\][[:space:]]+-[[:space:]]+[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9][[:space:]]*$/ {
    heading = $0
    sub(/^## \[/, "", heading)
    sub(/\].*$/, "", heading)
    if (heading == version) { count += 1 }
  }
  END { print count + 0 }
' CHANGELOG.md)"
[[ "$duplicate_release_count" == "1" ]] \
  || fail "CHANGELOG.md release version appears more than once: $changelog_version"

validate_semver "$cff_version"
[[ "$changelog_version" == "$cff_version" ]] \
  || fail "CITATION.cff version ($cff_version) and CHANGELOG.md version ($changelog_version) differ"

validate_date "$cff_date"
validate_date "$changelog_date"
[[ "$changelog_date" == "$cff_date" ]] \
  || fail "CITATION.cff date ($cff_date) and CHANGELOG.md date ($changelog_date) differ"

[[ "$marketing_version" == "$semver_core" ]] \
  || fail "project.yml MARKETING_VERSION ($marketing_version) must equal repository SemVer core ($semver_core)"
[[ "$marketing_version" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]] \
  || fail "project.yml MARKETING_VERSION is malformed: $marketing_version"
[[ "$build_number" =~ ^[1-9][0-9]*$ ]] \
  || fail "project.yml CURRENT_PROJECT_VERSION must be a positive integer: $build_number"

printf 'Version metadata is consistent: repository %s, bundle %s (%s), released %s.\n' \
  "$cff_version" "$marketing_version" "$build_number" "$cff_date"
printf 'This check verifies metadata consistency only; it does not verify a release.\n'
