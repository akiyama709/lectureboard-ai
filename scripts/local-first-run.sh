#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

./scripts/local-doctor.sh

echo
echo "Running LectureBoardCore tests..."
make test-core

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo
  echo "Core tests passed. Native project generation is available only on macOS."
  exit 0
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo >&2
  echo "XcodeGen is required to generate LectureBoardAI.xcodeproj." >&2
  echo "Install it explicitly, for example with: brew install xcodegen" >&2
  exit 1
fi

echo
echo "Generating the Xcode project..."
make generate

echo
echo "Local setup complete. Next: make build or make open"
