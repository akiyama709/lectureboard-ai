#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail
export LC_ALL=C
export PATH='/usr/bin:/bin:/usr/sbin:/sbin'
unset CDPATH

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && /bin/pwd -P)"
repository_root="$(cd -- "$script_directory/.." && /bin/pwd -P)"
cd "$repository_root"
temporary_root="$(/usr/bin/mktemp -d /private/tmp/lectureboard-release-shell-tests.XXXXXX)"
cleanup() {
  /usr/bin/find "$temporary_root" -depth -delete >/dev/null 2>&1 || true
  return 0
}
trap cleanup EXIT

attack_file="$temporary_root/bash-env-exit-zero.sh"
/usr/bin/printf 'exit 0\n' >"$attack_file"

assert_attack_rejected() {
  local label="$1" target="$2"
  shift 2
  local status=0

  BASH_ENV="$attack_file" "$target" "$@" >/dev/null 2>&1 || status=$?
  if [[ "$status" == 0 ]]; then
    /usr/bin/printf 'Release shell entry accepted BASH_ENV file attack: %s.\n' "$label" >&2
    exit 1
  fi

  status=0
  BASH_ENV=/dev/fd/9 "$target" "$@" 9<"$attack_file" >/dev/null 2>&1 || status=$?
  if [[ "$status" == 0 ]]; then
    /usr/bin/printf 'Release shell entry accepted BASH_ENV FD attack: %s.\n' "$label" >&2
    exit 1
  fi

  status=0
  printf() { exit 0; }
  export -f printf
  "$target" "$@" >/dev/null 2>&1 || status=$?
  unset -f printf
  if [[ "$status" == 0 ]]; then
    /usr/bin/printf 'Release shell entry imported an exported Bash function: %s.\n' "$label" >&2
    exit 1
  fi
}

assert_attack_rejected build-release-app \
  "$script_directory/build-release-app.sh" --unsupported-option
assert_attack_rejected package-release-dmg \
  "$script_directory/package-release-dmg.sh" --unsupported-option
assert_attack_rejected verify-release-code \
  "$script_directory/verify-release-code.sh" --unsupported-option
assert_attack_rejected release-artifact-tools \
  "$script_directory/release-artifact-tools.sh" unsupported-command
assert_attack_rejected release-package-evidence-tools \
  "$script_directory/release-package-evidence-tools.sh" unsupported-command
assert_attack_rejected release-preflight \
  "$script_directory/release-preflight.sh"
assert_attack_rejected release-make-shell \
  "$script_directory/release-make-shell.sh" --unsupported-option
assert_attack_rejected release-make-gate \
  "$script_directory/release-make-gate.sh" unsupported-target

assert_prepublish_environment_rejected() {
  local label="$1"
  shift
  local status=0
  "$@" "$script_directory/prepublish-check.sh" >/dev/null 2>&1 || status=$?
  [[ "$status" == 78 ]] \
    || { /usr/bin/printf 'Prepublication gate did not reject %s before work: status %s.\n' \
      "$label" "$status" >&2; exit 1; }
}
assert_prepublish_environment_rejected BASH_ENV-file \
  /usr/bin/env BASH_ENV="$attack_file"
assert_prepublish_environment_rejected ENV-file \
  /usr/bin/env ENV="$attack_file"
(
  injected_release_function() { return 0; }
  export -f injected_release_function
  assert_prepublish_environment_rejected exported-function /usr/bin/env
)
(
  # Keep the producer output larger than a pipe buffer. A grep -q consumer can
  # otherwise exit on its first match, give env SIGPIPE under pipefail, and
  # invert the rejection condition.
  function_padding="$(/usr/bin/awk 'BEGIN { for (i = 0; i < 256; i++) printf "x" }')"
  function_index=1
  while [[ "$function_index" -le 1200 ]]; do
    function_name="release_pollution_$function_index"
    eval "$function_name() { : '$function_padding'; }"
    export -f "$function_name"
    function_index=$((function_index + 1))
  done
  exit() { return 0; }
  export -f exit
  assert_prepublish_environment_rejected high-volume-exported-functions /usr/bin/env
)

