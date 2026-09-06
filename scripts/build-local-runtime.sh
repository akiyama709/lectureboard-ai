#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/.." && pwd)"
signing_requirement_script="$script_directory/runtime-signing-requirement.sh"
runtime_derived_data="$repository_root/DerivedData/RuntimeBuild"
generated_project_directory="$runtime_derived_data/GeneratedProject"
generated_project="$generated_project_directory/LectureBoardAI.xcodeproj"
local_package_link="$generated_project_directory/Packages"
info_plist_file="$repository_root/LectureBoardAI/Config/Info.plist"
entitlements_file="$repository_root/LectureBoardAI/Config/LectureBoardAI.entitlements"
generated_config_directory="$generated_project_directory/LectureBoardAI/Config"
generated_info_plist_link="$generated_config_directory/Info.plist"
generated_entitlements_link="$generated_config_directory/LectureBoardAI.entitlements"
runtime_app="$runtime_derived_data/Build/Products/Debug/LectureBoard AI.app"
bundle_identifier="io.github.akiyama709.LectureBoardAI"
scheme="LectureBoardAI"
required_localizations=(en ja)
code_sign_identity="${LECTUREBOARD_CODE_SIGN_IDENTITY:-}"
development_team="${LECTUREBOARD_DEVELOPMENT_TEAM:-}"

source "$signing_requirement_script"

if [[ -n "$code_sign_identity" && -z "$development_team" ]]; then
  printf 'LECTUREBOARD_DEVELOPMENT_TEAM must be set with LECTUREBOARD_CODE_SIGN_IDENTITY.\n' >&2
  exit 64
fi

if [[ -z "$code_sign_identity" && -n "$development_team" ]]; then
  printf 'LECTUREBOARD_CODE_SIGN_IDENTITY must be set with LECTUREBOARD_DEVELOPMENT_TEAM.\n' >&2
  exit 64
fi

if [[ -n "$code_sign_identity" ]]; then
  if [[ "$code_sign_identity" == "-" ]]; then
    printf 'LECTUREBOARD_CODE_SIGN_IDENTITY must name a non-ad-hoc signing identity.\n' >&2
    exit 64
  fi

  if [[ ! "$development_team" =~ ^[A-Z0-9]{10}$ ]]; then
    printf 'LECTUREBOARD_DEVELOPMENT_TEAM must be a 10-character Apple team identifier.\n' >&2
    exit 64
  fi

  signing_mode="developer-identity"
else
  signing_mode="ad-hoc"
fi

usage() {
  printf 'Usage: %s [--help|--print-config]\n' "$(basename -- "$0")"
  printf '%s\n' \
    'Optional stable signing requires both LECTUREBOARD_CODE_SIGN_IDENTITY and' \
    'LECTUREBOARD_DEVELOPMENT_TEAM. The script does not discover or create identities.'
}

print_config() {
  printf 'REPOSITORY_ROOT=%s\n' "$repository_root"
  printf 'DERIVED_DATA_PATH=%s\n' "$runtime_derived_data"
  printf 'GENERATED_PROJECT_PATH=%s\n' "$generated_project"
  printf 'LOCAL_PACKAGE_LINK=%s\n' "$local_package_link"
  printf 'LOCAL_PACKAGE_TARGET=%s\n' "$repository_root/Packages"
  printf 'INFO_PLIST_PATH=%s\n' "$info_plist_file"
  printf 'GENERATED_INFO_PLIST_LINK=%s\n' "$generated_info_plist_link"
  printf 'ENTITLEMENTS_PATH=%s\n' "$entitlements_file"
  printf 'GENERATED_ENTITLEMENTS_LINK=%s\n' "$generated_entitlements_link"
  printf 'APP_PATH=%s\n' "$runtime_app"
  printf 'BUNDLE_IDENTIFIER=%s\n' "$bundle_identifier"
  printf 'ARCHITECTURE=arm64\n'
  printf 'CONFIGURATION=Debug\n'
  printf 'DEBUG_DYLIB=disabled\n'
  printf 'LOCALIZATIONS=en,ja\n'
  printf 'SIGNING_MODE=%s\n' "$signing_mode"
  if [[ "$signing_mode" == "ad-hoc" ]]; then
    printf 'SIGNATURE_TYPE=ad hoc\n'
    printf 'DESIGNATED_REQUIREMENT_KIND=per-build cdhash\n'
    printf 'SCREEN_RECORDING_PERMISSION=may require authorization again after rebuild\n'
    printf 'DISTRIBUTION_STATUS=not distribution signed or notarized\n'
  else
    printf 'SIGNATURE_TYPE=explicit developer identity\n'
    printf 'SIGNING_CREDENTIALS=explicit identity and team provided\n'
    printf 'DESIGNATED_REQUIREMENT_KIND=Apple certificate-bound requirement\n'
    printf 'SCREEN_RECORDING_PERMISSION=eligible for stable matching across rebuilds with the same identity and team\n'
    printf 'DISTRIBUTION_STATUS=not notarized by this script\n'
  fi
}

