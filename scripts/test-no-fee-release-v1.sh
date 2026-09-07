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
require_text 'freeze_result_bundle_when_stable "$after_result" "$copied_result" "$isolated_source"'
reject_text 'materialize_result_bundle_for_queries "$after_result" "$isolated_source"'
require_text 'extract_result_bundle_query_outputs "$result_bundle" "$source_root" "$result_digest"'
require_text 'required_stable_observations=6 quiet_nanoseconds=5000000000'
require_text 'result-bundle.normalized.tree'
require_text '$2="-"; $3="-"; print; count += 1'
require_text 'maximum_observations=600 maximum_copy_attempts=2 deadline_nanoseconds=600000000000'
require_text 'local seconds_value="${SECONDS-}"'
require_text '(( seconds_value <= 9223372036 ))'
reject_text 'time.monotonic_ns()'
require_text 'result_bundle_pair_matches_digest'
require_text 'failure=pairConsistentButDeadlineExceeded'
require_text 'failure=observationLimitExceeded'
require_text 'retry=pairDigestMismatch'
require_text '"$first_token_after" == "$first_token_before"'
require_text '"$second_token_after" == "$second_token_before"'
require_text '"$post_pair_source_token" == "$post_digest_token"'
require_text 'delete_directory_with_identity "$destination_parent_physical" "$parent_identity"'
require_text 'A failed copier does not establish which inode'
require_text "die 'source or frozen result bundle changed before exclusive handoff'"
require_text 'private_evidence_directory_is_exact "$evidence_stage" "${after_result##*/}"'
require_text 'regular_file_matches_sha256 "$evidence_file" "$generated_evidence_digest"'
require_text 'published_evidence_stage="$evidence_stage"'
require_text 'cleanup_known_evidence_handoff \'
require_text 'validate_published_evidence_handoff \'
require_text 'published_evidence_parent_fd=9'
require_text 'published_evidence_stage_fd=8'
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

/usr/bin/python3 -I - "$tool" <<'PY'
import sys
data=open(sys.argv[1],encoding="utf-8").read()
start=data.index("generate_release_evidence() {")
end=data.index("\nrelease_test_evidence_tree_digest_matches() {",start)
body=data[start:end]
markers=[
 'private_evidence_directory_is_exact "$evidence_stage"',
 'regular_file_matches_sha256 "$evidence_file" "$generated_evidence_digest"',
 'published_evidence_stage="$evidence_stage"',
 '"$temp/release-exclusive-rename" "$evidence_stage" "$output_dir"',
 'validate_published_evidence_handoff',
 "published_evidence_parent=''",
]
positions=[body.index(marker) for marker in markers]
positions[1]=body.rindex(markers[1])
if positions!=sorted(positions): raise SystemExit(1)
PY

/usr/bin/python3 -I - "$tool" <<'PY'
import sys
data=open(sys.argv[1],encoding="utf-8").read()
start=data.index("freeze_result_bundle_when_stable() {")
end=data.index("\ncreate_isolated_commit_source() {",start)
body=data[start:end]
pair_done=body.index("phase=pairDigestCompleted")
clock=body.rindex("result_bundle_set_monotonic_now || return 1",0,pair_done)
identity=body.index('current_identity="$(directory_identity "$result_bundle")"',pair_done)
diagnostic=body.index("phase=finalSealStarted",identity)
destination=body.index('post_pair_destination_token="$(result_bundle_stability_token "$destination")"',diagnostic)
source=body.index('post_pair_source_token="$(result_bundle_stability_token "$result_bundle")"',destination)
success=body.index('frozen_result_bundle_digest="$current_digest"\n          return 0',source)
if [clock,identity,diagnostic,destination,source,success] != sorted(
    [clock,identity,diagnostic,destination,source,success]
): raise SystemExit(1)
source_success='''        elif ! post_pair_source_token="$(result_bundle_stability_token "$result_bundle")"; then
          final_seal_failure='sourceTokenUnavailable'
        elif [[ "$post_pair_source_token" == "$post_digest_token" ]]; then
          frozen_result_bundle_digest="$current_digest"
          return 0'''
if source_success not in body: raise SystemExit(1)
PY

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
  sed -n '/^result_bundle_tree_digest() {$/,/^}$/p' "$tool" \
    | /usr/bin/sed '1s/^result_bundle_tree_digest/result_bundle_tree_digest_original/'
  sed -n '/^result_bundle_pair_matches_digest() {$/,/^}$/p' "$tool"
  sed -n '/^result_bundle_pair_matches_digest() {$/,/^}$/p' "$tool" \
    | /usr/bin/sed '1s/^result_bundle_pair_matches_digest/result_bundle_pair_matches_digest_original/'
  sed -n '/^result_bundle_stability_pause() {$/,/^}$/p' "$tool"
  sed -n '/^result_bundle_set_monotonic_now() {$/,/^}$/p' "$tool"
  sed -n '/^result_bundle_set_monotonic_now() {$/,/^}$/p' "$tool" \
    | /usr/bin/sed '1s/^result_bundle_set_monotonic_now/result_bundle_set_monotonic_now_original/'
  sed -n '/^result_bundle_stability_token() {$/,/^}$/p' "$tool"
  sed -n '/^copy_result_bundle_for_freeze() {$/,/^}$/p' "$tool"
  sed -n '/^run_result_bundle_queries() {$/,/^}$/p' "$tool"
  sed -n '/^extract_result_bundle_query_outputs() {$/,/^}$/p' "$tool"
  sed -n '/^freeze_result_bundle_when_stable() {$/,/^}$/p' "$tool"
  sed -n '/^directory_identity() {$/,/^}$/p' "$tool"
  sed -n '/^regular_file_matches_sha256() {$/,/^}$/p' "$tool"
  sed -n '/^private_evidence_directory_is_exact() {$/,/^}$/p' "$tool"
  sed -n '/^delete_directory_with_identity() {$/,/^}$/p' "$tool"
  sed -n '/^directory_descriptor_matches_identity() {$/,/^}$/p' "$tool"
  sed -n '/^delete_directory_from_descriptors_with_identity() {$/,/^}$/p' "$tool"
  sed -n '/^cleanup_known_evidence_handoff() {$/,/^}$/p' "$tool"
  sed -n '/^evidence_handoff_identities_are_valid() {$/,/^}$/p' "$tool"
  sed -n '/^post_handoff_validation_pause() {$/,/^}$/p' "$tool"
  sed -n '/^post_handoff_final_token_pause() {$/,/^}$/p' "$tool"
  sed -n '/^published_evidence_content_is_valid() {$/,/^}$/p' "$tool"
  sed -n '/^published_evidence_content_is_valid() {$/,/^}$/p' "$tool" \
    | /usr/bin/sed '1s/^published_evidence_content_is_valid/published_evidence_content_is_valid_original/'
  sed -n '/^validate_published_evidence_handoff() {$/,/^}$/p' "$tool"
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

