#!/bin/bash -p
case "$-" in *p*) ;; *) /usr/bin/printf '%s\n' 'Release shell entry requires Bash privileged mode.' >&2; exit 78 ;; esac
set -euo pipefail
export PATH='/usr/bin:/bin:/usr/sbin:/sbin'
export LC_ALL=C
unset CDPATH
umask 022

# The no-fee path is intentionally self-contained.  It never invokes GitHub,
# network clients, a GUI, Developer ID signing, notarization, or a fallback.
# Debug builds and test fixtures are never accepted by these production paths.
product='LectureBoard AI'
bundle_id='io.github.akiyama709.LectureBoardAI'
version='1.0.0'
tag='v1.0.0'
die() { /usr/bin/printf 'no-fee v1 release failed: %s\n' "$1" >&2; exit 1; }
usage() {
  /usr/bin/printf '%s\n' \
    "Usage: $(/usr/bin/basename -- "$0") prepare --source-dir DIR --tag v1.0.0 --commit OID --test-result FILE --output-dir DIR" \
    "       $(/usr/bin/basename -- "$0") verify --archive ZIP --checksum FILE --sbom FILE --provenance FILE --commit OID" \
    "       $(/usr/bin/basename -- "$0") compare-public --approved-archive ZIP --downloaded-archive ZIP --checksum FILE"
}
abs_dir() { [[ "$1" == /* && "$1" != '/' ]] || die "$2 must be an absolute non-root path"; }
regular() { [[ "$1" == /* && -f "$1" && ! -L "$1" ]] || die "$2 must be an absolute regular file"; }
oid() { [[ "$1" =~ ^[0-9a-fA-F]{40}$ || "$1" =~ ^[0-9a-fA-F]{64}$ ]] || die "$2 must be a full commit object identifier"; }
json_string() { [[ "$1" != *'"'* && "$1" != *$'\n'* && "$1" != *'\\'* ]] || die 'unsafe metadata value'; }
sha256() { /usr/bin/shasum -a 256 -- "$1" | /usr/bin/awk '{print $1}'; }
lower() { /usr/bin/tr '[:upper:]' '[:lower:]' <<<"$1"; }

# The receipt is a read-only, adjacent manifest emitted only after the isolated
# approved-commit build has itself passed the full app verification boundary.
app_manifest_sha() {
  /usr/bin/python3 -c 'import hashlib,os,stat,sys
r=sys.argv[1]; rows=[]
for b,ds,fs in os.walk(r,followlinks=False):
 ds.sort();fs.sort()
 for n in ds+fs:
  m=os.lstat(os.path.join(b,n)).st_mode
  if stat.S_ISLNK(m) or not (stat.S_ISREG(m) or stat.S_ISDIR(m)): raise SystemExit(1)
 for n in fs:
  p=os.path.join(b,n); q=os.path.relpath(p,r)
  if q.startswith("../") or "\\x00" in q: raise SystemExit(1)
  rows.append(q+"\\t%04o\\t"%stat.S_IMODE(os.lstat(p).st_mode)+hashlib.sha256(open(p,"rb").read()).hexdigest()+"\\n")
print(hashlib.sha256("".join(rows).encode()).hexdigest())' "$1" || die 'application manifest calculation failed'
}
write_build_receipt() {
  local out="$1" app="$2" manifest toolchain
  manifest="$(app_manifest_sha "$app")"; toolchain="$(/usr/bin/xcodebuild -version | /usr/bin/tr '\n' ' ')" || die 'toolchain identity unavailable'
  /usr/bin/python3 - "$out" "$commit" "$tag_expected" "$manifest" "$toolchain" <<'PY'
import json,sys
p,c,t,m,x=sys.argv[1:]
json.dump({"schema":"lectureboard.approved-isolated-build-receipt.v1","commit":c,"tag":t,"appRelativePath":"LectureBoard AI.app","appManifestSha256":m,"toolchain":x,"buildIsolation":"git-archive-approved-commit"},open(p,"w"),sort_keys=True,separators=(",",":"));open(p,"a").write("\n")
PY
  /bin/chmod 444 "$out" || die 'build receipt protection failed'
}
verify_build_receipt() {
  local receipt="$1" app="$2" m
  regular "$receipt" build-receipt
  [[ "${receipt##*/}" == approved-build-receipt.json && "$(/usr/bin/dirname -- "$app")/approved-build-receipt.json" == "$receipt" && ! -w "$receipt" ]] || die 'build receipt placement or protection invalid'
  m="$(app_manifest_sha "$app")"
  /usr/bin/python3 - "$receipt" "$commit" "$tag_expected" "$m" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
assert set(d)=={"schema","commit","tag","appRelativePath","appManifestSha256","toolchain","buildIsolation"}
assert d["schema"]=="lectureboard.approved-isolated-build-receipt.v1" and d["commit"]==sys.argv[2] and d["tag"]==sys.argv[3] and d["appRelativePath"]=="LectureBoard AI.app" and d["appManifestSha256"]==sys.argv[4] and d["buildIsolation"]=="git-archive-approved-commit" and isinstance(d["toolchain"],str) and d["toolchain"]
PY
  [[ $? == 0 ]] || die 'build receipt does not bind the handed-off application'
}

reject_production_overrides() {
  local n
  for n in BASH_ENV ENV GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM \
    GIT_CONFIG_COUNT GIT_CONFIG_KEY_0 GIT_CONFIG_VALUE_0 XCODE_XCCONFIG_FILE DEVELOPER_DIR SDKROOT \
    TOOLCHAINS SWIFT_EXEC CC CXX LD DYLD_LIBRARY_PATH DYLD_INSERT_LIBRARIES CODESIGN_ALLOCATE \
    TAR_OPTIONS ZIPOPT; do
    [[ -z "${!n:-}" ]] || die "production input cannot set $n"
  done
}

git_env=(/usr/bin/env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_NO_REPLACE_OBJECTS=1 GIT_ATTR_NOSYSTEM=1)
git_read() { "${git_env[@]}" /usr/bin/git --no-replace-objects -c core.hooksPath=/dev/null -c core.attributesFile=/dev/null "$@"; }

parse_args() {
  command="$1"; shift
  while (( $# )); do
    case "$1" in
      --source-dir|--output-dir|--app|--build-receipt|--archive|--approved-archive|--downloaded-archive|--commit|--tag|--test-result|--checksum|--sbom|--provenance)
        (( $# >= 2 )) || { usage >&2; exit 64; }
        case "$1" in
          --source-dir) key=source_dir;; --output-dir) key=output_dir;; --test-result) key=test_result;;
          --build-receipt) key=build_receipt;; --approved-archive) key=approved_archive;; --downloaded-archive) key=downloaded_archive;; --provenance) key=provenance;; *) key="${1#--}";;
        esac
        [[ -z "${!key+x}" ]] || die "duplicate --$key"; printf -v "$key" '%s' "$2"; shift 2;;
      --help) usage; exit 0;; *) usage >&2; exit 64;;
    esac
  done
}