# The historical publisher must fail at its existing-checkout guard before any
# network or repository mutation. BASH_ENV and function imports cannot skip it.
(
  cd "$repository_root"
  assert_attack_rejected publish-to-github \
    "$script_directory/publish-to-github.sh"
)

# `exit` itself is function-importable in ordinary Bash. On the side-effect-free
# evidence helper, an imported no-op exit would turn an invalid command into a
# false success if privileged mode were ever lost.
exit() { return 0; }
export -f exit
exit_function_status=0
"$script_directory/release-package-evidence-tools.sh" unsupported-command \
  >/dev/null 2>&1 || exit_function_status=$?
unset -f exit
[[ "$exit_function_status" != 0 ]] \
  || { /usr/bin/printf 'Release helper imported an exported exit function.\n' >&2; exit 1; }

# GNU Make starts a recipe shell before the recipe can invoke a protected
# script. macOS GNU Make 3.81 does not enforce `.SHELLFLAGS`, so the fixed
# privileged wrapper is the separate required edge.
make_status=0
make_probe_output="$temporary_root/make-probe-output.txt"
make_probe_error="$temporary_root/make-probe-error.txt"
make_probe_file="$temporary_root/Makefile"
{
  /usr/bin/printf 'include %s\n' "$repository_root/Makefile"
  /usr/bin/printf 'release-shell-security-probe:\n'
  /usr/bin/printf '\t@printf "release-shell-probe-ran\\n"; exit 73\n'
} >"$make_probe_file"
BASH_ENV="$attack_file" /usr/bin/make -s -f "$make_probe_file" \
  release-shell-security-probe >"$make_probe_output" 2>"$make_probe_error" || make_status=$?
[[ "$make_status" == 2 \
  && "$(/usr/bin/awk 'END { print NR + 0 }' "$make_probe_output")" == 1 \
  && "$(/usr/bin/awk 'NR == 1 { print }' "$make_probe_output")" == 'release-shell-probe-ran' ]] \
  || { /usr/bin/printf 'Make recipe shell accepted BASH_ENV attack.\n' >&2; exit 1; }

make_override_status=0
make_override_output="$temporary_root/make-override-output.txt"
make_override_error="$temporary_root/make-override-error.txt"
BASH_ENV=/dev/fd/9 /usr/bin/make -s -f "$make_probe_file" \
  CURDIR=/private/tmp/untrusted-make-root SHELL=/bin/bash '.SHELLFLAGS=-c' \
  release-shell-security-probe 9<"$attack_file" \
  >"$make_override_output" 2>"$make_override_error" || make_override_status=$?
[[ "$make_override_status" == 2 \
  && "$(/usr/bin/awk 'END { print NR + 0 }' "$make_override_output")" == 1 \
  && "$(/usr/bin/awk 'NR == 1 { print }' "$make_override_output")" == 'release-shell-probe-ran' ]] \
  || { /usr/bin/printf 'Make command-line SHELL override bypassed the privileged wrapper.\n' >&2; exit 1; }

make_environment_status=0
make_environment_output="$temporary_root/make-environment-output.txt"
make_environment_error="$temporary_root/make-environment-error.txt"
SHELL=/bin/bash \
  MAKEFLAGS='CURDIR=/private/tmp/untrusted-make-root SHELL=/bin/bash .SHELLFLAGS=-c' \
  BASH_ENV=/dev/fd/9 \
  /usr/bin/make -s -f "$make_probe_file" release-shell-security-probe \
  9<"$attack_file" >"$make_environment_output" 2>"$make_environment_error" \
  || make_environment_status=$?
[[ "$make_environment_status" == 2 \
  && "$(/usr/bin/awk 'END { print NR + 0 }' "$make_environment_output")" == 1 \
  && "$(/usr/bin/awk 'NR == 1 { print }' "$make_environment_output")" == 'release-shell-probe-ran' ]] \
  || { /usr/bin/printf 'Make environment SHELL override bypassed the privileged wrapper.\n' >&2; exit 1; }

