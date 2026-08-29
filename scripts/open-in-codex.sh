#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

if command -v codex >/dev/null 2>&1; then
  exec codex app "$root"
fi

cat <<MESSAGE
Codex CLI was not found.

Open the ChatGPT desktop app, select Codex from the top-left menu, and open this local folder:
  $root

Alternatively, install Codex CLI from the official OpenAI instructions and run:
  codex app "$root"
MESSAGE
