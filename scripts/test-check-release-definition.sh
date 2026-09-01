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
cp "$script_directory/../AGENTS.md" "$fixture_root/AGENTS.md"
cp "$script_directory/../CHANGELOG.md" "$fixture_root/CHANGELOG.md"
cp "$script_directory/../ROADMAP.md" "$fixture_root/ROADMAP.md"
cp "$script_directory/../README.md" "$fixture_root/README.md"
cp "$script_directory/../docs/architecture.md" "$fixture_root/docs/architecture.md"
cp "$script_directory/../docs/build-verification.md" "$fixture_root/docs/build-verification.md"
cp "$script_directory/../docs/development-plan.md" "$fixture_root/docs/development-plan.md"
cp "$script_directory/../docs/README.md" "$fixture_root/docs/README.md"
cp "$script_directory/../docs/roadmap-ja.md" "$fixture_root/docs/roadmap-ja.md"
cp "$script_directory/../docs/technical-design-ja.md" \
  "$fixture_root/docs/technical-design-ja.md"
cp "$script_directory/../docs/technical-design-detailed-ja.md" \
  "$fixture_root/docs/technical-design-detailed-ja.md"
cp "$script_directory/../docs/local-codex-handoff-ja.md" "$fixture_root/docs/local-codex-handoff-ja.md"
cp "$script_directory/../docs/v1-release-checklist.md" "$fixture_root/docs/v1-release-checklist.md"
cp "$script_directory/../docs/adr/0006-mit-license.md" \
  "$fixture_root/docs/adr/0006-mit-license.md"
cp "$script_directory/../docs/adr/0007-public-v1-completion.md" \
  "$fixture_root/docs/adr/0007-public-v1-completion.md"
cp "$script_directory/../docs/adr/0011-bound-dense-change-fresh-samples.md" \
  "$fixture_root/docs/adr/0011-bound-dense-change-fresh-samples.md"

"$fixture_root/scripts/check-release-definition.sh" >/dev/null

assert_rejects_provenance_overclaim() {
  local path="$1"
  local forbidden="$2"
  local label="$3"
  local backup="$path.provenance-backup"

  cp "$path" "$backup"
  printf '\n%s\n' "$forbidden" >>"$path"
  if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
    printf 'The release-definition check accepted an overstrong %s provenance claim.\n' \
      "$label" >&2
    exit 1
  fi
  mv "$backup" "$path"
}

assert_rejects_provenance_overclaim \
  "$fixture_root/AGENTS.md" \
  'validate exactly six controlled inputs spaced eight seconds apart against exactly six non-reused interval-contained revision events' \
  'AGENTS detail'
assert_rejects_provenance_overclaim \
  "$fixture_root/AGENTS.md" \
  'one strictly interval-bounded six-input run' \
  'AGENTS summary'
assert_rejects_provenance_overclaim \
  "$fixture_root/ROADMAP.md" \
  'strictly matched exactly six inputs spaced eight seconds apart' \
  'ROADMAP'
assert_rejects_provenance_overclaim \
  "$fixture_root/docs/architecture.md" \
  'It strictly matched exactly six inputs spaced eight seconds apart' \
  'architecture'
assert_rejects_provenance_overclaim \
  "$fixture_root/docs/adr/0011-bound-dense-change-fresh-samples.md" \
  'Exactly six inputs spaced eight seconds apart mapped to six non-reused events within their strict input intervals' \
  'ADR 0011'
assert_rejects_provenance_overclaim \
  "$fixture_root/docs/local-codex-handoff-ja.md" \
  '各input completion後から次input開始前，又は最終cutoff前へ厳密に対応付け' \
  'local handoff detail'
assert_rejects_provenance_overclaim \
  "$fixture_root/docs/local-codex-handoff-ja.md" \
  '8秒間隔6入力のstrict dynamic interval及びsingle-stroke／eraseを完了した' \
  'local handoff summary'
assert_rejects_provenance_overclaim \
  "$fixture_root/README.md" \
  'six strictly input-bounded revision intervals' \
  'README'

mv "$fixture_root/docs/v1-release-checklist.md" "$fixture_root/docs/v1-release-checklist.backup"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing v1 checklist.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/v1-release-checklist.backup" "$fixture_root/docs/v1-release-checklist.md"

mv "$fixture_root/docs/adr/0011-bound-dense-change-fresh-samples.md" \
  "$fixture_root/docs/adr/0011-bound-dense-change-fresh-samples.backup"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing ADR 0011.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/adr/0011-bound-dense-change-fresh-samples.backup" \
  "$fixture_root/docs/adr/0011-bound-dense-change-fresh-samples.md"

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
sed 's/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult/Test-LectureBoardAI-2026.09.01_22-41-57-+0900.xcresult/g' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a stale current gate pointer.\n' >&2
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

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/The current schema-11 source passes 153 Core tests in 15 suites, 259 native app tests in 30 suites/The current schema-10 source passes 153 Core tests in 15 suites, 259 native app tests in 30 suites/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a stale README current schema.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/The current schema-11 source passes 153 Core tests in 15 suites, 259 native app tests in 30 suites/The current schema-11 source passes 142 Core tests in 15 suites, 251 native app tests in 30 suites/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted stale README test counts.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/A shared bounded one-shot fresh-sample path for either an exact post-baseline coarse candidate or a pending dense candidate/A bounded one-shot fresh-sample path for a pending dense content-change candidate/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a dense-only README fresh-sample status.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/c7a73f7cb1bdcaa46ec216218883872d480630f7cf4ff177170f8d1906c14a3c/current-live-dynamic-report-removed/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted removal of the current live dynamic README evidence.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
printf '\nno capture or input occurred and no static report exists\n' \
  >>"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted stale locked-checkpoint wording.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