cleanup_parent="$root/evidence-cleanup-parent"
/bin/mkdir "$cleanup_parent"
cleanup_parent_identity="$(directory_identity "$cleanup_parent")"

cleanup_stage="$cleanup_parent/.lectureboard-v1-evidence.helper-failed"
cleanup_output="$cleanup_parent/helper-failed-output"
/bin/mkdir -p "$cleanup_stage/content"
/usr/bin/printf '%s\n' 'known staged evidence' >"$cleanup_stage/content/payload"
cleanup_stage_identity="$(directory_identity "$cleanup_stage")"
cleanup_known_evidence_handoff "$cleanup_parent" "$cleanup_parent_identity" \
  "$cleanup_stage" "$cleanup_output" "$cleanup_stage_identity" \
  || { /usr/bin/printf '%s\n' 'A known pre-rename evidence stage was not cleaned.' >&2; exit 1; }
[[ ! -e "$cleanup_stage" && ! -L "$cleanup_stage" ]] \
  || { /usr/bin/printf '%s\n' 'Pre-rename cleanup left its known stage behind.' >&2; exit 1; }

cleanup_stage="$cleanup_parent/.lectureboard-v1-evidence.renamed-then-failed"
cleanup_output="$cleanup_parent/renamed-then-failed-output"
/bin/mkdir -p "$cleanup_stage/content"
/usr/bin/printf '%s\n' 'known renamed evidence' >"$cleanup_stage/content/payload"
cleanup_stage_identity="$(directory_identity "$cleanup_stage")"
/bin/mv "$cleanup_stage" "$cleanup_output"
cleanup_known_evidence_handoff "$cleanup_parent" "$cleanup_parent_identity" \
  "$cleanup_stage" "$cleanup_output" "$cleanup_stage_identity" \
  || { /usr/bin/printf '%s\n' 'A known post-rename evidence output was not cleaned.' >&2; exit 1; }
[[ ! -e "$cleanup_output" && ! -L "$cleanup_output" ]] \
  || { /usr/bin/printf '%s\n' 'Post-rename failure cleanup left its known output behind.' >&2; exit 1; }

cleanup_stage="$cleanup_parent/.lectureboard-v1-evidence.output-conflict"
cleanup_output="$cleanup_parent/output-conflict"
/bin/mkdir -p "$cleanup_stage/content" "$cleanup_output"
/usr/bin/printf '%s\n' 'known stage' >"$cleanup_stage/content/payload"
/usr/bin/printf '%s\n' 'unrelated conflicting output' >"$cleanup_output/do-not-delete"
cleanup_stage_identity="$(directory_identity "$cleanup_stage")"
cleanup_known_evidence_handoff "$cleanup_parent" "$cleanup_parent_identity" \
  "$cleanup_stage" "$cleanup_output" "$cleanup_stage_identity" \
  || { /usr/bin/printf '%s\n' 'Known-stage cleanup failed beside an output conflict.' >&2; exit 1; }
[[ ! -e "$cleanup_stage" && -f "$cleanup_output/do-not-delete" ]] \
  || { /usr/bin/printf '%s\n' 'A different-inode output conflict was removed.' >&2; exit 1; }

swapped_cleanup_target="$cleanup_parent/swapped-cleanup-target"
swapped_cleanup_saved="$cleanup_parent/swapped-cleanup-saved"
/bin/mkdir "$swapped_cleanup_target"
swapped_cleanup_identity="$(directory_identity "$swapped_cleanup_target")"
/bin/mv "$swapped_cleanup_target" "$swapped_cleanup_saved"
/bin/mkdir "$swapped_cleanup_target"
/usr/bin/printf '%s\n' 'replacement victim' >"$swapped_cleanup_target/do-not-delete"
if delete_directory_with_identity "$cleanup_parent" "$cleanup_parent_identity" \
  "$swapped_cleanup_target" "$swapped_cleanup_identity"; then
  /usr/bin/printf '%s\n' 'A path-swapped cleanup target was accepted.' >&2
  exit 1
fi
[[ -f "$swapped_cleanup_target/do-not-delete" && -d "$swapped_cleanup_saved" ]] \
  || { /usr/bin/printf '%s\n' 'Path-swap rejection deleted or lost an unrelated directory.' >&2; exit 1; }

unlinked_cleanup_parent="$root/unlinked-cleanup-parent"
unlinked_cleanup_stage="$unlinked_cleanup_parent/.lectureboard-v1-evidence.already-unlinked"
unlinked_cleanup_output="$unlinked_cleanup_parent/already-unlinked-output"
/bin/mkdir -p "$unlinked_cleanup_stage/content"
/usr/bin/printf '%s\n' 'unrelated sibling' >"$unlinked_cleanup_parent/do-not-delete"
unlinked_cleanup_parent_identity="$(directory_identity "$unlinked_cleanup_parent")"
unlinked_cleanup_stage_identity="$(directory_identity "$unlinked_cleanup_stage")"
exec 9<"$unlinked_cleanup_parent"
exec 8<"$unlinked_cleanup_stage"
/bin/mv "$unlinked_cleanup_stage" "$unlinked_cleanup_output"
delete_directory_with_identity "$unlinked_cleanup_parent" \
  "$unlinked_cleanup_parent_identity" "$unlinked_cleanup_output" \
  "$unlinked_cleanup_stage_identity" \
  || { /usr/bin/printf '%s\n' 'The retained target fixture could not be unlinked.' >&2; exit 1; }
if cleanup_known_evidence_handoff "$unlinked_cleanup_parent" \
  "$unlinked_cleanup_parent_identity" "$unlinked_cleanup_stage" \
  "$unlinked_cleanup_output" "$unlinked_cleanup_stage_identity" 9 8; then
  /usr/bin/printf '%s\n' \
    'A retained target absent from its retained parent was accepted as positively identified.' >&2
  exit 1
fi
exec 8<&-
exec 9<&-
[[ ! -e "$unlinked_cleanup_output" && -f "$unlinked_cleanup_parent/do-not-delete" ]] \
  || { /usr/bin/printf '%s\n' 'Fail-closed absent-target cleanup altered unrelated content.' >&2; exit 1; }

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

mid_token_result_bundle="$root/Test-LectureBoardAI-2026.09.06_09-11-26-+0900.xcresult"
/bin/mkdir -p "$mid_token_result_bundle/Data"
/usr/bin/printf '%s\n' 'hashed first' >"$mid_token_result_bundle/Data/a-first"
/usr/bin/printf '%s\n' 'hashed later' >"$mid_token_result_bundle/Data/z-later"
result_bundle_stability_token "$mid_token_result_bundle" >/dev/null \
  || { /usr/bin/printf '%s\n' 'Stable multi-entry token fixture was rejected.' >&2; exit 1; }
LECTUREBOARD_RELEASE_TEST_MODE=1
if result_bundle_stability_token "$mid_token_result_bundle" \
  Data/a-first Data/z-later >/dev/null; then
  /usr/bin/printf '%s\n' 'A previously hashed child changed mid-token was accepted.' >&2
  exit 1
