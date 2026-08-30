#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/.." && pwd)"
test_derived_data="$repository_root/DerivedData/AppTests"
generated_project_directory="$test_derived_data/GeneratedProject"
generated_project="$generated_project_directory/LectureBoardAI.xcodeproj"
local_package_link="$generated_project_directory/Packages"
scheme="LectureBoardAI"

usage() {
  printf 'Usage: %s [--help|--print-config]\n' "$(basename -- "$0")"
}

print_config() {
  printf 'REPOSITORY_ROOT=%s\n' "$repository_root"
  printf 'DERIVED_DATA_PATH=%s\n' "$test_derived_data"
  printf 'GENERATED_PROJECT_PATH=%s\n' "$generated_project"
  printf 'LOCAL_PACKAGE_LINK=%s\n' "$local_package_link"
  printf 'LOCAL_PACKAGE_TARGET=%s\n' "$repository_root/Packages"
  printf 'SCHEME=%s\n' "$scheme"
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

for required_command in xcodegen xcodebuild; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$required_command" >&2
    exit 1
  fi
done

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
  test
