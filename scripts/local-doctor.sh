#!/usr/bin/env bash
set -uo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

failures=0
warnings=0

ok() { printf '✓ %s\n' "$1"; }
warn() { printf '! %s\n' "$1"; warnings=$((warnings + 1)); }
fail() { printf '✗ %s\n' "$1"; failures=$((failures + 1)); }

printf 'LectureBoard AI local doctor\n'
printf 'Repository: %s\n\n' "$root"

if [[ "$(uname -s)" == "Darwin" ]]; then
  ok "Running on macOS"
else
  fail "Native app development requires macOS; detected $(uname -s)"
fi

arch_name="$(uname -m)"
if [[ "$arch_name" == "arm64" ]]; then
  ok "Apple silicon architecture detected"
else
  warn "Architecture is $arch_name; Apple silicon is the initial validation target"
fi

if command -v sw_vers >/dev/null 2>&1; then
  product_version="$(sw_vers -productVersion)"
  ok "macOS $product_version"
fi

if command -v xcodebuild >/dev/null 2>&1; then
  xcode_line="$(xcodebuild -version 2>/dev/null | tr '\n' ' ' | sed 's/[[:space:]]*$//')"
  ok "$xcode_line"
else
  fail "Xcode command-line tools were not found"
fi

if command -v swift >/dev/null 2>&1; then
  swift_line="$(swift --version 2>/dev/null | head -n 1)"
  ok "$swift_line"
else
  fail "Swift was not found"
fi

if command -v xcodegen >/dev/null 2>&1; then
  ok "XcodeGen $(xcodegen --version 2>/dev/null | head -n 1)"
else
  warn "XcodeGen is not installed; use: brew install xcodegen"
fi

if command -v git >/dev/null 2>&1; then
  ok "$(git --version)"
else
  fail "Git was not found"
fi

if command -v gh >/dev/null 2>&1; then
  ok "GitHub CLI is installed"
  login="$(gh api user --jq .login 2>/dev/null || true)"
  if [[ -n "$login" ]]; then
    if [[ "$login" == "akiyama709" ]]; then
      ok "GitHub CLI is authenticated as akiyama709"
    else
      warn "GitHub CLI is authenticated as $login, not akiyama709"
    fi
  else
    warn "GitHub CLI is not authenticated"
  fi
else
  warn "GitHub CLI is not installed; it is needed only when publishing"
fi

printf '\nResult: %d failure(s), %d warning(s)\n' "$failures" "$warnings"

if (( failures > 0 )); then
  exit 1
fi