fi
unset LECTUREBOARD_RELEASE_TEST_MODE
/usr/bin/grep -Fq 'mid-token-test-mutation' "$mid_token_result_bundle/Data/a-first" \
  || { /usr/bin/printf '%s\n' 'The deterministic mid-token mutation seam did not execute.' >&2; exit 1; }

post_digest_mutation_source="$root/Test-LectureBoardAI-2026.09.06_09-11-31-+0900.xcresult"
post_digest_mutation_copy="$root/post-digest-mutation-copy.xcresult"
/usr/bin/ditto --rsrc --extattr --acl "$result_bundle" "$post_digest_mutation_source"
/usr/bin/ditto --rsrc --extattr --acl "$result_bundle" "$post_digest_mutation_copy"
post_digest_expected="$(result_bundle_tree_digest_original \
  "$post_digest_mutation_source" "$source_root")"
post_digest_token="$(result_bundle_stability_token "$post_digest_mutation_source")"
post_digest_mutation_marker="$root/post-digest-mutation.marker"
result_bundle_tree_digest() {
  result_bundle_tree_digest_original "$@" || return 1
  if [[ "$1" == "$post_digest_mutation_source" \
    && ! -e "$post_digest_mutation_marker" ]]; then
    /usr/bin/printf '%s\n' 'mutation immediately after digest output' \
      >>"$post_digest_mutation_source/Data/payload"
    /usr/bin/touch "$post_digest_mutation_marker"
  fi
}
if result_bundle_pair_matches_digest "$post_digest_mutation_source" \
  "$post_digest_mutation_copy" "$source_root" "$post_digest_expected" \
  "$post_digest_token"; then
  /usr/bin/printf '%s\n' 'A source mutation immediately after digest output was accepted.' >&2
  exit 1
fi
[[ -f "$post_digest_mutation_marker" ]] \
  || { /usr/bin/printf '%s\n' 'The post-digest mutation seam did not execute.' >&2; exit 1; }
result_bundle_tree_digest() {
  result_bundle_tree_digest_original "$@"
}

ownership_normalized_source="$root/Test-LectureBoardAI-ownership-source.xcresult"
ownership_normalized_copy="$root/Test-LectureBoardAI-ownership-copy.xcresult"
/usr/bin/ditto --rsrc --extattr --acl "$result_bundle" "$ownership_normalized_source"
/usr/bin/ditto --rsrc --extattr --acl "$result_bundle" "$ownership_normalized_copy"
/usr/bin/chgrp -R 12 "$ownership_normalized_copy"
[[ "$(result_bundle_tree_digest "$ownership_normalized_source" "$source_root")" \
  == "$(result_bundle_tree_digest "$ownership_normalized_copy" "$source_root")" ]] \
  || { /usr/bin/printf '%s\n' 'A group-normalized result-bundle copy was rejected.' >&2; exit 1; }
/bin/chmod 600 "$ownership_normalized_copy/Data/payload"
if [[ "$(result_bundle_tree_digest "$ownership_normalized_source" "$source_root")" \
  == "$(result_bundle_tree_digest "$ownership_normalized_copy" "$source_root")" ]]; then
  /usr/bin/printf '%s\n' 'A result-bundle mode mismatch was ignored.' >&2
  exit 1
fi
/bin/chmod 644 "$ownership_normalized_copy/Data/payload"
/usr/bin/printf '%s\n' 'content mismatch' >>"$ownership_normalized_copy/Data/payload"
if [[ "$(result_bundle_tree_digest "$ownership_normalized_source" "$source_root")" \
  == "$(result_bundle_tree_digest "$ownership_normalized_copy" "$source_root")" ]]; then
  /usr/bin/printf '%s\n' 'A result-bundle content mismatch was ignored.' >&2
  exit 1
fi

(
  SECONDS=9000000000
  clock_seconds_before="$SECONDS"
  result_bundle_set_monotonic_now \
    || { /usr/bin/printf '%s\n' 'The production monotonic clock rejected a valid SECONDS value.' >&2; exit 1; }
  production_clock_first="$monotonic_now"
  clock_seconds_after="$SECONDS"
  (( production_clock_first >= clock_seconds_before * 1000000000 \
    && production_clock_first <= clock_seconds_after * 1000000000 )) \
    || { /usr/bin/printf '%s\n' 'The production monotonic clock is not bound to this Bash process SECONDS value.' >&2; exit 1; }
  /bin/sleep 2
  result_bundle_set_monotonic_now \
    || { /usr/bin/printf '%s\n' 'The production monotonic clock failed after a bounded wait.' >&2; exit 1; }
  (( monotonic_now - production_clock_first >= 1000000000 )) \
    || { /usr/bin/printf '%s\n' 'The production monotonic clock did not advance by at least one second.' >&2; exit 1; }
)
(
  SECONDS=9223372037
  if result_bundle_set_monotonic_now; then
    /usr/bin/printf '%s\n' 'The production monotonic clock accepted an overflowing SECONDS value.' >&2
    exit 1
  fi
)

fake_monotonic_now=0
result_bundle_set_monotonic_now() {
  fake_monotonic_now=$((fake_monotonic_now + 1000000000))
  monotonic_now="$fake_monotonic_now"
}

delayed_result_bundle="$root/Test-LectureBoardAI-2026.09.06_09-12-21-+0900.xcresult"
delayed_frozen_bundle="$root/delayed-frozen.xcresult"
/usr/bin/ditto --rsrc --extattr --acl "$result_bundle" "$delayed_result_bundle"
delayed_pause_count=0
result_bundle_stability_pause() {
  delayed_pause_count=$((delayed_pause_count + 1))
  if [[ "$delayed_pause_count" == 1 ]]; then
    /usr/bin/printf '%s\n' 'delayed xcresult service update' \
      >>"$delayed_result_bundle/Data/payload"
  fi
}
freeze_result_bundle_when_stable \
  "$delayed_result_bundle" "$delayed_frozen_bundle" "$source_root" \
  || { /usr/bin/printf '%s\n' 'A delayed but settling xcresult could not be frozen.' >&2; exit 1; }
[[ "$(result_bundle_tree_digest "$delayed_result_bundle" "$source_root")" \
  == "$(result_bundle_tree_digest "$delayed_frozen_bundle" "$source_root")" ]] \
  || { /usr/bin/printf '%s\n' 'The delayed xcresult freeze did not retain its settled bytes.' >&2; exit 1; }
/usr/bin/grep -Fq 'delayed xcresult service update' "$delayed_frozen_bundle/Data/payload" \
  || { /usr/bin/printf '%s\n' 'The delayed xcresult update was omitted from the frozen copy.' >&2; exit 1; }