# The authoritative non-Make launcher sanitizes Make's inherited behavior
# controls.  Both dry-run and ignore-errors would otherwise make a release gate
# report success without proving that its recipe succeeded.
make_gate_status=0
make_gate_output="$temporary_root/make-gate-output.txt"
make_gate_error="$temporary_root/make-gate-error.txt"
MAKEFLAGS='-n -i' MFLAGS='-n -i' GNUMAKEFLAGS='-n -i' \
  "$script_directory/release-make-gate.sh" -s -f "$make_probe_file" \
  release-shell-security-probe >"$make_gate_output" 2>"$make_gate_error" \
  || make_gate_status=$?
[[ "$make_gate_status" == 2 \
  && "$(/usr/bin/awk 'END { print NR + 0 }' "$make_gate_output")" == 1 \
  && "$(/usr/bin/awk 'NR == 1 { print }' "$make_gate_output")" == 'release-shell-probe-ran' ]] \
  || { /usr/bin/printf 'Authoritative Make launcher accepted inherited skip controls.\n' >&2; exit 1; }

# Make's MAKEFILES variable is an implicit pre-parse include.  It and shell
# startup/function records must not survive into Make, a recipe, or a nested
# ordinary Bash process.
makefiles_marker="$temporary_root/makefiles-was-loaded"
evil_makefile="$temporary_root/evil.mk"
/usr/bin/printf 'evil := $(shell /usr/bin/touch %s)\n' "$makefiles_marker" >"$evil_makefile"
MAKEFILES="$evil_makefile" "$script_directory/release-make-gate.sh" -s \
  -f "$make_probe_file" release-shell-security-probe \
  >"$temporary_root/makefiles-probe-output.txt" 2>/dev/null \
  || makefiles_status=$?
[[ "${makefiles_status:-0}" == 2 && ! -e "$makefiles_marker" && ! -L "$makefiles_marker" ]] \
  || { /usr/bin/printf 'Authoritative Make launcher accepted an implicit MAKEFILES include.\n' >&2; exit 1; }

grandchild_probe_file="$temporary_root/GrandchildProbe.mk"
{
  /usr/bin/printf 'include %s\n' "$repository_root/Makefile"
  /usr/bin/printf 'release-grandchild-security-probe:\n'
  /usr/bin/printf '\t@/bin/bash -c '\''type injected_release_function >/dev/null 2>&1'\''\n'
} >"$grandchild_probe_file"
(
  injected_release_function() { return 0; }
  export -f injected_release_function
  grandchild_status=0
  BASH_ENV="$attack_file" ENV="$attack_file" \
    "$script_directory/release-make-gate.sh" -s -f "$grandchild_probe_file" \
    release-grandchild-security-probe >/dev/null 2>&1 || grandchild_status=$?
  [[ "$grandchild_status" == 2 ]] \
    || { /usr/bin/printf 'Release recipe leaked shell pollution to an ordinary Bash grandchild.\n' >&2; exit 1; }
)

(
  injected_release_function() { return 0; }
  export -f injected_release_function
  wrapper_grandchild_status=0
  BASH_ENV="$attack_file" ENV="$attack_file" \
    "$script_directory/release-make-shell.sh" -c \
    '/bin/bash -c "type injected_release_function >/dev/null 2>&1"' \
    >/dev/null 2>&1 || wrapper_grandchild_status=$?
  [[ "$wrapper_grandchild_status" != 0 ]] \
    || { /usr/bin/printf 'Recipe-shell wrapper leaked pollution to a Bash grandchild.\n' >&2; exit 1; }
)

# A caller-controlled PATH cannot replace Make itself or commands run by a
# release recipe.  The fake commands would emit a sentinel if either boundary
# inherited the attacker directory.
fake_bin="$temporary_root/fake-bin"
/bin/mkdir "$fake_bin"
for fake_command in make swift uname git grep find xcodegen; do
  {
    /usr/bin/printf '#!/bin/bash\n'
    /usr/bin/printf '/usr/bin/printf "FAKE-PATH-COMMAND\\n"\n'
    /usr/bin/printf 'exit 0\n'
  } >"$fake_bin/$fake_command"
  /bin/chmod 755 "$fake_bin/$fake_command"