if (( $# > 1 )); then
  usage >&2
  exit 64
fi

case "${1:-}" in
  "")
    ;;
  --help)
    usage
    exit 0
    ;;
  --print-config)
    print_config
    exit 0
    ;;
  *)
    usage >&2
    exit 64
    ;;
esac

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'Runtime app builds require macOS.\n' >&2
  exit 1
fi

for required_command in xcodegen xcodebuild codesign plutil lipo tr; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$required_command" >&2
    exit 1
  fi
done


if [[ ! -f "$info_plist_file" || -L "$info_plist_file" ]]; then
  printf 'The runtime-build Info.plist is missing or symbolic: %s\n' \
    "$info_plist_file" >&2
  exit 1
fi

if ! plutil -lint "$info_plist_file" >/dev/null; then
  printf 'The runtime-build Info.plist is invalid: %s\n' "$info_plist_file" >&2
  exit 1
fi

if [[ ! -f "$entitlements_file" || -L "$entitlements_file" ]]; then
  printf 'The runtime-build entitlements file is missing or symbolic: %s\n' \
    "$entitlements_file" >&2
  exit 1
fi

if ! grep -Fq "PRODUCT_BUNDLE_IDENTIFIER: $bundle_identifier" "$repository_root/project.yml"; then
  printf 'The runtime bundle identifier does not match project.yml: %s\n' \
    "$bundle_identifier" >&2
  exit 1
fi

mkdir -p "$generated_project_directory"

if [[ -L "$local_package_link" ]]; then
  actual_package_target="$(readlink "$local_package_link")"
  if [[ "$actual_package_target" != "$repository_root/Packages" ]]; then
    printf 'Unexpected local-package link target: %s\n' "$actual_package_target" >&2
    exit 1
  fi
elif [[ -e "$local_package_link" ]]; then
  printf 'The local-package link path is occupied: %s\n' "$local_package_link" >&2
  exit 1
else
  ln -s "$repository_root/Packages" "$local_package_link"
fi

mkdir -p "$generated_config_directory"
if [[ -L "$generated_info_plist_link" ]]; then
  actual_info_plist_target="$(readlink "$generated_info_plist_link")"
  if [[ "$actual_info_plist_target" != "$info_plist_file" ]]; then
    printf 'Unexpected generated Info.plist link target: %s\n' \
      "$actual_info_plist_target" >&2
    exit 1
  fi
elif [[ -e "$generated_info_plist_link" ]]; then
  printf 'The generated Info.plist link path is occupied: %s\n' \
    "$generated_info_plist_link" >&2
  exit 1
else
  ln -s "$info_plist_file" "$generated_info_plist_link"
fi

if [[ -L "$generated_entitlements_link" ]]; then
  actual_entitlements_target="$(readlink "$generated_entitlements_link")"
  if [[ "$actual_entitlements_target" != "$entitlements_file" ]]; then
    printf 'Unexpected generated entitlements link target: %s\n' \
      "$actual_entitlements_target" >&2
    exit 1
  fi
elif [[ -e "$generated_entitlements_link" ]]; then
  printf 'The generated entitlements link path is occupied: %s\n' \
    "$generated_entitlements_link" >&2
  exit 1
else
  ln -s "$entitlements_file" "$generated_entitlements_link"
fi

printf 'Generating an isolated Xcode project for runtime verification...\n'
xcodegen generate \
  --spec "$repository_root/project.yml" \
  --project "$generated_project_directory" \
  --project-root "$repository_root"

signing_arguments=(
  CODE_SIGN_STYLE=Manual
  CODE_SIGNING_ALLOWED=YES
  CODE_SIGNING_REQUIRED=YES
)

if [[ "$signing_mode" == "ad-hoc" ]]; then
  signing_arguments+=(
    CODE_SIGN_IDENTITY=-
    EXPANDED_CODE_SIGN_IDENTITY=-
    DEVELOPMENT_TEAM=
  )
  printf 'Building the arm64 Debug runtime app with Xcode ad hoc signing...\n'
else
  signing_arguments+=(
    "CODE_SIGN_IDENTITY=$code_sign_identity"
    "DEVELOPMENT_TEAM=$development_team"
  )
  printf 'Building the arm64 Debug runtime app with the explicitly provided identity and team...\n'
fi

xcodebuild \
  -project "$generated_project" \
  -scheme "$scheme" \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$runtime_derived_data" \
  "${signing_arguments[@]}" \
  ENABLE_DEBUG_DYLIB=NO \
  clean \
  build

if [[ ! -d "$runtime_app" ]]; then
  printf 'Expected runtime app was not produced: %s\n' "$runtime_app" >&2
  exit 1
fi

info_plist="$runtime_app/Contents/Info.plist"
if [[ ! -f "$info_plist" ]]; then
  printf 'Runtime app Info.plist was not produced: %s\n' "$info_plist" >&2
  exit 1
