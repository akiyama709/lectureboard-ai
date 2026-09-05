#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail
export PATH='/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin'
export LC_ALL=C
unset CDPATH

# Privileged Bash ignores startup-file and exported-function imports for this
# process, but would otherwise pass their environment records to an ordinary
# Bash child.  Direct release checks fail before invoking any child when those
# records are present; Make children are separately launched through env -i.
if [[ -n "${BASH_ENV+x}" || -n "${ENV+x}" ]]; then
  /usr/bin/printf 'Prepublication gate rejects shell startup-file environment variables.\n' >&2
  exit 78
fi
if /usr/bin/env | /usr/bin/grep '^BASH_FUNC_' >/dev/null; then
  /usr/bin/printf 'Prepublication gate rejects exported Bash functions.\n' >&2
  exit 78
fi

current_user="$(/usr/bin/id -un)" \
  || { /usr/bin/printf 'Prepublication user could not be identified.\n' >&2; exit 78; }
trusted_home="$(/usr/bin/id -P "$current_user" \
  | /usr/bin/awk -F: 'NF >= 9 { print $9 }')" \
  || { /usr/bin/printf 'Prepublication home directory could not be identified.\n' >&2; exit 78; }
[[ "$trusted_home" == /* && -d "$trusted_home" && ! -L "$trusted_home" ]] \
  || { /usr/bin/printf 'Prepublication home directory is invalid.\n' >&2; exit 78; }

internal_environment_flag='--lectureboard-internal-sanitized-prepublish'
if [[ "${1:-}" != "$internal_environment_flag" ]]; then
  script_directory="$(cd -- "$(/usr/bin/dirname -- "${BASH_SOURCE[0]}")" \
    && /bin/pwd -P)"
  exec /usr/bin/env -i \
    HOME="$trusted_home" \
    USER="$current_user" \
    LOGNAME="$current_user" \
    TMPDIR=/private/tmp \
    PATH="$PATH" \
    LC_ALL=C \
    /bin/bash -p "$script_directory/prepublish-check.sh" \
    "$internal_environment_flag" "$@"
fi
shift
[[ "$#" == 0 ]] \
  || { /usr/bin/printf 'Prepublication gate accepts no arguments.\n' >&2; exit 64; }
[[ "$HOME" == "$trusted_home" && "$USER" == "$current_user" \
  && "$LOGNAME" == "$current_user" && "$TMPDIR" == /private/tmp ]] \
  || { /usr/bin/printf 'Prepublication sanitized identity environment is invalid.\n' >&2; exit 78; }
unexpected_environment="$(/usr/bin/env | /usr/bin/awk -F= '
  $1 != "HOME" && $1 != "USER" && $1 != "LOGNAME" &&
  $1 != "TMPDIR" && $1 != "PATH" && $1 != "LC_ALL" &&
  $1 != "PWD" && $1 != "SHLVL" && $1 != "_" { print $1 }
')"
[[ -z "$unexpected_environment" ]] \
  || { /usr/bin/printf 'Prepublication sanitized environment has unexpected entries.\n' >&2; exit 78; }

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
release_make='./scripts/release-make-gate.sh'

echo "[1/26] Linting Swift sources and tests"
/usr/bin/swift format lint --recursive \
  LectureBoardAI/Sources \
  LectureBoardAI/Tests \
  Packages/LectureBoardCore/Sources \
  Packages/LectureBoardCore/Tests

echo "[2/26] Running platform-neutral core tests"
"$release_make" test-core

echo "[3/26] Running native app tests when macOS and XcodeGen are available"
[[ "$(/usr/bin/uname -s)" == "Darwin" ]] \
  || { echo "Native app tests require macOS." >&2; exit 1; }
{ [[ -x /opt/homebrew/bin/xcodegen ]] || [[ -x /usr/local/bin/xcodegen ]]; } \
  || { echo "Native app tests require XcodeGen." >&2; exit 1; }
"$release_make" test-app

echo "[4/26] Building the native app when macOS and XcodeGen are available"
[[ "$(/usr/bin/uname -s)" == "Darwin" ]] \
  || { echo "Native app build requires macOS." >&2; exit 1; }
{ [[ -x /opt/homebrew/bin/xcodegen ]] || [[ -x /usr/local/bin/xcodegen ]]; } \
  || { echo "Native app build requires XcodeGen." >&2; exit 1; }
"$release_make" build

echo "[5/26] Building and smoke-testing the runtime app when macOS and XcodeGen are available"
[[ "$(/usr/bin/uname -s)" == "Darwin" ]] \
  || { echo "Runtime app verification requires macOS." >&2; exit 1; }
{ [[ -x /opt/homebrew/bin/xcodegen ]] || [[ -x /usr/local/bin/xcodegen ]]; } \
  || { echo "Runtime app verification requires XcodeGen." >&2; exit 1; }
"$release_make" build-runtime
"$release_make" test-runtime-launch-smoke

echo "[6/26] Testing the publication source tracking check"
"$release_make" test-publication-sources-script

echo "[7/26] Checking that all required sources are included in Git"
./scripts/check-publication-sources.sh

echo "[8/26] Checking README language boundaries"
./scripts/check-readme-language-boundary.sh

echo "[9/26] Testing the historical initial-publication fail-closed guard"
"$release_make" test-initial-publication-script

echo "[10/26] Testing the permission and hardened-runtime entitlement contract"
"$release_make" test-permission-contract-script

echo "[11/26] Checking the permission and hardened-runtime entitlement contract"
"$release_make" check-permission-contract

echo "[12/26] Testing version-metadata consistency"
"$release_make" test-version-consistency-script

echo "[13/26] Checking version-metadata consistency"
"$release_make" check-version-consistency

echo "[14/26] Testing the v1.0.0 completion-definition check"
"$release_make" test-release-definition-script

echo "[15/26] Checking v1.0.0 completion and release gates"
./scripts/check-release-definition.sh

echo "[16/26] Testing release-artifact manifest and project-boundary helpers"
"$release_make" test-release-artifact-tools-script

echo "[17/26] Testing deterministic release-app construction"
"$release_make" test-build-release-app-script

echo "[18/26] Testing exclusive release-output publication"
"$release_make" test-release-exclusive-rename-script

echo "[19/26] Checking release-package evidence-helper syntax"
"$release_make" check-release-package-evidence-tools-script

echo "[20/26] Testing notarized disk-image packaging policy"
"$release_make" test-package-release-dmg-script

echo "[21/26] Testing the distribution release preflight"
"$release_make" test-release-preflight-script

echo "[22/26] Testing release-code verification policy"
"$release_make" test-verify-release-code-script

echo "[23/26] Testing privileged and no-fee release shell entrypoints"
"$release_make" test-release-shell-security-script
"$release_make" test-no-fee-release-v1-script

echo "[24/26] Checking for tracked build output"
tracked_file_list="$(/usr/bin/mktemp "$TMPDIR/lectureboard-tracked-file-list.XXXXXX")"
if ! /usr/bin/git ls-files -z >"$tracked_file_list"; then
  /bin/rm -f -- "$tracked_file_list"
  echo "Tracked-file enumeration failed." >&2
  exit 1
fi
tracked_build_output_found=0
while IFS= read -r -d '' tracked_file; do
  case "$tracked_file" in
    .build/*|*/.build/*|DerivedData/*|*/DerivedData/*)
      tracked_build_output_found=1
      break
      ;;
  esac
done <"$tracked_file_list"
/bin/rm -f -- "$tracked_file_list"
if [[ "$tracked_build_output_found" == 1 ]]; then
  echo "Tracked build output found." >&2
  exit 1
fi

echo "[25/26] Checking for common secrets"
secret_scan_status=0
/usr/bin/grep -RInE --exclude-dir=.git --exclude-dir=.build --exclude='prepublish-check.sh' \
  '(BEGIN (RSA|OPENSSH|EC) PRIVATE KEY|LECTUREBOARD_API_KEY=[^[:space:]]+|sk-[A-Za-z0-9_-]{20,})' \
  . >/dev/null || secret_scan_status=$?
case "$secret_scan_status" in
  0)
    echo "Potential secret detected." >&2
    exit 1
    ;;
  1) ;;
  *)
    echo "Common-secret scan failed." >&2
    exit 1
    ;;
esac

echo "[26/26] Checking for lecture-data extensions"
lecture_file_list=''
cleanup_lecture_file_list() {
  if [[ -n "$lecture_file_list" ]]; then
    /bin/rm -f -- "$lecture_file_list"
  fi
}
trap cleanup_lecture_file_list EXIT
lecture_file_list="$(/usr/bin/mktemp "$TMPDIR/lectureboard-lecture-file-list.XXXXXX")"
if ! /usr/bin/find . -type f \
  ! -path './.git/*' \
  ! -path './.build/*' \
  -print0 >"$lecture_file_list"; then
  echo "Lecture-data file enumeration failed." >&2
  exit 1
fi
lecture_asset_found=0
while IFS= read -r -d '' repository_file; do
  case "$repository_file" in
    *.[pP][pP][tT]|*.[pP][pP][tT][xX]|*.[kK][eE][yY][nN][oO][tT][eE]|\
    *.[mM]4[aA]|*.[wW][aA][vV]|*.[mM][pP]3)
      lecture_asset_found=1
      break
      ;;
  esac
done <"$lecture_file_list"
cleanup_lecture_file_list
lecture_file_list=''
trap - EXIT
if [[ "$lecture_asset_found" == 1 ]]; then
  echo "Potential private or licensed lecture asset is present." >&2
  exit 1
fi

echo "Prepublication checks passed. Manual institutional IP and privacy review is still required."
