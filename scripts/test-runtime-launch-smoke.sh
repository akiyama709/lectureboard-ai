#!/usr/bin/env bash
set -euo pipefail

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd -- "$script_directory/.." && pwd)"
runtime_app="$repository_root/DerivedData/RuntimeBuild/Build/Products/Debug/LectureBoard AI.app"
runtime_executable="$runtime_app/Contents/MacOS/LectureBoard AI"
temporary_parent="${TMPDIR:-/tmp}"
temporary_directory="$(mktemp -d "$temporary_parent/lectureboard-runtime-smoke.XXXXXX")"
report_path="$temporary_directory/runtime-report.json"
report_plist="$temporary_directory/runtime-report.plist"
invalid_stdout="$temporary_directory/invalid.stdout"
invalid_stderr="$temporary_directory/invalid.stderr"
smoke_stdout="$temporary_directory/smoke.stdout"
smoke_stderr="$temporary_directory/smoke.stderr"
active_pid=""

terminate_active_process() {
  if [[ -n "$active_pid" ]] && kill -0 "$active_pid" >/dev/null 2>&1; then
    kill "$active_pid" >/dev/null 2>&1 || true
    for _ in {1..20}; do
      if ! kill -0 "$active_pid" >/dev/null 2>&1; then
        break
      fi
      sleep 0.05
    done
    if kill -0 "$active_pid" >/dev/null 2>&1; then
      kill -KILL "$active_pid" >/dev/null 2>&1 || true
    fi
    wait "$active_pid" >/dev/null 2>&1 || true
  fi
  active_pid=""
}

cleanup() {
  terminate_active_process

  rm -f -- \
    "$report_path" \
    "$report_plist" \
    "$invalid_stdout" \
    "$invalid_stderr" \
    "$smoke_stdout" \
    "$smoke_stderr"
  rmdir "$temporary_directory" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

fail_with_logs() {
  local message="$1"
  local stdout_path="$2"
  local stderr_path="$3"

  printf '%s\n' "$message" >&2
  if [[ -s "$stdout_path" ]]; then
    printf 'Captured stdout:\n' >&2
    sed -n '1,80p' "$stdout_path" >&2
  fi
  if [[ -s "$stderr_path" ]]; then
    printf 'Captured stderr:\n' >&2
    sed -n '1,80p' "$stderr_path" >&2
  fi
  exit 1
}

run_with_timeout() {
  local timeout_seconds="$1"
  local stdout_path="$2"
  local stderr_path="$3"
  shift 3

  "$@" >"$stdout_path" 2>"$stderr_path" &
  active_pid=$!
  local deadline=$((SECONDS + timeout_seconds))

  while kill -0 "$active_pid" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      terminate_active_process
      return 124
    fi
    sleep 0.1
  done

  local exit_status=0
  wait "$active_pid" || exit_status=$?
  active_pid=""
  return "$exit_status"
}

if [[ "$(uname -s)" != "Darwin" ]]; then
  printf 'Runtime launch smoke testing requires macOS.\n' >&2
  exit 1
fi

for required_command in plutil mktemp uuidgen; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$required_command" >&2
    exit 1
  fi
done

if [[ ! -x "$runtime_executable" ]]; then
  printf 'Built runtime executable not found: %s\n' "$runtime_executable" >&2
  printf 'Run make build-runtime before this smoke test.\n' >&2
  exit 1
fi

invalid_exit_status=0
run_with_timeout \
  8 \
  "$invalid_stdout" \
  "$invalid_stderr" \
  "$runtime_executable" \
  --runtime-verification \
  --window-id 0 \
  --observation-seconds 1 \
  --output-path "$report_path" \
  || invalid_exit_status=$?
if (( invalid_exit_status != 0 )); then
  if (( invalid_exit_status == 124 )); then
    fail_with_logs \
      'Invalid runtime arguments did not terminate within 8 seconds.' \
      "$invalid_stdout" \
      "$invalid_stderr"
  fi
  fail_with_logs \
    "Invalid runtime arguments exited unsuccessfully with status $invalid_exit_status." \
    "$invalid_stdout" \
    "$invalid_stderr"
fi

if ! grep -Fq 'Invalid runtime verification arguments:' "$invalid_stderr"; then
  fail_with_logs \
    'Invalid runtime arguments did not emit the expected diagnostic.' \
    "$invalid_stdout" \
    "$invalid_stderr"
fi

impossible_title="LectureBoard-Runtime-Smoke-No-Match-$(uuidgen)"
runtime_arguments=(
  --runtime-verification
  --window-title-contains "$impossible_title"
  --observation-seconds 1
  --output-path "$report_path"
)

for argument in "${runtime_arguments[@]}"; do
  if [[ "$argument" == "--request-screen-recording" ]]; then
    printf 'The smoke test must never request Screen Recording permission.\n' >&2
    exit 1
  fi
done

smoke_exit_status=0
run_with_timeout \
  25 \
  "$smoke_stdout" \
  "$smoke_stderr" \
  "$runtime_executable" \
  "${runtime_arguments[@]}" \
  || smoke_exit_status=$?
if (( smoke_exit_status != 0 )); then
  if (( smoke_exit_status == 124 )); then
    fail_with_logs \
      'Runtime verification did not terminate within 25 seconds.' \
      "$smoke_stdout" \
      "$smoke_stderr"
  fi
  fail_with_logs \
    "Runtime verification exited unsuccessfully with status $smoke_exit_status." \
    "$smoke_stdout" \
    "$smoke_stderr"
fi

if [[ ! -f "$report_path" ]]; then
  fail_with_logs \
    'Runtime verification did not produce its JSON report.' \
    "$smoke_stdout" \
    "$smoke_stderr"
fi

if ! grep -Eq '^[[:space:]]*\{' "$report_path" \
  || ! plutil -convert xml1 -o "$report_plist" "$report_path" >/dev/null 2>&1; then
  fail_with_logs \
    'Runtime verification produced invalid JSON.' \
    "$smoke_stdout" \
    "$smoke_stderr"
fi

allowed_report_keys="$(
  printf '%s\n' \
    schemaVersion \
    startedAt \
    finishedAt \
    requestedDurationSeconds \
    permissionWasRequested \
    permissionRequestReturned \
    preflightBefore \
    preflightAfter \
    matchedWindowCount \
    selectedWindowID \
    selectedBundleIdentifier \
    runStatus \
    failureCode \
    failureMessage \
    snapshots \
    timestamp \
    elapsedMilliseconds \
    screenRecordingPermission \
    captureState \
    visionState \
    frameCount \
    newFrameCount \
    repeatedFrameCount \
    stableFrameCount \
    slideChangeCount \
    recognizedTextCount \
    detectedRectangleCount \
    occupiedRegionCount \
    lastNewFrameAt \
    latestDifferenceFromStableFrame
)"

