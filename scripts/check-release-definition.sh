#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail
export PATH='/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin'
export LC_ALL=C
unset CDPATH

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    printf 'Required release document is missing: %s\n' "$path" >&2
    exit 1
  fi
}

require_text() {
  local path="$1"
  local expected="$2"
  if ! grep -F -- "$expected" "$path" >/dev/null; then
    printf 'Required release definition is missing from %s: %s\n' "$path" "$expected" >&2
    exit 1
  fi
}

require_text_count() {
  local path="$1"
  local expected="$2"
  local required_count="$3"
  local observed_count
  observed_count="$(/usr/bin/grep -Fc -- "$expected" "$path")" || true
  if [[ "$observed_count" != "$required_count" ]]; then
    printf 'Required release definition count is wrong in %s: %s (expected %s, found %s)\n' \
      "$path" "$expected" "$required_count" "$observed_count" >&2
    exit 1
  fi
}

reject_text() {
  local path="$1"
  local forbidden="$2"
  if grep -F -- "$forbidden" "$path" >/dev/null; then
    printf 'Known release overclaim is present in %s: %s\n' "$path" "$forbidden" >&2
    exit 1
  fi
}

require_ordered_text() {
  local path="$1"
  shift
  local expected
  local observed_count
  local observed_line
  local previous_line=0

  for expected in "$@"; do
    observed_count="$(/usr/bin/grep -Fc -- "$expected" "$path")" || true
    if [[ "$observed_count" != 1 ]]; then
      printf 'Ordered release definition must occur exactly once in %s: %s (found %s)\n' \
        "$path" "$expected" "$observed_count" >&2
      exit 1
    fi
    observed_line="$(/usr/bin/awk -v expected="$expected" '
      index($0, expected) {
        print NR
        exit
      }
    ' "$path")"
    if [[ ! "$observed_line" =~ ^[0-9]+$ || "$observed_line" -le "$previous_line" ]]; then
      printf 'Required release definitions are out of order in %s: %s\n' \
        "$path" "$expected" >&2
      exit 1
    fi
    previous_line="$observed_line"
  done
}

require_bash_syntax() {
  local path="$1"
  if ! /bin/bash -p -n "$path"; then
    printf 'Required release script has invalid Bash syntax: %s\n' "$path" >&2
    exit 1
  fi
}

require_privileged_shebang() {
  local path="$1"
  local first_line
  IFS= read -r first_line <"$path" \
    || { printf 'Required release script has no readable first line: %s\n' "$path" >&2; exit 1; }
  if [[ "$first_line" != '#!/bin/bash -p' ]]; then
    printf 'Required release script has an invalid first-line shebang: %s\n' "$path" >&2
    exit 1
  fi
}

require_prepublish_stage_sequence() {
  local path="$1"
  local expected_total=26
  local stages
  local observed=0
  local expected

  stages="$(/usr/bin/awk '
    /^echo "\[[0-9]+\/[0-9]+\]/ {
      stage = $0
      sub(/^echo "\[/, "", stage)
      sub(/\].*$/, "", stage)
      print stage
    }
  ' "$path")"
  [[ -n "$stages" ]] || {
    printf 'Prepublication gate has no numbered stages: %s\n' "$path" >&2
    exit 1
  }

  while IFS= read -r stage; do
    observed=$((observed + 1))
    expected="$observed/$expected_total"
    if [[ "$stage" != "$expected" ]]; then
      printf 'Prepublication gate stage sequence is inconsistent in %s: expected %s, found %s\n' \
        "$path" "$expected" "$stage" >&2
      exit 1
    fi
  done <<<"$stages"

  if [[ "$observed" -ne "$expected_total" ]]; then
    printf 'Prepublication gate stage count is inconsistent in %s: expected %s, found %s\n' \
      "$path" "$expected_total" "$observed" >&2
    exit 1
  fi
}

require_prepublish_prelude_contract() {
  local path="$1"
  local expected_digest='37e4d4b6a6dad659ca47d6d7d4a3f44595bdca408b1f25674f48f57fb808a965'
  local prelude
  local observed_digest

  if ! prelude="$(/usr/bin/awk '
    /^echo "\[1\/26\]/ { exit }
    { print }
  ' "$path")"; then
    printf 'Prepublication gate prelude could not be extracted from %s.\n' "$path" >&2
    exit 1
  fi
  if ! observed_digest="$(
    /usr/bin/printf '%s\n' "$prelude" \
      | /usr/bin/shasum -a 256 \
      | /usr/bin/awk '{ print $1 }'
  )"; then
    printf 'Prepublication gate prelude could not be hashed in %s.\n' "$path" >&2
    exit 1
  fi
  if [[ "$observed_digest" != "$expected_digest" ]]; then
    printf 'Prepublication gate prelude contract changed in %s.\n' "$path" >&2
    exit 1
  fi
}

