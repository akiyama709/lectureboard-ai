#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

marker='<a name="日本語"></a>'
marker_count="$(grep -Fxc "$marker" README.md)"

if [[ "$marker_count" -ne 1 ]]; then
  echo "README.md must contain exactly one Japanese-section marker." >&2
  exit 1
fi

english_section="$(awk -v marker="$marker" '$0 == marker { exit } { print }' README.md)"

if printf '%s\n' "$english_section" | LC_ALL=en_US.UTF-8 grep -nE '[ぁ-んァ-ヶ一-龠々〆〤]' >/dev/null; then
  echo "Japanese text found before the Japanese section of README.md:" >&2
  printf '%s\n' "$english_section" | LC_ALL=en_US.UTF-8 grep -nE '[ぁ-んァ-ヶ一-龠々〆〤]' >&2
  exit 1
fi

echo "README language boundary check passed."
