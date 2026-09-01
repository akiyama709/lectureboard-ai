#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    printf 'Required release document is missing: %s\n' "$path" >&2
    exit 1
  fi
}

require_text() {
  local path="$1"
  local expected="$2"
  if ! grep -F -- "$expected" "$path" >/dev/null; then
    printf 'Required release definition is missing from %s: %s\n' "$path" "$expected" >&2
    exit 1
  fi
}

reject_text() {
  local path="$1"
  local forbidden="$2"
  if grep -F -- "$forbidden" "$path" >/dev/null; then
    printf 'Known release overclaim is present in %s: %s\n' "$path" "$forbidden" >&2
    exit 1
  fi
}

required_files=(
  AGENTS.md
  CHANGELOG.md
  ROADMAP.md
  README.md
  docs/architecture.md
  docs/build-verification.md
  docs/development-plan.md
  docs/README.md
  docs/roadmap-ja.md
  docs/technical-design-ja.md
  docs/technical-design-detailed-ja.md
  docs/local-codex-handoff-ja.md
  docs/v1-release-checklist.md
  docs/adr/0006-mit-license.md
  docs/adr/0007-public-v1-completion.md
  docs/adr/0011-bound-dense-change-fresh-samples.md
)

for required_file in "${required_files[@]}"; do
  require_file "$required_file"
done