done
path_probe_file="$temporary_root/PathProbe.mk"
{
  /usr/bin/printf 'include %s\n' "$repository_root/Makefile"
  /usr/bin/printf 'release-path-security-probe:\n'
  /usr/bin/printf '\t@command -v swift; command -v uname; command -v git; command -v grep; command -v find; resolved="$$(command -v xcodegen 2>/dev/null || true)"; printf "%%s\\n" "$${resolved:-ABSENT}"\n'
} >"$path_probe_file"
path_probe_output="$temporary_root/path-probe-output.txt"
HOME="$temporary_root/untrusted-home" USER=attacker LOGNAME=attacker \
  DEVELOPER_DIR="$temporary_root/fake-xcode" TOOLCHAINS=attacker \
  SWIFT_EXEC="$fake_bin/swift" GIT_CONFIG_GLOBAL="$temporary_root/evil.gitconfig" \
  PATH="$fake_bin" "$script_directory/release-make-gate.sh" -s \
  -f "$path_probe_file" release-path-security-probe >"$path_probe_output"
trusted_xcodegen='ABSENT'
if [[ -x /opt/homebrew/bin/xcodegen ]]; then
  trusted_xcodegen='/opt/homebrew/bin/xcodegen'
elif [[ -x /usr/local/bin/xcodegen ]]; then
  trusted_xcodegen='/usr/local/bin/xcodegen'
fi
expected_path_probe="$(/usr/bin/printf '/usr/bin/swift\n/usr/bin/uname\n/usr/bin/git\n/usr/bin/grep\n/usr/bin/find\n%s' "$trusted_xcodegen")"
[[ "$(/usr/bin/awk 'END { print NR + 0 }' "$path_probe_output")" == 6 \
  && "$(/bin/cat "$path_probe_output")" == "$expected_path_probe" ]] \
  || { /usr/bin/printf 'Authoritative release gate inherited an untrusted PATH.\n' >&2; exit 1; }

# The recipe itself receives an exact environment allowlist.  This catches a
# future wrapper regression that filters PATH but leaks another caller record.
environment_probe_file="$temporary_root/EnvironmentProbe.mk"
{
  /usr/bin/printf 'include %s\n' "$repository_root/Makefile"
  /usr/bin/printf 'release-environment-security-probe:\n'
  /usr/bin/printf '\t@/usr/bin/env | /usr/bin/sort\n'
} >"$environment_probe_file"
environment_probe_output="$temporary_root/environment-probe-output.txt"
environment_probe_expected="$temporary_root/environment-probe-expected.txt"
trusted_user="$(/usr/bin/id -un)"
trusted_home="$(/usr/bin/id -P "$trusted_user" | /usr/bin/awk -F: 'NF >= 9 { print $9 }')"
EVIL_RELEASE_ENV=present HOME="$temporary_root/untrusted-home" USER=attacker LOGNAME=attacker \
  DEVELOPER_DIR="$temporary_root/fake-xcode" TOOLCHAINS=attacker \
  SWIFT_EXEC="$fake_bin/swift" GIT_CONFIG_GLOBAL="$temporary_root/evil.gitconfig" \
  "$script_directory/release-make-gate.sh" -s -f "$environment_probe_file" \
  release-environment-security-probe >"$environment_probe_output"
{
  /usr/bin/printf 'HOME=%s\n' "$trusted_home"
  /usr/bin/printf 'LC_ALL=C\n'
  /usr/bin/printf 'LOGNAME=%s\n' "$trusted_user"
  /usr/bin/printf 'PATH=/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin\n'
  /usr/bin/printf 'PWD=%s\n' "$repository_root"
  /usr/bin/printf 'SHLVL=1\n'
  /usr/bin/printf 'TMPDIR=/private/tmp\n'
  /usr/bin/printf 'USER=%s\n' "$trusted_user"
  /usr/bin/printf '_=/usr/bin/env\n'
} >"$environment_probe_expected"
/usr/bin/diff -u "$environment_probe_expected" "$environment_probe_output" \
  || { /usr/bin/printf 'Authoritative release recipe environment is not the exact allowlist.\n' >&2; exit 1; }

