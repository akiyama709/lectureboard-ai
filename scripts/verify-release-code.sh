#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail
export LC_ALL=C
export PATH='/usr/bin:/bin:/usr/sbin:/sbin'
unset CDPATH

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
requirement_policy="$script_directory/runtime-signing-requirement.sh"
artifact_tools="$script_directory/release-artifact-tools.sh"
expected_bundle_identifier='io.github.akiyama709.LectureBoardAI'
expected_macos_minimum_version='26.0'
developer_id_issuer_oid='1.2.840.113635.100.6.2.6'
developer_id_application_oid='1.2.840.113635.100.6.1.13'

fail() {
  printf 'Release code verification failed: %s\n' "$1" >&2
  exit 1
}

usage() {
  printf 'Usage: %s --kind app|dmg --path /absolute/path\n' "$(basename -- "$0")"
}

kind=''
target_path=''
kind_seen=0
path_seen=0
while (( $# > 0 )); do
  case "$1" in
    --kind)
      (( $# >= 2 )) || { usage >&2; exit 64; }
      (( kind_seen == 0 )) || { usage >&2; exit 64; }
      kind_seen=1
      kind="$2"
      shift 2
      ;;
    --path)
      (( $# >= 2 )) || { usage >&2; exit 64; }
      (( path_seen == 0 )) || { usage >&2; exit 64; }
      path_seen=1
      target_path="$2"
      shift 2
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 64
      ;;
  esac
done

[[ "$kind" == 'app' || "$kind" == 'dmg' ]] || { usage >&2; exit 64; }
[[ "$target_path" == /* ]] || fail 'the target path must be absolute'

expected_team_id="${LECTUREBOARD_DEVELOPMENT_TEAM:-}"
expected_identity_sha1="${LECTUREBOARD_DEVELOPER_ID_SHA1:-}"
expected_version="${LECTUREBOARD_RELEASE_VERSION:-}"
expected_build_number="${LECTUREBOARD_RELEASE_BUILD_NUMBER:-}"
expected_commit="${LECTUREBOARD_RELEASE_CI_COMMIT:-}"
expected_tag_object="${LECTUREBOARD_RELEASE_TAG_OBJECT:-}"
test_mode="${LECTUREBOARD_RELEASE_CODE_TEST_MODE:-}"
fixture_directory="${LECTUREBOARD_RELEASE_CODE_FIXTURE_DIR:-}"

[[ "$expected_team_id" =~ ^[A-Z0-9]{10}$ ]] \
  || fail 'LECTUREBOARD_DEVELOPMENT_TEAM must be a 10-character Apple team identifier'
[[ "$expected_identity_sha1" =~ ^[0-9A-Fa-f]{40}$ ]] \
  || fail 'LECTUREBOARD_DEVELOPER_ID_SHA1 must be a 40-digit SHA-1 fingerprint'
expected_identity_sha1="$(printf '%s' "$expected_identity_sha1" | tr '[:lower:]' '[:upper:]')"
if [[ "$kind" == 'app' ]]; then
  [[ "$expected_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
    || fail 'LECTUREBOARD_RELEASE_VERSION must be a three-component numeric version'
  [[ "$expected_build_number" =~ ^[1-9][0-9]*$ ]] \
    || fail 'LECTUREBOARD_RELEASE_BUILD_NUMBER must be a positive integer'
  [[ "$expected_commit" =~ ^[0-9A-Fa-f]{40}$|^[0-9A-Fa-f]{64}$ ]] \
    || fail 'LECTUREBOARD_RELEASE_CI_COMMIT must be a full commit object identifier'
  [[ "$expected_tag_object" =~ ^[0-9A-Fa-f]{40}$|^[0-9A-Fa-f]{64}$ ]] \
    || fail 'LECTUREBOARD_RELEASE_TAG_OBJECT must be a full annotated-tag object identifier'
  expected_commit="$(printf '%s' "$expected_commit" | /usr/bin/tr '[:lower:]' '[:upper:]')"
  expected_tag_object="$(printf '%s' "$expected_tag_object" | /usr/bin/tr '[:lower:]' '[:upper:]')"
fi

case "$test_mode" in
  '')
    [[ -z "$fixture_directory" ]] || fail 'fixture input requires explicit test mode'
    for forbidden_environment_variable in \
      BASH_ENV ENV DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH \
      DYLD_FALLBACK_LIBRARY_PATH DYLD_FALLBACK_FRAMEWORK_PATH DYLD_INSERT_LIBRARIES; do
      [[ -z "${!forbidden_environment_variable:-}" ]] \
        || fail 'production release-code verification forbids loader override inputs'
    done
    ;;
  fixture-v1)
    [[ "$fixture_directory" == /* && -d "$fixture_directory" ]] \
      || fail 'fixture-v1 requires an absolute fixture directory'
    ;;
  *) fail 'unsupported release-code test mode' ;;
esac

require_file() {
  [[ -f "$1" ]] || fail 'a required verification input is missing'
}

read_fixture() {
  local name="$1"
  require_file "$fixture_directory/$name"
  /bin/cat -- "$fixture_directory/$name"
}

temporary_root=''
temporary_parent="${TMPDIR:-/tmp}"
temporary_parent="${temporary_parent%/}"
cleanup() {
  if [[ -n "$temporary_root" && -d "$temporary_root" ]]; then
    case "$temporary_root" in
      "$temporary_parent"/lectureboard-release-code.*)
        /usr/bin/find "$temporary_root" -depth -delete
        ;;
    esac
  fi
}
trap cleanup EXIT

if [[ "$test_mode" == 'fixture-v1' ]]; then
  strict_status="$(read_fixture strict-verification-status.txt)"
  signature_details="$(read_fixture signature-details.txt)"
  requirement_details="$(read_fixture requirement-details.txt)"
  actual_identity_sha1="$(read_fixture leaf-certificate-sha1.txt)"
  entitlements_path="$fixture_directory/entitlements.plist"
  if [[ "$kind" == 'app' ]]; then
    code_layout_status="$(read_fixture code-layout-status.txt)"
    minimum_os_version="$(read_fixture minimum-os-version.txt)"
    bundle_identifier="$(read_fixture bundle-identifier.txt)"
    marketing_version="$(read_fixture marketing-version.txt)"
    build_number="$(read_fixture build-number.txt)"
    architecture="$(read_fixture architecture.txt)"
    embedded_commit="$(read_fixture embedded-commit.txt)"
    embedded_tag_object="$(read_fixture embedded-tag-object.txt)"
  fi
else
  [[ -e "$target_path" ]] || fail 'the release-code target does not exist'
  [[ -x /usr/bin/codesign && -x /usr/bin/openssl && -x /usr/bin/mktemp ]] \
    || fail 'required system code-verification tools are unavailable'
  if [[ "$kind" == 'app' ]]; then
    [[ -d "$target_path" && ! -L "$target_path" && "$target_path" == *.app ]] \
      || fail 'the app target must be an application bundle'
  else
    [[ -f "$target_path" && ! -L "$target_path" && "$target_path" == *.dmg ]] \
      || fail 'the dmg target must be a disk image file'
  fi

  if /usr/bin/codesign --verify --deep --strict=all --verbose=4 "$target_path" >/dev/null 2>&1; then
    strict_status='0'
  else
    strict_status='1'
  fi
  signature_details="$(/usr/bin/codesign --display --verbose=4 "$target_path" 2>&1)" \
    || fail 'code-signing details could not be read'
  requirement_details="$(/usr/bin/codesign --display --requirements - "$target_path" 2>&1)" \
    || fail 'the designated requirement could not be read'

  temporary_root="$(/usr/bin/mktemp -d "$temporary_parent/lectureboard-release-code.XXXXXX")" \
    || fail 'a temporary verification directory could not be created'
  case "$temporary_root" in
    "$temporary_parent"/lectureboard-release-code.*) ;;
    *) fail 'the temporary verification directory is unsafe' ;;
  esac
  certificate_prefix="$temporary_root/certificate"
  /usr/bin/codesign --display --extract-certificates "$certificate_prefix" "$target_path" \
    >/dev/null 2>&1 || fail 'the embedded signing certificate chain could not be extracted'
  require_file "${certificate_prefix}0"
  fingerprint_output="$(
    /usr/bin/openssl x509 -inform DER -in "${certificate_prefix}0" -noout -fingerprint -sha1 \
      2>/dev/null
  )" || fail 'the leaf signing-certificate fingerprint could not be read'
  actual_identity_sha1="${fingerprint_output#*=}"
  actual_identity_sha1="${actual_identity_sha1//:/}"

  entitlements_path="$temporary_root/entitlements.plist"
  : >"$entitlements_path"
  /usr/bin/codesign --display --xml --entitlements - "$target_path" \
    >"$entitlements_path" 2>/dev/null || fail 'embedded entitlements could not be read'

  if [[ "$kind" == 'app' ]]; then
    [[ -x /usr/bin/plutil && -x /usr/bin/lipo ]] \
      || fail 'required app metadata tools are unavailable'
    info_plist="$target_path/Contents/Info.plist"
    require_file "$info_plist"
    bundle_identifier="$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$info_plist" 2>/dev/null)" \
      || fail 'the app bundle identifier could not be read'
    marketing_version="$(/usr/bin/plutil -extract CFBundleShortVersionString raw -o - "$info_plist" 2>/dev/null)" \
      || fail 'the app marketing version could not be read'
    build_number="$(/usr/bin/plutil -extract CFBundleVersion raw -o - "$info_plist" 2>/dev/null)" \
      || fail 'the app build number could not be read'
    embedded_commit="$(/usr/bin/plutil -extract LectureBoardReleaseCommit raw -o - "$info_plist" 2>/dev/null)" \
      || fail 'the signed release commit provenance could not be read'
    embedded_tag_object="$(/usr/bin/plutil -extract LectureBoardReleaseTagObject raw -o - "$info_plist" 2>/dev/null)" \
      || fail 'the signed release-tag provenance could not be read'
    executable_name="$(/usr/bin/plutil -extract CFBundleExecutable raw -o - "$info_plist" 2>/dev/null)" \
      || fail 'the app executable name could not be read'
    [[ "$executable_name" =~ ^[A-Za-z0-9][A-Za-z0-9._\ -]*$ ]] \
      || fail 'the app executable name is malformed'
    executable_path="$target_path/Contents/MacOS/$executable_name"
    require_file "$executable_path"
    if [[ -f "$artifact_tools" ]] \
      && /usr/bin/env -u BASH_ENV -u ENV \
        PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C \
        /bin/bash -p "$artifact_tools" verify-app-code-layout \
          --app "$target_path" --main "$executable_path"; then
      code_layout_status='0'
    else
      code_layout_status='1'
    fi
    architecture="$(/usr/bin/lipo -archs "$executable_path" 2>/dev/null)" \
      || fail 'the app executable architecture could not be read'
    minimum_os_version="$(
      /usr/bin/env -u BASH_ENV -u ENV \
        PATH=/usr/bin:/bin:/usr/sbin:/sbin LC_ALL=C \
        /bin/bash -p "$artifact_tools" macos-min-version --path "$executable_path"
    )" || fail 'the app minimum macOS version could not be read'
  else
    code_layout_status='0'
    minimum_os_version=''
  fi
fi

[[ "$strict_status" == '0' ]] || fail 'strict complete-code signature verification did not pass'
grep -Fq 'Signature=adhoc' <<<"$signature_details" \
  && fail 'ad hoc signatures are not release signatures'
grep -Fq "TeamIdentifier=$expected_team_id" <<<"$signature_details" \
  || fail 'the signature team does not match the approved team'
authority_count="$(grep -Ec '^Authority=Developer ID Application:' <<<"$signature_details" || true)"
[[ "$authority_count" == '1' ]] || fail 'a Developer ID Application leaf authority is required'
grep -Eq '^Timestamp=.+$' <<<"$signature_details" \
  || fail 'a secure signing timestamp is required'
grep -Fqx 'Timestamp=none' <<<"$signature_details" \
  && fail 'a secure signing timestamp is required'
cdhash_count="$(grep -Ec '^CDHash=[0-9A-Fa-f]{40}$' <<<"$signature_details" || true)"
[[ "$cdhash_count" == '1' ]] || fail 'a single valid code-directory hash is required'
if [[ "$kind" == 'app' ]]; then
  grep -Eq '^CodeDirectory .*flags=.*\(runtime\)' <<<"$signature_details" \
    || fail 'the hardened-runtime code-directory flag is required'
  grep -Fq "Identifier=$expected_bundle_identifier" <<<"$signature_details" \
    || fail 'the signing identifier does not match the release bundle identifier'
fi

actual_identity_sha1="$(printf '%s' "$actual_identity_sha1" | tr '[:lower:]' '[:upper:]')"
[[ "$actual_identity_sha1" == "$expected_identity_sha1" ]] \
  || fail 'the embedded leaf certificate does not match the approved fingerprint'

[[ -f "$requirement_policy" && ! -L "$requirement_policy" ]] \
  || fail 'the runtime signing-requirement policy is missing or symbolic'
case "$-" in
  *p*) ;;
  *) fail 'the runtime signing-requirement policy may only be sourced by privileged Bash' ;;
esac
# This is the only sourced release helper. It is a function-only policy file,
# loaded from the fixed script directory after this privileged entrypoint has
# rejected loader overrides and established its bounded environment.
source "$requirement_policy"
runtime_requirement_is_team_bound "$requirement_details" "$expected_team_id" \
  || fail 'the designated requirement is not exclusively bound to the approved team'
grep -Fq "certificate 1[field.$developer_id_issuer_oid]" <<<"$requirement_details" \
  || fail 'the Developer ID issuer requirement is missing'
grep -Fq "certificate leaf[field.$developer_id_application_oid]" <<<"$requirement_details" \
  || fail 'the Developer ID Application leaf requirement is missing'

if [[ "$kind" == 'app' ]]; then
  [[ "$bundle_identifier" == "$expected_bundle_identifier" ]] \
    || fail 'the app bundle identifier is incorrect'
  [[ "$marketing_version" == "$expected_version" ]] \
    || fail 'the app marketing version does not match the release version'
  [[ "$build_number" == "$expected_build_number" ]] \
    || fail 'the app build number does not match the release build number'
  [[ "$embedded_commit" =~ ^[0-9A-Fa-f]{40}$|^[0-9A-Fa-f]{64}$ \
    && "$(printf '%s' "$embedded_commit" | /usr/bin/tr '[:lower:]' '[:upper:]')" == "$expected_commit" ]] \
    || fail 'the signed application is not bound to the approved release commit'
  [[ "$embedded_tag_object" =~ ^[0-9A-Fa-f]{40}$|^[0-9A-Fa-f]{64}$ \
    && "$(printf '%s' "$embedded_tag_object" | /usr/bin/tr '[:lower:]' '[:upper:]')" == "$expected_tag_object" ]] \
    || fail 'the signed application is not bound to the approved annotated tag object'
  [[ "$architecture" == 'arm64' ]] || fail 'the release app must contain exactly arm64 code'
  [[ "$minimum_os_version" == "$expected_macos_minimum_version" ]] \
    || fail 'the release app minimum macOS version must be exactly 26.0'
  [[ "$code_layout_status" == '0' ]] \
    || fail 'the application contains an invalid or undeclared executable-code layout'
  require_file "$entitlements_path"
  /usr/bin/plutil -lint "$entitlements_path" >/dev/null 2>&1 \
    || fail 'the embedded entitlement property list is malformed'
  [[ -x /usr/libexec/PlistBuddy ]] || fail 'PlistBuddy is required for entitlement verification'
  entitlement_key_count="$(grep -Ec '^[[:space:]]*<key>[^<]+</key>[[:space:]]*$' "$entitlements_path")"
  [[ "$entitlement_key_count" == '2' ]] \
    || fail 'the embedded entitlements differ from the exact two-key allowlist'
  for entitlement_key in \
    com.apple.security.automation.apple-events \
    com.apple.security.device.audio-input; do
    key_count="$(grep -Ec "^[[:space:]]*<key>${entitlement_key}</key>[[:space:]]*$" "$entitlements_path" || true)"
    [[ "$key_count" == '1' ]] || fail 'an approved release entitlement is missing or duplicated'
    entitlement_value="$(
      /usr/libexec/PlistBuddy -c "Print :$entitlement_key" "$entitlements_path" 2>/dev/null
    )" || fail 'an approved release entitlement could not be read'
    [[ "$entitlement_value" == 'true' ]] || fail 'an approved release entitlement is not true'
  done
else
  if [[ -s "$entitlements_path" ]]; then
    /usr/bin/plutil -lint "$entitlements_path" >/dev/null 2>&1 \
      || fail 'the disk image entitlement property list is malformed'
    entitlement_dictionary="$(
      /usr/libexec/PlistBuddy -c Print "$entitlements_path" 2>/dev/null
    )" || fail 'the disk image entitlement dictionary could not be read'
    [[ "$entitlement_dictionary" == $'Dict {\n}' ]] \
      || fail 'the disk image signature has unexpected entitlements'
  fi
fi

if [[ "$test_mode" == 'fixture-v1' ]]; then
  printf 'Release code fixture simulation passed; production verification was not established.\n'
else
  printf 'Release code verification passed for the exact %s bytes.\n' "$kind"
fi