while IFS= read -r report_key; do
  if ! grep -Fxq "$report_key" <<<"$allowed_report_keys"; then
    fail_with_logs \
      "Runtime verification report contains a non-metadata key: $report_key" \
      "$smoke_stdout" \
      "$smoke_stderr"
  fi
done < <(sed -n 's/^[[:space:]]*<key>\([^<]*\)<\/key>$/\1/p' "$report_plist")

permission_was_requested="$(
  plutil -extract permissionWasRequested raw -o - "$report_path"
)"
run_status="$(plutil -extract runStatus raw -o - "$report_path")"
failure_code="$(plutil -extract failureCode raw -o - "$report_path")"
snapshot_count="$(plutil -extract snapshots raw -o - "$report_path")"

if [[ "$permission_was_requested" != "false" \
  || "$run_status" != "failed" \
  || "$snapshot_count" != "0" ]] \
  || [[ "$failure_code" != "screenRecordingUnavailable" \
    && "$failure_code" != "windowNotFound" ]]; then
  fail_with_logs \
    'Runtime verification report did not record the expected safe failure.' \
    "$smoke_stdout" \
    "$smoke_stderr"
fi

if plutil -extract permissionRequestReturned raw -o - "$report_path" \
  >/dev/null 2>&1; then
  fail_with_logs \
    'Runtime verification unexpectedly recorded a permission-request result.' \
    "$smoke_stdout" \
    "$smoke_stderr"
fi

if grep -Fq "$impossible_title" "$report_path"; then
  fail_with_logs \
    'Runtime verification report exposed the requested window-title sentinel.' \
    "$smoke_stdout" \
    "$smoke_stderr"
fi

printf 'Runtime launch smoke tests passed without requesting Screen Recording permission.\n'
