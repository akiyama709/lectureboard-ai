#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/.." && pwd)"
test_derived_data="$repository_root/DerivedData/AppTests"
generated_project_directory="$test_derived_data/GeneratedProject"
generated_project="$generated_project_directory/LectureBoardAI.xcodeproj"
local_package_link="$generated_project_directory/Packages"
info_plist_file="$repository_root/LectureBoardAI/Config/Info.plist"
entitlements_file="$repository_root/LectureBoardAI/Config/LectureBoardAI.entitlements"
generated_config_directory="$generated_project_directory/LectureBoardAI/Config"
generated_info_plist_link="$generated_config_directory/Info.plist"
generated_entitlements_link="$generated_config_directory/LectureBoardAI.entitlements"
scheme="LectureBoardAI"
source_commit="$(
  /usr/bin/env -i \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    LC_ALL=C \
    GIT_CONFIG_NOSYSTEM=1 \
    GIT_CONFIG_GLOBAL=/dev/null \
    GIT_CONFIG_SYSTEM=/dev/null \
    GIT_NO_REPLACE_OBJECTS=1 \
    /usr/bin/git --no-replace-objects \
      -c core.hooksPath=/dev/null \
      -c core.attributesFile=/dev/null \
      -C "$repository_root" rev-parse --verify HEAD^{commit}
)" || { printf 'Native-app-test source commit could not be resolved.\n' >&2; exit 1; }
[[ "$source_commit" =~ ^[0-9a-f]{40}$ || "$source_commit" =~ ^[0-9a-f]{64}$ ]] \
  || { printf 'Native-app-test source commit is malformed.\n' >&2; exit 1; }

usage() {
  printf 'Usage: %s [--help|--print-config]\n' "$(basename -- "$0")"
}

print_config() {
  printf 'REPOSITORY_ROOT=%s\n' "$repository_root"
  printf 'DERIVED_DATA_PATH=%s\n' "$test_derived_data"
  printf 'GENERATED_PROJECT_PATH=%s\n' "$generated_project"
  printf 'LOCAL_PACKAGE_LINK=%s\n' "$local_package_link"
  printf 'LOCAL_PACKAGE_TARGET=%s\n' "$repository_root/Packages"
  printf 'INFO_PLIST_PATH=%s\n' "$info_plist_file"
  printf 'GENERATED_INFO_PLIST_LINK=%s\n' "$generated_info_plist_link"
  printf 'ENTITLEMENTS_PATH=%s\n' "$entitlements_file"
  printf 'GENERATED_ENTITLEMENTS_LINK=%s\n' "$generated_entitlements_link"
  printf 'SCHEME=%s\n' "$scheme"
  printf 'SOURCE_COMMIT=%s\n' "$source_commit"
  printf 'ARCHITECTURE=arm64\n'
  printf 'CONFIGURATION=Debug\n'
  printf 'SIGNATURE_TYPE=ad hoc\n'
  printf 'ACTION=test\n'
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
  printf 'Native app tests require macOS.\n' >&2
  exit 1
fi

for required_command in xcodegen xcodebuild plutil; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$required_command" >&2
    exit 1
  fi
done

if [[ ! -f "$info_plist_file" || -L "$info_plist_file" ]]; then
  printf 'The native-app-test Info.plist is missing or symbolic: %s\n' \
    "$info_plist_file" >&2
  exit 1
fi

if ! plutil -lint "$info_plist_file" >/dev/null; then
  printf 'The native-app-test Info.plist is invalid: %s\n' "$info_plist_file" >&2
  exit 1
fi

if [[ ! -f "$entitlements_file" || -L "$entitlements_file" ]]; then
  printf 'The native-app-test entitlements file is missing or symbolic: %s\n' \
    "$entitlements_file" >&2
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

printf 'Generating an isolated Xcode project for native app tests...\n'
xcodegen generate \
  --spec "$repository_root/project.yml" \
  --project "$generated_project_directory" \
  --project-root "$repository_root"

printf 'Running arm64 Debug native app tests with Xcode ad hoc signing...\n'
xcodebuild \
  -project "$generated_project" \
  -scheme "$scheme" \
  -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$test_derived_data" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  EXPANDED_CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=YES \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  LECTUREBOARD_RELEASE_COMMIT="$source_commit" \
  test
