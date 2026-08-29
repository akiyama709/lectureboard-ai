#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

echo "[1/7] Linting Swift sources"
swift format lint --recursive \
  LectureBoardAI/Sources \
  Packages/LectureBoardCore/Sources \
  Packages/LectureBoardCore/Tests

echo "[2/7] Running platform-neutral core tests"
make test-core

echo "[3/7] Building the native app when macOS and XcodeGen are available"
if [[ "$(uname -s)" == "Darwin" ]] && command -v xcodegen >/dev/null 2>&1; then
  make build
else
  echo "Native app build skipped in this environment."
fi

echo "[4/7] Checking that all Swift sources are included in Git"
./scripts/check-publication-sources.sh

echo "[5/7] Checking for tracked build output"
tracked="$(git ls-files)"
if printf '%s\n' "$tracked" | grep -E '(^|/)(\.build|DerivedData)/' >/dev/null; then
  echo "Tracked build output found." >&2
  exit 1
fi

echo "[6/7] Checking for common secrets"
if grep -RInE --exclude-dir=.git --exclude-dir=.build --exclude='prepublish-check.sh' \
  '(BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|LECTUREBOARD_API_KEY=[^[:space:]]+|sk-[A-Za-z0-9_-]{20,})' .; then
  echo "Potential secret detected." >&2
  exit 1
fi

echo "[7/7] Checking for lecture-data extensions"
if find . -type f \
  ! -path './.git/*' \
  ! -path './.build/*' \
  | grep -Ei '\.(pptx?|keynote|m4a|wav|mp3)$' >/dev/null; then
  echo "Potential private or licensed lecture asset is present." >&2
  exit 1
fi

echo "Prepublication checks passed. Manual institutional IP and privacy review is still required."
