#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
checker="$script_directory/check-release-definition.sh"
temporary_parent="${TMPDIR:-/tmp}"
fixture_root="$(mktemp -d "$temporary_parent/lectureboard-release-definition.XXXXXX")"

cleanup() {
  find "$fixture_root" -type f -delete
  find "$fixture_root" -depth -type d -empty -delete
}
trap cleanup EXIT

mkdir -p "$fixture_root/scripts" "$fixture_root/docs/adr"
cp "$checker" "$fixture_root/scripts/check-release-definition.sh"
cp "$script_directory/../CHANGELOG.md" "$fixture_root/CHANGELOG.md"
cp "$script_directory/../ROADMAP.md" "$fixture_root/ROADMAP.md"
cp "$script_directory/../README.md" "$fixture_root/README.md"
cp "$script_directory/../docs/roadmap-ja.md" "$fixture_root/docs/roadmap-ja.md"
cp "$script_directory/../docs/local-codex-handoff-ja.md" "$fixture_root/docs/local-codex-handoff-ja.md"
cp "$script_directory/../docs/v1-release-checklist.md" "$fixture_root/docs/v1-release-checklist.md"
cp "$script_directory/../docs/adr/0006-mit-license.md" \
  "$fixture_root/docs/adr/0006-mit-license.md"
cp "$script_directory/../docs/adr/0007-public-v1-completion.md" \
  "$fixture_root/docs/adr/0007-public-v1-completion.md"

"$fixture_root/scripts/check-release-definition.sh" >/dev/null

mv "$fixture_root/docs/v1-release-checklist.md" "$fixture_root/docs/v1-release-checklist.backup"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing v1 checklist.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/v1-release-checklist.backup" "$fixture_root/docs/v1-release-checklist.md"

cp "$fixture_root/ROADMAP.md" "$fixture_root/ROADMAP.backup"
sed 's/## Milestone 7 — Public v1.0.0 GitHub Release/## Milestone 7 — Removed/' \
  "$fixture_root/ROADMAP.backup" >"$fixture_root/ROADMAP.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing public v1 milestone.\n' >&2
  exit 1
fi
mv "$fixture_root/ROADMAP.backup" "$fixture_root/ROADMAP.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/Completion means publication of the public `v1.0.0` GitHub Release/Completion definition removed/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing README completion definition.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/The existing public repository and any alpha, beta, or release-candidate builds are intermediate milestones/Prerelease status removed/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted alpha, beta, and RC as non-intermediate milestones.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/docs/v1-release-checklist.md" \
  "$fixture_root/docs/v1-release-checklist.backup"
sed 's/The application uses the hardened runtime and an appropriate Developer ID Application signature/The application uses a release signature/' \
  "$fixture_root/docs/v1-release-checklist.backup" \
  >"$fixture_root/docs/v1-release-checklist.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing hardened-runtime gate.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/v1-release-checklist.backup" \
  "$fixture_root/docs/v1-release-checklist.md"

cp "$fixture_root/docs/v1-release-checklist.md" \
  "$fixture_root/docs/v1-release-checklist.backup"
sed 's/The artifact is downloaded from the public GitHub Release into a clean verification environment/The public release page is inspected/' \
  "$fixture_root/docs/v1-release-checklist.backup" \
  >"$fixture_root/docs/v1-release-checklist.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing public-artifact re-download gate.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/v1-release-checklist.backup" \
  "$fixture_root/docs/v1-release-checklist.md"

cp "$fixture_root/docs/v1-release-checklist.md" \
  "$fixture_root/docs/v1-release-checklist.backup"
sed 's/Developer ID signature, designated requirement, hardened runtime, notarization, stapling where applicable, and Gatekeeper acceptance are independently rechecked/Downloaded-artifact security rechecks removed/' \
  "$fixture_root/docs/v1-release-checklist.backup" \
  >"$fixture_root/docs/v1-release-checklist.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted missing downloaded-artifact security rechecks.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/v1-release-checklist.backup" \
  "$fixture_root/docs/v1-release-checklist.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
sed 's/Deterministic stable-frame and significant visual\/content-change classification with unit tests/Deterministic stable-frame and slide-change detection with unit tests/' \
  "$fixture_root/CHANGELOG.backup" >"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted an overclaim of implemented slide-change detection.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
sed 's/Build-specific historical synthetic PowerPoint evidence for static frame delivery, Vision execution, and pre-semantic dynamic calibration; not evidence for the current semantic build/Controlled synthetic PowerPoint runtime evidence for current static frame delivery and Vision execution/' \
  "$fixture_root/CHANGELOG.backup" >"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted historical runtime evidence as current-build evidence.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/docs/adr/0006-mit-license.md" \
  "$fixture_root/docs/adr/0006-mit-license.backup"
sed 's/Accepted for the initial public source repository; review remains required for materially changed v1.0.0 scope/Accepted for the alpha scaffold, pending institutional review before public publication/' \
  "$fixture_root/docs/adr/0006-mit-license.backup" \
  >"$fixture_root/docs/adr/0006-mit-license.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted the obsolete pre-publication review status.\n' >&2
  exit 1
fi

printf 'Release-definition regression fixtures passed.\n'