require_text ROADMAP.md 'Project completion means publishing a public `v1.0.0` GitHub Release'
require_text ROADMAP.md 'Alpha, beta, and release-candidate builds are intermediate validation gates'
require_text ROADMAP.md '## Milestone 5 — Beta gate'
require_text ROADMAP.md '## Milestone 6 — Release candidate'
require_text ROADMAP.md 'Apply Developer ID distribution signing and hardened runtime'
require_text ROADMAP.md '## Milestone 7 — Public v1.0.0 GitHub Release'
require_text ROADMAP.md 'Re-download the public artifact and independently verify its checksum, signature, notarization, installation, and launch'
require_text README.md 'Completion means publication of the public `v1.0.0` GitHub Release'
require_text README.md 'The existing public repository and any alpha, beta, or release-candidate builds are intermediate milestones'
require_text README.md 'The current schema-11 source passes 153 Core tests in 15 suites, 259 native app tests in 30 suites'
require_text README.md 'A shared bounded one-shot fresh-sample path for either an exact post-baseline coarse candidate or a pending dense candidate'
require_text README.md 'Schema 11 is the current source format and adds `latestContentRevisionEvent`'
require_text README.md 'negative, missing, malformed, unknown, or inconsistent schema-11 evidence fails decoding'
require_text AGENTS.md 'DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult'
require_text AGENTS.md 'The paired operator-captured helper sidecar'
require_text ROADMAP.md 'DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult'
require_text ROADMAP.md 'supports input-window attribution for those events under the controlled eight-second schedule'
require_text README.md 'The synchronized decoder-hardened automated gate result is `DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult`'
require_text README.md 'a6407496c7bd0044c3f30982e749a5556bd2b8e9a751ebd7ed476f59e9151cc9'
require_text README.md 'Those later results remain specific to its pre-decoder-hardening bytes and do not verify the current source'
require_text README.md 'The current decoder-hardened app'
require_text README.md 'The helper sidecar is operator-captured and is not cryptographically bound to the runtime report'
require_text README.md 'sidecarはruntime reportへ暗号的に結合されておらず，release-grade provenanceではありません'
require_text README.md 'c7a73f7cb1bdcaa46ec216218883872d480630f7cf4ff177170f8d1906c14a3c'
require_text README.md '70e5772d5d4e8ab8947c725b854749fe2743b38f9189434530de2f0ad9aa63a1'
require_text README.md '`boundedFreshSample` was not exercised'
require_text README.md 'two aggregate visual revision events in separate ink and erase phases'
require_text README.md 'Successful live `boundedFreshSample` confirmation through the shared exact-post-baseline-coarse or pending-dense one-shot path'
require_text README.md '現行schema 11 sourceは，開発用Mac上でCore 153件・15 suite，native App 259件・30 suite'
require_text README.md '現行continuous経路では別個の消去phase revisionを確認しましたが'
require_text docs/architecture.md 'The earlier schema-9 live erase candidates did not receive the third qualifying observation'
require_text docs/architecture.md 'DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult'
require_text docs/architecture.md 'The paired operator-captured helper sidecar'
require_text docs/build-verification.md 'At that schema-10 checkpoint, this automated evidence had not established'
require_text docs/build-verification.md 'DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult'
require_text docs/development-plan.md 'image differences and content revisions are not semantic slide identity'
require_text docs/development-plan.md 'a live current-build event sourced from `boundedFreshSample` has not yet been observed'
require_text docs/README.md 'ADR 0011 — Bound one-shot samples to the current visual-change candidate'
require_text docs/technical-design-ja.md '現行ソースはschema 11のdecoder-hardened alpha scaffoldである'
require_text docs/technical-design-ja.md '153件のCoreテスト（15 suites），259件のnative appテスト（30 suites）'
require_text docs/technical-design-ja.md 'live `boundedFreshSample`を裏付けるものではない'
require_text docs/technical-design-ja.md 'DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult'
require_text docs/technical-design-detailed-ja.md '同一のpost-baseline coarse視覚差分候補又はdense内容更新候補がpendingである間だけ'
require_text docs/technical-design-detailed-ja.md '`boundedFreshSample`は発生しなかった'
require_text CHANGELOG.md 'Deterministic stable-frame and significant visual/content-change classification with unit tests'
require_text CHANGELOG.md 'Build-specific historical synthetic PowerPoint evidence for static frame delivery, Vision execution, and pre-semantic dynamic calibration; not evidence for the current semantic build'
require_text CHANGELOG.md 'An exact-window-bound production PowerPoint slide-identity provider and live validation before actual slide transitions are claimed'
require_text CHANGELOG.md 'Metadata-only schema-11 latest-content-revision evidence with exact ordinal'
require_text CHANGELOG.md 'fail-closed decoding for negative counts'
require_text CHANGELOG.md 'A shared bounded one-shot fresh-sample path for either an exact post-baseline coarse candidate or a pending dense candidate'
require_text CHANGELOG.md 'Current decoder-hardened automated verification on the development Mac: 153 Core tests in 15 suites, 259 native app tests in 30 suites'
require_text CHANGELOG.md 'A byte-identical current runtime preserved as `LectureBoard AI Schema 11 Decoder Hardened Verification.app`'
require_text CHANGELOG.md 'c7a73f7cb1bdcaa46ec216218883872d480630f7cf4ff177170f8d1906c14a3c'
require_text CHANGELOG.md '70e5772d5d4e8ab8947c725b854749fe2743b38f9189434530de2f0ad9aa63a1'
require_text CHANGELOG.md 'that schema-8 attempt did not verify dynamic slides or mouse ink'
require_text CHANGELOG.md 'including a controlled post-erase candidate confirmed by that source'
require_text CHANGELOG.md 'is not cryptographically bound to the runtime report and is not release-grade provenance'
require_text docs/roadmap-ja.md '## M7：GitHub正式版v1.0.0'
require_text docs/local-codex-handoff-ja.md '公開`v1.0.0` GitHub Releaseの成立を指す'
require_text docs/local-codex-handoff-ja.md 'DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult'
require_text docs/local-codex-handoff-ja.md 'sidecarはruntime reportへ暗号的に結合されておらず，release-grade provenanceではない'
require_text docs/v1-release-checklist.md '## Definition of completion'
require_text docs/v1-release-checklist.md 'Alpha, beta, and release-candidate builds are intermediate validation gates'
require_text docs/v1-release-checklist.md 'Developer ID-signed and notarized installable macOS artifact'
require_text docs/v1-release-checklist.md 'The application uses the hardened runtime and an appropriate Developer ID Application signature'
require_text docs/v1-release-checklist.md '## 5. Post-publication verification — completion gate'
require_text docs/v1-release-checklist.md 'The artifact is downloaded from the public GitHub Release into a clean verification environment'
require_text docs/v1-release-checklist.md 'Developer ID signature, designated requirement, hardened runtime, notarization, stapling where applicable, and Gatekeeper acceptance are independently rechecked'
require_text docs/v1-release-checklist.md 'Do not rerun the initial publication script'
require_text docs/adr/0006-mit-license.md 'Accepted for the initial public source repository; review remains required for materially changed v1.0.0 scope'
require_text docs/adr/0006-mit-license.md 'recorded the applicable institutional intellectual-property and software-publication checks as complete before the source repository was made public'
require_text docs/adr/0006-mit-license.md 'The completed initial-publication review does not authorize or verify every later artifact or supported use'
require_text docs/adr/0007-public-v1-completion.md 'Project completion means publication of the public `v1.0.0` GitHub Release'
require_text docs/adr/0011-bound-dense-change-fresh-samples.md 'The paired operator-captured helper sidecar'
require_text docs/adr/0011-bound-dense-change-fresh-samples.md 'is not cryptographically bound to the runtime report and is not release-grade provenance'
reject_text CHANGELOG.md 'Deterministic stable-frame and slide-change detection with unit tests'
reject_text CHANGELOG.md 'Controlled synthetic PowerPoint runtime evidence for current static frame delivery and Vision execution'
reject_text CHANGELOG.md 'PowerPoint slide identity is complete'
reject_text README.md 'The current schema-10 source passes 142 Core tests in 15 suites, 251 native app tests in 30 suites'
reject_text README.md '現行schema 10 sourceは，開発用Mac上でCore 142件・15 suite，native App 251件・30 suite'
reject_text CHANGELOG.md 'A bounded one-shot fresh-sample path for a pending dense content-change candidate'
reject_text CHANGELOG.md 'Live PowerPoint validation of the bounded dense-change fresh-sample path'
reject_text README.md 'Automated schema-11 tests pass, but no current decoder-hardened live report has been recorded'
reject_text README.md 'decoder hardening後の現行sourceによるlive reportは未検証です'
reject_text README.md 'no capture or input occurred and no static report exists'
reject_text README.md 'capture，入力及びstatic reportはありません'
reject_text README.md 'live current-source `SCScreenshotManager` attachments, timing, coarse confirmation, and post-erase behavior remain unverified'
reject_text README.md '実PowerPoint上のcoarse fresh確定及び別個のpost-erase revisionは未検証です'
reject_text README.md '取得timing及び消去後revisionは未検証です'
reject_text README.md 'a separately attributed post-erase content revision'
reject_text README.md 'including whether it records a distinct post-erase revision'
reject_text README.md 'six strictly input-bounded revision intervals'
reject_text README.md 'This verifies strict per-input visual-revision interval attribution'
reject_text README.md 'dynamic runは6件の入力境界内revision intervalを記録し'
reject_text AGENTS.md 'validate exactly six controlled inputs spaced eight seconds apart against exactly six non-reused interval-contained revision events'
reject_text AGENTS.md 'one strictly interval-bounded six-input run'
reject_text ROADMAP.md 'strictly matched exactly six inputs spaced eight seconds apart'
reject_text docs/architecture.md 'It strictly matched exactly six inputs spaced eight seconds apart'
reject_text docs/adr/0011-bound-dense-change-fresh-samples.md 'Exactly six inputs spaced eight seconds apart mapped to six non-reused events within their strict input intervals'
reject_text docs/local-codex-handoff-ja.md '各input completion後から次input開始前，又は最終cutoff前へ厳密に対応付け'
reject_text docs/local-codex-handoff-ja.md '8秒間隔6入力のstrict dynamic interval及びsingle-stroke／eraseを完了した'
reject_text README.md 'DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_22-41-57-+0900.xcresult'
reject_text docs/architecture.md 'The live erase candidate did not receive the third qualifying observation'
reject_text docs/build-verification.md 'This automated evidence does not establish that live PowerPoint supplies'
reject_text docs/development-plan.md 'Stable-frame and slide-change detection'
reject_text docs/README.md 'ADR 0011 — Bounded dense-change fresh samples'
reject_text docs/technical-design-ja.md '本準備環境で8件の自動テストが通過した'
reject_text docs/technical-design-ja.md 'スライド切替と安定フレームの検出'
reject_text docs/technical-design-detailed-ja.md '同一のdense内容更新候補がpendingである間だけ'
reject_text CHANGELOG.md 'dynamic slides and mouse ink remain unverified'
reject_text CHANGELOG.md 'including a separately identified post-erase rerun'

printf 'Release definition and v1.0.0 gates are consistent.\n'