require_prepublish_stage_contract() {
  local path="$1"
  local expected_stage_digests=(
    ''
    '2bd23c6c7201dd4e44d9eed748f90b3d36507c523c46908ca8c5b6517477f7fd'
    'be431dd37ba65349bba9018b7e463c448730706d02fde20e6b6f50c2dab946fe'
    '9ea49d61e19da5bd6b075790aae5c78f627130e44bf2bdfe1ff950d3b7a8aa7c'
    '18d41c5998c2cfef883b7c8158fa5f9dbd7e2028e778a2bb0146f6a400fc6ec8'
    '5c235c6948dc9b2ac0fcc5602a13714d5c643b43c60bfedfff1588d918dbc0a1'
    'e1fd9064654b7643575460a02ec721597f99f80009cd61f9375b466bea95022b'
    'f630f0e0e49eefdbb49977a0cb5a3e4c99965286a080373e9a0ff038ffdfe3b1'
    'ec7fdb81b457595aa6b56c217c495423d539cd805786b8911fffd7747078e013'
    '443517abd9db4f1bb3f92c9793ded4610e4a34a8d8b02465d6fe0d11a28ad2a0'
    '086ece197a7b665701ed0e6afa94e0a1653192a8883c29270efd7b6aea140f43'
    '3dad6eec34cb18e1669807be1f6a45ec0e1662a499f86bf7f5018529497bf343'
    '8285f66e9e9762893dbd9205f948d550a6c774d08dd0cdaafa14973051b8efd9'
    '6914ddef8aec304860cdfb4f0f539ba86fa10c5916437895dd26c7412d4100ae'
    'ef2abcd99219f0727ab3ecf47af785eae9a933e8a6331510061e78014c7656d5'
    '1ea54e63b3808d2d5731bfcb32a2c7f2e17d1de826b94b3fbfda6bb1abfc332c'
    '3cb8624640e46f8ee3819ca45c977c98bb70ddcaeab3ad859628bb3da2aa6327'
    '6aba94b422f5aeb626b093262cab77e29f0d3092195b9922b8aa44c956981973'
    'e7e5d8996afaa4b8b7a9cde022ac7d3f7826c83e2750f3d44e7897102b65a139'
    '4fc33e2c6ac3968c74d8ae9a78680857535c358112db41e86192406e86eeef8c'
    '5ba1b2aea36e2e9d23bfcecacac848017f87d07ca969b84cdb8f56ab3973bf22'
    '171723de1e129fb0dfc58672acd95fafb7a14478e012b0b704765241ccfec564'
    'ec98e3a7c1a64ab4f438c627393d44f038e3c177f9550c19ebe277be19b41978'
    '2be9d81d160dbf8518e68d0696ed204c381c64f06b9b7e97905da44357583cac'
    '838b31d924fc50b0d8f0deee3df7ac5136db6296ebbcf0b76cac9a110c50e30e'
    'ef497b363bd788efd57c9e8ac80771b24e90e3821f975f15d9b2a21594c213d8'
    '92bd8fc5765211df51373f971a5160432a4c173405077f36a07814e22f1c885e'
  )
  local stage_number
  local stage_block
  local observed_digest

  for stage_number in $(/usr/bin/seq 1 26); do
    if ! stage_block="$(/usr/bin/awk -v target="$stage_number" '
      BEGIN { capture = 0; found = 0 }
      /^echo "\[[0-9]+\/26\]/ {
        if (capture) {
          exit
        }
        prefix = "echo \"[" target "/26]"
        if (index($0, prefix) == 1) {
          capture = 1
          found++
        }
      }
      capture { print }
      END {
        if (found != 1) {
          exit 93
        }
      }
    ' "$path")"; then
      printf 'Prepublication gate stage %s could not be extracted from %s.\n' \
        "$stage_number" "$path" >&2
      exit 1
    fi
    if ! observed_digest="$(
      /usr/bin/printf '%s\n' "$stage_block" \
        | /usr/bin/shasum -a 256 \
        | /usr/bin/awk '{ print $1 }'
    )"; then
      printf 'Prepublication gate stage %s could not be hashed in %s.\n' \
        "$stage_number" "$path" >&2
      exit 1
    fi
    if [[ "$observed_digest" != "${expected_stage_digests[$stage_number]}" ]]; then
      printf 'Prepublication gate stage %s command contract changed in %s.\n' \
        "$stage_number" "$path" >&2
      exit 1
    fi
  done
}

required_files=(
  Makefile
  .github/workflows/ci.yml
  AGENTS.md
  CHANGELOG.md
  ROADMAP.md
  README.md
  project.yml
  LectureBoardAI/Config/LectureBoardAI.entitlements
  docs/architecture.md
  docs/build-verification.md
  docs/development-plan.md
  docs/README.md
  docs/roadmap-ja.md
  docs/technical-design-ja.md
  docs/technical-design-detailed-ja.md
  docs/local-codex-handoff-ja.md
  docs/v1-release-checklist.md
  docs/user-acceptance-ja.md
  docs/user-guide.md
  docs/user-guide-ja.md
  docs/no-fee-release-process.md
  docs/privacy-and-security.md
  docs/privacy-security-ja.md
  docs/release-process.md
  docs/versioning.md
  docs/adr/0006-mit-license.md
  docs/adr/0007-public-v1-completion.md
  docs/adr/0011-bound-dense-change-fresh-samples.md
  docs/adr/0012-causal-managed-slideshow-binding.md
  docs/adr/0013-no-fee-public-v1-distribution.md
  scripts/check-permission-contract.sh
  scripts/test-check-permission-contract.sh
  scripts/prepublish-check.sh
  scripts/publish-to-github.sh
  scripts/release-artifact-tools.sh
  scripts/release-make-gate.sh
  scripts/release-make-shell.sh
  scripts/test-release-artifact-tools.sh
  scripts/build-release-app.sh
  scripts/test-build-release-app.sh
  scripts/release-exclusive-rename.c
  scripts/test-release-exclusive-rename.sh
  scripts/release-package-evidence-tools.sh
  scripts/package-release-dmg.sh
  scripts/test-package-release-dmg.sh
  scripts/no-fee-release-v1.sh
  scripts/test-no-fee-release-v1.sh
  scripts/test-release-shell-security.sh
  scripts/release-preflight.sh
  scripts/test-release-preflight.sh
  scripts/verify-release-code.sh
  scripts/test-verify-release-code.sh
)

