#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
checker="$script_directory/check-publication-sources.sh"
temporary_parent="${TMPDIR:-/tmp}"
fixture_root="$(mktemp -d "$temporary_parent/lectureboard-publication-sources.XXXXXX")"

cleanup() {
  rm -rf -- "$fixture_root"
}
trap cleanup EXIT

mkdir -p \
  "$fixture_root/LectureBoardAI/Sources" \
  "$fixture_root/LectureBoardAI/Tests" \
  "$fixture_root/LectureBoardAI/Config" \
  "$fixture_root/Packages/LectureBoardCore/Sources" \
  "$fixture_root/Packages/LectureBoardCore/Tests" \
  "$fixture_root/scripts"
cp "$checker" "$fixture_root/scripts/check-publication-sources.sh"
printf 'struct AppFixture {}\n' > "$fixture_root/LectureBoardAI/Sources/AppFixture.swift"
printf 'struct AppFixtureTests {}\n' > "$fixture_root/LectureBoardAI/Tests/AppFixtureTests.swift"
printf 'struct CoreFixture {}\n' > "$fixture_root/Packages/LectureBoardCore/Sources/CoreFixture.swift"
printf 'struct CoreFixtureTests {}\n' > "$fixture_root/Packages/LectureBoardCore/Tests/CoreFixtureTests.swift"
printf '#!/usr/bin/env bash\n' > "$fixture_root/scripts/runtime-launch-preflight.sh"
printf 'import CoreGraphics\n' > "$fixture_root/scripts/runtime-window-server-probe.swift"
printf '#!/usr/bin/env bash\n' > "$fixture_root/scripts/test-runtime-launch-preflight.sh"
printf 'name: Fixture\n' > "$fixture_root/project.yml"
printf '<plist version="1.0"><dict/></plist>\n' \
  > "$fixture_root/LectureBoardAI/Config/Info.plist"
printf '<plist version="1.0"><dict/></plist>\n' \
  > "$fixture_root/LectureBoardAI/Config/LectureBoardAI.entitlements"

git -C "$fixture_root" init -q
git -C "$fixture_root" add \
  LectureBoardAI/Sources/AppFixture.swift \
  Packages/LectureBoardCore/Sources/CoreFixture.swift \
  project.yml \
  LectureBoardAI/Config/LectureBoardAI.entitlements \
  scripts/check-publication-sources.sh

failure_output="$fixture_root/failure-output.txt"
if "$fixture_root/scripts/check-publication-sources.sh" >"$failure_output" 2>&1; then
  printf 'The publication source check accepted an untracked runtime probe.\n' >&2
  exit 1
fi

for required_source in \
  LectureBoardAI/Tests/AppFixtureTests.swift \
  Packages/LectureBoardCore/Tests/CoreFixtureTests.swift \
  LectureBoardAI/Config/Info.plist \
  scripts/runtime-launch-preflight.sh \
  scripts/runtime-window-server-probe.swift \
  scripts/test-runtime-launch-preflight.sh; do
  if ! grep -Fq \
    "Required source is not included in Git: $required_source" \
    "$failure_output"; then
    printf 'The publication source check did not identify %s.\n' "$required_source" >&2
    exit 1
  fi
done

git -C "$fixture_root" add \
  LectureBoardAI/Tests/AppFixtureTests.swift \
  Packages/LectureBoardCore/Tests/CoreFixtureTests.swift \
  LectureBoardAI/Config/Info.plist \
  scripts/runtime-launch-preflight.sh \
  scripts/runtime-window-server-probe.swift \
  scripts/test-runtime-launch-preflight.sh
"$fixture_root/scripts/check-publication-sources.sh" >/dev/null

mv "$fixture_root/LectureBoardAI/Tests" \
  "$fixture_root/LectureBoardAI/Tests.unavailable"
enumeration_failure_output="$fixture_root/enumeration-failure-output.txt"
if "$fixture_root/scripts/check-publication-sources.sh" \
  >"$enumeration_failure_output" 2>&1; then
  printf 'The publication source check accepted an incomplete source enumeration.\n' >&2
  exit 1
fi
if ! grep -Fq 'Publication source enumeration failed.' \
  "$enumeration_failure_output"; then
  printf 'The publication source check did not report its source-enumeration failure.\n' >&2
  exit 1
fi
mv "$fixture_root/LectureBoardAI/Tests.unavailable" \
  "$fixture_root/LectureBoardAI/Tests"

printf 'Publication source tracking tests passed.\n'
