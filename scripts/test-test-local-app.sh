#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/.." && pwd)"
app_test_script="$script_directory/test-local-app.sh"

/bin/bash -p -n "$app_test_script"

config_output="$("$app_test_script" --print-config)"

expect_config_line() {
  local expected_line="$1"
  if ! grep -Fxq "$expected_line" <<<"$config_output"; then
    printf 'Missing native-app-test configuration line: %s\n' "$expected_line" >&2
    exit 1
  fi
}

expect_config_line "REPOSITORY_ROOT=$repository_root"
expect_config_line "DERIVED_DATA_PATH=$repository_root/DerivedData/AppTests"
expect_config_line \
  "GENERATED_PROJECT_PATH=$repository_root/DerivedData/AppTests/GeneratedProject/LectureBoardAI.xcodeproj"
expect_config_line \
  "LOCAL_PACKAGE_LINK=$repository_root/DerivedData/AppTests/GeneratedProject/Packages"
expect_config_line "LOCAL_PACKAGE_TARGET=$repository_root/Packages"
expect_config_line \
  "ENTITLEMENTS_PATH=$repository_root/LectureBoardAI/Config/LectureBoardAI.entitlements"
expect_config_line \
  "GENERATED_ENTITLEMENTS_LINK=$repository_root/DerivedData/AppTests/GeneratedProject/LectureBoardAI/Config/LectureBoardAI.entitlements"
expect_config_line 'SCHEME=LectureBoardAI'
expect_config_line 'ARCHITECTURE=arm64'
expect_config_line 'CONFIGURATION=Debug'
expect_config_line 'SIGNATURE_TYPE=ad hoc'
expect_config_line 'ACTION=test'

if "$app_test_script" --unsupported >/dev/null 2>&1; then
  printf 'The native-app-test script accepted an unsupported argument.\n' >&2
  exit 1
fi

if "$app_test_script" --print-config unexpected >/dev/null 2>&1; then
  printf 'The native-app-test script accepted multiple arguments.\n' >&2
  exit 1
fi

printf 'Native-app-test script configuration tests passed.\n'