for required_file in "${required_files[@]}"; do
  require_file "$required_file"
done

require_bash_syntax scripts/release-package-evidence-tools.sh
require_bash_syntax scripts/no-fee-release-v1.sh
require_bash_syntax scripts/test-no-fee-release-v1.sh
require_bash_syntax scripts/prepublish-check.sh
require_prepublish_stage_sequence scripts/prepublish-check.sh
require_prepublish_prelude_contract scripts/prepublish-check.sh
require_prepublish_stage_contract scripts/prepublish-check.sh

require_text Makefile 'test-release-artifact-tools-script:'
require_text Makefile 'test-build-release-app-script:'
require_text Makefile 'test-release-exclusive-rename-script:'
require_text Makefile 'check-release-package-evidence-tools-script:'
require_text Makefile 'test-package-release-dmg-script:'
require_text Makefile 'test-no-fee-release-v1-script:'
require_text Makefile 'test-release-shell-security-script:'
require_text Makefile 'test-release-preflight-script:'
require_text Makefile 'test-verify-release-code-script:'
require_text Makefile './scripts/test-release-artifact-tools.sh'
require_text Makefile './scripts/test-build-release-app.sh'
require_text Makefile './scripts/test-release-exclusive-rename.sh'
require_text Makefile '/bin/bash -p -n scripts/release-package-evidence-tools.sh'
require_text Makefile './scripts/test-package-release-dmg.sh'
require_text Makefile './scripts/test-no-fee-release-v1.sh'
require_text Makefile './scripts/test-release-shell-security.sh'
require_text scripts/prepublish-check.sh "release_make='./scripts/release-make-gate.sh'"
require_text scripts/prepublish-check.sh \
  "export PATH='/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin'"
require_text scripts/prepublish-check.sh \
  'Prepublication gate rejects exported Bash functions.'
require_text scripts/prepublish-check.sh \
  "internal_environment_flag='--lectureboard-internal-sanitized-prepublish'"
require_text scripts/prepublish-check.sh 'unexpected_environment='
require_text scripts/release-make-gate.sh 'exec /usr/bin/env -i'
require_text scripts/release-make-shell.sh 'exec /usr/bin/env -i'
require_text Makefile 'override SHELL := $(abspath .)/scripts/release-make-shell.sh'
require_text Makefile 'override .SHELLFLAGS := -c'
require_text Makefile './scripts/test-release-preflight.sh'
require_text Makefile './scripts/test-verify-release-code.sh'
require_text Makefile 'verify:'
require_text Makefile './scripts/prepublish-check.sh'
require_text scripts/prepublish-check.sh '"$release_make" test-release-artifact-tools-script'
require_text scripts/prepublish-check.sh '"$release_make" test-build-release-app-script'
require_text scripts/prepublish-check.sh '"$release_make" test-release-exclusive-rename-script'
require_text scripts/prepublish-check.sh '"$release_make" check-release-package-evidence-tools-script'
require_text scripts/prepublish-check.sh '"$release_make" test-package-release-dmg-script'
require_text scripts/prepublish-check.sh '"$release_make" test-no-fee-release-v1-script'
require_text scripts/prepublish-check.sh '"$release_make" test-release-shell-security-script'
require_text scripts/prepublish-check.sh '"$release_make" test-release-preflight-script'
require_text scripts/prepublish-check.sh '"$release_make" test-verify-release-code-script'

for privileged_release_entry in \
  scripts/build-release-app.sh \
  scripts/package-release-dmg.sh \
  scripts/no-fee-release-v1.sh \
  scripts/release-artifact-tools.sh \
  scripts/release-make-gate.sh \
  scripts/release-make-shell.sh \
  scripts/release-package-evidence-tools.sh \
  scripts/release-preflight.sh \
  scripts/verify-release-code.sh \
  scripts/check-release-definition.sh \
  scripts/prepublish-check.sh \
  scripts/publish-to-github.sh; do
  require_privileged_shebang "$privileged_release_entry"
  require_text "$privileged_release_entry" 'Release shell entry requires Bash privileged mode.'
done
require_text scripts/package-release-dmg.sh \
  'committed_evidence_tools="$approved_source_root/scripts/release-package-evidence-tools.sh"'
require_text scripts/no-fee-release-v1.sh \
  'evidence --source-dir DIR --commit OID --output-dir DIR'
require_text scripts/no-fee-release-v1.sh \
  'prepare --source-dir DIR --tag v1.0.0 --commit OID --test-result FILE --test-result-bundle DIR --gate-log FILE --output-dir DIR'
require_text scripts/no-fee-release-v1.sh \
  'compare-public --approved-dir DIR --downloaded-dir DIR --release-metadata FILE --tag-refs FILE --commit OID'