printf '\nlive current-source `SCScreenshotManager` attachments, timing, coarse confirmation, and post-erase behavior remain unverified\n' \
  >>"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted stale current post-erase wording.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/two aggregate visual revision events in separate ink and erase phases/a separately attributed post-erase content revision/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted stale English post-erase wording.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/Successful live `boundedFreshSample` confirmation through the shared exact-post-baseline-coarse or pending-dense one-shot path/Live PowerPoint behavior of the shared path, including whether it records a distinct post-erase revision/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a stale bounded-fresh live gate.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/取得timing及びone-shot確定は未検証です．現行continuous経路では別個の消去phase revisionを確認しましたが/取得timing及び消去後revisionは未検証です．/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted stale Japanese post-erase wording.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/docs/README.md" "$fixture_root/docs/README.backup"
sed 's/ADR 0011 — Bound one-shot samples to the current visual-change candidate/ADR 0011 — Bounded dense-change fresh samples/' \
  "$fixture_root/docs/README.backup" >"$fixture_root/docs/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted the stale ADR 0011 display title.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/README.backup" "$fixture_root/docs/README.md"

cp "$fixture_root/docs/build-verification.md" \
  "$fixture_root/docs/build-verification.backup"
sed 's/At that schema-10 checkpoint, this automated evidence had not established/This automated evidence does not establish that live PowerPoint supplies/' \
  "$fixture_root/docs/build-verification.backup" \
  >"$fixture_root/docs/build-verification.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted current-tense schema-10 history.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/build-verification.backup" \
  "$fixture_root/docs/build-verification.md"

cp "$fixture_root/docs/development-plan.md" \
  "$fixture_root/docs/development-plan.backup"
sed 's/Stable visual-frame detection and persistent visual-content-update detection/Stable-frame and slide-change detection/' \
  "$fixture_root/docs/development-plan.backup" \
  >"$fixture_root/docs/development-plan.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted semantic slide-change overclaim wording.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/development-plan.backup" \
  "$fixture_root/docs/development-plan.md"

cp "$fixture_root/docs/technical-design-ja.md" \
  "$fixture_root/docs/technical-design-ja.backup"
sed 's/現行ソースはschema 11のdecoder-hardened alpha scaffoldである/本準備環境で8件の自動テストが通過した/' \
  "$fixture_root/docs/technical-design-ja.backup" \
  >"$fixture_root/docs/technical-design-ja.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted the obsolete pre-Mac design status.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/technical-design-ja.backup" \
  "$fixture_root/docs/technical-design-ja.md"

cp "$fixture_root/docs/architecture.md" "$fixture_root/docs/architecture.backup"
sed 's/The earlier schema-9 live erase candidates did not receive the third qualifying observation/The live erase candidate did not receive the third qualifying observation/' \
  "$fixture_root/docs/architecture.backup" >"$fixture_root/docs/architecture.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted an unqualified historical erase result.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/architecture.backup" "$fixture_root/docs/architecture.md"

cp "$fixture_root/docs/technical-design-detailed-ja.md" \
  "$fixture_root/docs/technical-design-detailed-ja.backup"
sed 's/同一のpost-baseline coarse視覚差分候補又はdense内容更新候補がpendingである間だけ/同一のdense内容更新候補がpendingである間だけ/' \
  "$fixture_root/docs/technical-design-detailed-ja.backup" \
  >"$fixture_root/docs/technical-design-detailed-ja.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a dense-only detailed design.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/technical-design-detailed-ja.backup" \
  "$fixture_root/docs/technical-design-detailed-ja.md"

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
printf '\n- Deterministic stable-frame and slide-change detection with unit tests\n' \
  >>"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted an appended slide-change overclaim.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
sed 's/Metadata-only schema-11 latest-content-revision evidence with exact ordinal/Metadata-only revision evidence/' \
  "$fixture_root/CHANGELOG.backup" >"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted removal of the schema-11 changelog sentinel.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
sed 's/A shared bounded one-shot fresh-sample path for either an exact post-baseline coarse candidate or a pending dense candidate/A bounded one-shot fresh-sample path for a pending dense content-change candidate/' \
  "$fixture_root/CHANGELOG.backup" >"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a dense-only changelog fresh-sample status.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
sed 's/A byte-identical current runtime preserved as `LectureBoard AI Schema 11 Decoder Hardened Verification.app`/Current live runtime evidence removed/' \
  "$fixture_root/CHANGELOG.backup" >"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted removal of the current live changelog sentinel.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
sed 's/that schema-8 attempt did not verify dynamic slides or mouse ink/dynamic slides and mouse ink remain unverified/' \
  "$fixture_root/CHANGELOG.backup" >"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted current-tense schema-8 history.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
sed 's/including a controlled post-erase candidate confirmed by that source/including a separately identified post-erase rerun/' \
  "$fixture_root/CHANGELOG.backup" >"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted an ambiguous planned erase checkpoint.\n' >&2
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

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
printf '\n- Controlled synthetic PowerPoint runtime evidence for current static frame delivery and Vision execution\n' \
  >>"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted appended historical evidence as current evidence.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
sed 's/An exact-window-bound production PowerPoint slide-identity provider and live validation before actual slide transitions are claimed/PowerPoint slide identity is complete/' \
  "$fixture_root/CHANGELOG.backup" >"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted removal of the unverified production identity-provider gate.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
printf '\n- PowerPoint slide identity is complete\n' >>"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted an appended production-identity overclaim.\n' >&2
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