internal_environment_status=0
HOME="$temporary_root/untrusted-home" USER=attacker LOGNAME=attacker \
  DEVELOPER_DIR="$temporary_root/fake-xcode" TOOLCHAINS=attacker \
  SWIFT_EXEC="$fake_bin/swift" GIT_CONFIG_GLOBAL="$temporary_root/evil.gitconfig" \
  /usr/bin/env -u BASH_ENV -u ENV \
  "$script_directory/prepublish-check.sh" \
  --lectureboard-internal-sanitized-prepublish >/dev/null 2>&1 \
  || internal_environment_status=$?
[[ "$internal_environment_status" == 78 ]] \
  || { /usr/bin/printf 'Caller forged the prepublication sanitized environment boundary.\n' >&2; exit 1; }

# Exercise the tracked-build scan against a NUL-sensitive filename and a
# deterministic Git producer failure without running earlier release stages.
tracked_scan_fixture_root="$temporary_root/prepublish-tracked-scan-fixture"
tracked_scan_base="$temporary_root/prepublish-tracked-scan.base.sh"
/bin/mkdir -p "$tracked_scan_fixture_root/scripts" "$tracked_scan_fixture_root/.build"
/usr/bin/awk '
  /^echo "\[1\/26\]/ {
    print
    print ":"
    skipping = 1
    next
  }
  skipping && /^echo "\[24\/26\]/ {
    skipping = 0
  }
  !skipping { print }
' "$script_directory/prepublish-check.sh" >"$tracked_scan_base"
/bin/chmod 755 "$tracked_scan_base"
/bin/cp "$tracked_scan_base" \
  "$tracked_scan_fixture_root/scripts/prepublish-check.sh"
/bin/chmod 755 "$tracked_scan_fixture_root/scripts/prepublish-check.sh"
/usr/bin/git -C "$tracked_scan_fixture_root" init -q
newline_build_file="$tracked_scan_fixture_root/.build/tracked
artifact"
/usr/bin/printf 'tracked build output\n' >"$newline_build_file"
/usr/bin/git -C "$tracked_scan_fixture_root" add -f -- ".build/tracked
artifact"
tracked_scan_output="$tracked_scan_fixture_root/tracked-scan-output.txt"
tracked_scan_status=0
"$tracked_scan_fixture_root/scripts/prepublish-check.sh" \
  >"$tracked_scan_output" 2>&1 || tracked_scan_status=$?
[[ "$tracked_scan_status" != 0 ]] \
  || { /usr/bin/printf 'Prepublication gate missed a NUL-sensitive tracked build path.\n' >&2; exit 1; }
/usr/bin/grep -Fq 'Tracked build output found.' "$tracked_scan_output" \
  || { /usr/bin/printf 'Prepublication gate did not report tracked build output.\n' >&2; exit 1; }

fake_scan_git="$tracked_scan_fixture_root/fail-git"
{
  /usr/bin/printf '#!/bin/bash\n'
  /usr/bin/printf 'exit 2\n'
} >"$fake_scan_git"
/bin/chmod 755 "$fake_scan_git"
/usr/bin/sed "s#/usr/bin/git ls-files -z#$fake_scan_git ls-files -z#" \
  "$tracked_scan_base" \
  >"$tracked_scan_fixture_root/scripts/prepublish-check.sh"
/bin/chmod 755 "$tracked_scan_fixture_root/scripts/prepublish-check.sh"
tracked_producer_status=0
"$tracked_scan_fixture_root/scripts/prepublish-check.sh" \
  >"$tracked_scan_output" 2>&1 || tracked_producer_status=$?
