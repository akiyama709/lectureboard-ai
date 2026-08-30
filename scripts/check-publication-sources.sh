#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "A Git worktree is required to verify the publication source set." >&2
  exit 1
fi

missing=0
while IFS= read -r source_file; do
  source_file="${source_file#./}"
  if ! git ls-files --error-unmatch "$source_file" >/dev/null 2>&1; then
    echo "Required source is not included in Git: $source_file" >&2
    missing=1
  fi
done < <(
  {
    find \
      LectureBoardAI/Sources \
      LectureBoardAI/Tests \
      Packages/LectureBoardCore/Sources \
      Packages/LectureBoardCore/Tests \
      -type f -name '*.swift' -print
    find scripts -maxdepth 1 -type f -print
  } | sort -u
)

if (( missing > 0 )); then
  exit 1
fi

echo "All required source files are included in Git."