slow_success_result_bundle="$root/Test-LectureBoardAI-2026.09.06_09-12-51-+0900.xcresult"
slow_success_frozen_bundle="$root/slow-success-frozen.xcresult"
slow_success_log="$root/slow-success.log"
/usr/bin/ditto --rsrc --extattr --acl "$result_bundle" "$slow_success_result_bundle"
slow_success_clock_calls=0
result_bundle_set_monotonic_now() {
  slow_success_clock_calls=$((slow_success_clock_calls + 1))
  if [[ "$slow_success_clock_calls" == 14 ]]; then
    monotonic_now=300000000000
  elif (( slow_success_clock_calls >= 15 )); then
    monotonic_now=$((500000000000 + (slow_success_clock_calls - 15) * 1000000000))
  else
    monotonic_now=$((slow_success_clock_calls * 1000000000))
  fi
}
result_bundle_stability_pause() { :; }
copy_result_bundle_for_freeze() {
  /usr/bin/ditto --rsrc --extattr --acl "$1" "$2"
}
freeze_result_bundle_when_stable \
  "$slow_success_result_bundle" "$slow_success_frozen_bundle" "$source_root" \
  2>"$slow_success_log" \
  || { /usr/bin/printf '%s\n' 'A consistent slow digest was rejected inside the bounded deadline.' >&2; exit 1; }
/usr/bin/grep -Fq 'phase=finalSealStarted' "$slow_success_log" \
  || { /usr/bin/printf '%s\n' 'The slow-success final seal was not diagnosed.' >&2; exit 1; }
[[ "$(result_bundle_tree_digest "$slow_success_result_bundle" "$source_root")" \
  == "$(result_bundle_tree_digest "$slow_success_frozen_bundle" "$source_root")" ]] \
  || { /usr/bin/printf '%s\n' 'The slow-success freeze accepted inconsistent bytes.' >&2; exit 1; }

expired_pair_result_bundle="$root/Test-LectureBoardAI-2026.09.06_09-12-56-+0900.xcresult"
expired_pair_frozen_bundle="$root/expired-pair-frozen.xcresult"
expired_pair_log="$root/expired-pair.log"
/usr/bin/ditto --rsrc --extattr --acl "$result_bundle" "$expired_pair_result_bundle"
expired_pair_clock_calls=0
result_bundle_set_monotonic_now() {
  expired_pair_clock_calls=$((expired_pair_clock_calls + 1))
  if [[ "$expired_pair_clock_calls" == 14 ]]; then
    monotonic_now=300000000000
  elif (( expired_pair_clock_calls >= 15 )); then
    monotonic_now=$((602000000000 + (expired_pair_clock_calls - 15) * 1000000000))
  else
    monotonic_now=$((expired_pair_clock_calls * 1000000000))
  fi
}
if freeze_result_bundle_when_stable \
  "$expired_pair_result_bundle" "$expired_pair_frozen_bundle" "$source_root" \
  2>"$expired_pair_log"; then
  /usr/bin/printf '%s\n' 'A consistent result pair beyond the bounded deadline was accepted.' >&2
  exit 1
fi
/usr/bin/grep -Fq 'failure=pairConsistentButDeadlineExceeded' "$expired_pair_log" \
  || { /usr/bin/printf '%s\n' 'The post-pair deadline rejection was not diagnosed exactly.' >&2; exit 1; }
[[ ! -e "$expired_pair_frozen_bundle" && ! -L "$expired_pair_frozen_bundle" ]] \
  || { /usr/bin/printf '%s\n' 'A post-deadline pair left a frozen candidate behind.' >&2; exit 1; }

seal_window_result_bundle="$root/Test-LectureBoardAI-2026.09.06_09-13-01-+0900.xcresult"
seal_window_frozen_bundle="$root/seal-window-frozen.xcresult"
seal_window_log="$root/seal-window.log"
seal_window_unrelated="$root/seal-window-unrelated"
/usr/bin/ditto --rsrc --extattr --acl "$result_bundle" "$seal_window_result_bundle"
/usr/bin/printf '%s\n' 'unrelated fixture' >"$seal_window_unrelated"
seal_window_source_digest="$(result_bundle_tree_digest "$seal_window_result_bundle" "$source_root")"
seal_window_clock_calls=0
seal_window_mutations=0
result_bundle_set_monotonic_now() {
  seal_window_clock_calls=$((seal_window_clock_calls + 1))
  monotonic_now=$((seal_window_clock_calls * 1000000000))
  if [[ -d "$seal_window_frozen_bundle" && ! -L "$seal_window_frozen_bundle" ]]; then
    seal_window_mutations=$((seal_window_mutations + 1))
    /usr/bin/printf '%s\n' 'destination mutation in the final clock window' \
      >>"$seal_window_frozen_bundle/Data/payload"
  fi
}
if freeze_result_bundle_when_stable \
  "$seal_window_result_bundle" "$seal_window_frozen_bundle" "$source_root" \
  2>"$seal_window_log"; then
  /usr/bin/printf '%s\n' 'A destination mutation in the final clock window was accepted.' >&2
  exit 1
fi
[[ "$seal_window_mutations" == 2 ]] \
  || { /usr/bin/printf '%s\n' 'The final clock-window mutation did not exercise both bounded retries.' >&2; exit 1; }
/usr/bin/grep -Fq 'retry=finalTokenMismatch' "$seal_window_log" \
  || { /usr/bin/printf '%s\n' 'The final clock-window mutation was not rejected by the final seal.' >&2; exit 1; }
[[ ! -e "$seal_window_frozen_bundle" && ! -L "$seal_window_frozen_bundle" ]] \
  || { /usr/bin/printf '%s\n' 'A final clock-window mutation left a frozen candidate behind.' >&2; exit 1; }
[[ -f "$seal_window_unrelated" ]] \
  || { /usr/bin/printf '%s\n' 'Final clock-window cleanup removed an unrelated sibling.' >&2; exit 1; }
[[ "$(result_bundle_tree_digest "$seal_window_result_bundle" "$source_root")" \
  == "$seal_window_source_digest" ]] \
  || { /usr/bin/printf '%s\n' 'Final clock-window cleanup changed the source result bundle.' >&2; exit 1; }

for result_freeze_log in "$slow_success_log" "$expired_pair_log" "$seal_window_log"; do
  if /usr/bin/grep -Fq "$root" "$result_freeze_log" \
    || /usr/bin/grep -Fq "$source_root" "$result_freeze_log"; then
    /usr/bin/printf '%s\n' 'Result-freeze diagnostics disclosed a fixture or source-root path.' >&2
    exit 1
  fi
  if /usr/bin/grep -Eq '[0-9A-Fa-f]{64}' "$result_freeze_log"; then
    /usr/bin/printf '%s\n' 'Result-freeze diagnostics disclosed a digest or token.' >&2
    exit 1
  fi
done

fake_monotonic_now=0
result_bundle_set_monotonic_now() {
  fake_monotonic_now=$((fake_monotonic_now + 1000000000))
  monotonic_now="$fake_monotonic_now"
}

