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

required_files=(
  CHANGELOG.md
  ROADMAP.md
  README.md
  docs/roadmap-ja.md
  docs/local-codex-handoff-ja.md
  docs/v1-release-checklist.md
  docs/adr/0006-mit-license.md
  docs/adr/0007-public-v1-completion.md
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
require_text CHANGELOG.md 'Deterministic stable-frame and significant visual/content-change classification with unit tests'
require_text CHANGELOG.md 'Build-specific historical synthetic PowerPoint evidence for static frame delivery, Vision execution, and pre-semantic dynamic calibration; not evidence for the current semantic build'
require_text CHANGELOG.md 'An independent PowerPoint slide-identity signal before actual slide transitions are counted'
require_text docs/roadmap-ja.md '## M7：GitHub正式版v1.0.0'
require_text docs/local-codex-handoff-ja.md '公開`v1.0.0` GitHub Releaseの成立を指す'
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

printf 'Release definition and v1.0.0 gates are consistent.\n'