[[ "$tracked_producer_status" != 0 ]] \
  || { /usr/bin/printf 'Prepublication gate treated a tracked-file producer error as clean.\n' >&2; exit 1; }
/usr/bin/grep -Fq 'Tracked-file enumeration failed.' "$tracked_scan_output" \
  || { /usr/bin/printf 'Prepublication gate did not report its tracked-file producer error.\n' >&2; exit 1; }

# Exercise only the final repository scans in an isolated copy.  Test-only
# exact-tool substitution makes read/enumeration failures deterministic while
# the production script continues to use absolute system-tool paths.
scan_fixture_root="$temporary_root/prepublish-scan-fixture"
scan_fixture_base="$temporary_root/prepublish-scan.base.sh"
scan_find_failure_base="$temporary_root/prepublish-scan.find-failure.sh"
/bin/mkdir -p "$scan_fixture_root/scripts"
/usr/bin/awk '
  /^echo "\[1\/26\]/ {
    print
    print ":"
    skipping = 1
    next
  }
  skipping && /^echo "\[25\/26\]/ {
    skipping = 0
  }
  !skipping { print }
' "$script_directory/prepublish-check.sh" >"$scan_fixture_base"
/bin/chmod 755 "$scan_fixture_base"

fake_scan_grep="$scan_fixture_root/fail-grep"
{
  /usr/bin/printf '#!/bin/bash\n'
  /usr/bin/printf 'exit 2\n'
} >"$fake_scan_grep"
/bin/chmod 755 "$fake_scan_grep"
/usr/bin/sed "s#/usr/bin/grep -RInE#$fake_scan_grep -RInE#" \
  "$scan_fixture_base" \
  >"$scan_fixture_root/scripts/prepublish-check.sh"
/bin/chmod 755 "$scan_fixture_root/scripts/prepublish-check.sh"
secret_scan_output="$temporary_root/prepublish-secret-scan-output.txt"
secret_scan_status=0
"$scan_fixture_root/scripts/prepublish-check.sh" >"$secret_scan_output" 2>&1 \
  || secret_scan_status=$?
[[ "$secret_scan_status" != 0 ]] \
  || { /usr/bin/printf 'Prepublication gate treated a secret-scan read error as clean.\n' >&2; exit 1; }
/usr/bin/grep -Fq 'Common-secret scan failed.' "$secret_scan_output" \
  || { /usr/bin/printf 'Prepublication gate did not report its secret-scan read error.\n' >&2; exit 1; }

fake_scan_find="$scan_fixture_root/fail-find"
fake_scan_find_marker="$temporary_root/prepublish-fake-find-ran"
{
  /usr/bin/printf '#!/bin/bash\n'
  /usr/bin/printf '/usr/bin/touch %s\n' "$fake_scan_find_marker"
  /usr/bin/printf 'exit 2\n'
} >"$fake_scan_find"
/bin/chmod 755 "$fake_scan_find"
/usr/bin/sed "s#/usr/bin/find \. -type f#$fake_scan_find . -type f#" \
  "$scan_fixture_base" \
  >"$scan_find_failure_base"
known_lecture_list="$scan_fixture_root/known-lecture-file-list"
fake_scan_mktemp="$scan_fixture_root/fake-mktemp"
fake_scan_mktemp_marker="$temporary_root/prepublish-fake-mktemp-ran"
{
  /usr/bin/printf '#!/bin/bash\n'
  /usr/bin/printf '/usr/bin/touch %s\n' "$fake_scan_mktemp_marker"
  /usr/bin/printf '/usr/bin/touch %s\n' "$known_lecture_list"
  /usr/bin/printf '/usr/bin/printf "%%s\\n" %s\n' "$known_lecture_list"
} >"$fake_scan_mktemp"
/bin/chmod 755 "$fake_scan_mktemp"
/usr/bin/sed "s#/usr/bin/mktemp#$fake_scan_mktemp#" \
  "$scan_find_failure_base" \
  >"$scan_fixture_root/scripts/prepublish-check.sh"