copy_race_result_bundle="$root/Test-LectureBoardAI-2026.09.06_09-13-21-+0900.xcresult"
copy_race_frozen_bundle="$root/copy-race-frozen.xcresult"
/usr/bin/ditto --rsrc --extattr --acl "$result_bundle" "$copy_race_result_bundle"
copy_race_count=0
result_bundle_stability_pause() { :; }
copy_result_bundle_for_freeze() {
  /usr/bin/ditto --rsrc --extattr --acl "$1" "$2" || return 1
  copy_race_count=$((copy_race_count + 1))
  if [[ "$copy_race_count" == 1 ]]; then
    /usr/bin/printf '%s\n' 'source mutation during first freeze copy' \
      >>"$copy_race_result_bundle/Data/payload"
  fi
}
freeze_result_bundle_when_stable \
  "$copy_race_result_bundle" "$copy_race_frozen_bundle" "$source_root" \
  || { /usr/bin/printf '%s\n' 'A settling copy-time xcresult update could not be retried safely.' >&2; exit 1; }
[[ "$copy_race_count" == 2 ]] \
  || { /usr/bin/printf '%s\n' 'A copy-time xcresult mutation was not rejected exactly once.' >&2; exit 1; }
[[ "$(result_bundle_tree_digest "$copy_race_result_bundle" "$source_root")" \
  == "$(result_bundle_tree_digest "$copy_race_frozen_bundle" "$source_root")" ]] \
  || { /usr/bin/printf '%s\n' 'The copy-time retry accepted inconsistent result bytes.' >&2; exit 1; }
/usr/bin/grep -Fq 'source mutation during first freeze copy' \
  "$copy_race_frozen_bundle/Data/payload" \
  || { /usr/bin/printf '%s\n' 'The copy-time mutation was absent from the final frozen result.' >&2; exit 1; }

candidate_race_result_bundle="$root/Test-LectureBoardAI-2026.09.06_09-13-51-+0900.xcresult"
candidate_race_frozen_bundle="$root/candidate-race-frozen.xcresult"
/usr/bin/ditto --rsrc --extattr --acl "$result_bundle" "$candidate_race_result_bundle"
candidate_race_count=0
copy_result_bundle_for_freeze() {
  /usr/bin/ditto --rsrc --extattr --acl "$1" "$2" || return 1
  candidate_race_count=$((candidate_race_count + 1))
  if [[ "$candidate_race_count" == 1 ]]; then
    /usr/bin/printf '%s\n' 'candidate mutation during first freeze copy' >>"$2/Data/payload"
  fi
}
freeze_result_bundle_when_stable \
  "$candidate_race_result_bundle" "$candidate_race_frozen_bundle" "$source_root" \
  || { /usr/bin/printf '%s\n' 'A mutated freeze candidate could not be discarded and retried.' >&2; exit 1; }
[[ "$candidate_race_count" == 2 ]] \
  || { /usr/bin/printf '%s\n' 'A mutated freeze candidate was not rejected exactly once.' >&2; exit 1; }
[[ "$(result_bundle_tree_digest "$candidate_race_result_bundle" "$source_root")" \
  == "$(result_bundle_tree_digest "$candidate_race_frozen_bundle" "$source_root")" ]] \
  || { /usr/bin/printf '%s\n' 'The candidate retry accepted inconsistent result bytes.' >&2; exit 1; }
if /usr/bin/grep -Fq 'candidate mutation during first freeze copy' \
  "$candidate_race_frozen_bundle/Data/payload"; then
  /usr/bin/printf '%s\n' 'The rejected candidate mutation survived retry cleanup.' >&2
  exit 1
fi

cleanup_swap_result_bundle="$root/Test-LectureBoardAI-2026.09.06_09-13-56-+0900.xcresult"
cleanup_swap_frozen_bundle="$root/cleanup-swap-frozen.xcresult"
cleanup_swap_saved_bundle="$root/cleanup-swap-saved.xcresult"
/usr/bin/ditto --rsrc --extattr --acl "$result_bundle" "$cleanup_swap_result_bundle"
copy_result_bundle_for_freeze() {
  /usr/bin/ditto --rsrc --extattr --acl "$1" "$2"
}
result_bundle_pair_matches_digest() {
  if [[ "$2" == "$cleanup_swap_frozen_bundle" ]]; then
    /bin/mv "$cleanup_swap_frozen_bundle" "$cleanup_swap_saved_bundle"
    /bin/mkdir -p "$cleanup_swap_frozen_bundle/Data"
    /usr/bin/printf '%s\n' 'replacement victim' \
      >"$cleanup_swap_frozen_bundle/Data/do-not-delete"
    return 1
  fi
  result_bundle_pair_matches_digest_original "$@"
}
if freeze_result_bundle_when_stable "$cleanup_swap_result_bundle" \
  "$cleanup_swap_frozen_bundle" "$source_root"; then
  /usr/bin/printf '%s\n' 'A path-swapped retry candidate was accepted.' >&2
  exit 1
fi
[[ -f "$cleanup_swap_frozen_bundle/Data/do-not-delete" \
  && -d "$cleanup_swap_saved_bundle" ]] \
  || { /usr/bin/printf '%s\n' 'Retry cleanup deleted a path-swapped victim.' >&2; exit 1; }
result_bundle_pair_matches_digest() {
  result_bundle_pair_matches_digest_original "$@"
}

swapped_result_bundle="$root/Test-LectureBoardAI-2026.09.06_09-14-01-+0900.xcresult"
swapped_result_original="$root/swapped-result-original.xcresult"
swapped_result_frozen="$root/swapped-result-frozen.xcresult"
/usr/bin/ditto --rsrc --extattr --acl "$result_bundle" "$swapped_result_bundle"
swapped_result_pause_count=0
result_bundle_stability_pause() {
  swapped_result_pause_count=$((swapped_result_pause_count + 1))
  if [[ "$swapped_result_pause_count" == 1 ]]; then
    /bin/mv "$swapped_result_bundle" "$swapped_result_original"
    /usr/bin/ditto --rsrc --extattr --acl "$swapped_result_original" "$swapped_result_bundle"
  fi
}
if freeze_result_bundle_when_stable \
  "$swapped_result_bundle" "$swapped_result_frozen" "$source_root"; then
  /usr/bin/printf '%s\n' 'A replaced result-bundle root identity was accepted.' >&2
  exit 1
fi
[[ ! -e "$swapped_result_frozen" && ! -L "$swapped_result_frozen" ]] \
  || { /usr/bin/printf '%s\n' 'A root-identity rejection left a frozen candidate.' >&2; exit 1; }

