#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

echo "[1/11] Linting Swift sources and tests"
swift format lint --recursive \
  LectureBoardAI/Sources \
  LectureBoardAI/Tests \
  Packages/LectureBoardCore/Sources \
  Packages/LectureBoardCore/Tests

echo "[2/11] Running platform-neutral core tests"
make test-core

echo "[3/11] Running native app tests when macOS and XcodeGen are available"
if [[ "$(uname -s)" == "Darwin" ]] && command -v xcodegen >/dev/null 2>&1; then
  make test-app
else
  echo "Native app tests skipped: macOS and XcodeGen are required."
fi

echo "[4/11] Building the native app when macOS and XcodeGen are available"
if [[ "$(uname -s)" == "Darwin" ]] && command -v xcodegen >/dev/null 2>&1; then
  make build
else
  echo "Native app build skipped: macOS and XcodeGen are required."
fi

echo "[5/11] Building and smoke-testing the runtime app when macOS and XcodeGen are available"
if [[ "$(uname -s)" == "Darwin" ]] && command -v xcodegen >/dev/null 2>&1; then
  make build-runtime
  make test-runtime-launch-smoke
else
  echo "Runtime app build and launch smoke test skipped: macOS and XcodeGen are required."
fi

echo "[6/11] Testing the publication source tracking check"
make test-publication-sources-script

echo "[7/11] Checking that all required sources are included in Git"
./scripts/check-publication-sources.sh

echo "[8/11] Checking README language boundaries"
./scripts/check-readme-language-boundary.sh

echo "[9/11] Checking for tracked build output"
tracked="$(git ls-files)"
if printf '%s\n' "$tracked" | grep -E '(^|/)(\.build|DerivedData)/' >/dev/null; then
  echo "Tracked build output found." >&2
  exit 1
fi

echo "[10/11] Checking for common secrets"
if grep -RInE --exclude-dir=.git --exclude-dir=.build --exclude='prepublish-check.sh' \
  '(BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|LECTUREBOARD_API_KEY=[^[:space:]]+|sk-[A-Za-z0-9_-]{20,})' .; then
  echo "Potential secret detected." >&2
  exit 1
fi

echo "[11/11] Checking for lecture-data extensions"
if find . -type f \
  ! -path './.git/*' \
  ! -path './.build/*' \
  | grep -Ei '\.(pptx?|keynote|m4a|wav|mp3)$' >/dev/null; then
  echo "Potential private or licensed lecture asset is present." >&2
  exit 1
fi

echo "Prepublication checks passed. Manual institutional IP and privacy review is still required."
