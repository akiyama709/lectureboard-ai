#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
temporary_parent="${TMPDIR:-/tmp}"
fixture_root="$(mktemp -d "$temporary_parent/lectureboard-initial-publish.XXXXXX")"
fixture="$fixture_root/repository"
fake_bin="$fixture_root/bin"
command_log="$fixture_root/git-commands.log"
output_log="$fixture_root/output.log"

cleanup() {
  find "$fixture_root" -type f -delete
  find "$fixture_root" -depth -type d -empty -delete
}
trap cleanup EXIT

mkdir -p "$fixture/scripts" "$fake_bin"
cp "$script_directory/publish-to-github.sh" "$fixture/scripts/publish-to-github.sh"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [[ "$1" == "api" && "$2" == "user" ]]; then' \
  '  printf "akiyama709\\n"' \
  '  exit 0' \
  'fi' \
  'if [[ "$1" == "api" && "$2" == "--include" ]]; then' \
  '  case "${PUBLISH_TEST_GH_REPO_STATUS:-503}" in' \
  '    200) printf "HTTP/2.0 200 OK\\n"; exit 0 ;;' \
  '    404) printf "HTTP/2.0 404 Not Found\\n"; exit 1 ;;' \
  '    *) printf "network unavailable\\n" >&2; exit 1 ;;' \
  '  esac' \
  'fi' \
  'exit 99' >"$fake_bin/gh"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'if [[ "$1" == "rev-parse" ]]; then' \
  '  exit 1' \
  'fi' \
  'printf "%s\\n" "$1" >>"$PUBLISH_TEST_GIT_LOG"' \
  'if [[ "$1" == "init" ]]; then' \
  '  exit 42' \
  'fi' \
  'exit 99' >"$fake_bin/git"

chmod +x "$fixture/scripts/publish-to-github.sh" "$fake_bin/gh" "$fake_bin/git"

run_fixture() {
  local repository_status="$1"
  local status=0
  : >"$command_log"
  : >"$output_log"
  (
    cd "$fixture"
    PATH="$fake_bin:$PATH" \
      PUBLISH_TEST_GH_REPO_STATUS="$repository_status" \
      PUBLISH_TEST_GIT_LOG="$command_log" \
      ./scripts/publish-to-github.sh </dev/null
  ) >"$output_log" 2>&1 || status=$?
  printf '%s' "$status"
}

mkdir "$fixture/.git"
status="$(run_fixture 200)"
if [[ "$status" -ne 1 ]] || ! grep -F 'refuses to run inside an existing Git checkout' "$output_log" >/dev/null; then
  printf 'Existing-checkout guard did not fail closed before publication.\n' >&2
  exit 1
fi
if [[ -s "$command_log" ]]; then
  printf 'Existing-checkout guard invoked a mutating Git command.\n' >&2
  exit 1
fi
find "$fixture/.git" -depth -delete

status="$(run_fixture 200)"
if [[ "$status" -ne 1 ]] || ! grep -F 'already exists' "$output_log" >/dev/null; then
  printf 'Existing-remote guard did not fail closed before local initialization.\n' >&2
  exit 1
fi
if [[ -s "$command_log" ]]; then
  printf 'Existing-remote guard invoked a mutating Git command.\n' >&2
  exit 1
fi

status="$(run_fixture 503)"
if [[ "$status" -ne 1 ]] || ! grep -F 'Unable to confirm safely' "$output_log" >/dev/null; then
  printf 'Indeterminate-remote guard did not fail closed.\n' >&2
  exit 1
fi
if [[ -s "$command_log" ]]; then
  printf 'Indeterminate-remote guard invoked a mutating Git command.\n' >&2
  exit 1
fi

status="$(run_fixture 404)"
if [[ "$status" -ne 42 ]] || [[ "$(cat "$command_log")" != "init" ]]; then
  printf 'Confirmed remote absence did not reach initial local initialization exactly once.\n' >&2
  exit 1
fi

printf 'Initial-publication fail-closed regression fixtures passed.\n'