parent_swap_result_bundle="$root/Test-LectureBoardAI-2026.09.06_09-14-11-+0900.xcresult"
parent_swap_root="$root/parent-swap-root"
parent_swap_original="$root/parent-swap-original"
parent_swap_frozen="$parent_swap_root/frozen.xcresult"
/usr/bin/ditto --rsrc --extattr --acl "$result_bundle" "$parent_swap_result_bundle"
/bin/mkdir "$parent_swap_root"
parent_swap_pause_count=0
result_bundle_stability_pause() {
  parent_swap_pause_count=$((parent_swap_pause_count + 1))
  if [[ "$parent_swap_pause_count" == 1 ]]; then
    /bin/mv "$parent_swap_root" "$parent_swap_original"
    /bin/mkdir "$parent_swap_root"
  fi
}
if freeze_result_bundle_when_stable \
  "$parent_swap_result_bundle" "$parent_swap_frozen" "$source_root"; then
  /usr/bin/printf '%s\n' 'A replaced freeze-parent identity was accepted.' >&2
  exit 1
fi
[[ ! -e "$parent_swap_frozen" && ! -L "$parent_swap_frozen" ]] \
  || { /usr/bin/printf '%s\n' 'A parent-identity rejection left a frozen candidate.' >&2; exit 1; }

changing_result_bundle="$root/Test-LectureBoardAI-2026.09.06_09-14-21-+0900.xcresult"
changing_frozen_bundle="$root/changing-frozen.xcresult"
/usr/bin/ditto --rsrc --extattr --acl "$result_bundle" "$changing_result_bundle"
changing_pause_count=0
result_bundle_stability_pause() {
  changing_pause_count=$((changing_pause_count + 1))
  /usr/bin/printf '%s\n' "$changing_pause_count" \
    >>"$changing_result_bundle/Data/payload"
}
copy_result_bundle_for_freeze() {
  /usr/bin/ditto --rsrc --extattr --acl "$1" "$2"
}
if freeze_result_bundle_when_stable \
  "$changing_result_bundle" "$changing_frozen_bundle" "$source_root"; then
  /usr/bin/printf '%s\n' 'A continuously changing result bundle was accepted.' >&2
  exit 1
fi
[[ ! -e "$changing_frozen_bundle" && ! -L "$changing_frozen_bundle" ]] \
  || { /usr/bin/printf '%s\n' 'A rejected changing result left a frozen candidate behind.' >&2; exit 1; }

query_source_bundle="$root/Test-LectureBoardAI-2026.09.06_09-15-21-+0900.xcresult"
query_frozen_bundle="$root/query-frozen.xcresult"
/usr/bin/ditto --rsrc --extattr --acl "$result_bundle" "$query_source_bundle"
result_bundle_stability_pause() { :; }
copy_result_bundle_for_freeze() {
  /usr/bin/ditto --rsrc --extattr --acl "$1" "$2"
}
freeze_result_bundle_when_stable \
  "$query_source_bundle" "$query_frozen_bundle" "$source_root" \
  || { /usr/bin/printf '%s\n' 'The raw result bundle could not be frozen before querying.' >&2; exit 1; }
query_digest_before="$(result_bundle_tree_digest "$query_frozen_bundle" "$source_root")"
run_result_bundle_queries() {
  /usr/bin/printf '%s\n' '{"fixture":"summary"}' >"$2"
  /usr/bin/printf '%s\n' '{"fixture":"build"}' >"$3"
  /usr/bin/printf '%s\n' '{"fixture":"action"}' >"$4"
  /usr/bin/printf '%s\n' 'lazy query index materialized' >>"$1/Data/database.sqlite3"
}
extract_result_bundle_query_outputs "$query_frozen_bundle" "$source_root" \
  "$query_digest_before" "$root/disposable-summary.json" \
  "$root/disposable-build.json" "$root/disposable-action.json" \
  || { /usr/bin/printf '%s\n' 'Disposable result queries were rejected.' >&2; exit 1; }
[[ "$(result_bundle_tree_digest "$query_frozen_bundle" "$source_root")" \
    == "$query_digest_before" \
  && ! -e "$query_source_bundle/Data/database.sqlite3" \
  && ! -e "$query_frozen_bundle/Data/database.sqlite3" ]] \
  || { /usr/bin/printf '%s\n' 'A disposable query mutated the source or authoritative frozen bundle.' >&2; exit 1; }
for query_output in "$root/disposable-summary.json" "$root/disposable-build.json" \
  "$root/disposable-action.json"; do
  [[ -f "$query_output" && ! -L "$query_output" ]] \
    || { /usr/bin/printf '%s\n' 'A disposable query output is missing.' >&2; exit 1; }
done
result_bundle_stability_pause() { /bin/sleep 1; }
result_bundle_set_monotonic_now() {
  result_bundle_set_monotonic_now_original
}
result_bundle_digest="$(result_bundle_tree_digest "$result_bundle" "$source_root")"
gate_log="$root/prepublication-gate.log"
/usr/bin/printf 'LectureBoard evidence transaction source commit: %s\n' \
  "$commit" >"$gate_log"
for stage_number in $(/usr/bin/seq 1 26); do
  /usr/bin/printf '[%s/26] fixture stage\n' "$stage_number" >>"$gate_log"
  if [[ "$stage_number" == 2 ]]; then
    /usr/bin/printf '%s\n' \
      '✔ Test run with 250 tests in 19 suites passed after 0.001 seconds.' >>"$gate_log"
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
  "{\"schema\":\"lectureboard.release-test-evidence.v1\",\"sourceCommit\":\"$commit\",\"generatedAt\":\"2026-09-06T00:00:00Z\",\"prepublicationGate\":{\"command\":\"./scripts/prepublish-check.sh\",\"result\":\"Passed\",\"passedStages\":26,\"totalStages\":26,\"logSha256\":\"$gate_log_digest\",\"scriptBlobOid\":\"dddddddddddddddddddddddddddddddddddddddd\"},\"coreTests\":{\"result\":\"Passed\",\"tests\":250,\"suites\":19,\"failed\":0,\"skipped\":0},\"nativeAppTests\":{\"result\":\"Passed\",\"authoritativeTests\":480,\"deviceRuns\":542,\"parameterizedTests\":14,\"parameterizedRuns\":76,\"failed\":0,\"skipped\":0,\"expectedFailures\":0,\"resultBundleName\":\"${result_bundle##*/}\",\"resultBundleTreeSha256\":\"$result_bundle_digest\"},\"environment\":{\"architecture\":\"arm64\",\"macOS\":\"26.6.2\",\"macOSBuild\":\"25G83\",\"xcode\":\"26.6\",\"xcodeBuild\":\"17F113\"},\"claimBoundary\":\"Automated source-candidate evidence only; no live PowerPoint, user acceptance, installation, publication, or public-redownload result is implied.\"}" \
  >"$valid_test_evidence"
release_test_evidence_is_valid "$valid_test_evidence" "$commit" \
  || { /usr/bin/printf '%s\n' 'Valid release test evidence was rejected.' >&2; exit 1; }
validated_evidence_digest="$(sha256 "$valid_test_evidence")"
regular_file_matches_sha256 "$valid_test_evidence" "$validated_evidence_digest" \
  || { /usr/bin/printf '%s\n' 'A byte-identical pinned evidence file was rejected.' >&2; exit 1; }