require_text scripts/no-fee-release-v1.sh \
  'verify-public --source-dir DIR --approved-dir DIR --commit OID --output-dir DIR'
require_text scripts/no-fee-release-v1.sh \
  'buildIsolation":"git-archive-approved-commit"'
require_text scripts/no-fee-release-v1.sh \
  'provided release asset set exactly matches approved local bytes'
require_text scripts/no-fee-release-v1.sh \
  "Signature=adhoc"
require_text scripts/no-fee-release-v1.sh \
  'create_isolated_commit_source "$source_dir" "$commit" "$isolated_source"'
require_text scripts/no-fee-release-v1.sh \
  '"$source_dir" "$commit" "$isolated_repository"'
require_text scripts/no-fee-release-v1.sh \
  '/usr/bin/xcrun xcresulttool get log --type action'
require_text scripts/no-fee-release-v1.sh \
  'LectureBoard native-test embedded source commit:'
require_text scripts/no-fee-release-v1.sh \
  '-c core.fsmonitor=false -c core.untrackedCache=false'
require_text scripts/no-fee-release-v1.sh \
  'blob in {"0"*40,"0"*64} or len(blob)!=len(c)'
require_text scripts/no-fee-release-v1.sh \
  '[[ -z "$(/usr/bin/find "$result_bundle" -type l -print -quit)" ]] || return 1'
require_text scripts/no-fee-release-v1.sh \
  '/usr/bin/find "$app/Contents/MacOS"'
require_text scripts/no-fee-release-v1.sh \
  '| /usr/bin/tr -d'
require_text scripts/no-fee-release-v1.sh \
  'for offset in (0,1):'
require_text scripts/no-fee-release-v1.sh \
  'toolchain_value_is_valid "$build_toolchain_before"'
require_text scripts/no-fee-release-v1.sh \
  '[[ "$build_toolchain_after" == "$build_toolchain_before" ]]'
require_text scripts/no-fee-release-v1.sh \
  '[[ "$toolchain" == "$(toolchain_identity)" ]]'
require_text scripts/no-fee-release-v1.sh \
  "ZipFile(out,'x',compression=zipfile.ZIP_DEFLATED"
require_text scripts/no-fee-release-v1.sh \
  'not decompressor.eof or decompressor.unused_data or decompressor.unconsumed_tail'
require_text scripts/no-fee-release-v1.sh \
  'approved_snapshot="$public_stage/approved"'
require_text scripts/no-fee-release-v1.sh \
  'public_acquisition="$(/usr/bin/mktemp -d \'
require_text_count scripts/no-fee-release-v1.sh \
  '  public_inputs_match_snapshot \' 3
require_text_count scripts/no-fee-release-v1.sh \
  '  compare_public_release "$approved_snapshot" "$downloaded" "$metadata" "$refs" "$commit"' 3
require_text_count scripts/no-fee-release-v1.sh \
  '    "$parent_device" "$parent_inode" "$stage_device" "$stage_inode" \' 3
require_text scripts/no-fee-release-v1.sh \
  '"$commit:scripts/release-exclusive-rename.c" >"$helper_source"'
require_text scripts/no-fee-release-v1.sh \
  'https://api.github.com/repos/akiyama709/lectureboard-ai/releases/tags/v1.0.0'
require_text scripts/no-fee-release-v1.sh \
  'https://github.com/akiyama709/lectureboard-ai/releases/download/v1.0.0/$name'
require_text scripts/no-fee-release-v1.sh \
  'release.get("name")!="LectureBoard AI v1.0.0"'
require_text scripts/no-fee-release-v1.sh \
  'release.get("prerelease") is not False or release.get("immutable") is not True'
require_text scripts/release-exclusive-rename.c 'if (argc != 7'
require_text scripts/release-exclusive-rename.c \
  '(uintmax_t)parent_status.st_ino != expected_parent_inode'
require_text scripts/release-exclusive-rename.c \
  '(uintmax_t)source_status.st_ino != expected_source_inode'
require_text scripts/build-release-app.sh \
  '"${output_parent_identity% *}" "${output_parent_identity#* }" \'
require_text scripts/build-release-app.sh \
  '"${output_stage_identity% *}" "${output_stage_identity#* }"'
require_text scripts/package-release-dmg.sh \
  '"${output_parent_identity% *}" "${output_parent_identity#* }" \'
require_text scripts/package-release-dmg.sh \
  '"${output_stage_identity% *}" "${output_stage_identity#* }" \'

require_text .github/workflows/ci.yml 'runs-on: macos-26'
require_text .github/workflows/ci.yml 'sudo xcode-select --switch /Applications/Xcode_26.6.app/Contents/Developer'
require_text .github/workflows/ci.yml 'run: brew install xcodegen'
require_text .github/workflows/ci.yml 'run: ./scripts/prepublish-check.sh'
require_text .github/workflows/ci.yml 'uses: actions/upload-artifact@v7'
require_text .github/workflows/ci.yml 'git diff --exit-code -- LectureBoardAI.xcodeproj'
reject_text .github/workflows/ci.yml 'runs-on: macos-15'