verify_app() {
  local app="$1" expected_commit="$2" expected_tag_object="$3" info exe ent keys details components nested_details
  [[ "$app" == /* && -d "$app" && ! -L "$app" && "${app##*/}" == "$product.app" ]] || die 'application bundle path/name is invalid'
  info="$app/Contents/Info.plist"; exe="$app/Contents/MacOS/$product"
  regular "$info" 'application Info.plist'; [[ -x "$exe" && ! -L "$exe" ]] || die 'application executable is missing'
  [[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$info" 2>/dev/null)" == "$bundle_id" ]] || die 'bundle identifier is not exact'
  [[ "$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$info" 2>/dev/null)" == "$version" ]] || die 'marketing version is not exact'
  [[ "$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$info" 2>/dev/null)" =~ ^[1-9][0-9]*$ ]] || die 'build number is invalid'
  [[ "$(/usr/bin/plutil -extract LectureBoardReleaseCommit raw -o - "$info" 2>/dev/null)" == "$expected_commit" ]] || die 'bundle commit provenance is not exact'
  [[ "$(/usr/bin/plutil -extract LectureBoardReleaseTag raw -o - "$info" 2>/dev/null)" == "$tag_expected" ]] || die 'bundle tag provenance is not exact'
  [[ "$(/usr/bin/plutil -extract LectureBoardReleaseTagObject raw -o - "$info" 2>/dev/null)" == "$expected_tag_object" ]] || die 'bundle tag-object provenance is not exact'
  [[ -z "$(find "$app/Contents/MacOS" -maxdepth 1 -type f -name '*.debug.dylib' -o -name '__preview.dylib' 2>/dev/null)" ]] || die 'debug dylib is present'
  {
    details="$(/usr/bin/codesign -d --verbose=4 "$app" 2>&1)" || die 'codesign inspection failed'
    [[ "$details" == *'Signature=adhoc'* && "$details" == *'TeamIdentifier=not set'* ]] || die 'application is not ad hoc-only signed'
    [[ "$details" != *'Authority=Developer ID'* && "$details" != *'Authority=Apple Development'* && "$details" != *'Timestamp='* ]] || die 'Developer ID, development, or timestamp signature rejected'
    [[ "$details" == *'flags=0x10000'* || "$details" == *'(runtime)'* ]] || die 'hardened runtime flag is missing'
    [[ "$(/usr/bin/lipo -archs "$exe" 2>/dev/null)" == 'arm64' ]] || die 'application is not thin exact arm64'
    ent="$(/usr/bin/mktemp /private/tmp/lectureboard-entitlements.XXXXXX)" || die 'entitlement staging failed'
    if ! /usr/bin/codesign -d --entitlements :- "$app" >"$ent" 2>/dev/null; then /bin/unlink "$ent"; die 'entitlement inspection failed'; fi
    if ! /usr/bin/plutil -convert json -o - "$ent" | /usr/bin/python3 -c 'import json,sys
d=json.load(sys.stdin)
expected={"com.apple.security.automation.apple-events": True,"com.apple.security.device.audio-input": True}
if d != expected: raise SystemExit(1)' >/dev/null; then
      /bin/unlink "$ent"; die 'entitlements are not the exact release allowlist'
    fi
    /bin/unlink "$ent"
    /usr/bin/codesign --verify --deep --strict "$app" >/dev/null 2>&1 || die 'application signature strict verification failed'
    # Libraries are often non-executable files, so inspect every Mach-O object,
    # not merely files whose Unix mode happens to have an execute bit.
    components="$(/usr/bin/find "$app" -type f -print)" || die 'application Mach-O enumeration failed'
    while IFS= read -r component; do
      [[ -n "$component" ]] || continue
      [[ "$component" == "$exe" ]] && continue
      [[ "$(/usr/bin/file "$component")" == *'Mach-O'* ]] || continue
      [[ "$(/usr/bin/lipo -archs "$component" 2>/dev/null)" == 'arm64' ]] || die 'Mach-O is not thin exact arm64'
      /usr/bin/codesign --verify --strict "$component" >/dev/null 2>&1 || die 'nested executable signature verification failed'
      nested_details="$(/usr/bin/codesign -d --verbose=4 "$component" 2>&1)" || die 'nested executable signature inspection failed'
      [[ "$nested_details" == *'Signature=adhoc'* && "$nested_details" == *'TeamIdentifier=not set'* ]] || die 'nested executable is not ad hoc-only signed'
      [[ "$nested_details" != *'Authority=Developer ID'* && "$nested_details" != *'Authority=Apple Development'* && "$nested_details" != *'Timestamp='* ]] || die 'nested Developer ID, development, or timestamp signature rejected'
      [[ "$nested_details" == *'flags=0x10000'* || "$nested_details" == *'(runtime)'* ]] || die 'nested executable hardened runtime flag is missing'
      [[ "$nested_details" != *'get-task-allow'* && "$nested_details" != *'com.apple.security.cs.debugger'* ]] || die 'nested development entitlement present'
    done <<< "$components"
  }
}

build_production() {
  abs_dir "$source_dir" source-dir; abs_dir "$output_dir" output-dir; oid "$commit" commit; [[ "$tag" == "$tag_expected" ]] || die 'tag must be v1.0.0'; [[ ! -e "$output_dir" && ! -L "$output_dir" ]] || die 'output directory must not already exist'; reject_production_overrides
  [[ "$(git_read -C "$source_dir" rev-parse --show-toplevel)" == "$source_dir" ]] || die 'source-dir is not the worktree root'
  [[ "$(git_read -C "$source_dir" status --porcelain=v1)" == '' ]] || die 'source tree is dirty'
  target="$(git_read -C "$source_dir" rev-parse --verify "$tag^{commit}")" || die 'release tag cannot be resolved'; [[ "$target" == "$commit" ]] || die 'tag does not target approved commit'
  tag_object="$(git_read -C "$source_dir" rev-parse --verify "refs/tags/$tag")" || die 'release tag object cannot be resolved'; oid "$tag_object" tag-object
  [[ "$(git_read -C "$source_dir" cat-file -t "refs/tags/$tag")" == tag ]] || die 'release tag must be annotated'
  [[ -z "$(git_read -C "$source_dir" ls-tree -r --name-only "$commit" -- .gitattributes)" ]] || die 'tracked Git attributes are not allowed for release export'
  [[ ! -s "$source_dir/.git/info/attributes" ]] || die 'local Git attributes are not allowed for release export'
  temp="$(/usr/bin/mktemp -d /private/tmp/lectureboard-v1-build.XXXXXX)" || die 'temporary build root failed'
  /bin/mkdir "$temp/source"; (git_read -C "$source_dir" archive --format=tar "$commit" | /usr/bin/tar -xf - -C "$temp/source") || die 'isolated source extraction failed'
  [[ -z "$(/usr/bin/find "$temp/source" -type l -print -quit)" ]] || die 'isolated source contains a symbolic link'
  [[ -z "$(/usr/bin/find "$temp/source" \( -type b -o -type c -o -type p \) -print -quit)" ]] || die 'isolated source contains a special file'
  /usr/bin/xcodebuild -project "$temp/source/LectureBoardAI.xcodeproj" -scheme LectureBoardAI -configuration Release -sdk macosx -arch arm64 -derivedDataPath "$temp/DerivedData" \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION=1 CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM='' CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO ENABLE_HARDENED_RUNTIME=YES ENABLE_DEBUG_DYLIB=NO \
    LECTUREBOARD_RELEASE_COMMIT="$commit" LECTUREBOARD_RELEASE_TAG="$tag" LECTUREBOARD_RELEASE_TAG_OBJECT="$tag_object" build || die 'isolated Release build failed'
  built="$temp/DerivedData/Build/Products/Release/$product.app"; [[ -d "$built" ]] || die 'Release application output missing'; verify_app "$built" "$commit" "$tag_object"
  /bin/mkdir "$output_dir"; /usr/bin/ditto --rsrc --extattr --acl "$built" "$output_dir/$product.app" || die 'verified application handoff failed'; verify_app "$output_dir/$product.app" "$commit" "$tag_object"
  write_build_receipt "$output_dir/approved-build-receipt.json" "$output_dir/$product.app"
  verify_build_receipt "$output_dir/approved-build-receipt.json" "$output_dir/$product.app"
}

prepare_release() {
  local final_output_dir="$output_dir"
  regular "$test_result" test-result
  [[ ! -e "$final_output_dir" && ! -L "$final_output_dir" ]] \
    || die 'output directory must not already exist'
  handoff_root="$(/usr/bin/mktemp -d /private/tmp/lectureboard-v1-handoff.XXXXXX)" \
    || die 'temporary handoff root failed'
  output_dir="$handoff_root/approved"
  build_production
  app="$output_dir/$product.app"
  build_receipt="$output_dir/approved-build-receipt.json"
  output_dir="$final_output_dir"
  package_release
}

package_release() {
  abs_dir "$output_dir" output-dir; abs_dir "$source_dir" source-dir; regular "$test_result" test-result; oid "$commit" commit; [[ "$tag" == "$tag_expected" ]] || die 'tag must be v1.0.0'; [[ -d "$app" ]] || die 'application missing'; [[ ! -e "$output_dir" && ! -L "$output_dir" ]] || die 'output directory must not already exist';
  reject_production_overrides
  [[ "$(git_read -C "$source_dir" rev-parse --show-toplevel)" == "$source_dir" ]] || die 'source-dir is not the worktree root'
  [[ "$(git_read -C "$source_dir" status --porcelain=v1)" == '' ]] || die 'source tree is dirty'
  [[ "$(git_read -C "$source_dir" rev-parse --verify HEAD^{commit})" == "$commit" ]] || die 'source HEAD is not the approved commit'
  [[ "$(git_read -C "$source_dir" rev-parse --verify "$tag^{commit}")" == "$commit" ]] || die 'source tag is not bound to the approved commit'
  [[ "$(git_read -C "$source_dir" cat-file -t "refs/tags/$tag")" == tag ]] || die 'release tag must be annotated'
  tag_object="$(git_read -C "$source_dir" rev-parse --verify "refs/tags/$tag")" || die 'source tag object cannot be resolved'; oid "$tag_object" tag-object
  verify_app "$app" "$commit" "$tag_object"; verify_build_receipt "$build_receipt" "$app"; /bin/mkdir "$output_dir"; archive="$output_dir/LectureBoard-AI-v1.0.0-arm64.zip"; /usr/bin/ditto -c -k --keepParent --rsrc --extattr --acl "$app" "$archive" || die 'ZIP producer failed';
  archive_sha_pre="$(sha256 "$archive")"; /usr/bin/printf '%s  %s\n' "$archive_sha_pre" "${archive##*/}" >"$output_dir/SHA256SUMS" || die 'checksum producer failed'
  app_sha="$(sha256 "$app/Contents/MacOS/$product")"; archive_sha="$(sha256 "$archive")"; test_sha="$(sha256 "$test_result")"; json_string "$commit"
  toolchain="$(/usr/bin/xcodebuild -version | /usr/bin/tr '\n' ' ')" || die 'toolchain identity could not be read'
  [[ -n "$toolchain" ]] || die 'toolchain identity is empty'; json_string "$toolchain"
  created_at="$(/bin/date -u '+%Y-%m-%dT%H:%M:%SZ')" || die 'SBOM creation time unavailable'; json_string "$created_at"
  /usr/bin/printf '{\n  "spdxVersion":"SPDX-2.3",\n  "dataLicense":"CC0-1.0",\n  "SPDXID":"SPDXRef-DOCUMENT",\n  "name":"LectureBoard AI v1.0.0",\n  "documentNamespace":"https://github.com/akiyama709/lectureboard-ai/releases/download/v1.0.0/SBOM.spdx.json#%s",\n  "creationInfo":{"created":"%s","creators":["Tool: no-fee-release-v1.sh"]},\n  "packages":[{"SPDXID":"SPDXRef-Package-LectureBoardAI","name":"LectureBoard AI","versionInfo":"1.0.0","downloadLocation":"https://github.com/akiyama709/lectureboard-ai/releases/download/v1.0.0/%s","supplier":"Person: Tomohiro Akiyama","filesAnalyzed":false,"checksums":[{"algorithm":"SHA256","checksumValue":"%s"}],"licenseConcluded":"MIT","licenseDeclared":"MIT","copyrightText":"Copyright (c) 2026 Tomohiro Akiyama"}],\n  "documentDescribes":["SPDXRef-Package-LectureBoardAI"]\n}\n' "$commit" "$created_at" "${archive##*/}" "$archive_sha" >"$output_dir/SBOM.spdx.json" || die 'SBOM producer failed'
  /usr/bin/printf '{\n  "schema":"lectureboard.no-fee-provenance.v1",\n  "repository":"akiyama709/lectureboard-ai",\n  "tag":"%s",\n  "tagObject":"%s",\n  "commit":"%s",\n  "bundleIdentifier":"%s",\n  "version":"%s",\n  "architecture":"arm64",\n  "configuration":"Release",\n  "signature":"ad hoc",\n  "hardenedRuntime":true,\n  "entitlements":{"keys":["com.apple.security.automation.apple-events","com.apple.security.device.audio-input"],"canonicalJsonSha256":"2ef41daa1f5a828d3492e8e40efdd881b539169e6b1b95aad9be949c73de01b0"},\n  "toolchain":"%s",\n  "archive":{"name":"%s","sha256":"%s"},\n  "executableSha256":"%s",\n  "testResultSha256":"%s"\n}\n' "$tag" "$tag_object" "$commit" "$bundle_id" "$version" "$toolchain" "${archive##*/}" "$archive_sha" "$app_sha" "$test_sha" >"$output_dir/provenance.json" || die 'provenance producer failed'
  /usr/bin/python3 -m json.tool "$output_dir/SBOM.spdx.json" >/dev/null || die 'SBOM is not valid JSON'; /usr/bin/python3 -m json.tool "$output_dir/provenance.json" >/dev/null || die 'provenance is not valid JSON'; verify_archive "$archive" "$commit" "$output_dir/SHA256SUMS" "$output_dir/SBOM.spdx.json" "$output_dir/provenance.json" "$test_result"
}

verify_archive() {
  local archive="$1" expected_commit="$2" checksum="$3" sbom="$4" provenance="$5" expected_test="${6:-}" root entries expected_tag_object
  reject_production_overrides
  regular "$archive" archive; regular "$checksum" checksum; regular "$sbom" SBOM; regular "$provenance" provenance; oid "$expected_commit" commit
  [[ -z "$expected_test" ]] || regular "$expected_test" test-result
  [[ "${archive##*/}" == 'LectureBoard-AI-v1.0.0-arm64.zip' ]] || die 'archive filename is not exact'
  [[ "$(/usr/bin/awk 'END {print NR}' "$checksum")" == 1 ]] || die 'checksum file must contain exactly one line'
  expected_sha="$(/usr/bin/awk -v name="${archive##*/}" 'NF == 2 && $2 == name { print $1 }' "$checksum")"; [[ "$expected_sha" =~ ^[0-9a-f]{64}$ ]] || die 'checksum file malformed'; [[ "$(sha256 "$archive")" == "$expected_sha" ]] || die 'archive checksum mismatch'; /usr/bin/python3 -m json.tool "$sbom" >/dev/null || die 'SBOM invalid'; /usr/bin/python3 -m json.tool "$provenance" >/dev/null || die 'provenance invalid';
  [[ "$(/usr/bin/plutil -extract schema raw -o - "$provenance" 2>/dev/null)" == 'lectureboard.no-fee-provenance.v1' ]] || die 'provenance schema is not exact';
  [[ "$(/usr/bin/plutil -extract repository raw -o - "$provenance" 2>/dev/null)" == 'akiyama709/lectureboard-ai' ]] || die 'provenance repository is not exact';
  [[ "$(/usr/bin/plutil -extract tag raw -o - "$provenance" 2>/dev/null)" == "$tag_expected" ]] || die 'provenance tag is not exact';
  expected_tag_object="$(/usr/bin/plutil -extract tagObject raw -o - "$provenance" 2>/dev/null)" || die 'provenance tag object is absent'; oid "$expected_tag_object" tag-object
  [[ "$(/usr/bin/plutil -extract commit raw -o - "$provenance" 2>/dev/null)" == "$expected_commit" ]] || die 'provenance commit is not exact';
  [[ "$(/usr/bin/plutil -extract bundleIdentifier raw -o - "$provenance" 2>/dev/null)" == "$bundle_id" && "$(/usr/bin/plutil -extract version raw -o - "$provenance" 2>/dev/null)" == "$version" ]] || die 'provenance bundle metadata is not exact';
  [[ "$(/usr/bin/plutil -extract architecture raw -o - "$provenance" 2>/dev/null)" == arm64 && "$(/usr/bin/plutil -extract signature raw -o - "$provenance" 2>/dev/null)" == 'ad hoc' ]] || die 'provenance signing metadata is not exact';
  [[ "$(/usr/bin/plutil -extract hardenedRuntime raw -o - "$provenance" 2>/dev/null)" == true ]] || die 'provenance hardened-runtime claim is absent';
  [[ "$(/usr/bin/plutil -extract configuration raw -o - "$provenance" 2>/dev/null)" == Release && -n "$(/usr/bin/plutil -extract toolchain raw -o - "$provenance" 2>/dev/null)" ]] || die 'provenance toolchain binding is absent';
  /usr/bin/python3 - "$provenance" <<'PY'
import hashlib,json,sys
d=json.load(open(sys.argv[1]))
keys=["com.apple.security.automation.apple-events","com.apple.security.device.audio-input"]
e=d.get("entitlements")
assert isinstance(e,dict) and set(e)=={"keys","canonicalJsonSha256"} and e["keys"]==keys
canonical=json.dumps({key:True for key in keys},sort_keys=True,separators=(",",":"))
assert e["canonicalJsonSha256"]==hashlib.sha256(canonical.encode()).hexdigest()
PY
  [[ $? == 0 ]] || die 'provenance entitlement binding is not exact';
  if [[ -n "$expected_test" ]]; then [[ "$(/usr/bin/plutil -extract testResultSha256 raw -o - "$provenance" 2>/dev/null)" == "$(sha256 "$expected_test")" ]] || die 'provenance test-result binding is not exact'; fi
  [[ "$(/usr/bin/plutil -extract archive.name raw -o - "$provenance" 2>/dev/null)" == "${archive##*/}" && "$(/usr/bin/plutil -extract archive.sha256 raw -o - "$provenance" 2>/dev/null)" == "$(lower "$expected_sha")" ]] || die 'provenance archive binding is not exact';
  root="$(/usr/bin/mktemp -d /private/tmp/lectureboard-v1-verify.XXXXXX)" || die 'verification root failed'; trap '[[ -n "${root:-}" && -d "$root" ]] && /usr/bin/find "$root" -depth -delete' RETURN
  /usr/bin/python3 - "$archive" "$product.app" <<'PY'
import posixpath,stat,sys,unicodedata,zipfile
z=zipfile.ZipFile(sys.argv[1]); root=sys.argv[2]+'/'; seen=set()
for i in z.infolist():
 p=i.filename; n=unicodedata.normalize('NFC',p)
 if not p or p!=n or '\x00' in p or '\n' in p or p.startswith('/') or '\\' in p or n in seen or posixpath.normpath(n)!=n.rstrip('/') or n==root[:-1] or not n.startswith(root): raise SystemExit(1)
 seen.add(n); mode=i.external_attr>>16; kind=stat.S_IFMT(mode); directory=n.endswith('/')
 if stat.S_ISLNK(mode) or kind not in (0,stat.S_IFREG,stat.S_IFDIR) or (directory and kind not in (0,stat.S_IFDIR)) or (not directory and kind not in (0,stat.S_IFREG)) or mode&0o022 or i.flag_bits&1: raise SystemExit(1)
if root not in seen or root+'Contents/Info.plist' not in seen: raise SystemExit(1)
PY
  [[ $? == 0 ]] || die 'ZIP central-directory preflight failed'
  /usr/bin/ditto -x -k --rsrc --extattr --acl "$archive" "$root" || die 'ZIP extraction failed'; [[ -d "$root/$product.app" ]] || die 'extracted application missing'; [[ -z "$(/usr/bin/find "$root" -type l -print -quit)" ]] || die 'ZIP contains a symbolic link'; verify_app "$root/$product.app" "$expected_commit" "$expected_tag_object";
  exe_sha="$(sha256 "$root/$product.app/Contents/MacOS/$product")"; [[ "$(/usr/bin/plutil -extract executableSha256 raw -o - "$provenance" 2>/dev/null)" == "$exe_sha" ]] || die 'provenance executable binding is not exact';
  [[ "$(/usr/bin/plutil -extract spdxVersion raw -o - "$sbom" 2>/dev/null)" == 'SPDX-2.3' && "$(/usr/bin/plutil -extract documentNamespace raw -o - "$sbom" 2>/dev/null)" == "https://github.com/akiyama709/lectureboard-ai/releases/download/v1.0.0/SBOM.spdx.json#$expected_commit" && "$(/usr/bin/plutil -extract packages.0.name raw -o - "$sbom" 2>/dev/null)" == "$product" && "$(/usr/bin/plutil -extract packages.0.versionInfo raw -o - "$sbom" 2>/dev/null)" == "$version" && "$(/usr/bin/plutil -extract packages.0.licenseDeclared raw -o - "$sbom" 2>/dev/null)" == MIT && "$(/usr/bin/plutil -extract packages.0.checksums.0.algorithm raw -o - "$sbom" 2>/dev/null)" == SHA256 && "$(/usr/bin/plutil -extract packages.0.checksums.0.checksumValue raw -o - "$sbom" 2>/dev/null)" == "$expected_sha" ]] || die 'SBOM package metadata is not exact';
  [[ "$(/usr/bin/find "$root" -mindepth 1 -maxdepth 1 -type d | /usr/bin/wc -l | tr -d ' ')" == 1 ]] || die 'ZIP contains multiple root entries'; /usr/bin/printf '%s\n' 'no-fee v1 release verification passed'
}

cleanup_release_temporaries() {
  local candidate
  for candidate in "${temp:-}" "${handoff_root:-}"; do
    [[ -z "$candidate" || ! -d "$candidate" ]] && continue
    case "$candidate" in
      /private/tmp/lectureboard-v1-build.*|/private/tmp/lectureboard-v1-handoff.*)
        /usr/bin/find "$candidate" -depth -delete
        ;;
      *) /usr/bin/printf '%s\n' 'refusing to clean unexpected release temporary path' >&2 ;;
    esac
  done
}
trap cleanup_release_temporaries EXIT

command="${1:-}"; [[ -n "$command" ]] || { usage >&2; exit 64; }; unset source_dir output_dir app build_receipt approved_archive downloaded_archive commit tag test_result checksum sbom provenance; tag_expected='v1.0.0'; parse_args "$@"; [[ -z "${commit:-}" ]] || commit="$(lower "$commit")"; [[ -z "${LECTUREBOARD_RELEASE_TEST_MODE:-}" ]] || die 'production commands reject fixture mode'; case "$command" in
  prepare) [[ -n "${source_dir:-}" && -n "${output_dir:-}" && -n "${commit:-}" && -n "${tag:-}" && -n "${test_result:-}" ]] || { usage >&2; exit 64; }; prepare_release;;
  verify) [[ -n "${archive:-}" && -n "${checksum:-}" && -n "${sbom:-}" && -n "${provenance:-}" && -n "${commit:-}" ]] || { usage >&2; exit 64; }; verify_archive "$archive" "$commit" "$checksum" "$sbom" "$provenance" "${test_result:-}";;
  compare-public) regular "$approved_archive" approved-archive; regular "$downloaded_archive" downloaded-archive; regular "$checksum" checksum; [[ "${approved_archive##*/}" == 'LectureBoard-AI-v1.0.0-arm64.zip' && "${downloaded_archive##*/}" == 'LectureBoard-AI-v1.0.0-arm64.zip' ]] || die 'public comparison archive filename is not exact'; [[ "$(/usr/bin/awk 'END {print NR}' "$checksum")" == 1 ]] || die 'checksum file must contain exactly one line'; expected_sha="$(/usr/bin/awk -v name="${approved_archive##*/}" 'NF == 2 && $2 == name { print $1 }' "$checksum")"; [[ "$expected_sha" =~ ^[0-9a-f]{64}$ && "$(sha256 "$approved_archive")" == "$expected_sha" ]] || die 'approved archive checksum mismatch'; [[ "$(sha256 "$downloaded_archive")" == "$expected_sha" ]] || die 'public archive checksum mismatch'; /usr/bin/cmp -s -- "$approved_archive" "$downloaded_archive" || die 'public archive bytes differ from approved local archive'; /usr/bin/printf '%s\n' 'public redownload bytes exactly match approved local archive';;
  *) usage >&2; exit 64;; esac