for pinned_mutation in authoritative-tests environment generated-at; do
  pinned_root="$root/pinned-$pinned_mutation"
  /bin/mkdir "$pinned_root"
  case "$pinned_mutation" in
    authoritative-tests)
      /usr/bin/sed 's/"authoritativeTests":480/"authoritativeTests":481/' \
        "$valid_test_evidence" >"$pinned_root/$release_test_evidence_name"
      ;;
    environment)
      /usr/bin/sed 's/"xcode":"26.6"/"xcode":"26.7"/' \
        "$valid_test_evidence" >"$pinned_root/$release_test_evidence_name"
      ;;
    generated-at)
      /usr/bin/sed 's/2026-09-06T00:00:00Z/2026-09-06T00:00:01Z/' \
        "$valid_test_evidence" >"$pinned_root/$release_test_evidence_name"
      ;;
  esac
  if regular_file_matches_sha256 "$pinned_root/$release_test_evidence_name" \
    "$validated_evidence_digest"; then
    /usr/bin/printf '%s\n' \
      "A post-validation $pinned_mutation evidence mutation retained the byte pin." >&2
    exit 1
  fi
done

exact_private_evidence="$root/exact-private-evidence"
/bin/mkdir "$exact_private_evidence"
/bin/cp "$valid_test_evidence" \
  "$exact_private_evidence/$release_test_evidence_name"
/bin/cp "$gate_log" "$exact_private_evidence/prepublication-gate.log"
/usr/bin/ditto --rsrc --extattr --acl "$result_bundle" \
  "$exact_private_evidence/${result_bundle##*/}"
private_evidence_directory_is_exact "$exact_private_evidence" "${result_bundle##*/}" \
  || { /usr/bin/printf '%s\n' 'An exact three-entry private evidence directory was rejected.' >&2; exit 1; }
/usr/bin/printf '%s\n' 'unexpected top-level bytes' >"$exact_private_evidence/extra.txt"
if private_evidence_directory_is_exact "$exact_private_evidence" "${result_bundle##*/}"; then
  /usr/bin/printf '%s\n' 'An extra private-evidence regular file was accepted.' >&2
  exit 1
fi
/bin/unlink "$exact_private_evidence/extra.txt"
/bin/ln -s "$gate_log" "$exact_private_evidence/extra-link"
if private_evidence_directory_is_exact "$exact_private_evidence" "${result_bundle##*/}"; then
  /usr/bin/printf '%s\n' 'An extra private-evidence symlink was accepted.' >&2
  exit 1
fi
/bin/unlink "$exact_private_evidence/extra-link"
second_private_result="$exact_private_evidence/Test-LectureBoardAI-2026.09.06_09-99-99-+0900.xcresult"
/bin/mkdir "$second_private_result"
if private_evidence_directory_is_exact "$exact_private_evidence" "${result_bundle##*/}"; then
  /usr/bin/printf '%s\n' 'A second private-evidence result bundle was accepted.' >&2
  exit 1
fi
/bin/rmdir "$second_private_result"
private_evidence_directory_is_exact "$exact_private_evidence" "${result_bundle##*/}" \
  || { /usr/bin/printf '%s\n' 'Exact private evidence was not restored after rejection fixtures.' >&2; exit 1; }

setup_post_handoff_fixture() {
  local fixture_name="$1"
  post_handoff_parent="$root/post-handoff-$fixture_name"
  post_handoff_stage="$post_handoff_parent/.lectureboard-v1-evidence.post-validation"
  post_handoff_output="$post_handoff_parent/published-evidence"
  post_handoff_result_name="Test-LectureBoardAI-2026.09.06_10-00-00-+0900.xcresult"
  /bin/mkdir -p "$post_handoff_stage/$post_handoff_result_name/Data"
  /usr/bin/printf '%s\n' '{"fixture":"post-handoff"}' \
    >"$post_handoff_stage/$release_test_evidence_name"
  /usr/bin/printf '%s\n' 'gate fixture' \
    >"$post_handoff_stage/prepublication-gate.log"
  /usr/bin/printf '%s\n' 'result fixture' \
    >"$post_handoff_stage/$post_handoff_result_name/Data/payload"
  /usr/bin/printf '%s\n' 'unrelated sibling' >"$post_handoff_parent/do-not-delete"
  post_handoff_evidence_digest="$(sha256 \
    "$post_handoff_stage/$release_test_evidence_name")"
  post_handoff_parent_identity="$(directory_identity "$post_handoff_parent")"
  post_handoff_stage_identity="$(directory_identity "$post_handoff_stage")"
  exec 9<"$post_handoff_parent"
  exec 8<"$post_handoff_stage"
  directory_descriptor_matches_identity 9 "$post_handoff_parent_identity" || return 1
  directory_descriptor_matches_identity 8 "$post_handoff_stage_identity" || return 1
  /bin/mv "$post_handoff_stage" "$post_handoff_output"
}
cleanup_post_handoff_fixture() {
  local cleanup_status=0
  cleanup_known_evidence_handoff \
    "$post_handoff_parent" "$post_handoff_parent_identity" \
    "$post_handoff_stage" "$post_handoff_output" "$post_handoff_stage_identity" 9 8 \
    || cleanup_status=$?
  exec 8<&-
  exec 9<&-
  [[ "$cleanup_status" == 0 ]]
}
published_evidence_content_is_valid() { :; }

setup_post_handoff_fixture output-inode-swap \
  || { /usr/bin/printf '%s\n' 'Output-swap handoff fixture setup failed.' >&2; exit 1; }
post_handoff_pause_marker="$root/output-inode-swap.pause"
post_handoff_validation_pause() {
  /usr/bin/touch "$post_handoff_pause_marker"
  /bin/mv "$post_handoff_output" "$post_handoff_stage"
  /bin/mkdir "$post_handoff_output"
  /usr/bin/printf '%s\n' 'replacement output' >"$post_handoff_output/do-not-delete"
}
if validate_published_evidence_handoff \
  "$post_handoff_parent" "$post_handoff_parent_identity" \
  "$post_handoff_stage" "$post_handoff_output" "$post_handoff_stage_identity" 9 8 \
  "$post_handoff_result_name" "$post_handoff_evidence_digest" "$source_root" "$commit"; then
  /usr/bin/printf '%s\n' 'A post-validation output-inode swap was accepted.' >&2
  exit 1
fi
[[ -f "$post_handoff_pause_marker" ]] \
  || { /usr/bin/printf '%s\n' 'Output-inode injection did not reach the validation seam.' >&2; exit 1; }
cleanup_post_handoff_fixture \
  || { /usr/bin/printf '%s\n' 'Known output inode was not cleaned after its swap.' >&2; exit 1; }
[[ ! -e "$post_handoff_stage" && -f "$post_handoff_output/do-not-delete" \
  && -f "$post_handoff_parent/do-not-delete" ]] \
  || { /usr/bin/printf '%s\n' 'Output-swap cleanup deleted replacement or unrelated content.' >&2; exit 1; }