require_text project.yml 'INFOPLIST_FILE: LectureBoardAI/Config/Info.plist'
require_text LectureBoardAI/Config/Info.plist '<key>NSAppleEventsUsageDescription</key>'
require_text LectureBoardAI/Config/Info.plist '<key>LectureBoardReleaseCommit</key>'
require_text LectureBoardAI/Config/Info.plist '<key>LectureBoardReleaseTagObject</key>'
require_text project.yml 'CODE_SIGN_ENTITLEMENTS: LectureBoardAI/Config/LectureBoardAI.entitlements'
require_text LectureBoardAI/Config/LectureBoardAI.entitlements 'com.apple.security.automation.apple-events'
require_text LectureBoardAI/Config/LectureBoardAI.entitlements 'com.apple.security.device.audio-input'
reject_text LectureBoardAI/Config/LectureBoardAI.entitlements 'com.apple.security.get-task-allow'
require_text scripts/release-preflight.sh "expected_tag='v1.0.0'"
require_text scripts/release-preflight.sh 'exactly one Developer ID Application identity is required'
require_text scripts/release-preflight.sh 'the worktree contains tracked or untracked changes'
require_text scripts/release-preflight.sh 'no fetch or remote freshness proof occurred'
require_text scripts/verify-release-code.sh 'ad hoc signatures are not release signatures'
require_text scripts/verify-release-code.sh 'the hardened-runtime code-directory flag is required'
require_text scripts/verify-release-code.sh 'the embedded entitlements differ from the exact two-key allowlist'

