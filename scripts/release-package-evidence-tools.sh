#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail
export LC_ALL=C
export PATH='/usr/bin:/bin:/usr/sbin:/sbin'
unset CDPATH

maximum_bytes=1048576

fail() {
  printf 'Release package evidence check failed: %s\n' "$1" >&2
  exit 1
}

normalize_hex() {
  printf '%s' "$1" | /usr/bin/tr '[:lower:]' '[:upper:]'
}

usage() {
  printf '%s\n' \
    'Usage:' \
    '  release-package-evidence-tools.sh notary-submit --json /absolute/result.json' \
    '  release-package-evidence-tools.sh notary-log --json /absolute/log.json --id UUID --sha256 DIGEST' \
    '  release-package-evidence-tools.sh attach-plist --plist /absolute/attach.plist --mountpoint /absolute/mount' \
    '  release-package-evidence-tools.sh verify-tree-export --manifest /absolute/manifest --root /absolute/tree' \
    '  release-package-evidence-tools.sh require-absent --path /absolute/path'
}

require_file() {
  local path="$1" label="$2" size
  [[ "$path" == /* && "$path" != '/' && -f "$path" && ! -L "$path" ]] \
    || fail "$label must be an absolute regular non-symbolic-link file"
  size="$(/usr/bin/stat -f '%z' "$path")" || fail "$label size could not be read"
  [[ "$size" =~ ^[1-9][0-9]*$ && "$size" -le "$maximum_bytes" ]] \
    || fail "$label is empty or exceeds the bounded size"
  /usr/bin/plutil -convert xml1 -o - "$path" >/dev/null 2>&1 \
    || fail "$label is not a JSON or property-list document"
}

scalar() {
  local path="$1" key="$2" label="$3" value
  [[ "$(/usr/bin/plutil -type "$key" "$path" 2>/dev/null)" == 'string' ]] \
    || fail "$label must be a string"
  value="$(/usr/bin/plutil -extract "$key" raw -o - "$path" 2>/dev/null)" \
    || fail "$label is missing"
  [[ -n "$value" ]] || fail "$label is empty"
  printf '%s\n' "$value"
}

command_name="${1:-}"
[[ -n "$command_name" ]] || { usage >&2; exit 64; }
shift

case "$command_name" in
  notary-submit)
    [[ "$#" == 2 && "$1" == '--json' ]] || { usage >&2; exit 64; }
    json="$2"
    require_file "$json" 'notary submission response'
    submission_id="$(scalar "$json" id 'notary submission identifier')"
    status="$(scalar "$json" status 'notary submission status')"
    [[ "$submission_id" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] \
      || fail 'notary submission identifier is malformed'
    [[ "$status" == 'Accepted' ]] || fail 'notary submission was not Accepted'
    printf '%s\n' "$submission_id"
    ;;
  notary-log)
    [[ "$#" == 6 && "$1" == '--json' && "$3" == '--id' && "$5" == '--sha256' ]] \
      || { usage >&2; exit 64; }
    json="$2" expected_id="$4" expected_sha="$6"
    [[ "$expected_id" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] \
      || fail 'expected notary identifier is malformed'
    [[ "$expected_sha" =~ ^[0-9A-Fa-f]{64}$ ]] || fail 'expected archive digest is malformed'
    require_file "$json" 'notary log'
    job_id="$(scalar "$json" jobId 'notary log job identifier')"
    status="$(scalar "$json" status 'notary log status')"
    sha="$(scalar "$json" sha256 'notary log archive digest')"
    [[ "$(/usr/bin/plutil -type statusCode "$json" 2>/dev/null)" == 'integer' ]] \
      || fail 'notary log status code must be an integer'
    status_code="$(/usr/bin/plutil -extract statusCode raw -o - "$json" 2>/dev/null)"
    [[ "$(normalize_hex "$job_id")" == "$(normalize_hex "$expected_id")" ]] \
      || fail 'notary log does not match the submission'
    [[ "$status" == 'Accepted' && "$status_code" == '0' ]] \
      || fail 'notary log did not confirm Accepted status'
    [[ "$sha" =~ ^[0-9A-Fa-f]{64}$ \
      && "$(normalize_hex "$sha")" == "$(normalize_hex "$expected_sha")" ]] \
      || fail 'notary log is not bound to the submitted bytes'
    issues_type="$(/usr/bin/plutil -type issues "$json" 2>/dev/null || true)"
    if [[ "$issues_type" == 'array' ]]; then
      [[ "$(/usr/bin/plutil -extract issues raw -o - "$json" 2>/dev/null)" == '0' ]] \
        || fail 'notary log contains issues'
    elif [[ "$issues_type" != 'null' ]]; then
      fail 'notary log issues are missing or malformed'
    fi
    /usr/bin/shasum -a 256 "$json" | /usr/bin/awk '{ print $1 }'
    ;;
  attach-plist)
    [[ "$#" == 4 && "$1" == '--plist' && "$3" == '--mountpoint' ]] \
      || { usage >&2; exit 64; }
    plist="$2" mountpoint="$4"
    [[ "$mountpoint" == /* && "$mountpoint" != '/' ]] || fail 'mount point must be absolute and non-root'
    require_file "$plist" 'disk-image attach property list'
    [[ "$(/usr/bin/plutil -type system-entities "$plist" 2>/dev/null)" == 'array' ]] \
      || fail 'mount entity list must be an array'
    count="$(/usr/bin/plutil -extract system-entities raw -o - "$plist" 2>/dev/null)"
    [[ "$count" =~ ^[1-9][0-9]*$ && "$count" -le 16 ]] || fail 'mount entity count is invalid'
    matches=0 device=''
    for ((index = 0; index < count; index++)); do
      type="$(/usr/bin/plutil -type "system-entities.$index" "$plist" 2>/dev/null || true)"
      [[ "$type" == 'dictionary' ]] || fail 'mount entity must be a dictionary'
      if [[ "$(/usr/bin/plutil -type "system-entities.$index.mount-point" "$plist" 2>/dev/null || true)" == 'string' ]]; then
        observed="$(/usr/bin/plutil -extract "system-entities.$index.mount-point" raw -o - "$plist")"
        if [[ "$observed" == "$mountpoint" ]]; then
          candidate="$(scalar "$plist" "system-entities.$index.dev-entry" 'mounted device')"
          [[ "$candidate" =~ ^/dev/disk[0-9]+(s[0-9]+)*$ ]] || fail 'mounted device is malformed'
          matches=$((matches + 1)); device="$candidate"
        fi
      fi
    done
    [[ "$matches" == 1 ]] || fail 'attach result did not contain exactly one expected mounted volume'
    printf '%s\n' "$device"
    ;;
  verify-tree-export)
    [[ "$#" == 4 && "$1" == '--manifest' && "$3" == '--root' ]] \
      || { usage >&2; exit 64; }
    manifest="$2" root="$4"
    [[ "$manifest" == /* && "$manifest" != '/' && -f "$manifest" && ! -L "$manifest" ]] \
      || fail 'expected export manifest must be an absolute regular non-symbolic-link file'
    [[ "$root" == /* && "$root" != '/' && -d "$root" && ! -L "$root" ]] \
      || fail 'export root must be an absolute non-symbolic-link directory'
    manifest_size="$(/usr/bin/stat -f '%z' "$manifest")" \
      || fail 'expected export manifest size could not be read'
    [[ "$manifest_size" =~ ^[1-9][0-9]*$ && "$manifest_size" -le 16777216 ]] \
      || fail 'expected export manifest is empty or exceeds the bounded size'
    entry_list="$(/usr/bin/mktemp /private/tmp/lectureboard-export-entries.XXXXXX)" \
      || fail 'export entry list could not be created'
    actual_manifest="$(/usr/bin/mktemp /private/tmp/lectureboard-export-manifest.XXXXXX)" \
      || { /bin/unlink "$entry_list"; fail 'actual export manifest could not be created'; }
    cleanup_export() {
      [[ -f "${entry_list:-}" ]] && /bin/unlink "$entry_list"
      [[ -f "${actual_manifest:-}" ]] && /bin/unlink "$actual_manifest"
    }
    trap cleanup_export EXIT
    (cd "$root" && /usr/bin/find . -mindepth 1 -print0 >"$entry_list") \
      || fail 'export tree could not be enumerated'
    if ! (
      cd "$root"
      while IFS= read -r -d '' relative; do
        [[ "$relative" == ./* && "$relative" != *$'\n'* && "$relative" != *$'\t'* \
          && "$relative" != *'|'* ]] || exit 81
        relative="${relative#./}"
        if [[ -L "$relative" ]]; then
          exit 82
        elif [[ -d "$relative" ]]; then
          printf 'directory|040000|%s\n' "$relative"
        elif [[ -f "$relative" ]]; then
          if [[ -x "$relative" ]]; then mode='100755'; else mode='100644'; fi
          digest="$(/usr/bin/shasum -a 256 "$relative" | /usr/bin/awk '{ print $1 }')" \
            || exit 83
          [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || exit 84
          printf 'file|%s|%s|%s\n' "$mode" "$relative" "$digest"
        else
          exit 85
        fi
      done <"$entry_list"
    ) | /usr/bin/sort >"$actual_manifest"; then
      fail 'export tree contains an unsafe or unrepresentable entry'
    fi
    expected_line_count="$(/usr/bin/awk '
      /^directory\|040000\|[^|]+$/ { valid += 1; next }
      /^file\|100(644|755)\|[^|]+\|[0-9a-f]{64}$/ { valid += 1; next }
      { invalid += 1 }
      END { if (invalid > 0 || valid == 0) exit 1; print valid }
    ' "$manifest")" || fail 'expected export manifest is malformed'
    actual_line_count="$(/usr/bin/awk 'END { print NR + 0 }' "$actual_manifest")"
    [[ "$actual_line_count" == "$expected_line_count" ]] \
      || fail 'export tree entry count differs from the approved commit'
    /usr/bin/cmp -s "$manifest" "$actual_manifest" \
      || fail 'export tree differs from the approved commit path, mode, or blob digest'
    /bin/unlink "$entry_list"; entry_list=''
    /bin/unlink "$actual_manifest"; actual_manifest=''
    trap - EXIT
    ;;
  require-absent)
    [[ "$#" == 2 && "$1" == '--path' && "$2" == /* && "$2" != '/' ]] \
      || { usage >&2; exit 64; }
    [[ ! -e "$2" && ! -L "$2" ]] \
      || fail 'path still exists or is a symbolic link'
    ;;
  *) usage >&2; exit 64 ;;
esac
