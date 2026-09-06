#!/bin/bash -p
case "$-" in *p*) ;; *) exit 78 ;; esac
set -euo pipefail
export PATH='/usr/bin:/bin:/usr/sbin:/sbin'
export LC_ALL=C
tool="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && /bin/pwd -P)/no-fee-release-v1.sh"
/bin/bash -p -n "$tool"
require_text() {
  /usr/bin/grep -Fq -- "$1" "$tool" \
    || { /usr/bin/printf '%s\n' "missing no-fee release contract: $1" >&2; exit 1; }
}
reject_text() {
  ! /usr/bin/grep -Fq -- "$1" "$tool" \
    || { /usr/bin/printf '%s\n' "obsolete no-fee release contract remains: $1" >&2; exit 1; }
}
require_text 'SBOM.spdx.json#%s'
reject_text 'SBOM-%s.spdx.json'
require_text 'LECTUREBOARD_RELEASE_COMMIT="$commit"'
require_text 'LECTUREBOARD_RELEASE_TAG="$tag"'
require_text 'LECTUREBOARD_RELEASE_TAG_OBJECT="$tag_object"'
reject_text 'INFOPLIST_KEY_LectureBoardReleaseCommit='
require_text 'flags_value=$((16#$flags_hex))'
require_text '(( (flags_value & 0x10000) == 0x10000 ))'
reject_text 'flags=0x10000'
require_text '"tagObject":"%s"'
require_text "die 'bundle tag-object provenance is not exact'"
require_text "die 'provenance tag object is absent'"
require_text '"entitlements":{"keys":["com.apple.security.automation.apple-events","com.apple.security.device.audio-input"],"canonicalJsonSha256":"2ef41daa1f5a828d3492e8e40efdd881b539169e6b1b95aad9be949c73de01b0"}'
require_text "die 'provenance entitlement binding is not exact'"
require_text 'packages.0.checksums.0.algorithm'

root="$(/usr/bin/mktemp -d /private/tmp/lectureboard-no-fee-v1-test.XXXXXX)"
trap '[[ -d "$root" ]] && /usr/bin/find "$root" -depth -delete' EXIT
runtime_flag_function="$root/hardened-runtime-flag-function.sh"
sed -n '/^hardened_runtime_flag_is_set() {$/,/^}$/p' "$tool" \
  >"$runtime_flag_function"
source "$runtime_flag_function"

for accepted_flags in \
  'CodeDirectory v=20500 size=1 flags=0x10000(runtime) hashes=1+7 location=embedded' \
  'CodeDirectory v=20500 size=1 flags=0x10002(adhoc,runtime) hashes=1+7 location=embedded' \
  'CodeDirectory v=20500 size=1 flags=0x110002(adhoc,runtime,other) hashes=1+7 location=embedded'; do
  hardened_runtime_flag_is_set "$accepted_flags" \
    || { printf 'No-fee tooling rejected a runtime-bit flag value.\n' >&2; exit 1; }
done

for rejected_flags in \
  'CodeDirectory v=20500 size=1 flags=0x2(adhoc) hashes=1+7 location=embedded' \
  'CodeDirectory v=20500 size=1 flags=0x0(none) hashes=1+7 location=embedded' \
  'CodeDirectory v=20500 size=1 flags=not-hex(runtime) hashes=1+7 location=embedded' \
  $'CodeDirectory v=20500 size=1 flags=0x10002(adhoc,runtime) hashes=1+7 location=embedded\nCodeDirectory v=20500 size=1 flags=0x10002(adhoc,runtime) hashes=1+7 location=embedded'; do
  if hardened_runtime_flag_is_set "$rejected_flags"; then
    printf 'No-fee tooling accepted malformed or runtime-bit-free code flags.\n' >&2
    exit 1
  fi
done
commit=0123456789012345678901234567890123456789
for command in prepare verify compare-public; do
  if LECTUREBOARD_RELEASE_TEST_MODE=fixture-v1 /bin/bash -p "$tool" "$command" >/dev/null 2>&1; then
    /usr/bin/printf '%s\n' "fixture bypass accepted by $command" >&2; exit 1
  fi
done
a="$root/LectureBoard-AI-v1.0.0-arm64.zip"; b="$root/download/LectureBoard-AI-v1.0.0-arm64.zip"; /bin/mkdir -p "$(dirname "$b")"
/usr/bin/printf 'approved bytes\n' >"$a"; /bin/cp "$a" "$b"
/usr/bin/shasum -a 256 "$a" | /usr/bin/awk '{print $1 "  LectureBoard-AI-v1.0.0-arm64.zip"}' >"$root/SHA256SUMS"
/bin/bash -p "$tool" compare-public --approved-archive "$a" --downloaded-archive "$b" --checksum "$root/SHA256SUMS" >/dev/null
/usr/bin/printf '%064d  LectureBoard-AI-v1.0.0-arm64.zip\n' 0 >"$root/bad-SHA256SUMS"
if /bin/bash -p "$tool" compare-public --approved-archive "$a" --downloaded-archive "$b" --checksum "$root/bad-SHA256SUMS" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'public comparison accepted a checksum that did not bind the approved archive' >&2; exit 1
fi
/bin/cp "$root/SHA256SUMS" "$root/extra-SHA256SUMS"
/usr/bin/printf '%064d  unexpected.zip\n' 0 >>"$root/extra-SHA256SUMS"
if /bin/bash -p "$tool" compare-public --approved-archive "$a" --downloaded-archive "$b" --checksum "$root/extra-SHA256SUMS" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'public comparison accepted a multi-entry checksum file' >&2; exit 1
fi
if LECTUREBOARD_RELEASE_TEST_MODE=fixture-v1 /bin/bash -p "$tool" compare-public --approved-archive "$a" --downloaded-archive "$b" --checksum "$root/SHA256SUMS" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'public comparison accepted fixture mode with otherwise valid inputs' >&2; exit 1
fi
/usr/bin/printf x >>"$b"
if /bin/bash -p "$tool" compare-public --approved-archive "$a" --downloaded-archive "$b" --checksum "$root/SHA256SUMS" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'different public bytes accepted' >&2; exit 1
fi
if /bin/bash -p "$tool" build --source-dir "$root" --commit "$commit" --tag v1.0.0 --output-dir "$root/out" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'removed split build command was still accepted' >&2; exit 1
fi
if /bin/bash -p "$tool" package --app "$root/no.app" --source-dir "$root" --commit "$commit" --tag v1.0.0 --test-result "$a" --output-dir "$root/out" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'removed split package command was still accepted' >&2; exit 1
fi
/usr/bin/printf '%s\n' 'No-fee v1 release tooling boundary tests passed.'
