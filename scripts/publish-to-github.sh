#!/usr/bin/env bash
set -euo pipefail

EXPECTED_ACCOUNT="akiyama709"
REPOSITORY="${EXPECTED_ACCOUNT}/lectureboard-ai"

if [[ -e .git ]] || git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "This initial-publication script refuses to run inside an existing Git checkout."
  echo "Use a working branch, pull request, and the v1 release checklist instead."
  exit 1
fi

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

repository_probe_status=0
repository_probe="$(gh api --include "repos/$REPOSITORY" 2>&1)" || repository_probe_status=$?
if [[ "$repository_probe_status" -eq 0 ]]; then
  echo "The GitHub repository ${REPOSITORY} already exists."
  echo "This historical initial-publication script will not modify the local directory."
  exit 1
fi
if ! grep -Eq '^HTTP/[0-9.]+ 404([[:space:]]|$)' <<<"$repository_probe"; then
  echo "Unable to confirm safely that ${REPOSITORY} does not exist."
  echo "No local Git repository was initialized and no files were staged."
  exit 1
fi

git init -b main
git add .
./scripts/prepublish-check.sh

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
