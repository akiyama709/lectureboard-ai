#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail
export LC_ALL=C

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
source_file="$script_directory/release-exclusive-rename.c"
temporary_parent="${TMPDIR:-/tmp}"
temporary_parent="${temporary_parent%/}"
temporary_root="$(mktemp -d "$temporary_parent/lectureboard-exclusive-rename-tests.XXXXXX")"

cleanup() {
  case "$temporary_root" in
    "$temporary_parent"/lectureboard-exclusive-rename-tests.*)
      find "$temporary_root" -depth -delete
      ;;
  esac
}
trap cleanup EXIT

helper="$temporary_root/release-exclusive-rename"
/usr/bin/clang -std=c17 -Wall -Wextra -Werror -O2 "$source_file" -o "$helper"
handoff() {
  local source="$1" destination="$2" parent_identity source_identity
  parent_identity="$(/usr/bin/stat -f '%d %i' "$(/usr/bin/dirname -- "$source")")"
  source_identity="$(/usr/bin/stat -f '%d %i' "$source")"
  "$helper" "$source" "$destination" \
    ${parent_identity% *} ${parent_identity#* } \
    ${source_identity% *} ${source_identity#* }
}

source_directory="$temporary_root/source"
destination_directory="$temporary_root/destination"
mkdir "$source_directory"
printf 'verified\n' >"$source_directory/marker.txt"
handoff "$source_directory" "$destination_directory"
[[ ! -e "$source_directory" ]]
[[ "$(<"$destination_directory/marker.txt")" == 'verified' ]]

cross_parent_source="$temporary_root/cross-parent-source"
cross_parent_directory="$temporary_root/other-parent"
mkdir "$cross_parent_source" "$cross_parent_directory"
if handoff "$cross_parent_source" "$cross_parent_directory/destination"; then
  printf 'Exclusive rename accepted different source and destination parents.\n' >&2
  exit 1
fi
[[ -d "$cross_parent_source" ]]
[[ ! -e "$cross_parent_directory/destination" ]]

existing_source="$temporary_root/existing-source"
existing_destination="$temporary_root/existing-destination"
mkdir "$existing_source" "$existing_destination"
printf 'source\n' >"$existing_source/marker.txt"
printf 'destination\n' >"$existing_destination/marker.txt"
if handoff "$existing_source" "$existing_destination"; then
  printf 'Exclusive rename replaced or nested into an existing destination.\n' >&2
  exit 1
fi
[[ "$(<"$existing_source/marker.txt")" == 'source' ]]
[[ "$(<"$existing_destination/marker.txt")" == 'destination' ]]
[[ ! -e "$existing_destination/$(basename -- "$existing_source")" ]]

source_file_path="$temporary_root/source-file"
printf 'file\n' >"$source_file_path"
if handoff "$source_file_path" "$temporary_root/file-destination"; then
  printf 'Exclusive rename accepted a non-directory source.\n' >&2
  exit 1
fi

swapped_source="$temporary_root/swapped-source"
swapped_destination="$temporary_root/swapped-destination"
mkdir "$swapped_source"
printf 'verified\n' >"$swapped_source/marker.txt"
swapped_parent_identity="$(/usr/bin/stat -f '%d %i' "$temporary_root")"
swapped_source_identity="$(/usr/bin/stat -f '%d %i' "$swapped_source")"
mv "$swapped_source" "$temporary_root/original-swapped-source"
mkdir "$swapped_source"
printf 'forged-after-validation\n' >"$swapped_source/marker.txt"
if "$helper" "$swapped_source" "$swapped_destination" \
  ${swapped_parent_identity% *} ${swapped_parent_identity#* } \
  ${swapped_source_identity% *} ${swapped_source_identity#* }; then
  printf 'Exclusive rename accepted a path-swapped source directory.\n' >&2
  exit 1
fi
[[ ! -e "$swapped_destination" ]]
[[ "$(<"$temporary_root/original-swapped-source/marker.txt")" == 'verified' ]]
[[ "$(<"$swapped_source/marker.txt")" == 'forged-after-validation' ]]

for invalid_invocation in \
  'missing-arguments' \
  'relative-source' \
  'relative-destination' \
  'same-path'; do
  case "$invalid_invocation" in
    missing-arguments)
      if "$helper" >/dev/null 2>&1; then exit 1; fi
      ;;
    relative-source)
      if "$helper" relative "$temporary_root/unused-1" 1 1 1 1 >/dev/null 2>&1; then exit 1; fi
      ;;
    relative-destination)
      if "$helper" "$temporary_root/unused-2" relative 1 1 1 1 >/dev/null 2>&1; then exit 1; fi
      ;;
    same-path)
      if "$helper" "$temporary_root/unused-3" "$temporary_root/unused-3" 1 1 1 1 \
        >/dev/null 2>&1; then exit 1; fi
      ;;
  esac
done

printf 'Exclusive release-output handoff tests passed.\n'
