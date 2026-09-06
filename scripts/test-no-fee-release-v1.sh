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
require_text 'create_portable_zip "$app" "$archive"'
require_text "ZipFile(out,'x',compression=zipfile.ZIP_DEFLATED"
require_text "archive.comment=b''"
require_text 'if eocd[0]!=0x06054B50'
require_text 'not decompressor.eof or decompressor.unused_data or decompressor.unconsumed_tail'
require_text '/usr/bin/unzip -qq "$archive" -d "$unzip_root"'
require_text "any(not part or part.startswith('._') for part in parts)"
reject_text '/usr/bin/ditto -c -k --keepParent --norsrc --noqtn'
reject_text '/usr/bin/ditto -c -k --keepParent --rsrc --extattr --acl "$app" "$archive"'
require_text 'release_test_evidence_is_valid "$test_result" "$commit"'
require_text '/bin/cp -X "$test_result" "$release_test_result"'
require_text '"testResult":{"name":"%s","sha256":"%s"}'
reject_text '"testResultSha256":"%s"'
require_text 'checksum file must contain the exact four release payload records'
require_text 'release_test_evidence_matches_result_bundle "$test_result" "$test_result_bundle" "$temp/source"'
require_text 'generate_release_evidence'
require_text 'release_gate_log_matches "$test_result" "$gate_log"'
require_text 'production commands reject exported Bash functions'
require_text '/usr/bin/xcrun xcresulttool get test-results summary'
require_text '/usr/bin/xcrun xcresulttool get log --type action'
require_text 'create_isolated_commit_source "$source_dir" "$commit" "$isolated_source"'
require_text '"$source_dir" "$commit" "$isolated_repository"'
require_text 'release-exclusive-rename.c'
require_text 'verify-public --source-dir DIR --approved-dir DIR --commit OID --output-dir DIR'
require_text 'git_read -C "$source_dir" show'
require_text '"$commit:scripts/release-exclusive-rename.c" >"$helper_source"'
require_text 'approved_snapshot="$public_stage/approved"'
require_text 'compare_public_release "$approved_snapshot" "$downloaded" "$metadata" "$refs" "$commit"'
require_text 'public_acquisition="$(/usr/bin/mktemp -d'
require_text 'public_inputs_match_snapshot \'
require_text "die 'public inputs changed after archive verification'"
reject_text "'public release asset set exactly matches approved local bytes'"
require_text 'compare_public_release "$approved_dir" "$downloaded_dir" "$release_metadata" "$tag_refs" "$commit"'
require_text 'TAR_OPTIONS ZIPOPT UNZIP UNZIPOPT'
require_text 'PYTHONPATH PYTHONHOME PYTHONSTARTUP PYTHONUSERBASE'
require_text '-c core.fsmonitor=false -c core.untrackedCache=false'
require_text '/usr/bin/find "$app/Contents/MacOS"'
require_text '| /usr/bin/tr -d'
reject_text '$(find "$app/Contents/MacOS"'
reject_text '| tr -d'
require_text 'toolchain_value_is_valid "$build_toolchain_before"'
require_text '[[ "$build_toolchain_after" == "$build_toolchain_before" ]]'
require_text 'write_build_receipt "$output_dir/approved-build-receipt.json"'
require_text '"$output_dir/$product.app" "$build_toolchain_before"'
require_text '[[ "$toolchain" == "$(toolchain_identity)" ]]'
require_text 'application_content_has_no_private_paths "$app"'
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

toolchain_validation_function="$root/toolchain-validation-function.sh"
sed -n '/^toolchain_value_is_valid() {$/,/^}$/p' "$tool" \
  >"$toolchain_validation_function"
source "$toolchain_validation_function"

toolchain_value_is_valid 'Xcode 26.6; Build version 17F113' \
  || { /usr/bin/printf '%s\n' 'A valid Xcode toolchain identity was rejected.' >&2; exit 1; }
for malformed_toolchain in \
  '' \
  'Xcode 26; Build version 17F113' \
  'Xcode 26.6' \
  '/Applications/Xcode.app' \
  $'Xcode 26.6; Build version 17F113\nXcode 99.9; Build version forged'; do
  if toolchain_value_is_valid "$malformed_toolchain"; then
    /usr/bin/printf '%s\n' \
      "A malformed Xcode toolchain identity was accepted: $malformed_toolchain" >&2
    exit 1
  fi
done

