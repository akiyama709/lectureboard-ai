#!/usr/bin/env bash
set -euo pipefail

EXPECTED_ACCOUNT="akiyama709"
REPOSITORY="${EXPECTED_ACCOUNT}/lectureboard-ai"

if ! command -v gh >/dev/null 2>&1; then
  echo "GitHub CLI is required. Install it with: brew install gh"
  exit 1
fi

ACTIVE_ACCOUNT="$(gh api user --jq .login 2>/dev/null || true)"
if [[ "$ACTIVE_ACCOUNT" != "$EXPECTED_ACCOUNT" ]]; then
  echo "The active GitHub account is '${ACTIVE_ACCOUNT:-none}', not '${EXPECTED_ACCOUNT}'."
  echo "Run: gh auth login --hostname github.com"
  echo "Then select the ${EXPECTED_ACCOUNT} account before publishing."
  exit 1
fi

./scripts/prepublish-check.sh

if [[ ! -d .git ]]; then
  git init -b main
fi

git add .
if ! git diff --cached --quiet; then
  git commit -m "Initialize LectureBoard AI macOS alpha"
fi

read -r -p "Create the PUBLIC repository ${REPOSITORY} and push now? [y/N] " answer
if [[ ! "$answer" =~ ^[Yy]$ ]]; then
  echo "Cancelled."
  exit 0
fi

gh repo create "$REPOSITORY" \
  --public \
  --source=. \
  --remote=origin \
  --push \
  --description "Context-aware digital ink for PowerPoint lectures on macOS"