/bin/chmod 755 "$scan_fixture_root/scripts/prepublish-check.sh"
lecture_scan_output="$temporary_root/prepublish-lecture-scan-output.txt"
lecture_scan_status=0
"$scan_fixture_root/scripts/prepublish-check.sh" >"$lecture_scan_output" 2>&1 \
  || lecture_scan_status=$?
[[ "$lecture_scan_status" != 0 ]] \
  || { /usr/bin/printf 'Prepublication gate treated a lecture-file enumeration error as clean.\n' >&2; exit 1; }
[[ -e "$fake_scan_find_marker" && -e "$fake_scan_mktemp_marker" ]] \
  || { /usr/bin/printf 'Prepublication lecture-file failure fixture did not execute both fake tools.\n' >&2; exit 1; }
/usr/bin/grep -Fq 'Lecture-data file enumeration failed.' "$lecture_scan_output" \
  || { /usr/bin/printf 'Prepublication gate did not report its lecture-file enumeration error.\n' >&2; exit 1; }
[[ ! -e "$known_lecture_list" && ! -L "$known_lecture_list" ]] \
  || { /usr/bin/printf 'Prepublication gate left its lecture-file list after failure.\n' >&2; exit 1; }

# No supported invocation may replace a release shebang with a plain Bash
# interpreter.
shell_file_list="$temporary_root/release-shell-files.txt"
/usr/bin/find "$repository_root/scripts" -type f -name '*.sh' \
  ! -name test-release-shell-security.sh -print0 >"$shell_file_list" \
  || { /usr/bin/printf 'Release shell file enumeration failed.\n' >&2; exit 1; }
if ! plain_invocations="$({
  while IFS= read -r -d '' shell_file; do
    /usr/bin/awk '
      {
        original = $0
        candidate = $0
        gsub(/\/bin\/bash -p/, "", candidate)
        if (candidate ~ /\/bin\/bash[[:space:]]+/) {
          print FILENAME ":" NR ":" original
        }
        if (original ~ /(^|[;&|()[:space:]])bash[[:space:]]+/) {
          print FILENAME ":" NR ":" original
        }
      }
    ' "$shell_file" || exit 91
  done <"$shell_file_list"
  /usr/bin/awk '
    index($0, "/bin/bash") {
      original = $0
      candidate = $0
      gsub(/\/bin\/bash -p/, "", candidate)
      if (candidate ~ /\/bin\/bash[[:space:]]+/) {
        print FILENAME ":" NR ":" original
      }
    }
  ' "$repository_root/Makefile" || exit 92
})"; then
  /usr/bin/printf 'Plain-Bash invocation scan did not complete.\n' >&2
  exit 1
fi
[[ -z "$plain_invocations" ]] \
  || { /usr/bin/printf 'A supported plain-Bash release invocation remains:\n%s\n' \
    "$plain_invocations" >&2; exit 1; }

/usr/bin/grep -Fqx 'override SHELL := $(abspath .)/scripts/release-make-shell.sh' \
  "$repository_root/Makefile" \
  || { /usr/bin/printf 'Makefile lost its privileged recipe-shell wrapper.\n' >&2; exit 1; }
/usr/bin/grep -Fqx 'override .SHELLFLAGS := -c' "$repository_root/Makefile" \
  || { /usr/bin/printf 'Makefile lost fixed recipe-shell flags.\n' >&2; exit 1; }
/usr/bin/grep -Fqx '        run: ./scripts/prepublish-check.sh' \
  "$repository_root/.github/workflows/ci.yml" \
  || { /usr/bin/printf 'CI no longer invokes the authoritative release gate directly.\n' >&2; exit 1; }
/usr/bin/grep -Fqx "export PATH='/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin:/usr/local/bin'" \
  "$repository_root/scripts/prepublish-check.sh" \
  || { /usr/bin/printf 'Authoritative release gate lost its fixed tool PATH.\n' >&2; exit 1; }

/usr/bin/printf 'Release shell-entry security tests passed.\n'
