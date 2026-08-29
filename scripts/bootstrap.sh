#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift was not found. Install Xcode and its Command Line Tools." >&2
  exit 1
fi

swift --version
make test-core

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo
  echo "LectureBoard AI is macOS-only. The platform-neutral core tests passed; the app project was not generated."
  exit 0
fi

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "XcodeGen is required. Install it with: brew install xcodegen" >&2
  exit 1
fi

xcodegen --version
make generate

echo
echo "Bootstrap complete. Open LectureBoardAI.xcodeproj in Xcode."