fi

actual_bundle_identifier="$(plutil -extract CFBundleIdentifier raw -o - "$info_plist")"
if [[ "$actual_bundle_identifier" != "$bundle_identifier" ]]; then
  printf 'Unexpected runtime bundle identifier: %s\n' "$actual_bundle_identifier" >&2
  exit 1
fi

for localization in "${required_localizations[@]}"; do
  localized_strings="$runtime_app/Contents/Resources/$localization.lproj/Localizable.strings"
  if [[ ! -f "$localized_strings" ]]; then
    printf 'Runtime app localization was not produced: %s\n' "$localized_strings" >&2
    exit 1
  fi

  if ! plutil -lint "$localized_strings" >/dev/null; then
    printf 'Runtime app localization is not a valid property list: %s\n' \
      "$localized_strings" >&2
    exit 1
  fi
done

executable_name="$(plutil -extract CFBundleExecutable raw -o - "$info_plist")"
runtime_executable="$runtime_app/Contents/MacOS/$executable_name"
if [[ ! -f "$runtime_executable" ]]; then
  printf 'Runtime executable was not produced: %s\n' "$runtime_executable" >&2
  exit 1
fi

debug_dylib="$runtime_app/Contents/MacOS/$executable_name.debug.dylib"
if [[ -e "$debug_dylib" ]]; then
  printf 'Standalone runtime app unexpectedly contains a debug dylib: %s\n' \
    "$debug_dylib" >&2
  exit 1
fi

actual_architecture="$(lipo -archs "$runtime_executable")"
if [[ "$actual_architecture" != "arm64" ]]; then
  printf 'Unexpected runtime executable architecture: %s\n' "$actual_architecture" >&2
  exit 1
fi

signature_details="$(codesign --display --verbose=4 "$runtime_app" 2>&1)"
if ! grep -Fq "Identifier=$bundle_identifier" <<<"$signature_details"; then
  printf 'The code-signing identifier does not match the bundle identifier.\n' >&2
  exit 1
fi

requirement_details="$(codesign -d -r- "$runtime_app" 2>&1)"

if [[ "$signing_mode" == "ad-hoc" ]]; then
  if ! grep -Fq 'Signature=adhoc' <<<"$signature_details"; then
    printf 'The runtime app does not have an ad hoc signature.\n' >&2
    exit 1
  fi

  if ! grep -Eq '^# designated => cdhash H"[[:xdigit:]]{40}"$' \
    <<<"$requirement_details"; then
    printf 'The ad hoc runtime app does not have the expected per-build cdhash requirement.\n' >&2
    exit 1
  fi
else
  if grep -Fq 'Signature=adhoc' <<<"$signature_details"; then
    printf 'The runtime app unexpectedly has an ad hoc signature.\n' >&2
    exit 1
  fi

  if ! grep -Fq "TeamIdentifier=$development_team" <<<"$signature_details"; then
    printf 'The runtime app signature does not match the explicitly provided team.\n' >&2
    exit 1
  fi

  if grep -Fq 'cdhash H"' <<<"$requirement_details"; then
    printf 'The developer-signed runtime app unexpectedly has a cdhash-only requirement.\n' >&2
    exit 1
  fi

  if ! grep -Fq "designated => identifier \"$bundle_identifier\"" \
    <<<"$requirement_details" \
    || ! grep -Fq 'anchor apple generic' <<<"$requirement_details" \
    || ! grep -Eq 'certificate (leaf|[0-9]+)\[' <<<"$requirement_details"; then
    printf 'The runtime app does not have the expected Apple certificate-bound requirement.\n' >&2
    exit 1
  fi

  if ! runtime_requirement_is_team_bound \
    "$requirement_details" \
    "$development_team"; then
    printf 'The designated requirement is not bound to the explicitly provided team.\n' >&2
    exit 1
  fi
fi

printf 'Verifying the complete app bundle signature...\n'
codesign --verify --deep --strict --verbose=2 "$runtime_app"

printf 'Runtime app: %s\n' "$runtime_app"
printf 'Bundle identifier: %s\n' "$bundle_identifier"
printf 'Architecture: %s\n' "$actual_architecture"
printf 'Localizations: en, ja\n'
if [[ "$signing_mode" == "ad-hoc" ]]; then
  printf 'Signature type: ad hoc\n'
  printf 'Designated requirement: per-build cdhash (value omitted)\n'
  printf 'Screen recording permission: macOS may require authorization again after rebuild.\n'
  printf 'Distribution status: not distribution signed or notarized\n'
else
  printf 'Signature type: explicit developer identity\n'
  printf 'Designated requirement: Apple certificate-bound requirement\n'
  printf 'Screen recording permission: eligible for stable matching across rebuilds with the same identity and team.\n'
  printf 'Distribution status: not notarized by this script\n'
fi