setup_post_handoff_fixture parent-inode-swap \
  || { /usr/bin/printf '%s\n' 'Parent-swap handoff fixture setup failed.' >&2; exit 1; }
post_handoff_saved_parent="$root/post-handoff-parent-inode-swap.saved"
post_handoff_pause_marker="$root/parent-inode-swap.pause"
post_handoff_validation_pause() {
  /usr/bin/touch "$post_handoff_pause_marker"
  /bin/mv "$post_handoff_parent" "$post_handoff_saved_parent"
  /bin/mkdir -p "$post_handoff_output"
  /usr/bin/printf '%s\n' 'replacement parent output' >"$post_handoff_output/do-not-delete"
}
if validate_published_evidence_handoff \
  "$post_handoff_parent" "$post_handoff_parent_identity" \
  "$post_handoff_stage" "$post_handoff_output" "$post_handoff_stage_identity" 9 8 \
  "$post_handoff_result_name" "$post_handoff_evidence_digest" "$source_root" "$commit"; then
  /usr/bin/printf '%s\n' 'A post-validation parent-inode swap was accepted.' >&2
  exit 1
fi
[[ -f "$post_handoff_pause_marker" ]] \
  || { /usr/bin/printf '%s\n' 'Parent-inode injection did not reach the validation seam.' >&2; exit 1; }
cleanup_post_handoff_fixture \
  || { /usr/bin/printf '%s\n' 'Known output inode was not cleaned through its retained parent.' >&2; exit 1; }
[[ ! -e "$post_handoff_saved_parent/${post_handoff_output##*/}" \
  && -f "$post_handoff_saved_parent/do-not-delete" \
  && -f "$post_handoff_output/do-not-delete" ]] \
  || { /usr/bin/printf '%s\n' 'Parent-swap cleanup deleted replacement or unrelated content.' >&2; exit 1; }

setup_post_handoff_fixture extra-top-level-entry \
  || { /usr/bin/printf '%s\n' 'Extra-entry handoff fixture setup failed.' >&2; exit 1; }
post_handoff_pause_marker="$root/extra-top-level-entry.pause"
post_handoff_validation_pause() {
  /usr/bin/touch "$post_handoff_pause_marker"
  /usr/bin/printf '%s\n' 'late extra entry' >"$post_handoff_output/extra.txt"
}
if validate_published_evidence_handoff \
  "$post_handoff_parent" "$post_handoff_parent_identity" \
  "$post_handoff_stage" "$post_handoff_output" "$post_handoff_stage_identity" 9 8 \
  "$post_handoff_result_name" "$post_handoff_evidence_digest" "$source_root" "$commit"; then
  /usr/bin/printf '%s\n' 'A post-validation extra top-level entry was accepted.' >&2
  exit 1
fi
[[ -f "$post_handoff_pause_marker" ]] \
  || { /usr/bin/printf '%s\n' 'Extra-entry injection did not reach the validation seam.' >&2; exit 1; }
cleanup_post_handoff_fixture \
  || { /usr/bin/printf '%s\n' 'Known evidence inode was not cleaned after late mutation.' >&2; exit 1; }
[[ ! -e "$post_handoff_output" && -f "$post_handoff_parent/do-not-delete" ]] \
  || { /usr/bin/printf '%s\n' 'Extra-entry cleanup deleted unrelated sibling content.' >&2; exit 1; }

post_handoff_validation_pause() { :; }
setup_post_handoff_fixture final-token-gate-mutation \
  || { /usr/bin/printf '%s\n' 'Final-token handoff fixture setup failed.' >&2; exit 1; }
post_handoff_pause_marker="$root/final-token-gate-mutation.pause"
post_handoff_final_token_pause() {
  /usr/bin/touch "$post_handoff_pause_marker"
  /usr/bin/printf '%s\n' 'mutation in the final validation window' \
    >>"$post_handoff_output/prepublication-gate.log"
}
if validate_published_evidence_handoff \
  "$post_handoff_parent" "$post_handoff_parent_identity" \
  "$post_handoff_stage" "$post_handoff_output" "$post_handoff_stage_identity" 9 8 \
  "$post_handoff_result_name" "$post_handoff_evidence_digest" "$source_root" "$commit"; then
  /usr/bin/printf '%s\n' 'A gate-log mutation immediately before the final token was accepted.' >&2
  exit 1
fi
[[ -f "$post_handoff_pause_marker" ]] \
  || { /usr/bin/printf '%s\n' 'Final-token mutation did not reach its injection seam.' >&2; exit 1; }
cleanup_post_handoff_fixture \
  || { /usr/bin/printf '%s\n' 'Known evidence inode was not cleaned after final-window mutation.' >&2; exit 1; }
[[ ! -e "$post_handoff_output" && -f "$post_handoff_parent/do-not-delete" ]] \
  || { /usr/bin/printf '%s\n' 'Final-window cleanup deleted unrelated sibling content.' >&2; exit 1; }

post_handoff_final_token_pause() { :; }
published_evidence_content_is_valid() {
  published_evidence_content_is_valid_original "$@"
}
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
/bin/mkdir "$root/wrong-core-count"
/usr/bin/sed 's/"tests":250/"tests":251/' \
  "$valid_test_evidence" >"$root/wrong-core-count/$release_test_evidence_name"
if release_test_evidence_is_valid \
  "$root/wrong-core-count/$release_test_evidence_name" "$commit"; then
  /usr/bin/printf '%s\n' 'An off-by-one Core test count was accepted.' >&2
  exit 1
fi
/bin/mkdir "$root/inconsistent-runs"
/usr/bin/sed 's/"deviceRuns":542/"deviceRuns":543/' \
  "$valid_test_evidence" >"$root/inconsistent-runs/$release_test_evidence_name"
if release_test_evidence_is_valid \
  "$root/inconsistent-runs/$release_test_evidence_name" "$commit"; then
  /usr/bin/printf '%s\n' 'Inconsistent authoritative and parameterized run totals were accepted.' >&2
  exit 1
fi
/bin/mkdir "$root/core-boolean-count"
/usr/bin/sed 's/"suites":19,"failed":0,"skipped":0/"suites":19,"failed":false,"skipped":0/' \
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
  '{"title":"Test - LectureBoardAI","startTime":1788652700.0,"finishTime":1788652790.0,"devicesAndConfigurations":[{"device":{"architecture":"arm64","osBuildNumber":"25G83","osVersion":"26.6.2","platform":"macOS"},"expectedFailures":0,"failedTests":0,"passedTests":542,"skippedTests":0}],"expectedFailures":0,"failedTests":0,"passedTests":480,"result":"Passed","skippedTests":0,"statistics":[{"subtitle":"76 test runs","title":"14 tests ran with dynamic parameters"}],"totalTestCount":480}' \
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
/usr/bin/sed 's/"passedTests":480/"passedTests":477/' \
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