require_text ROADMAP.md 'Project completion means publishing a public, immutable, non-prerelease `v1.0.0` GitHub Release'
require_text ROADMAP.md 'No alpha, beta, or release-candidate GitHub Release will be published'
require_text ROADMAP.md '## Milestone 4 — Supported-workflow acceptance'
require_text ROADMAP.md '## Milestone 5 — Representative-use validation'
require_text ROADMAP.md '## Milestone 6 — Exact v1.0.0 publication candidate'
require_text ROADMAP.md 'Apply the hardened runtime and an ad hoc signature without expanding the entitlement allowlist'
require_text ROADMAP.md '## Milestone 7 — Public v1.0.0 GitHub Release'
require_text ROADMAP.md 'checksum manifest, content-free test evidence, SBOM, and provenance'
require_text ROADMAP.md 'Run the unauthenticated `verify-public` transaction to retain public REST metadata and annotated-tag refs'
require_text README.md 'Completion means publication of the public, immutable, non-prerelease `v1.0.0` GitHub Release'
require_text README.md 'checksums, content-free test evidence, SBOM, provenance'
require_text README.md '正確な5件だけを添付した'
require_text README.md 'No alpha, beta, or release-candidate application Release will be published'
require_text README.md '[English user guide](docs/user-guide.md)'
require_text README.md '[公開前ユーザー受入](docs/user-acceptance-ja.md)'
require_text README.md 'Status: **pre-release development**'
require_text README.md 'The current source implements a managed, windowed PowerPoint workflow'
require_text README.md 'They have not yet completed the release-artifact live workflow'
require_text README.md 'Earlier schema-11 diagnostics are preserved as build-specific historical evidence and must not be generalized to this source'
require_text README.md 'A shared bounded one-shot fresh-sample path for either an exact post-baseline coarse candidate or a pending dense candidate'
require_text README.md 'negative, malformed, unknown, missing, or inconsistent schema-11 evidence fails decoding'
require_text AGENTS.md 'DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult'
require_text AGENTS.md 'The paired operator-captured helper sidecar'
require_text ROADMAP.md 'DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult'
require_text ROADMAP.md 'supports input-window attribution for those events under the controlled eight-second schedule'
require_text README.md 'this implementation has deterministic tests but no successful live managed-session evidence yet'
require_text README.md 'a live release-artifact export remains unverified'
require_text README.md 'sidecarはruntime reportへ暗号的に結合されておらず，release-grade provenanceではありません'
require_text README.md 'c7a73f7cb1bdcaa46ec216218883872d480630f7cf4ff177170f8d1906c14a3c'
require_text README.md '70e5772d5d4e8ab8947c725b854749fe2743b38f9189434530de2f0ad9aa63a1'
require_text README.md '`boundedFreshSample` was not exercised'
require_text README.md 'two aggregate visual revision events in separate ink and erase phases'
require_text README.md 'Successful live `boundedFreshSample` confirmation through the shared exact-post-baseline-coarse or pending-dense one-shot path'
require_text README.md '現段階は公開前の開発中です'
require_text README.md '現行release artifactによるmanaged PowerPoint遷移，microphone，canvas精度，可視alignment，板書の有用性及びexportの一連の実機動作はまだ未検証です'
require_text README.md 'managed production identity providerは実装済みであり，合成資料の固定診断Appではexact結合と2回の意味的切替を確認しましたが，production配布App及び本人資料は未検証です．'
require_text README.md '現行continuous経路では別個の消去phase revisionを確認しましたが'
require_text docs/architecture.md 'The earlier schema-9 live erase candidates did not receive the third qualifying observation'
require_text docs/architecture.md 'DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult'
require_text docs/architecture.md 'The paired operator-captured helper sidecar'
require_text docs/build-verification.md 'At that schema-10 checkpoint, this automated evidence had not established'
require_text docs/build-verification.md 'DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult'
require_text docs/build-verification.md 'ADR 0013 now supersedes its Developer ID and Apple-notarization requirements'
require_text docs/development-plan.md 'image differences and content revisions are not semantic slide identity'
require_text docs/development-plan.md 'a live current-build event sourced from `boundedFreshSample` has not yet been observed'
require_text docs/README.md 'ADR 0011 — Bound one-shot samples to the current visual-change candidate'
require_text docs/README.md 'ADR 0012 — Managed slide-show candidate and role challenge'
require_text docs/README.md 'Versioning'
require_text docs/README.md 'No-fee v1 distribution process'
require_text docs/release-process.md 'On the development Mac audited on 2026-09-02, no valid code-signing identity was available'
require_text docs/release-process.md 'Only after the final DMG staple, compute the release checksum'
require_text docs/release-process.md 'explicit publication approval naming the exact commit and final DMG SHA-256'
require_text docs/versioning.md 'This consistency check validates version and date metadata only'
require_text docs/technical-design-ja.md '現行ソースはschema 11のdecoder-hardenedな公開前開発sourceである'
require_text docs/technical-design-ja.md '153件のCoreテスト（15 suites），259件のnative appテスト（30 suites）'
require_text docs/technical-design-ja.md 'live `boundedFreshSample`を裏付けるものではない'
require_text docs/technical-design-ja.md 'DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult'
require_text docs/technical-design-detailed-ja.md '同一のpost-baseline coarse視覚差分候補又はdense内容更新候補がpendingである間だけ'
require_text docs/technical-design-detailed-ja.md '`boundedFreshSample`は発生しなかった'
require_text CHANGELOG.md 'Deterministic stable-frame and significant visual/content-change classification with unit tests'
require_text CHANGELOG.md 'Build-specific historical synthetic PowerPoint evidence for static frame delivery, Vision execution, and pre-semantic dynamic calibration; not evidence for the current semantic build'
require_text CHANGELOG.md 'Live validation of the implemented exact-window-bound managed PowerPoint slide-identity provider before actual slide transitions are claimed'
require_text CHANGELOG.md 'A privacy-bounded JSON and SVG session exporter containing only confirmed or pinned public board scenes'
require_text CHANGELOG.md 'An authoritative no-fee `v1.0.0` evidence, build, packaging, and public-verification path'
require_text CHANGELOG.md 'Metadata-only schema-11 latest-content-revision evidence with exact ordinal'
require_text CHANGELOG.md 'fail-closed decoding for negative counts'
require_text CHANGELOG.md 'A shared bounded one-shot fresh-sample path for either an exact post-baseline coarse candidate or a pending dense candidate'
require_text CHANGELOG.md 'The 2026-09-01 decoder-hardened checkpoint on the development Mac: 153 Core tests in 15 suites, 259 native app tests in 30 suites'
require_text CHANGELOG.md 'The byte-identical 2026-09-01 checkpoint runtime preserved as `LectureBoard AI Schema 11 Decoder Hardened Verification.app`'
require_text CHANGELOG.md 'c7a73f7cb1bdcaa46ec216218883872d480630f7cf4ff177170f8d1906c14a3c'
require_text CHANGELOG.md '70e5772d5d4e8ab8947c725b854749fe2743b38f9189434530de2f0ad9aa63a1'
require_text CHANGELOG.md 'that schema-8 attempt did not verify dynamic slides or mouse ink'
require_text CHANGELOG.md 'including a controlled post-erase candidate confirmed by that source'
require_text CHANGELOG.md 'is not cryptographically bound to the runtime report and is not release-grade provenance'
require_text docs/roadmap-ja.md '## M7：GitHub正式版v1.0.0'
require_text docs/roadmap-ja.md '## M4：対応範囲の実機受入'
require_text docs/roadmap-ja.md '## M5：代表条件の検証'
require_text docs/roadmap-ja.md '## M6：正確なv1.0.0公開候補'
require_text docs/local-codex-handoff-ja.md '公開`v1.0.0` GitHub Releaseの成立を指す'
require_text docs/local-codex-handoff-ja.md 'DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult'
require_text docs/local-codex-handoff-ja.md 'sidecarはruntime reportへ暗号的に結合されておらず，release-grade provenanceではない'
require_text docs/v1-release-checklist.md '## Definition of completion'
require_text docs/v1-release-checklist.md 'No alpha, beta, or release-candidate GitHub Release will be published'
require_text docs/v1-release-checklist.md 'The application uses the hardened runtime and an ad hoc signature with no team identity or secure timestamp'
require_text docs/v1-release-checklist.md '## 5. Post-publication verification — completion gate'
require_text docs/v1-release-checklist.md 'All five attached assets are downloaded from the public GitHub Release into a clean verification environment'
require_text docs/v1-release-checklist.md 'Bundle identity, ad hoc signature, hardened runtime, architecture, version, entitlement allowlist, SBOM, and provenance are independently rechecked'
require_text docs/v1-release-checklist.md "Apple's per-application Open Anyway exception"
require_text docs/v1-release-checklist.md 'identifies the exact release commit and final application-archive SHA-256'
require_text docs/v1-release-checklist.md 'the project owner personally completes `user-acceptance-ja.md` against this exact candidate'
require_text docs/v1-release-checklist.md 'omits unneeded AppleDouble/resource-fork/extended-attribute entries'
require_text docs/v1-release-checklist.md 'the content-free test-evidence JSON'
require_text docs/v1-release-checklist.md '## 6. Withdrawal and rollback triggers'
require_text docs/v1-release-checklist.md 'Do not rerun the initial publication script'
require_text docs/adr/0006-mit-license.md 'Accepted for the initial public source repository; review remains required for materially changed v1.0.0 scope'
require_text docs/adr/0006-mit-license.md 'recorded the applicable institutional intellectual-property and software-publication checks as complete before the source repository was made public'
require_text docs/adr/0006-mit-license.md 'The completed initial-publication review does not authorize or verify every later artifact or supported use'
require_text docs/adr/0007-public-v1-completion.md 'Project completion means publication of the public `v1.0.0` GitHub Release'
require_text docs/adr/0011-bound-dense-change-fresh-samples.md 'The paired operator-captured helper sidecar'
require_text docs/adr/0011-bound-dense-change-fresh-samples.md 'is not cryptographically bound to the runtime report and is not release-grade provenance'
require_text docs/adr/0012-causal-managed-slideshow-binding.md 'window-birth correlation is only a **candidate**'
require_text docs/adr/0012-causal-managed-slideshow-binding.md 'The current unavailable provider remains the application default'
require_text docs/adr/0012-causal-managed-slideshow-binding.md 'test verifies live Automation consent, PowerPoint command execution, the returned object specifier'
require_text docs/adr/0012-causal-managed-slideshow-binding.md 'cannot detect a same-ID, same-PID, same-bundle lifecycle replacement'
require_text docs/adr/0013-no-fee-public-v1-distribution.md 'Publish the final v1 release without paid Apple distribution services'
require_text docs/adr/0013-no-fee-public-v1-distribution.md 'ad hoc code signature'
require_text docs/adr/0013-no-fee-public-v1-distribution.md 'public, immutable, non-prerelease `v1.0.0` GitHub Release'
require_text docs/adr/0013-no-fee-public-v1-distribution.md '- `LectureBoard-AI-v1.0.0-arm64.zip`;'
require_text docs/adr/0013-no-fee-public-v1-distribution.md '- `LectureBoard-AI-v1.0.0-test-results.json`;'
require_text docs/adr/0013-no-fee-public-v1-distribution.md '- `SBOM.spdx.json`;'
require_text docs/adr/0013-no-fee-public-v1-distribution.md '- `SHA256SUMS`; and'
require_text docs/adr/0013-no-fee-public-v1-distribution.md '- `provenance.json`.'
require_text AGENTS.md 'Project completion means a public, immutable, non-prerelease `v1.0.0` GitHub Release with exactly five attached assets'
require_text docs/no-fee-release-process.md 'This is the authoritative distribution path for the public `v1.0.0` release'
require_text docs/no-fee-release-process.md 'Never disable Gatekeeper globally or remove quarantine'
require_text docs/no-fee-release-process.md 'after both macOS `ditto` and `/usr/bin/unzip` extraction.'
require_text docs/no-fee-release-process.md 'The attached asset set contains exactly five regular files'
require_text docs/no-fee-release-process.md '- `LectureBoard-AI-v1.0.0-arm64.zip`;'
require_text docs/no-fee-release-process.md '- `LectureBoard-AI-v1.0.0-test-results.json`;'
require_text docs/no-fee-release-process.md '- `SBOM.spdx.json`;'
require_text docs/no-fee-release-process.md '- `SHA256SUMS`; and'
require_text docs/no-fee-release-process.md '- `provenance.json`.'
require_text docs/no-fee-release-process.md 'Retain the frozen `.xcresult` and'
require_text docs/no-fee-release-process.md '`prepublication-gate.log` as private evidence; neither is a GitHub Release asset.'
require_text docs/no-fee-release-process.md './scripts/no-fee-release-v1.sh evidence \'
require_text docs/no-fee-release-process.md './scripts/no-fee-release-v1.sh prepare \'
require_text docs/no-fee-release-process.md './scripts/no-fee-release-v1.sh verify-public \'
require_text docs/no-fee-release-process.md 'publish only those five attachments in an immutable,'
require_text docs/no-fee-release-process.md '`compare-public` command is available only when the five public assets and both public metadata'
require_text docs/user-acceptance-ja.md '現在の状態は**未実施**である'
require_text docs/user-acceptance-ja.md '元のPPTXを上書きしない'
require_text docs/user-acceptance-ja.md '画面収録が許可済みなら，「画面収録を許可」を再度押さない'
require_text docs/user-acceptance-ja.md '元PPTX及び受入用複製物のbyte sizeとSHA-256が実施前後で一致する'
require_text docs/user-acceptance-ja.md 'この受入は，公開の承認とは別である'
require_text docs/user-acceptance-ja.md '少なくとも1件の自動板書がPowerPoint上に実際に見えることを目視確認する'
require_text docs/user-acceptance-ja.md '診断値にかかわらず不合格とする'
require_ordered_text docs/user-acceptance-ja.md \
  '9. 文字起こしを停止し，final transcriptが確定した後に，文字起こしが停止済みであることを確認する．' \
  '10. Appの取得を停止し，managed slide showが片付けられ，PowerPoint editing windowへ安全に戻ったことを確認する．' \
  '11. 取得状態が停止済みであることを確認してから，lecture sessionをJSON及びSVGへexportし，slide画像，OCR全文，音声，文字起こし，window title又は非公開intentが含まれないことを確認する．'