portable_archive_functions="$root/portable-archive-functions.sh"
{
  sed -n '/^create_portable_zip() {$/,/^}$/p' "$tool"
  sed -n '/^archive_central_directory_is_safe_and_portable() {$/,/^}$/p' "$tool"
  sed -n '/^release_test_evidence_is_valid() {$/,/^}$/p' "$tool"
  sed -n '/^native_result_summary_is_valid() {$/,/^}$/p' "$tool"
  sed -n '/^release_gate_log_matches() {$/,/^}$/p' "$tool"
  sed -n '/^release_gate_script_matches_commit() {$/,/^}$/p' "$tool"
  sed -n '/^result_bundle_tree_digest() {$/,/^}$/p' "$tool"
  sed -n '/^release_test_evidence_tree_digest_matches() {$/,/^}$/p' "$tool"
  sed -n '/^release_sbom_is_valid() {$/,/^}$/p' "$tool"
  sed -n '/^release_provenance_is_valid() {$/,/^}$/p' "$tool"
  sed -n '/^release_directory_has_exact_assets() {$/,/^}$/p' "$tool"
  sed -n '/^public_inputs_match_snapshot() {$/,/^}$/p' "$tool"
  sed -n '/^application_content_has_no_private_paths() {$/,/^}$/p' "$tool"
  sed -n '/^signed_component_has_no_entitlements() {$/,/^}$/p' "$tool"
  sed -n '/^create_isolated_commit_source() {$/,/^}$/p' "$tool"
  sed -n '/^commit_contains_git_attributes() {$/,/^}$/p' "$tool"
  sed -n '/^oid() {$/,/^}$/p' "$tool"
} >"$portable_archive_functions"
die() { /usr/bin/printf '%s\n' "$1" >&2; return 1; }
regular() { [[ "$1" == /* && -f "$1" && ! -L "$1" ]] || die "$2"; }
bounded_regular() {
  local path="$1" label="$2" maximum="$3" size
  regular "$path" "$label" || return 1
  size="$(/usr/bin/stat -f '%z' "$path")" || return 1
  [[ "$size" =~ ^[0-9]+$ ]] && (( size <= maximum ))
}
sha256() { /usr/bin/shasum -a 256 -- "$1" | /usr/bin/awk '{print $1}'; }
git_env=(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_NO_REPLACE_OBJECTS=1 GIT_ATTR_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0)
git_read() {
  "${git_env[@]}" /usr/bin/git --no-replace-objects \
    -c core.hooksPath=/dev/null -c core.attributesFile=/dev/null \
    -c core.fsmonitor=false -c core.untrackedCache=false "$@"
}
source "$portable_archive_functions"

commit=0123456789012345678901234567890123456789
oid "$commit" commit-fixture
if oid 0000000000000000000000000000000000000000 null-commit-fixture; then
  /usr/bin/printf '%s\n' 'Git null object identifier was accepted.' >&2
  exit 1
fi

isolation_repository="$root/isolation-repository"
isolated_checkout="$root/isolated-checkout"
/bin/mkdir "$isolation_repository"
git_read -C "$isolation_repository" init -q
/bin/mkdir "$isolation_repository/scripts"
/usr/bin/printf '%s\n' 'committed bytes' >"$isolation_repository/tracked.txt"
/usr/bin/printf '%s\n' '#!/bin/bash' 'exit 0' \
  >"$isolation_repository/scripts/prepublish-check.sh"
git_read -C "$isolation_repository" add -- tracked.txt scripts/prepublish-check.sh
git_read -C "$isolation_repository" -c user.name=Fixture -c user.email=fixture@example.invalid \
  commit -q -m fixture
isolation_commit="$(git_read -C "$isolation_repository" rev-parse HEAD)"
fsmonitor_marker="$root/fsmonitor-executed"
fsmonitor_script="$root/fsmonitor.sh"
/usr/bin/printf '%s\n' '#!/bin/bash' \
  "/usr/bin/touch '$fsmonitor_marker'" 'exit 0' >"$fsmonitor_script"
/bin/chmod 700 "$fsmonitor_script"
/usr/bin/git -C "$isolation_repository" config core.fsmonitor "$fsmonitor_script"
git_read -C "$isolation_repository" status --porcelain=v1 >/dev/null
[[ ! -e "$fsmonitor_marker" ]] \
  || { /usr/bin/printf '%s\n' 'Repository-local Git fsmonitor code executed.' >&2; exit 1; }
git_read -C "$isolation_repository" update-index --skip-worktree tracked.txt
/usr/bin/printf '%s\n' 'hidden working-tree bytes' >"$isolation_repository/tracked.txt"
[[ -z "$(git_read -C "$isolation_repository" status --porcelain=v1)" ]] \
  || { /usr/bin/printf '%s\n' 'Skip-worktree fixture was not status-clean.' >&2; exit 1; }
create_isolated_commit_source \
  "$isolation_repository" "$isolation_commit" "$isolated_checkout"
/usr/bin/grep -Fxq 'committed bytes' "$isolated_checkout/tracked.txt" \
  || { /usr/bin/printf '%s\n' 'Isolated evidence clone used hidden working-tree bytes.' >&2; exit 1; }
gate_script_blob="$(git_read -C "$isolation_repository" rev-parse \
  "$isolation_commit:scripts/prepublish-check.sh")"
/usr/bin/printf '{"prepublicationGate":{"scriptBlobOid":"%s"}}\n' \
  "$gate_script_blob" >"$root/gate-script-evidence.json"
release_gate_script_matches_commit \
  "$root/gate-script-evidence.json" "$isolation_repository" "$isolation_commit" \
  || { /usr/bin/printf '%s\n' 'Matching gate-script blob was rejected.' >&2; exit 1; }
/usr/bin/sed "s/$gate_script_blob/2222222222222222222222222222222222222222/" \
  "$root/gate-script-evidence.json" >"$root/wrong-gate-script-evidence.json"
if release_gate_script_matches_commit \
  "$root/wrong-gate-script-evidence.json" "$isolation_repository" "$isolation_commit"; then
  /usr/bin/printf '%s\n' 'Evidence naming another gate-script blob was accepted.' >&2
  exit 1
fi
if commit_contains_git_attributes "$isolation_repository" "$isolation_commit"; then
  /usr/bin/printf '%s\n' 'A commit without Git attributes was misclassified.' >&2
  exit 1
fi
/bin/mkdir "$isolation_repository/nested"
/usr/bin/printf '%s\n' '*.txt ident' \
  >"$isolation_repository/nested/.gitattributes"
git_read -C "$isolation_repository" add -- nested/.gitattributes
git_read -C "$isolation_repository" -c user.name=Fixture -c user.email=fixture@example.invalid \
  commit -q -m nested-attributes
attributes_commit="$(git_read -C "$isolation_repository" rev-parse HEAD)"
commit_contains_git_attributes "$isolation_repository" "$attributes_commit" \
  || { /usr/bin/printf '%s\n' 'Nested tracked Git attributes were not detected.' >&2; exit 1; }
if create_isolated_commit_source \
  "$isolation_repository" "$attributes_commit" "$root/attributes-checkout"; then
  /usr/bin/printf '%s\n' 'Evidence checkout accepted nested tracked Git attributes.' >&2
  exit 1
fi

release_test_evidence_name='LectureBoard-AI-v1.0.0-test-results.json'
release_asset_name_list=$'LectureBoard-AI-v1.0.0-arm64.zip\nLectureBoard-AI-v1.0.0-test-results.json\nSBOM.spdx.json\nSHA256SUMS\nprovenance.json'
source_root="$(cd -- "$(dirname -- "$tool")/.." && /bin/pwd -P)"
result_bundle="$root/Test-LectureBoardAI-2026.09.06_09-11-21-+0900.xcresult"
/bin/mkdir -p "$result_bundle/Data"
/usr/bin/printf '%s\n' 'authoritative result fixture' >"$result_bundle/Data/payload"
result_bundle_digest="$(result_bundle_tree_digest "$result_bundle" "$source_root")"
gate_log="$root/prepublication-gate.log"
/usr/bin/printf 'LectureBoard evidence transaction source commit: %s\n' \
  "$commit" >"$gate_log"
for stage_number in $(/usr/bin/seq 1 26); do
  /usr/bin/printf '[%s/26] fixture stage\n' "$stage_number" >>"$gate_log"
  if [[ "$stage_number" == 2 ]]; then
    /usr/bin/printf '%s\n' \
      '✔ Test run with 204 tests in 18 suites passed after 0.001 seconds.' >>"$gate_log"
  fi
done
/usr/bin/printf '%s\n' \
  'Prepublication checks passed. Manual institutional IP and privacy review is still required.' \
  >>"$gate_log"
/usr/bin/printf 'LectureBoard evidence transaction completed for source commit: %s\n' \
  "$commit" >>"$gate_log"
gate_log_digest="$(sha256 "$gate_log")"
valid_test_evidence="$root/$release_test_evidence_name"
/usr/bin/printf '%s\n' \
  "{\"schema\":\"lectureboard.release-test-evidence.v1\",\"sourceCommit\":\"$commit\",\"generatedAt\":\"2026-09-06T00:00:00Z\",\"prepublicationGate\":{\"command\":\"./scripts/prepublish-check.sh\",\"result\":\"Passed\",\"passedStages\":26,\"totalStages\":26,\"logSha256\":\"$gate_log_digest\",\"scriptBlobOid\":\"dddddddddddddddddddddddddddddddddddddddd\"},\"coreTests\":{\"result\":\"Passed\",\"tests\":204,\"suites\":18,\"failed\":0,\"skipped\":0},\"nativeAppTests\":{\"result\":\"Passed\",\"authoritativeTests\":417,\"deviceRuns\":479,\"parameterizedTests\":14,\"parameterizedRuns\":76,\"failed\":0,\"skipped\":0,\"expectedFailures\":0,\"resultBundleName\":\"${result_bundle##*/}\",\"resultBundleTreeSha256\":\"$result_bundle_digest\"},\"environment\":{\"architecture\":\"arm64\",\"macOS\":\"26.6.2\",\"macOSBuild\":\"25G83\",\"xcode\":\"26.6\",\"xcodeBuild\":\"17F113\"},\"claimBoundary\":\"Automated source-candidate evidence only; no live PowerPoint, user acceptance, installation, publication, or public-redownload result is implied.\"}" \
  >"$valid_test_evidence"
release_test_evidence_is_valid "$valid_test_evidence" "$commit" \
  || { /usr/bin/printf '%s\n' 'Valid release test evidence was rejected.' >&2; exit 1; }
for malformed_blob in \
  0000000000000000000000000000000000000000 \
  0000000000000000000000000000000000000000000000000000000000000000 \
  eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee; do
  malformed_root="$root/blob-$malformed_blob"
  /bin/mkdir "$malformed_root"
  /usr/bin/sed \
    "s/dddddddddddddddddddddddddddddddddddddddd/$malformed_blob/" \
    "$valid_test_evidence" >"$malformed_root/$release_test_evidence_name"
  if release_test_evidence_is_valid \
    "$malformed_root/$release_test_evidence_name" "$commit"; then
    /usr/bin/printf '%s\n' \
      "A null or object-format-mismatched gate-script blob was accepted: $malformed_blob" >&2
    exit 1
  fi
done
release_gate_log_matches "$valid_test_evidence" "$gate_log" \
  || { /usr/bin/printf '%s\n' 'Matching prepublication gate log was rejected.' >&2; exit 1; }
/usr/sbin/mkfile -n 16777217 "$root/oversized-gate.log"
if release_gate_log_matches "$valid_test_evidence" "$root/oversized-gate.log"; then
  /usr/bin/printf '%s\n' 'An oversized gate log was accepted.' >&2
  exit 1
fi
/bin/cp "$gate_log" "$root/wrong-gate.log"
/usr/bin/printf '%s\n' 'post-gate mutation' >>"$root/wrong-gate.log"
if release_gate_log_matches "$valid_test_evidence" "$root/wrong-gate.log"; then
  /usr/bin/printf '%s\n' 'A changed prepublication gate log was accepted.' >&2
  exit 1
fi
/bin/cp "$valid_test_evidence" "$root/wrong-name.json"
if release_test_evidence_is_valid "$root/wrong-name.json" "$commit"; then
  /usr/bin/printf '%s\n' 'Wrong test-evidence filename was accepted.' >&2
  exit 1
fi
if release_test_evidence_is_valid "$valid_test_evidence" 1111111111111111111111111111111111111111; then
  /usr/bin/printf '%s\n' 'Test evidence for another commit was accepted.' >&2
  exit 1
fi
/bin/mkdir "$root/zero-digest"
/usr/bin/sed \
  "s/$result_bundle_digest/0000000000000000000000000000000000000000000000000000000000000000/" \
  "$valid_test_evidence" >"$root/zero-digest/$release_test_evidence_name"
if release_test_evidence_is_valid \
  "$root/zero-digest/$release_test_evidence_name" "$commit"; then
  /usr/bin/printf '%s\n' 'Placeholder result-bundle digest was accepted.' >&2
  exit 1
fi
/bin/mkdir "$root/boolean-count"
/usr/bin/sed 's/"failed":0/"failed":false/g' \
  "$valid_test_evidence" >"$root/boolean-count/$release_test_evidence_name"
if release_test_evidence_is_valid \
  "$root/boolean-count/$release_test_evidence_name" "$commit"; then
  /usr/bin/printf '%s\n' 'Boolean test counters were accepted as integers.' >&2
  exit 1
fi
/bin/mkdir "$root/inconsistent-runs"
/usr/bin/sed 's/"deviceRuns":479/"deviceRuns":480/' \
  "$valid_test_evidence" >"$root/inconsistent-runs/$release_test_evidence_name"
if release_test_evidence_is_valid \
  "$root/inconsistent-runs/$release_test_evidence_name" "$commit"; then
  /usr/bin/printf '%s\n' 'Inconsistent authoritative and parameterized run totals were accepted.' >&2
  exit 1
fi
/bin/mkdir "$root/core-boolean-count"
/usr/bin/sed 's/"suites":18,"failed":0,"skipped":0/"suites":18,"failed":false,"skipped":0/' \
  "$valid_test_evidence" >"$root/core-boolean-count/$release_test_evidence_name"
if release_test_evidence_is_valid \
  "$root/core-boolean-count/$release_test_evidence_name" "$commit"; then
  /usr/bin/printf '%s\n' 'A Core-only Boolean counter was accepted as an integer.' >&2
  exit 1
fi
/bin/mkdir "$root/incomplete-gate"
/usr/bin/sed 's/"passedStages":26,"totalStages":26/"passedStages":1,"totalStages":1/' \
  "$valid_test_evidence" >"$root/incomplete-gate/$release_test_evidence_name"
if release_test_evidence_is_valid \
  "$root/incomplete-gate/$release_test_evidence_name" "$commit"; then
  /usr/bin/printf '%s\n' 'A one-stage prepublication gate was accepted.' >&2
  exit 1
fi
/bin/mkdir "$root/local-path"
/usr/bin/sed 's/"macOS":"26.6.2"/"macOS":"\/Users\/owner\/private"/' \
  "$valid_test_evidence" >"$root/local-path/$release_test_evidence_name"
if release_test_evidence_is_valid \
  "$root/local-path/$release_test_evidence_name" "$commit"; then
  /usr/bin/printf '%s\n' 'A local path was accepted in public test evidence.' >&2
  exit 1
fi
/bin/mkdir "$root/invalid-date"
/usr/bin/sed 's/2026-09-06T00:00:00Z/2026-99-99T99:99:99Z/' \
  "$valid_test_evidence" >"$root/invalid-date/$release_test_evidence_name"
if release_test_evidence_is_valid \
  "$root/invalid-date/$release_test_evidence_name" "$commit"; then
  /usr/bin/printf '%s\n' 'An impossible evidence timestamp was accepted.' >&2
  exit 1
fi
/bin/mkdir "$root/duplicate-key"
/usr/bin/sed 's/^{"schema"/{"schema":"duplicate","schema"/' \
  "$valid_test_evidence" >"$root/duplicate-key/$release_test_evidence_name"
if release_test_evidence_is_valid \
  "$root/duplicate-key/$release_test_evidence_name" "$commit"; then
  /usr/bin/printf '%s\n' 'Duplicate JSON keys were accepted.' >&2
  exit 1
fi

release_test_evidence_tree_digest_matches \
  "$valid_test_evidence" "$result_bundle" "$source_root" \
  || { /usr/bin/printf '%s\n' 'Matching result-bundle tree digest was rejected.' >&2; exit 1; }
/usr/bin/printf '%s\n' 'external mutable database fixture' >"$root/external-result-data"
/bin/ln -s "$root/external-result-data" "$result_bundle/Data/external-link"
if result_bundle_tree_digest "$result_bundle" "$source_root" >/dev/null; then
  /usr/bin/printf '%s\n' 'A result bundle containing an external symlink was accepted.' >&2
  exit 1
fi
/bin/unlink "$result_bundle/Data/external-link"
/usr/bin/printf '%s\n' 'changed result fixture' >>"$result_bundle/Data/payload"
if release_test_evidence_tree_digest_matches \
  "$valid_test_evidence" "$result_bundle" "$source_root"; then
  /usr/bin/printf '%s\n' 'A wrong but nonzero result-bundle tree digest was accepted.' >&2
  exit 1
fi
/usr/bin/printf '%s\n' 'authoritative result fixture' >"$result_bundle/Data/payload"

summary_fixture="$root/result-summary.json"
/usr/bin/printf '%s\n' \
  '{"title":"Test - LectureBoardAI","startTime":1788652700.0,"finishTime":1788652790.0,"devicesAndConfigurations":[{"device":{"architecture":"arm64","osBuildNumber":"25G83","osVersion":"26.6.2","platform":"macOS"},"expectedFailures":0,"failedTests":0,"passedTests":479,"skippedTests":0}],"expectedFailures":0,"failedTests":0,"passedTests":417,"result":"Passed","skippedTests":0,"statistics":[{"subtitle":"76 test runs","title":"14 tests ran with dynamic parameters"}],"totalTestCount":417}' \
  >"$summary_fixture"
build_fixture="$root/result-build.json"
/usr/bin/printf '%s\n' \
  '{"actionTitle":"Testing project LectureBoardAI with scheme LectureBoardAI","status":"succeeded","errorCount":0,"startTime":1788652700.0,"endTime":1788652790.0,"destination":{"architecture":"arm64","osBuildNumber":"25G83","osVersion":"26.6.2","platform":"macOS"}}' \
  >"$build_fixture"
action_fixture="$root/result-action.json"
/usr/bin/printf '%s\n' \
  "{\"subsections\":[{\"commandInvocationDetails\":{\"emittedOutput\":\"LectureBoard native-test embedded source commit: $commit\\n\"}}]}" \
  >"$action_fixture"
native_result_summary_is_valid \
  "$valid_test_evidence" "$summary_fixture" "$build_fixture" "$action_fixture" "$commit" \
  26.6.2 25G83 26.6 17F113 \
  || { /usr/bin/printf '%s\n' 'Matching xcresult summary was rejected.' >&2; exit 1; }
/usr/bin/sed 's/"passedTests":417/"passedTests":416/' \
  "$summary_fixture" >"$root/wrong-result-summary.json"
if native_result_summary_is_valid \
  "$valid_test_evidence" "$root/wrong-result-summary.json" "$build_fixture" \
  "$action_fixture" "$commit" 26.6.2 25G83 26.6 17F113; then
  /usr/bin/printf '%s\n' 'A mismatched xcresult summary was accepted.' >&2
  exit 1
fi
/usr/bin/sed 's/"failedTests":0/"failedTests":false/g' \
  "$summary_fixture" >"$root/boolean-result-summary.json"
if native_result_summary_is_valid \
  "$valid_test_evidence" "$root/boolean-result-summary.json" "$build_fixture" \
  "$action_fixture" "$commit" 26.6.2 25G83 26.6 17F113; then
  /usr/bin/printf '%s\n' 'Boolean xcresult counters were accepted as integers.' >&2
  exit 1
fi
/usr/bin/sed 's/LectureBoardAI with scheme LectureBoardAI/OtherProject with scheme OtherScheme/' \
  "$build_fixture" >"$root/wrong-result-build.json"
if native_result_summary_is_valid \
  "$valid_test_evidence" "$summary_fixture" "$root/wrong-result-build.json" \
  "$action_fixture" "$commit" 26.6.2 25G83 26.6 17F113; then
  /usr/bin/printf '%s\n' 'An xcresult for another project and scheme was accepted.' >&2
  exit 1
fi

/usr/bin/sed "s/$commit/1111111111111111111111111111111111111111/" \
  "$action_fixture" >"$root/wrong-result-action.json"
if native_result_summary_is_valid \
  "$valid_test_evidence" "$summary_fixture" "$build_fixture" \
  "$root/wrong-result-action.json" "$commit" 26.6.2 25G83 26.6 17F113; then
  /usr/bin/printf '%s\n' 'An xcresult carrying another source commit was accepted.' >&2
  exit 1
fi

archive_digest=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
test_digest=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
executable_digest=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc
valid_sbom="$root/valid-SBOM.spdx.json"
valid_provenance="$root/valid-provenance.json"
/usr/bin/printf '%s\n' \
  "{\"spdxVersion\":\"SPDX-2.3\",\"dataLicense\":\"CC0-1.0\",\"SPDXID\":\"SPDXRef-DOCUMENT\",\"name\":\"LectureBoard AI v1.0.0\",\"documentNamespace\":\"https://github.com/akiyama709/lectureboard-ai/releases/download/v1.0.0/SBOM.spdx.json#$commit\",\"creationInfo\":{\"created\":\"2026-09-06T00:00:00Z\",\"creators\":[\"Tool: no-fee-release-v1.sh\"]},\"packages\":[{\"SPDXID\":\"SPDXRef-Package-LectureBoardAI\",\"name\":\"LectureBoard AI\",\"versionInfo\":\"1.0.0\",\"downloadLocation\":\"https://github.com/akiyama709/lectureboard-ai/releases/download/v1.0.0/LectureBoard-AI-v1.0.0-arm64.zip\",\"supplier\":\"Person: Tomohiro Akiyama\",\"filesAnalyzed\":false,\"checksums\":[{\"algorithm\":\"SHA256\",\"checksumValue\":\"$archive_digest\"}],\"licenseConcluded\":\"MIT\",\"licenseDeclared\":\"MIT\",\"copyrightText\":\"Copyright (c) 2026 Tomohiro Akiyama\"}],\"documentDescribes\":[\"SPDXRef-Package-LectureBoardAI\"]}" \
  >"$valid_sbom"
/usr/bin/printf '%s\n' \
  "{\"schema\":\"lectureboard.no-fee-provenance.v1\",\"repository\":\"akiyama709/lectureboard-ai\",\"tag\":\"v1.0.0\",\"tagObject\":\"1111111111111111111111111111111111111111\",\"commit\":\"$commit\",\"bundleIdentifier\":\"io.github.akiyama709.LectureBoardAI\",\"version\":\"1.0.0\",\"architecture\":\"arm64\",\"configuration\":\"Release\",\"signature\":\"ad hoc\",\"hardenedRuntime\":true,\"entitlements\":{\"keys\":[\"com.apple.security.automation.apple-events\",\"com.apple.security.device.audio-input\"],\"canonicalJsonSha256\":\"2ef41daa1f5a828d3492e8e40efdd881b539169e6b1b95aad9be949c73de01b0\"},\"toolchain\":\"Xcode 26.6; Build version 17F113\",\"archive\":{\"name\":\"LectureBoard-AI-v1.0.0-arm64.zip\",\"sha256\":\"$archive_digest\"},\"executableSha256\":\"$executable_digest\",\"testResult\":{\"name\":\"LectureBoard-AI-v1.0.0-test-results.json\",\"sha256\":\"$test_digest\"}}" \
  >"$valid_provenance"
release_sbom_is_valid "$valid_sbom" "$commit" "$archive_digest" \
  || { /usr/bin/printf '%s\n' 'Valid exact SBOM was rejected.' >&2; exit 1; }
release_provenance_is_valid "$valid_provenance" "$commit" "$archive_digest" "$test_digest" \
  || { /usr/bin/printf '%s\n' 'Valid exact provenance was rejected.' >&2; exit 1; }
/usr/bin/sed 's/^{/{"privateLocalPath":"\/Users\/owner\/secret",/' \
  "$valid_sbom" >"$root/extra-SBOM.json"
if release_sbom_is_valid "$root/extra-SBOM.json" "$commit" "$archive_digest"; then
  /usr/bin/printf '%s\n' 'An SBOM with an extra private path was accepted.' >&2; exit 1
fi
/usr/bin/sed 's/^{/{"repository":"duplicate",/' \
  "$valid_provenance" >"$root/duplicate-provenance.json"
if release_provenance_is_valid \
  "$root/duplicate-provenance.json" "$commit" "$archive_digest" "$test_digest"; then
  /usr/bin/printf '%s\n' 'Duplicate provenance keys were accepted.' >&2; exit 1
fi

content_safe_app="$root/ContentSafe.app"
/bin/mkdir -p "$content_safe_app/Contents/Resources"
/usr/bin/printf '%s\n' 'public release resource' \
  >"$content_safe_app/Contents/Resources/public.txt"
application_content_has_no_private_paths "$content_safe_app" \
  || { /usr/bin/printf '%s\n' 'Benign application content was rejected.' >&2; exit 1; }
/usr/bin/printf '%s\n' '/Users/owner/Documents/Unpublished Lecture.pptx' \
  >"$content_safe_app/Contents/Resources/private-build-path.txt"
if application_content_has_no_private_paths "$content_safe_app"; then
  /usr/bin/printf '%s\n' 'A private lecture path inside the app was accepted.' >&2
  exit 1
fi
/usr/bin/python3 -I - "$content_safe_app/Contents/Resources/private-build-path.txt" <<'PY'
import sys
open(sys.argv[1],"wb").write("/Users/owner/Documents/Unpublished Lecture.pptx".encode("utf-16-le"))
PY
if application_content_has_no_private_paths "$content_safe_app"; then
  /usr/bin/printf '%s\n' 'A UTF-16LE private lecture path inside the app was accepted.' >&2
  exit 1
fi
/usr/bin/python3 -I - "$content_safe_app/Contents/Resources/private-build-path.txt" <<'PY'
import sys
open(sys.argv[1],"wb").write(b"X"+"/Users/owner/Documents/private.dat".encode("utf-16-le"))
PY
if application_content_has_no_private_paths "$content_safe_app"; then
  /usr/bin/printf '%s\n' \
    'An odd-offset UTF-16LE private path inside the app was accepted.' >&2
  exit 1
fi
/bin/unlink "$content_safe_app/Contents/Resources/private-build-path.txt"
/usr/bin/printf '%s\n' 'opaque fixture bytes' \
  >"$content_safe_app/Contents/Resources/Unpublished Lecture.pptx"
if application_content_has_no_private_paths "$content_safe_app"; then
  /usr/bin/printf '%s\n' 'A private lecture filename inside the app was accepted.' >&2
  exit 1
fi
/bin/unlink "$content_safe_app/Contents/Resources/Unpublished Lecture.pptx"
/usr/bin/printf '%s\n' 'mode fixture' \
  >"$content_safe_app/Contents/Resources/unreadable.bin"
/bin/chmod 000 "$content_safe_app/Contents/Resources/unreadable.bin"
if application_content_has_no_private_paths "$content_safe_app"; then
  /usr/bin/printf '%s\n' 'An unreadable-mode application file was accepted.' >&2
  exit 1
fi
/bin/chmod 600 "$content_safe_app/Contents/Resources/unreadable.bin"
/bin/unlink "$content_safe_app/Contents/Resources/unreadable.bin"
/bin/chmod 000 "$content_safe_app/Contents/Resources"
if application_content_has_no_private_paths "$content_safe_app"; then
  /usr/bin/printf '%s\n' 'An inaccessible-mode application directory was accepted.' >&2
  exit 1
fi
/bin/chmod 700 "$content_safe_app/Contents/Resources"
application_content_has_no_private_paths "$content_safe_app" \
  || { /usr/bin/printf '%s\n' 'Restored benign application content was rejected.' >&2; exit 1; }

portable_app="$root/Portable.app"
portable_zip="$root/portable.zip"
unsafe_zip="$root/appledouble.zip"
/bin/mkdir -p "$portable_app/Contents"
/usr/bin/printf '%s\n' 'portable fixture' >"$portable_app/Contents/Info.plist"
/usr/bin/printf '%s\n' 'sealed payload' >"$portable_app/Contents/payload"
/usr/bin/xattr -w com.apple.provenance fixture \
  "$portable_app/Contents/payload"
create_portable_zip "$portable_app" "$portable_zip"
archive_central_directory_is_safe_and_portable "$portable_zip" 'Portable.app' \
  || { /usr/bin/printf '%s\n' 'Portable ZIP was rejected.' >&2; exit 1; }
if /usr/bin/unzip -Z1 "$portable_zip" | /usr/bin/grep -Eq '(^|/)\._'; then
  /usr/bin/printf '%s\n' 'Portable ZIP retained an AppleDouble entry.' >&2
  exit 1
fi
/bin/mkdir "$root/portable-unzip"
/usr/bin/unzip -qq "$portable_zip" -d "$root/portable-unzip"
/usr/bin/cmp -s \
  "$portable_app/Contents/payload" \
  "$root/portable-unzip/Portable.app/Contents/payload" \
  || { /usr/bin/printf '%s\n' 'Portable unzip changed payload bytes.' >&2; exit 1; }

trailing_bytes_zip="$root/trailing-bytes.zip"
global_comment_zip="$root/global-comment.zip"
entry_comment_zip="$root/entry-comment.zip"
entry_extra_zip="$root/entry-extra.zip"
forged_usize_zip="$root/forged-usize.zip"
null_alias_zip="$root/null-alias.zip"
/bin/cp "$portable_zip" "$trailing_bytes_zip"
/usr/bin/printf '%s' 'trailing payload' >>"$trailing_bytes_zip"
/usr/bin/python3 -I - \
  "$portable_zip" "$global_comment_zip" "$entry_comment_zip" "$entry_extra_zip" \
  "$forged_usize_zip" "$null_alias_zip" <<'PY'
import binascii,shutil,stat,struct,sys,zipfile
source,global_comment,entry_comment,entry_extra,forged,null_alias=sys.argv[1:]
shutil.copyfile(source,global_comment)
with zipfile.ZipFile(global_comment,"a") as archive:
 archive.comment=b"forbidden"
def info(name,mode,kind):
 value=zipfile.ZipInfo(name)
 value.create_system=3
 value.external_attr=(kind|mode)<<16
 value.compress_type=zipfile.ZIP_DEFLATED if kind==stat.S_IFREG else zipfile.ZIP_STORED
 return value
for path,attribute in ((entry_comment,"comment"),(entry_extra,"extra")):
 with zipfile.ZipFile(path,"x",allowZip64=False) as archive:
  archive.writestr(info("Portable.app/",0o755,stat.S_IFDIR),b"")
  archive.writestr(info("Portable.app/Contents/",0o755,stat.S_IFDIR),b"")
  item=info("Portable.app/Contents/Info.plist",0o644,stat.S_IFREG)
  setattr(item,attribute,b"forbidden" if attribute=="comment" else b"\x01\x00\x00\x00")
  archive.writestr(item,b"fixture\n")
with zipfile.ZipFile(forged,"x",compression=zipfile.ZIP_DEFLATED,allowZip64=False) as archive:
 archive.writestr(info("Forged.app/",0o755,stat.S_IFDIR),b"")
 archive.writestr(info("Forged.app/Contents/",0o755,stat.S_IFDIR),b"")
 archive.writestr(info("Forged.app/Contents/Info.plist",0o644,stat.S_IFREG),b"0"*(4*1024*1024))
with zipfile.ZipFile(forged) as archive:
 target=archive.getinfo("Forged.app/Contents/Info.plist")
 local_offset=target.header_offset
 raw=open(forged,"rb").read()
 eocd=raw.rfind(b"PK\x05\x06")
 central_offset=struct.unpack_from("<I",raw,eocd+16)[0]
 position=central_offset; central_target=None
 while raw[position:position+4]==b"PK\x01\x02":
  name_len,extra_len,comment_len=struct.unpack_from("<HHH",raw,position+28)
  name=raw[position+46:position+46+name_len].decode("utf-8")
  if name==target.orig_filename: central_target=position
  position+=46+name_len+extra_len+comment_len
 if central_target is None: raise SystemExit(1)
claimed=512*1024
claimed_crc=binascii.crc32(b"0"*claimed)&0xffffffff
with open(forged,"r+b") as stream:
 for offset in (local_offset+14,central_target+16):
  stream.seek(offset); stream.write(struct.pack("<I",claimed_crc))
 for offset in (local_offset+22,central_target+24):
  stream.seek(offset); stream.write(struct.pack("<I",claimed))
with zipfile.ZipFile(forged) as archive:
 if len(archive.read("Forged.app/Contents/Info.plist"))!=claimed or archive.testzip() is not None:
  raise SystemExit(1)
with zipfile.ZipFile(null_alias,"x",allowZip64=False) as archive:
 archive.writestr(info("Portable.app/",0o755,stat.S_IFDIR),b"")
 archive.writestr(info("Portable.app/Contents/",0o755,stat.S_IFDIR),b"")
 archive.writestr(info("Portable.app/Contents/Info.plist",0o644,stat.S_IFREG),b"fixture\n")
raw=bytearray(open(null_alias,"rb").read())
needle=b"Portable.app/Contents/Info.plist"
replacement=b"Portable.app/Contents/Info.plis\x00"
if len(needle)!=len(replacement) or raw.count(needle)!=2: raise SystemExit(1)
raw=raw.replace(needle,replacement)
open(null_alias,"wb").write(raw)
PY
for unsafe_case in \
  "$trailing_bytes_zip:Portable.app" \
  "$global_comment_zip:Portable.app" \
  "$entry_comment_zip:Portable.app" \
  "$entry_extra_zip:Portable.app" \
  "$forged_usize_zip:Forged.app" \
  "$null_alias_zip:Portable.app"; do
  if archive_central_directory_is_safe_and_portable \
    "${unsafe_case%%:*}" "${unsafe_case##*:}"; then
    /usr/bin/printf '%s\n' 'A forged, hidden, or trailing ZIP payload was accepted.' >&2
    exit 1
  fi
done

/usr/bin/python3 -I - "$unsafe_zip" <<'PY'
import zipfile,sys
with zipfile.ZipFile(sys.argv[1],"w") as z:
    z.writestr("AppleDouble.app/",b"")
    z.writestr("AppleDouble.app/Contents/",b"")
    z.writestr("AppleDouble.app/Contents/Info.plist",b"unsafe fixture\n")
    z.writestr("AppleDouble.app/Contents/._Info.plist",b"AppleDouble metadata\n")
PY
/usr/bin/unzip -Z1 "$unsafe_zip" | /usr/bin/grep -Eq '(^|/)\._' \
  || { /usr/bin/printf '%s\n' 'Unsafe fixture did not contain AppleDouble evidence.' >&2; exit 1; }
if archive_central_directory_is_safe_and_portable "$unsafe_zip" 'AppleDouble.app'; then
  /usr/bin/printf '%s\n' 'AppleDouble ZIP passed the portability boundary.' >&2
  exit 1
fi

trailing_alias_zip="$root/trailing-alias.zip"
case_collision_zip="$root/case-collision.zip"
setuid_zip="$root/setuid.zip"
zip_bomb="$root/zip-bomb.zip"
/usr/bin/python3 -I - "$trailing_alias_zip" "$case_collision_zip" "$setuid_zip" "$zip_bomb" <<'PY'
import stat,sys,zipfile
with zipfile.ZipFile(sys.argv[1],"w") as z:
    z.writestr("Trailing.app/",b"")
    z.writestr("Trailing.app//",b"")
    z.writestr("Trailing.app/Contents/Info.plist",b"fixture\n")
with zipfile.ZipFile(sys.argv[2],"w") as z:
    z.writestr("Case.app/",b"")
    z.writestr("Case.app/Contents/",b"")
    z.writestr("Case.app/contents/",b"")
    z.writestr("Case.app/Contents/Info.plist",b"fixture\n")
with zipfile.ZipFile(sys.argv[3],"w") as z:
    z.writestr("Setuid.app/",b"")
    info=zipfile.ZipInfo("Setuid.app/Contents/Info.plist")
    info.create_system=3
    info.external_attr=(stat.S_IFREG|0o4644)<<16
    z.writestr(info,b"fixture\n")
with zipfile.ZipFile(sys.argv[4],"w",compression=zipfile.ZIP_DEFLATED) as z:
    z.writestr("Bomb.app/",b"")
    z.writestr("Bomb.app/Contents/",b"")
    z.writestr("Bomb.app/Contents/Info.plist",b"0"*(2*1024*1024))
PY
for unsafe_case in \
  "$trailing_alias_zip:Trailing.app" \
  "$case_collision_zip:Case.app" \
  "$setuid_zip:Setuid.app" \
  "$zip_bomb:Bomb.app"; do
  if archive_central_directory_is_safe_and_portable \
    "${unsafe_case%%:*}" "${unsafe_case##*:}"; then
    /usr/bin/printf '%s\n' 'A noncanonical or dangerous ZIP entry was accepted.' >&2
    exit 1
  fi
done

signed_app="$root/SignedFixture.app"
/bin/mkdir -p "$signed_app/Contents/MacOS"
/usr/bin/printf '%s\n' 'int main(void) { return 0; }' >"$root/signed-fixture.c"
/usr/bin/xcrun clang -arch arm64 "$root/signed-fixture.c" \
  -o "$signed_app/Contents/MacOS/SignedFixture"
/usr/bin/plutil -create xml1 "$signed_app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string SignedFixture "$signed_app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleIdentifier -string io.github.akiyama709.SignedFixture "$signed_app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundlePackageType -string APPL "$signed_app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleShortVersionString -string 1.0 "$signed_app/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleVersion -string 1 "$signed_app/Contents/Info.plist"
/usr/bin/codesign --force --sign - --options runtime "$signed_app"
/usr/bin/codesign --verify --deep --strict "$signed_app"
/usr/bin/xattr -w com.apple.provenance fixture "$signed_app/Contents/Info.plist"
signed_zip="$root/signed-portable.zip"
create_portable_zip "$signed_app" "$signed_zip"
/bin/mkdir "$root/signed-ditto" "$root/signed-unzip"
/usr/bin/ditto -x -k --norsrc --noqtn "$signed_zip" "$root/signed-ditto"
/usr/bin/unzip -qq "$signed_zip" -d "$root/signed-unzip"
/usr/bin/codesign --verify --deep --strict "$root/signed-ditto/SignedFixture.app"
/usr/bin/codesign --verify --deep --strict "$root/signed-unzip/SignedFixture.app"
signed_component_has_no_entitlements "$signed_app/Contents/MacOS/SignedFixture" \
  || { /usr/bin/printf '%s\n' 'A nested component without entitlements was rejected.' >&2; exit 1; }
entitled_binary="$root/EntitledFixture"
/usr/bin/xcrun clang -arch arm64 "$root/signed-fixture.c" -o "$entitled_binary"
/usr/bin/python3 -I - "$root/forbidden-entitlements.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],"xb") as stream:
 plistlib.dump({"com.apple.security.get-task-allow":True},stream)
PY
/usr/bin/codesign --force --sign - --options runtime \
  --entitlements "$root/forbidden-entitlements.plist" "$entitled_binary"
if signed_component_has_no_entitlements "$entitled_binary"; then
  /usr/bin/printf '%s\n' 'A nested component carrying an entitlement was accepted.' >&2
  exit 1
fi
if /usr/bin/find "$root/signed-unzip/SignedFixture.app" -name '._*' -print -quit \
  | /usr/bin/grep -q .; then
  /usr/bin/printf '%s\n' 'Generic unzip materialized AppleDouble inside the signed fixture.' >&2
  exit 1
fi

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
for command in evidence prepare verify compare-public verify-public; do
  if LECTUREBOARD_RELEASE_TEST_MODE=fixture-v1 /bin/bash -p "$tool" "$command" >/dev/null 2>&1; then
    /usr/bin/printf '%s\n' "fixture bypass accepted by $command" >&2; exit 1
  fi
done
fake_path="$root/fake-path"
/bin/mkdir "$fake_path"
for fake_utility in find tr; do
  /usr/bin/printf '%s\n' '#!/bin/bash' \
    "/usr/bin/touch '$root/fake-$fake_utility-executed'" 'exit 99' \
    >"$fake_path/$fake_utility"
  /bin/chmod 700 "$fake_path/$fake_utility"
done
/usr/bin/env PATH="$fake_path:/usr/bin:/bin:/usr/sbin:/sbin" \
  /bin/bash -p "$tool" verify >/dev/null 2>&1 || true
for fake_utility in find tr; do
  [[ ! -e "$root/fake-$fake_utility-executed" ]] \
    || { /usr/bin/printf '%s\n' "Caller-supplied $fake_utility executed." >&2; exit 1; }
done
approved_assets="$root/approved-assets"
downloaded_assets="$root/downloaded-assets"
/bin/mkdir "$approved_assets" "$downloaded_assets"
tag_object=1111111111111111111111111111111111111111
for asset_name in \
  LectureBoard-AI-v1.0.0-arm64.zip \
  LectureBoard-AI-v1.0.0-test-results.json \
  SBOM.spdx.json \
  provenance.json; do
  if [[ "$asset_name" == provenance.json ]]; then
    /usr/bin/printf '{"tagObject":"%s"}\n' "$tag_object" >"$approved_assets/$asset_name"
  else
    /usr/bin/printf 'approved %s bytes\n' "$asset_name" >"$approved_assets/$asset_name"
  fi
done
(
  cd -- "$approved_assets"
  /usr/bin/shasum -a 256 \
    LectureBoard-AI-v1.0.0-arm64.zip \
    LectureBoard-AI-v1.0.0-test-results.json \
    SBOM.spdx.json \
    provenance.json
) >"$approved_assets/SHA256SUMS"
/usr/bin/ditto --norsrc --noqtn "$approved_assets" "$downloaded_assets"
release_metadata="$root/public-release.json"
public_tag_refs="$root/public-tag-refs.txt"
/usr/bin/printf '%s\t%s\n%s\t%s\n' \
  "$tag_object" 'refs/tags/v1.0.0' "$commit" 'refs/tags/v1.0.0^{}' \
  >"$public_tag_refs"
/usr/bin/python3 -I - "$release_metadata" "$approved_assets" <<'PY'
import hashlib,json,os,sys,urllib.parse
out,root=sys.argv[1:]
names=["LectureBoard-AI-v1.0.0-arm64.zip","LectureBoard-AI-v1.0.0-test-results.json","SBOM.spdx.json","SHA256SUMS","provenance.json"]
assets=[]
for name in names:
 path=os.path.join(root,name)
 assets.append({"name":name,"state":"uploaded","size":os.path.getsize(path),
  "digest":"sha256:"+hashlib.sha256(open(path,"rb").read()).hexdigest(),
  "browser_download_url":"https://github.com/akiyama709/lectureboard-ai/releases/download/v1.0.0/"+urllib.parse.quote(name,safe="")})
release={"id":1,"tag_name":"v1.0.0","name":"LectureBoard AI v1.0.0","target_commitish":"main",
 "draft":False,"prerelease":False,"immutable":True,"published_at":"2026-09-06T00:00:00Z",
 "html_url":"https://github.com/akiyama709/lectureboard-ai/releases/tag/v1.0.0","assets":assets}
with open(out,"x",encoding="utf-8") as stream: json.dump(release,stream,separators=(",",":"))
PY
compare_public() {
  /bin/bash -p "$tool" compare-public \
    --approved-dir "$1" --downloaded-dir "$2" \
    --release-metadata "$release_metadata" --tag-refs "$public_tag_refs" --commit "$commit"
}
compare_public "$approved_assets" "$downloaded_assets" >/dev/null

release_metadata_snapshot="$root/public-release-snapshot.json"
public_tag_refs_snapshot="$root/public-tag-refs-snapshot.txt"
/bin/cp -X "$release_metadata" "$release_metadata_snapshot"
/bin/cp -X "$public_tag_refs" "$public_tag_refs_snapshot"
public_inputs_match_snapshot \
  "$approved_assets" "$downloaded_assets" \
  "$release_metadata" "$release_metadata_snapshot" \
  "$public_tag_refs" "$public_tag_refs_snapshot" \
  || { /usr/bin/printf '%s\n' 'An unchanged public-input snapshot was rejected.' >&2; exit 1; }
/usr/bin/printf x >>"$downloaded_assets/provenance.json"
if public_inputs_match_snapshot \
  "$approved_assets" "$downloaded_assets" \
  "$release_metadata" "$release_metadata_snapshot" \
  "$public_tag_refs" "$public_tag_refs_snapshot"; then
  /usr/bin/printf '%s\n' 'A post-comparison public asset mutation was accepted.' >&2
  exit 1
fi
/bin/cp -X "$approved_assets/provenance.json" "$downloaded_assets/provenance.json"
/usr/bin/printf x >>"$release_metadata_snapshot"
if public_inputs_match_snapshot \
  "$approved_assets" "$downloaded_assets" \
  "$release_metadata" "$release_metadata_snapshot" \
  "$public_tag_refs" "$public_tag_refs_snapshot"; then
  /usr/bin/printf '%s\n' 'A post-comparison public metadata mutation was accepted.' >&2
  exit 1
fi
/bin/cp -X "$release_metadata" "$release_metadata_snapshot"
/usr/bin/printf x >>"$public_tag_refs_snapshot"
if public_inputs_match_snapshot \
  "$approved_assets" "$downloaded_assets" \
  "$release_metadata" "$release_metadata_snapshot" \
  "$public_tag_refs" "$public_tag_refs_snapshot"; then
  /usr/bin/printf '%s\n' 'A post-comparison public tag-ref mutation was accepted.' >&2
  exit 1
fi
/bin/cp -X "$public_tag_refs" "$public_tag_refs_snapshot"

hardlinked_assets="$root/hardlinked-assets"
/bin/mkdir "$hardlinked_assets"
for asset_name in \
  LectureBoard-AI-v1.0.0-arm64.zip \
  LectureBoard-AI-v1.0.0-test-results.json \
  SBOM.spdx.json \
  SHA256SUMS \
  provenance.json; do
  /bin/ln "$approved_assets/$asset_name" "$hardlinked_assets/$asset_name"
done
if compare_public "$approved_assets" "$hardlinked_assets" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'Public assets sharing approved inodes were accepted.' >&2
  exit 1
fi

/usr/bin/sed 's/"immutable":true/"immutable":false/' \
  "$release_metadata" >"$root/mutable-release.json"
if /bin/bash -p "$tool" compare-public \
  --approved-dir "$approved_assets" --downloaded-dir "$downloaded_assets" \
  --release-metadata "$root/mutable-release.json" --tag-refs "$public_tag_refs" \
  --commit "$commit" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'Mutable GitHub release metadata was accepted.' >&2; exit 1
fi
/usr/bin/sed 's/"prerelease":false/"prerelease":true/' \
  "$release_metadata" >"$root/prerelease.json"
if /bin/bash -p "$tool" compare-public \
  --approved-dir "$approved_assets" --downloaded-dir "$downloaded_assets" \
  --release-metadata "$root/prerelease.json" --tag-refs "$public_tag_refs" \
  --commit "$commit" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'A prerelease GitHub release was accepted.' >&2; exit 1
fi
/usr/bin/sed 's/LectureBoard AI v1.0.0/LectureBoard AI release/' \
  "$release_metadata" >"$root/wrong-release-name.json"
if /bin/bash -p "$tool" compare-public \
  --approved-dir "$approved_assets" --downloaded-dir "$downloaded_assets" \
  --release-metadata "$root/wrong-release-name.json" --tag-refs "$public_tag_refs" \
  --commit "$commit" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'A GitHub release with the wrong name was accepted.' >&2; exit 1
fi
/usr/bin/sed 's/2026-09-06T00:00:00Z/2026-99-99T99:99:99Z/' \
  "$release_metadata" >"$root/invalid-published-at.json"
if /bin/bash -p "$tool" compare-public \
  --approved-dir "$approved_assets" --downloaded-dir "$downloaded_assets" \
  --release-metadata "$root/invalid-published-at.json" --tag-refs "$public_tag_refs" \
  --commit "$commit" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'A GitHub release with an invalid publication time was accepted.' >&2; exit 1
fi
/usr/bin/sed 's/"draft":false/"draft":true/' \
  "$release_metadata" >"$root/draft-release.json"
if /bin/bash -p "$tool" compare-public \
  --approved-dir "$approved_assets" --downloaded-dir "$downloaded_assets" \
  --release-metadata "$root/draft-release.json" --tag-refs "$public_tag_refs" \
  --commit "$commit" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'Draft GitHub release metadata was accepted.' >&2; exit 1
fi
/usr/bin/python3 -I - "$release_metadata" "$root/extra-asset-release.json" <<'PY'
import json,sys
data=json.load(open(sys.argv[1],encoding="utf-8"))
data["assets"].append({"name":"unexpected.txt","state":"uploaded","size":1,
 "browser_download_url":"https://github.com/akiyama709/lectureboard-ai/releases/download/v1.0.0/unexpected.txt"})
json.dump(data,open(sys.argv[2],"x",encoding="utf-8"),separators=(",",":"))
PY
if /bin/bash -p "$tool" compare-public \
  --approved-dir "$approved_assets" --downloaded-dir "$downloaded_assets" \
  --release-metadata "$root/extra-asset-release.json" --tag-refs "$public_tag_refs" \
  --commit "$commit" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'An extra GitHub release asset was accepted.' >&2; exit 1
fi
/usr/bin/sed "s/$commit/2222222222222222222222222222222222222222/" \
  "$public_tag_refs" >"$root/wrong-public-tag-refs.txt"
if /bin/bash -p "$tool" compare-public \
  --approved-dir "$approved_assets" --downloaded-dir "$downloaded_assets" \
  --release-metadata "$release_metadata" --tag-refs "$root/wrong-public-tag-refs.txt" \
  --commit "$commit" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'A public tag peeled to another commit was accepted.' >&2; exit 1
fi
/usr/bin/sed "s/$tag_object/3333333333333333333333333333333333333333/" \
  "$public_tag_refs" >"$root/wrong-public-tag-object.txt"
if /bin/bash -p "$tool" compare-public \
  --approved-dir "$approved_assets" --downloaded-dir "$downloaded_assets" \
  --release-metadata "$release_metadata" --tag-refs "$root/wrong-public-tag-object.txt" \
  --commit "$commit" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'A public tag with another tag-object ID was accepted.' >&2; exit 1
fi
if LECTUREBOARD_RELEASE_TEST_MODE=fixture-v1 /bin/bash -p "$tool" compare-public \
  --approved-dir "$approved_assets" --downloaded-dir "$downloaded_assets" \
  --release-metadata "$release_metadata" --tag-refs "$public_tag_refs" \
  --commit "$commit" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'public comparison accepted fixture mode with otherwise valid inputs' >&2; exit 1
fi

same_directory_log="$root/same-directory.log"
if compare_public "$approved_assets" "$approved_assets" >"$same_directory_log" 2>&1; then
  /usr/bin/printf '%s\n' 'The same literal directory was accepted as public evidence.' >&2
  exit 1
fi
/usr/bin/grep -Fq \
  'approved and public release directories must be distinct physical directories' \
  "$same_directory_log" \
  || { /usr/bin/printf '%s\n' 'Same-directory rejection was not specific.' >&2; exit 1; }
/bin/ln -s "$root" "$root/parent-alias"
if compare_public "$approved_assets" \
  "$root/parent-alias/approved-assets" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'A physical-directory alias was accepted as public evidence.' >&2
  exit 1
fi

/usr/bin/printf x >>"$downloaded_assets/provenance.json"
if compare_public "$approved_assets" "$downloaded_assets" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'Different public provenance bytes were accepted.' >&2; exit 1
fi
/bin/cp "$approved_assets/provenance.json" "$downloaded_assets/provenance.json"
/usr/bin/printf x >>"$downloaded_assets/LectureBoard-AI-v1.0.0-arm64.zip"
if compare_public "$approved_assets" "$downloaded_assets" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'Different public archive bytes were accepted.' >&2; exit 1
fi
/bin/cp "$approved_assets/LectureBoard-AI-v1.0.0-arm64.zip" \
  "$downloaded_assets/LectureBoard-AI-v1.0.0-arm64.zip"
/bin/unlink "$downloaded_assets/SBOM.spdx.json"
if compare_public "$approved_assets" "$downloaded_assets" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'A missing public release asset was accepted.' >&2; exit 1
fi
/bin/cp "$approved_assets/SBOM.spdx.json" "$downloaded_assets/SBOM.spdx.json"
/usr/bin/printf '%s\n' unexpected >"$downloaded_assets/unexpected.txt"
if compare_public "$approved_assets" "$downloaded_assets" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'An extra public release asset was accepted.' >&2; exit 1
fi
/bin/unlink "$downloaded_assets/unexpected.txt"
/bin/cp "$approved_assets/SHA256SUMS" "$root/full-SHA256SUMS"
/usr/bin/head -n 3 "$root/full-SHA256SUMS" >"$approved_assets/SHA256SUMS"
if compare_public "$approved_assets" "$downloaded_assets" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'An incomplete checksum manifest was accepted.' >&2; exit 1
fi
/bin/cp "$root/full-SHA256SUMS" "$approved_assets/SHA256SUMS"
if /bin/bash -p "$tool" compare-public \
  --approved-archive "$approved_assets/LectureBoard-AI-v1.0.0-arm64.zip" \
  --downloaded-archive "$downloaded_assets/LectureBoard-AI-v1.0.0-arm64.zip" \
  --checksum "$approved_assets/SHA256SUMS" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'The obsolete ZIP-only public comparison interface was accepted.' >&2; exit 1
fi

for override_name in UNZIP UNZIPOPT; do
  override_log="$root/$override_name.log"
  if /usr/bin/env "$override_name=-j" /bin/bash -p "$tool" verify \
    --archive "$approved_assets/LectureBoard-AI-v1.0.0-arm64.zip" \
    --checksum "$approved_assets/SHA256SUMS" \
    --sbom "$approved_assets/SBOM.spdx.json" \
    --provenance "$approved_assets/provenance.json" \
    --test-result "$approved_assets/LectureBoard-AI-v1.0.0-test-results.json" \
    --commit "$commit" >"$override_log" 2>&1; then
    /usr/bin/printf '%s\n' "$override_name override was accepted." >&2; exit 1
  fi
  /usr/bin/grep -Fq "production input cannot set $override_name" "$override_log" \
    || { /usr/bin/printf '%s\n' "$override_name was not rejected at the environment boundary." >&2; exit 1; }
done

/bin/mkdir "$root/python-injection" "$root/perl-injection"
/usr/bin/printf '%s\n' \
  "open('$root/python-marker','w').write('executed')" \
  >"$root/python-injection/sitecustomize.py"
if /usr/bin/env PYTHONPATH="$root/python-injection" /bin/bash -p "$tool" compare-public \
  --approved-dir "$approved_assets" --downloaded-dir "$downloaded_assets" \
  --release-metadata "$release_metadata" --tag-refs "$public_tag_refs" --commit "$commit" \
  >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'PYTHONPATH was accepted by the release boundary.' >&2; exit 1
fi
[[ ! -e "$root/python-marker" ]] \
  || { /usr/bin/printf '%s\n' 'PYTHONPATH code executed inside the release tool.' >&2; exit 1; }
/usr/bin/printf '%s\n' \
  "BEGIN { open my \$fh, '>', '$root/perl-marker'; print \$fh 'executed'; close \$fh; } 1;" \
  >"$root/perl-injection/ReleaseAudit.pm"
if /usr/bin/env PERL5OPT="-I$root/perl-injection -MReleaseAudit" \
  /bin/bash -p "$tool" compare-public \
  --approved-dir "$approved_assets" --downloaded-dir "$downloaded_assets" \
  --release-metadata "$release_metadata" --tag-refs "$public_tag_refs" --commit "$commit" \
  >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'PERL5OPT was accepted by the release boundary.' >&2; exit 1
fi
[[ ! -e "$root/perl-marker" ]] \
  || { /usr/bin/printf '%s\n' 'PERL5OPT code executed inside the release tool.' >&2; exit 1; }

if /bin/bash -p "$tool" build --source-dir "$root" --commit "$commit" --tag v1.0.0 --output-dir "$root/out" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'removed split build command was still accepted' >&2; exit 1
fi
if /bin/bash -p "$tool" package --app "$root/no.app" --source-dir "$root" --commit "$commit" --tag v1.0.0 --test-result "$valid_test_evidence" --output-dir "$root/out" >/dev/null 2>&1; then
  /usr/bin/printf '%s\n' 'removed split package command was still accepted' >&2; exit 1
fi
/usr/bin/printf '%s\n' 'No-fee v1 release tooling boundary tests passed.'