require_text docs/user-guide.md 'Status: procedural draft'
require_text docs/user-guide.md 'Never disable Gatekeeper globally and never remove quarantine metadata'
require_text docs/user-guide.md 'fails closed instead of using a network fallback'
require_text docs/user-guide.md 'Accessibility** and **Full Disk Access:** not required'
require_text docs/user-guide.md 'shasum -a 256 -c SHA256SUMS'
require_text docs/user-guide.md 'cd -- "/absolute/path/to/downloaded-release-assets"'
require_text docs/user-guide-ja.md '状態：手順案'
require_text docs/user-guide-ja.md 'Gatekeeper全体を無効化せず，Terminalでquarantine metadataを除去しない'
require_text docs/user-guide-ja.md 'network fallbackを使わず停止する'
require_text docs/user-guide-ja.md 'アクセシビリティ及びフルディスクアクセス'
require_text docs/user-guide-ja.md 'shasum -a 256 -c SHA256SUMS'
require_text docs/user-guide-ja.md 'cd -- "/absolute/path/to/downloaded-release-assets"'
require_text docs/privacy-and-security.md 'transcription fails closed instead of permitting a network fallback'
require_text docs/privacy-and-security.md 'requiresOnDeviceRecognition'
require_text docs/privacy-security-ja.md 'network fallbackを許さず文字起こしを開始しない'
require_text docs/privacy-security-ja.md '`supportsOnDeviceRecognition`もtrueでなければならない'
reject_text CHANGELOG.md 'Deterministic stable-frame and slide-change detection with unit tests'
reject_text CHANGELOG.md 'Controlled synthetic PowerPoint runtime evidence for current static frame delivery and Vision execution'
reject_text CHANGELOG.md 'PowerPoint slide identity is complete'
reject_text README.md 'The current schema-10 source passes 142 Core tests in 15 suites, 251 native app tests in 30 suites'
reject_text README.md '現行schema 10 sourceは，開発用Mac上でCore 142件・15 suite，native App 251件・30 suite'
reject_text CHANGELOG.md 'A bounded one-shot fresh-sample path for a pending dense content-change candidate'
reject_text CHANGELOG.md 'Live PowerPoint validation of the bounded dense-change fresh-sample path'
reject_text README.md 'Automated schema-11 tests pass, but no current decoder-hardened live report has been recorded'
reject_text README.md 'decoder hardening後の現行sourceによるlive reportは未検証です'
reject_text README.md 'no capture or input occurred and no static report exists'
reject_text README.md 'capture，入力及びstatic reportはありません'
reject_text README.md 'live current-source `SCScreenshotManager` attachments, timing, coarse confirmation, and post-erase behavior remain unverified'
reject_text docs/user-guide.md 'LectureBoard-AI-1.0.0-macos-arm64.zip'
reject_text docs/user-guide-ja.md 'LectureBoard-AI-1.0.0-macos-arm64.zip'
reject_text README.md '実PowerPoint上のcoarse fresh確定及び別個のpost-erase revisionは未検証です'
reject_text README.md '取得timing及び消去後revisionは未検証です'
reject_text README.md 'a separately attributed post-erase content revision'
reject_text README.md 'including whether it records a distinct post-erase revision'
reject_text README.md 'six strictly input-bounded revision intervals'
reject_text README.md 'This verifies strict per-input visual-revision interval attribution'
reject_text README.md 'dynamic runは6件の入力境界内revision intervalを記録し'
reject_text AGENTS.md 'validate exactly six controlled inputs spaced eight seconds apart against exactly six non-reused interval-contained revision events'
reject_text AGENTS.md 'one strictly interval-bounded six-input run'
reject_text ROADMAP.md 'strictly matched exactly six inputs spaced eight seconds apart'
reject_text docs/architecture.md 'It strictly matched exactly six inputs spaced eight seconds apart'
reject_text docs/adr/0011-bound-dense-change-fresh-samples.md 'Exactly six inputs spaced eight seconds apart mapped to six non-reused events within their strict input intervals'
reject_text docs/local-codex-handoff-ja.md '各input completion後から次input開始前，又は最終cutoff前へ厳密に対応付け'
reject_text docs/local-codex-handoff-ja.md '8秒間隔6入力のstrict dynamic interval及びsingle-stroke／eraseを完了した'
reject_text README.md 'DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_22-41-57-+0900.xcresult'
reject_text docs/architecture.md 'The live erase candidate did not receive the third qualifying observation'
reject_text docs/build-verification.md 'This automated evidence does not establish that live PowerPoint supplies'
reject_text docs/development-plan.md 'Stable-frame and slide-change detection'
reject_text docs/README.md 'ADR 0011 — Bounded dense-change fresh samples'
reject_text docs/technical-design-ja.md '本準備環境で8件の自動テストが通過した'
reject_text docs/technical-design-ja.md 'スライド切替と安定フレームの検出'
reject_text docs/technical-design-detailed-ja.md '同一のdense内容更新候補がpendingである間だけ'
reject_text CHANGELOG.md 'dynamic slides and mouse ink remain unverified'
reject_text CHANGELOG.md 'including a separately identified post-erase rerun'

printf 'Release definition and v1.0.0 gates are consistent.\n'
