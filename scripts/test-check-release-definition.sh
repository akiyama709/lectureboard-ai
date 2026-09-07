#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail

script_directory="$(cd "$(dirname "$0")" && pwd)"
checker="$script_directory/check-release-definition.sh"
temporary_parent="${TMPDIR:-/tmp}"
fixture_root="$(mktemp -d "$temporary_parent/lectureboard-release-definition.XXXXXX")"

cleanup() {
  find "$fixture_root" -type f -delete
  find "$fixture_root" -depth -type d -empty -delete
}
trap cleanup EXIT

mkdir -p \
  "$fixture_root/.github/workflows" \
  "$fixture_root/scripts" \
  "$fixture_root/docs/adr" \
  "$fixture_root/LectureBoardAI/Config"
cp "$checker" "$fixture_root/scripts/check-release-definition.sh"
cp "$script_directory/../Makefile" "$fixture_root/Makefile"
cp "$script_directory/../.github/workflows/ci.yml" "$fixture_root/.github/workflows/ci.yml"
cp "$script_directory/../AGENTS.md" "$fixture_root/AGENTS.md"
cp "$script_directory/../CHANGELOG.md" "$fixture_root/CHANGELOG.md"
cp "$script_directory/../ROADMAP.md" "$fixture_root/ROADMAP.md"
cp "$script_directory/../README.md" "$fixture_root/README.md"
cp "$script_directory/../project.yml" "$fixture_root/project.yml"
cp "$script_directory/../LectureBoardAI/Config/Info.plist" \
  "$fixture_root/LectureBoardAI/Config/Info.plist"
cp "$script_directory/../LectureBoardAI/Config/LectureBoardAI.entitlements" \
  "$fixture_root/LectureBoardAI/Config/LectureBoardAI.entitlements"
cp "$script_directory/../docs/architecture.md" "$fixture_root/docs/architecture.md"
cp "$script_directory/../docs/build-verification.md" "$fixture_root/docs/build-verification.md"
cp "$script_directory/../docs/development-plan.md" "$fixture_root/docs/development-plan.md"
cp "$script_directory/../docs/README.md" "$fixture_root/docs/README.md"
cp "$script_directory/../docs/roadmap-ja.md" "$fixture_root/docs/roadmap-ja.md"
cp "$script_directory/../docs/technical-design-ja.md" \
  "$fixture_root/docs/technical-design-ja.md"
cp "$script_directory/../docs/technical-design-detailed-ja.md" \
  "$fixture_root/docs/technical-design-detailed-ja.md"
cp "$script_directory/../docs/local-codex-handoff-ja.md" "$fixture_root/docs/local-codex-handoff-ja.md"
cp "$script_directory/../docs/v1-release-checklist.md" "$fixture_root/docs/v1-release-checklist.md"
cp "$script_directory/../docs/user-acceptance-ja.md" "$fixture_root/docs/user-acceptance-ja.md"
cp "$script_directory/../docs/user-guide.md" "$fixture_root/docs/user-guide.md"
cp "$script_directory/../docs/user-guide-ja.md" "$fixture_root/docs/user-guide-ja.md"
cp "$script_directory/../docs/no-fee-release-process.md" "$fixture_root/docs/no-fee-release-process.md"
cp "$script_directory/../docs/privacy-and-security.md" "$fixture_root/docs/privacy-and-security.md"
cp "$script_directory/../docs/privacy-security-ja.md" "$fixture_root/docs/privacy-security-ja.md"
cp "$script_directory/../docs/release-process.md" "$fixture_root/docs/release-process.md"
cp "$script_directory/../docs/versioning.md" "$fixture_root/docs/versioning.md"
cp "$script_directory/../docs/adr/0006-mit-license.md" \
  "$fixture_root/docs/adr/0006-mit-license.md"
cp "$script_directory/../docs/adr/0007-public-v1-completion.md" \
  "$fixture_root/docs/adr/0007-public-v1-completion.md"
cp "$script_directory/../docs/adr/0011-bound-dense-change-fresh-samples.md" \
  "$fixture_root/docs/adr/0011-bound-dense-change-fresh-samples.md"
cp "$script_directory/../docs/adr/0012-causal-managed-slideshow-binding.md" \
  "$fixture_root/docs/adr/0012-causal-managed-slideshow-binding.md"
cp "$script_directory/../docs/adr/0013-no-fee-public-v1-distribution.md" \
  "$fixture_root/docs/adr/0013-no-fee-public-v1-distribution.md"
cp "$script_directory/../docs/adr/0014-visual-observation-workflow.md" \
  "$fixture_root/docs/adr/0014-visual-observation-workflow.md"
cp "$script_directory/../scripts/check-permission-contract.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/test-check-permission-contract.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/prepublish-check.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/release-artifact-tools.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/release-make-gate.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/release-make-shell.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/test-release-artifact-tools.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/build-release-app.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/test-build-release-app.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/release-exclusive-rename.c" "$fixture_root/scripts/"
cp "$script_directory/../scripts/test-release-exclusive-rename.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/release-package-evidence-tools.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/package-release-dmg.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/test-package-release-dmg.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/no-fee-release-v1.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/test-no-fee-release-v1.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/test-release-shell-security.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/publish-to-github.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/release-preflight.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/test-release-preflight.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/verify-release-code.sh" "$fixture_root/scripts/"
cp "$script_directory/../scripts/test-verify-release-code.sh" "$fixture_root/scripts/"

"$fixture_root/scripts/check-release-definition.sh" >/dev/null

assert_rejects_missing_release_contract() {
  local path="$1" required="$2" label="$3"
  local backup="$path.contract-backup"
  cp "$path" "$backup"
  /usr/bin/python3 -I - "$path" "$required" <<'PY'
import sys
path,required=sys.argv[1:]
data=open(path,encoding="utf-8").read()
if required not in data: raise SystemExit(2)
open(path,"w",encoding="utf-8").write(data.replace(required,"removed-release-contract"))
PY
  if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
    printf 'The release-definition check accepted removal of %s.\n' "$label" >&2
    exit 1
  fi
  mv "$backup" "$path"
}

assert_rejects_missing_release_contract \
  "$fixture_root/scripts/no-fee-release-v1.sh" \
  'prepare --source-dir DIR --tag v1.0.0 --commit OID --test-result FILE --test-result-bundle DIR --gate-log FILE --output-dir DIR' \
  'the evidence-bound prepare interface'
assert_rejects_missing_release_contract \
  "$fixture_root/scripts/no-fee-release-v1.sh" \
  '/usr/bin/xcrun xcresulttool get log --type action' \
  'native action-log provenance validation'
assert_rejects_missing_release_contract \
  "$fixture_root/scripts/no-fee-release-v1.sh" \
  'not decompressor.eof or decompressor.unused_data or decompressor.unconsumed_tail' \
  'raw DEFLATE completion validation'
assert_rejects_missing_release_contract \
  "$fixture_root/scripts/no-fee-release-v1.sh" \
  'approved_snapshot="$public_stage/approved"' \
  'pre-network approved-asset snapshotting'
assert_rejects_missing_release_contract \
  "$fixture_root/scripts/no-fee-release-v1.sh" \
  '-c core.fsmonitor=false -c core.untrackedCache=false' \
  'repository-local fsmonitor suppression'
assert_rejects_missing_release_contract \
  "$fixture_root/scripts/no-fee-release-v1.sh" \
  'blob in {"0"*40,"0"*64} or len(blob)!=len(c)' \
  'null and mixed-format gate-script object rejection'
assert_rejects_missing_release_contract \
  "$fixture_root/scripts/no-fee-release-v1.sh" \
  'for offset in (0,1):' \
  'odd-offset UTF-16 private-path scanning'
assert_rejects_missing_release_contract \
  "$fixture_root/scripts/no-fee-release-v1.sh" \
  '[[ -z "$(/usr/bin/find "$result_bundle" -type l -print -quit)" ]] || return 1' \
  'result-bundle symbolic-link rejection'
assert_rejects_missing_release_contract \
  "$fixture_root/scripts/no-fee-release-v1.sh" \
  '[[ "$build_toolchain_after" == "$build_toolchain_before" ]]' \
  'build-time toolchain continuity'
assert_rejects_missing_release_contract \
  "$fixture_root/scripts/no-fee-release-v1.sh" \
  '[[ "$toolchain" == "$(toolchain_identity)" ]]' \
  'build-to-package toolchain continuity'
assert_rejects_missing_release_contract \
  "$fixture_root/scripts/no-fee-release-v1.sh" \
  'public_acquisition="$(/usr/bin/mktemp -d \' \
  'separate public-input acquisition staging'
assert_rejects_missing_release_contract \
  "$fixture_root/scripts/no-fee-release-v1.sh" \
  '  public_inputs_match_snapshot \' \
  'repeated public-input snapshot validation'
assert_rejects_missing_release_contract \
  "$fixture_root/scripts/release-exclusive-rename.c" \
  '(uintmax_t)source_status.st_ino != expected_source_inode' \
  'exclusive-handoff source identity validation'
assert_rejects_missing_release_contract \
  "$fixture_root/scripts/no-fee-release-v1.sh" \
  'https://api.github.com/repos/akiyama709/lectureboard-ai/releases/tags/v1.0.0' \
  'the fixed unauthenticated public metadata endpoint'
assert_rejects_missing_release_contract \
  "$fixture_root/docs/no-fee-release-process.md" \
  '- `LectureBoard-AI-v1.0.0-test-results.json`;' \
  'the exact public test-evidence asset name'
assert_rejects_missing_release_contract \
  "$fixture_root/docs/no-fee-release-process.md" \
  '`prepublication-gate.log` as private evidence; neither is a GitHub Release asset.' \
  'the private evidence/public asset boundary'
assert_rejects_missing_release_contract \
  "$fixture_root/docs/no-fee-release-process.md" \
  './scripts/no-fee-release-v1.sh verify-public \' \
  'the authoritative unauthenticated public-verification command'
assert_rejects_missing_release_contract \
  "$fixture_root/docs/no-fee-release-process.md" \
  'publish only those five attachments in an immutable,' \
  'the immutable exact-five publication requirement'
assert_rejects_missing_release_contract \
  "$fixture_root/docs/adr/0013-no-fee-public-v1-distribution.md" \
  'public, immutable, non-prerelease `v1.0.0` GitHub Release' \
  'the ADR immutable final-release requirement'
assert_rejects_missing_release_contract \
  "$fixture_root/docs/adr/0013-no-fee-public-v1-distribution.md" \
  '- `LectureBoard-AI-v1.0.0-arm64.zip`;' \
  'the ADR exact application-archive filename'

for required_release_tool in \
  release-artifact-tools.sh \
  release-make-gate.sh \
  release-make-shell.sh \
  test-release-artifact-tools.sh \
  build-release-app.sh \
  test-build-release-app.sh \
  release-exclusive-rename.c \
  test-release-exclusive-rename.sh \
  release-package-evidence-tools.sh \
  package-release-dmg.sh \
  test-package-release-dmg.sh \
  no-fee-release-v1.sh \
  test-no-fee-release-v1.sh \
  test-release-shell-security.sh \
  publish-to-github.sh; do
  mv "$fixture_root/scripts/$required_release_tool" \
    "$fixture_root/scripts/$required_release_tool.missing"
  if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
    printf 'The release-definition check accepted a missing release tool: %s.\n' \
      "$required_release_tool" >&2
    exit 1
  fi
  mv "$fixture_root/scripts/$required_release_tool.missing" \
    "$fixture_root/scripts/$required_release_tool"
done

cp "$fixture_root/scripts/release-package-evidence-tools.sh" \
  "$fixture_root/scripts/release-package-evidence-tools.backup"
printf '\nif then\n' >>"$fixture_root/scripts/release-package-evidence-tools.sh"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted malformed package-evidence helper syntax.\n' >&2
  exit 1
fi
mv "$fixture_root/scripts/release-package-evidence-tools.backup" \
  "$fixture_root/scripts/release-package-evidence-tools.sh"

cp "$fixture_root/scripts/prepublish-check.sh" \
  "$fixture_root/scripts/prepublish-check.backup"
sed 's/\[16\/26\]/[16\/25]/' \
  "$fixture_root/scripts/prepublish-check.backup" \
  >"$fixture_root/scripts/prepublish-check.sh"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted inconsistent prepublish stage numbering.\n' >&2
  exit 1
fi
mv "$fixture_root/scripts/prepublish-check.backup" \
  "$fixture_root/scripts/prepublish-check.sh"

cp "$fixture_root/scripts/prepublish-check.sh" \
  "$fixture_root/scripts/prepublish-check.backup"
/usr/bin/awk '
  /^echo "\[1\/26\]/ && !injected {
    print "exit 0"
    injected = 1
  }
  { print }
' "$fixture_root/scripts/prepublish-check.backup" \
  >"$fixture_root/scripts/prepublish-check.sh"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a pre-stage early-success exit.\n' >&2
  exit 1
fi
mv "$fixture_root/scripts/prepublish-check.backup" \
  "$fixture_root/scripts/prepublish-check.sh"

# Every numbered stage is an execution contract, not merely a progress label.
# Replacing the whole command block of any one stage with a no-op must make the
# release-definition check fail.
for stage_number in $(/usr/bin/seq 1 26); do
  cp "$fixture_root/scripts/prepublish-check.sh" \
    "$fixture_root/scripts/prepublish-check.backup"
  /usr/bin/awk -v target="$stage_number" '
    BEGIN { replacing = 0; replacement_written = 0 }
    $0 ~ "^echo \\\"\\[" target "/26\\]" {
      print
      replacing = 1
      next
    }
    replacing && /^echo "\[[0-9]+\/26\]/ {
      print ":"
      replacement_written = 1
      replacing = 0
    }
    !replacing { print }
    END {
      if (replacing && !replacement_written) {
        print ":"
      }
    }
  ' "$fixture_root/scripts/prepublish-check.backup" \
    >"$fixture_root/scripts/prepublish-check.sh"
  if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
    printf 'The release-definition check accepted a no-op command block for stage %s.\n' \
      "$stage_number" >&2
    exit 1
  fi
  mv "$fixture_root/scripts/prepublish-check.backup" \
    "$fixture_root/scripts/prepublish-check.sh"
done

# A privileged entrypoint must carry its required interpreter on line one.
# Merely retaining the expected shebang later in the file is insufficient.
for privileged_entry in check-release-definition.sh prepublish-check.sh; do
  entry_path="$fixture_root/scripts/$privileged_entry"
  cp "$entry_path" "$entry_path.shebang-backup"
  {
    /usr/bin/printf '#!/bin/bash\n'
    /usr/bin/tail -n +2 "$entry_path.shebang-backup"
    /usr/bin/printf '\n#!/bin/bash -p\n'
  } >"$entry_path"
  if /bin/bash -p "$fixture_root/scripts/check-release-definition.sh" \
    >/dev/null 2>&1; then
    printf 'The release-definition check accepted a misplaced privileged shebang: %s.\n' \
      "$privileged_entry" >&2
    exit 1
  fi
  mv "$entry_path.shebang-backup" "$entry_path"
done

# Caller PATH contents cannot replace the checker utilities.
fake_bin="$fixture_root/fake-bin"
fake_grep_marker="$fixture_root/fake-grep-ran"
mkdir -p "$fake_bin"
{
  /usr/bin/printf '#!/bin/bash\n'
  /usr/bin/printf '/usr/bin/touch "${FAKE_GREP_MARKER:?}"\n'
  /usr/bin/printf 'exec /usr/bin/grep "$@"\n'
} >"$fake_bin/grep"
/bin/chmod 755 "$fake_bin/grep"
FAKE_GREP_MARKER="$fake_grep_marker" PATH="$fake_bin:/usr/bin:/bin:/usr/sbin:/sbin" \
  "$fixture_root/scripts/check-release-definition.sh" >/dev/null
if [[ -e "$fake_grep_marker" || -L "$fake_grep_marker" ]]; then
  printf 'The release-definition check executed a caller-supplied grep.\n' >&2
  exit 1
fi

for required_prepublish_target in \
  test-release-artifact-tools-script \
  test-build-release-app-script \
  test-release-exclusive-rename-script \
  check-release-package-evidence-tools-script \
  test-package-release-dmg-script \
  test-no-fee-release-v1-script \
  test-release-shell-security-script \
  test-release-preflight-script \
  test-verify-release-code-script; do
  cp "$fixture_root/scripts/prepublish-check.sh" \
    "$fixture_root/scripts/prepublish-check.backup"
  sed "s/$required_prepublish_target/removed-release-gate/" \
    "$fixture_root/scripts/prepublish-check.backup" \
    >"$fixture_root/scripts/prepublish-check.sh"
  if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
    printf 'The release-definition check accepted a missing prepublish target: %s.\n' \
      "$required_prepublish_target" >&2
    exit 1
  fi
  mv "$fixture_root/scripts/prepublish-check.backup" \
    "$fixture_root/scripts/prepublish-check.sh"
done

cp "$fixture_root/Makefile" "$fixture_root/Makefile.backup"
sed 's/test-package-release-dmg-script:/package-release-dmg-test-removed:/' \
  "$fixture_root/Makefile.backup" >"$fixture_root/Makefile"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a Makefile without the package test target.\n' >&2
  exit 1
fi
mv "$fixture_root/Makefile.backup" "$fixture_root/Makefile"

cp "$fixture_root/.github/workflows/ci.yml" "$fixture_root/.github/workflows/ci.backup.yml"
sed 's/runs-on: macos-26/runs-on: macos-15/' \
  "$fixture_root/.github/workflows/ci.backup.yml" \
  >"$fixture_root/.github/workflows/ci.yml"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted CI without the required macOS 26 native gate.\n' >&2
  exit 1
fi
mv "$fixture_root/.github/workflows/ci.backup.yml" "$fixture_root/.github/workflows/ci.yml"

assert_rejects_provenance_overclaim() {
  local path="$1"
  local forbidden="$2"
  local label="$3"
  local backup="$path.provenance-backup"

  cp "$path" "$backup"
  printf '\n%s\n' "$forbidden" >>"$path"
  if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
    printf 'The release-definition check accepted an overstrong %s provenance claim.\n' \
      "$label" >&2
    exit 1
  fi
  mv "$backup" "$path"
}

assert_rejects_provenance_overclaim \
  "$fixture_root/AGENTS.md" \
  'validate exactly six controlled inputs spaced eight seconds apart against exactly six non-reused interval-contained revision events' \
  'AGENTS detail'
assert_rejects_provenance_overclaim \
  "$fixture_root/AGENTS.md" \
  'one strictly interval-bounded six-input run' \
  'AGENTS summary'
assert_rejects_provenance_overclaim \
  "$fixture_root/ROADMAP.md" \
  'strictly matched exactly six inputs spaced eight seconds apart' \
  'ROADMAP'
assert_rejects_provenance_overclaim \
  "$fixture_root/docs/architecture.md" \
  'It strictly matched exactly six inputs spaced eight seconds apart' \
  'architecture'
assert_rejects_provenance_overclaim \
  "$fixture_root/docs/adr/0011-bound-dense-change-fresh-samples.md" \
  'Exactly six inputs spaced eight seconds apart mapped to six non-reused events within their strict input intervals' \
  'ADR 0011'
assert_rejects_provenance_overclaim \
  "$fixture_root/docs/local-codex-handoff-ja.md" \
  '各input completion後から次input開始前，又は最終cutoff前へ厳密に対応付け' \
  'local handoff detail'
assert_rejects_provenance_overclaim \
  "$fixture_root/docs/local-codex-handoff-ja.md" \
  '8秒間隔6入力のstrict dynamic interval及びsingle-stroke／eraseを完了した' \
  'local handoff summary'
assert_rejects_provenance_overclaim \
  "$fixture_root/README.md" \
  'six strictly input-bounded revision intervals' \
  'README'

mv "$fixture_root/docs/v1-release-checklist.md" "$fixture_root/docs/v1-release-checklist.backup"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing v1 checklist.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/v1-release-checklist.backup" "$fixture_root/docs/v1-release-checklist.md"

mv "$fixture_root/docs/user-acceptance-ja.md" "$fixture_root/docs/user-acceptance-ja.backup"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing user-acceptance procedure.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/user-acceptance-ja.backup" "$fixture_root/docs/user-acceptance-ja.md"

cp "$fixture_root/docs/user-acceptance-ja.md" \
  "$fixture_root/docs/user-acceptance-ja.backup"
sed 's/現在の状態は\*\*未実施\*\*である/現在の状態は完了である/' \
  "$fixture_root/docs/user-acceptance-ja.backup" \
  >"$fixture_root/docs/user-acceptance-ja.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a user-acceptance procedure without an unverified initial state.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/user-acceptance-ja.backup" "$fixture_root/docs/user-acceptance-ja.md"

cp "$fixture_root/docs/user-acceptance-ja.md" \
  "$fixture_root/docs/user-acceptance-ja.backup"
sed 's/少なくとも1件の自動板書がPowerPoint上に実際に見えることを目視確認する/診断値だけを成功とみなす/' \
  "$fixture_root/docs/user-acceptance-ja.backup" \
  >"$fixture_root/docs/user-acceptance-ja.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted owner acceptance without visible automatic board output.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/user-acceptance-ja.backup" "$fixture_root/docs/user-acceptance-ja.md"

cp "$fixture_root/docs/user-acceptance-ja.md" \
  "$fixture_root/docs/user-acceptance-ja.backup"
/usr/bin/python3 -I - "$fixture_root/docs/user-acceptance-ja.md" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
stop = "10. Appの取得を停止し，PowerPoint slide showが開いたまま通常操作できることを確認する．"
export = "11. 取得状態が停止済みであることを確認してから，lecture sessionをJSON及びSVGへexportし，slide画像，OCR全文，音声，文字起こし，window title又は非公開intentが含まれないことを確認する．"
lines = path.read_text(encoding="utf-8").splitlines(keepends=True)
if sum(line.rstrip("\r\n") == stop for line in lines) != 1:
    raise SystemExit(2)
if sum(line.rstrip("\r\n") == export for line in lines) != 1:
    raise SystemExit(2)
stop_index = next(index for index, line in enumerate(lines) if line.rstrip("\r\n") == stop)
export_index = next(index for index, line in enumerate(lines) if line.rstrip("\r\n") == export)
lines[stop_index], lines[export_index] = lines[export_index], lines[stop_index]
path.write_text("".join(lines), encoding="utf-8")
PY
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted session export before capture stop and PowerPoint handback.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/user-acceptance-ja.backup" "$fixture_root/docs/user-acceptance-ja.md"

mv "$fixture_root/docs/user-guide.md" "$fixture_root/docs/user-guide.backup"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing user guide.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/user-guide.backup" "$fixture_root/docs/user-guide.md"

cp "$fixture_root/docs/user-guide-ja.md" "$fixture_root/docs/user-guide-ja.backup"
sed 's/Gatekeeper全体を無効化せず，Terminalでquarantine metadataを除去しない/Gatekeeperを無効化する/' \
  "$fixture_root/docs/user-guide-ja.backup" >"$fixture_root/docs/user-guide-ja.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted an unsafe Gatekeeper guide.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/user-guide-ja.backup" "$fixture_root/docs/user-guide-ja.md"

mv "$fixture_root/docs/privacy-and-security.md" "$fixture_root/docs/privacy-and-security.backup"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing privacy statement.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/privacy-and-security.backup" "$fixture_root/docs/privacy-and-security.md"

cp "$fixture_root/docs/privacy-security-ja.md" \
  "$fixture_root/docs/privacy-security-ja.backup"
sed 's/network fallbackを許さず文字起こしを開始しない/network fallbackを許す/' \
  "$fixture_root/docs/privacy-security-ja.backup" \
  >"$fixture_root/docs/privacy-security-ja.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a privacy statement that permits speech network fallback.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/privacy-security-ja.backup" "$fixture_root/docs/privacy-security-ja.md"

mv "$fixture_root/docs/no-fee-release-process.md" "$fixture_root/docs/no-fee-release-process.backup"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing no-fee distribution process.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/no-fee-release-process.backup" "$fixture_root/docs/no-fee-release-process.md"

mv "$fixture_root/docs/release-process.md" "$fixture_root/docs/release-process.backup"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing distribution process.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/release-process.backup" "$fixture_root/docs/release-process.md"

mv "$fixture_root/docs/versioning.md" "$fixture_root/docs/versioning.backup"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted missing versioning rules.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/versioning.backup" "$fixture_root/docs/versioning.md"

mv "$fixture_root/LectureBoardAI/Config/LectureBoardAI.entitlements" \
  "$fixture_root/LectureBoardAI/Config/LectureBoardAI.entitlements.backup"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing release entitlement allowlist.\n' >&2
  exit 1
fi
mv "$fixture_root/LectureBoardAI/Config/LectureBoardAI.entitlements.backup" \
  "$fixture_root/LectureBoardAI/Config/LectureBoardAI.entitlements"

cp "$fixture_root/LectureBoardAI/Config/LectureBoardAI.entitlements" \
  "$fixture_root/LectureBoardAI/Config/LectureBoardAI.entitlements.backup"
sed '/<\/dict>/i\
\t<key>com.apple.security.automation.apple-events</key>\
\t<true\/>' \
  "$fixture_root/LectureBoardAI/Config/LectureBoardAI.entitlements.backup" \
  >"$fixture_root/LectureBoardAI/Config/LectureBoardAI.entitlements"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted the Automation entitlement.\n' >&2
  exit 1
fi
mv "$fixture_root/LectureBoardAI/Config/LectureBoardAI.entitlements.backup" \
  "$fixture_root/LectureBoardAI/Config/LectureBoardAI.entitlements"

cp "$fixture_root/LectureBoardAI/Config/Info.plist" \
  "$fixture_root/LectureBoardAI/Config/Info.plist.backup"
sed '/<\/dict>/i\
\t<key>NSAppleEventsUsageDescription</key>\
\t<string>Unexpected Automation request<\/string>' \
  "$fixture_root/LectureBoardAI/Config/Info.plist.backup" \
  >"$fixture_root/LectureBoardAI/Config/Info.plist"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted an Apple Events usage description.\n' >&2
  exit 1
fi
mv "$fixture_root/LectureBoardAI/Config/Info.plist.backup" \
  "$fixture_root/LectureBoardAI/Config/Info.plist"

mv "$fixture_root/scripts/release-preflight.sh" "$fixture_root/scripts/release-preflight.backup"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing release preflight.\n' >&2
  exit 1
fi
mv "$fixture_root/scripts/release-preflight.backup" "$fixture_root/scripts/release-preflight.sh"

mv "$fixture_root/docs/adr/0011-bound-dense-change-fresh-samples.md" \
  "$fixture_root/docs/adr/0011-bound-dense-change-fresh-samples.backup"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing ADR 0011.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/adr/0011-bound-dense-change-fresh-samples.backup" \
  "$fixture_root/docs/adr/0011-bound-dense-change-fresh-samples.md"

mv "$fixture_root/docs/adr/0012-causal-managed-slideshow-binding.md" \
  "$fixture_root/docs/adr/0012-causal-managed-slideshow-binding.backup"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing ADR 0012.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/adr/0012-causal-managed-slideshow-binding.backup" \
  "$fixture_root/docs/adr/0012-causal-managed-slideshow-binding.md"

mv "$fixture_root/docs/adr/0013-no-fee-public-v1-distribution.md" \
  "$fixture_root/docs/adr/0013-no-fee-public-v1-distribution.backup"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing ADR 0013.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/adr/0013-no-fee-public-v1-distribution.backup" \
  "$fixture_root/docs/adr/0013-no-fee-public-v1-distribution.md"

mv "$fixture_root/docs/adr/0014-visual-observation-workflow.md" \
  "$fixture_root/docs/adr/0014-visual-observation-workflow.backup"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing ADR 0014.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/adr/0014-visual-observation-workflow.backup" \
  "$fixture_root/docs/adr/0014-visual-observation-workflow.md"

cp "$fixture_root/ROADMAP.md" "$fixture_root/ROADMAP.backup"
sed 's/## Milestone 7 — Public v1.0.0 GitHub Release/## Milestone 7 — Removed/' \
  "$fixture_root/ROADMAP.backup" >"$fixture_root/ROADMAP.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing public v1 milestone.\n' >&2
  exit 1
fi
mv "$fixture_root/ROADMAP.backup" "$fixture_root/ROADMAP.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/Completion means publication of the public, immutable, non-prerelease `v1.0.0` GitHub Release/Completion definition removed/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing README completion definition.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult/Test-LectureBoardAI-2026.09.01_22-41-57-+0900.xcresult/g' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a stale current gate pointer.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/No alpha, beta, or release-candidate application Release will be published/Prerelease status removed/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted removal of the final-only application-release policy.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/Status: \*\*pre-release development\*\*/Status: **complete**/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a false README completion status.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/each confirmed significant visual change starts a new local slide epoch/visual change handling removed/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted removal of the local visual-epoch invariant.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/A shared bounded one-shot fresh-sample path for either an exact post-baseline coarse candidate or a pending dense candidate/A bounded one-shot fresh-sample path for a pending dense content-change candidate/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a dense-only README fresh-sample status.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/c7a73f7cb1bdcaa46ec216218883872d480630f7cf4ff177170f8d1906c14a3c/current-live-dynamic-report-removed/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted removal of the current live dynamic README evidence.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
printf '\nno capture or input occurred and no static report exists\n' \
  >>"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted stale locked-checkpoint wording.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
printf '\nlive current-source `SCScreenshotManager` attachments, timing, coarse confirmation, and post-erase behavior remain unverified\n' \
  >>"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted stale current post-erase wording.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/two aggregate visual revision events in separate ink and erase phases/a separately attributed post-erase content revision/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted stale English post-erase wording.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/Successful live `boundedFreshSample` confirmation through the shared exact-post-baseline-coarse or pending-dense one-shot path/Live PowerPoint behavior of the shared path, including whether it records a distinct post-erase revision/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a stale bounded-fresh live gate.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/取得timing及びone-shot確定は未検証です．現行continuous経路では別個の消去phase revisionを確認しましたが/取得timing及び消去後revisionは未検証です．/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted stale Japanese post-erase wording.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/docs/README.md" "$fixture_root/docs/README.backup"
sed 's/ADR 0011 — Bound one-shot samples to the current visual-change candidate/ADR 0011 — Bounded dense-change fresh samples/' \
  "$fixture_root/docs/README.backup" >"$fixture_root/docs/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted the stale ADR 0011 display title.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/README.backup" "$fixture_root/docs/README.md"

cp "$fixture_root/docs/README.md" "$fixture_root/docs/README.backup"
sed '/ADR 0014 — Visual-only observation workflow for public v1/d' \
  "$fixture_root/docs/README.backup" >"$fixture_root/docs/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing ADR 0014 index link.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/README.backup" "$fixture_root/docs/README.md"

cp "$fixture_root/docs/build-verification.md" \
  "$fixture_root/docs/build-verification.backup"
sed 's/At that schema-10 checkpoint, this automated evidence had not established/This automated evidence does not establish that live PowerPoint supplies/' \
  "$fixture_root/docs/build-verification.backup" \
  >"$fixture_root/docs/build-verification.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted current-tense schema-10 history.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/build-verification.backup" \
  "$fixture_root/docs/build-verification.md"

cp "$fixture_root/docs/build-verification.md" \
  "$fixture_root/docs/build-verification.backup"
sed '/ADR 0013 now supersedes its Developer ID and Apple-notarization requirements/d' \
  "$fixture_root/docs/build-verification.backup" \
  >"$fixture_root/docs/build-verification.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted unqualified obsolete Developer ID completion history.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/build-verification.backup" \
  "$fixture_root/docs/build-verification.md"

cp "$fixture_root/docs/development-plan.md" \
  "$fixture_root/docs/development-plan.backup"
sed 's/Stable visual-frame detection and persistent visual-content-update detection/Stable-frame and slide-change detection/' \
  "$fixture_root/docs/development-plan.backup" \
  >"$fixture_root/docs/development-plan.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted semantic slide-change overclaim wording.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/development-plan.backup" \
  "$fixture_root/docs/development-plan.md"

cp "$fixture_root/docs/technical-design-ja.md" \
  "$fixture_root/docs/technical-design-ja.backup"
sed 's/現行ソースはschema 11のdecoder-hardenedな公開前開発sourceである/本準備環境で8件の自動テストが通過した/' \
  "$fixture_root/docs/technical-design-ja.backup" \
  >"$fixture_root/docs/technical-design-ja.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted the obsolete pre-Mac design status.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/technical-design-ja.backup" \
  "$fixture_root/docs/technical-design-ja.md"

cp "$fixture_root/docs/architecture.md" "$fixture_root/docs/architecture.backup"
sed 's/The earlier schema-9 live erase candidates did not receive the third qualifying observation/The live erase candidate did not receive the third qualifying observation/' \
  "$fixture_root/docs/architecture.backup" >"$fixture_root/docs/architecture.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted an unqualified historical erase result.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/architecture.backup" "$fixture_root/docs/architecture.md"

cp "$fixture_root/docs/technical-design-detailed-ja.md" \
  "$fixture_root/docs/technical-design-detailed-ja.backup"
sed 's/同一のpost-baseline coarse視覚差分候補又はdense内容更新候補がpendingである間だけ/同一のdense内容更新候補がpendingである間だけ/' \
  "$fixture_root/docs/technical-design-detailed-ja.backup" \
  >"$fixture_root/docs/technical-design-detailed-ja.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a dense-only detailed design.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/technical-design-detailed-ja.backup" \
  "$fixture_root/docs/technical-design-detailed-ja.md"

cp "$fixture_root/docs/v1-release-checklist.md" \
  "$fixture_root/docs/v1-release-checklist.backup"
sed 's/The application uses the hardened runtime and an ad hoc signature with no team identity or secure timestamp/The application uses a release signature/' \
  "$fixture_root/docs/v1-release-checklist.backup" \
  >"$fixture_root/docs/v1-release-checklist.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing hardened-runtime gate.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/v1-release-checklist.backup" \
  "$fixture_root/docs/v1-release-checklist.md"

cp "$fixture_root/docs/v1-release-checklist.md" \
  "$fixture_root/docs/v1-release-checklist.backup"
sed 's/All five attached assets are downloaded from the public GitHub Release into a clean verification environment/Only the archive page is inspected/' \
  "$fixture_root/docs/v1-release-checklist.backup" \
  >"$fixture_root/docs/v1-release-checklist.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a missing public-artifact re-download gate.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/v1-release-checklist.backup" \
  "$fixture_root/docs/v1-release-checklist.md"

cp "$fixture_root/docs/v1-release-checklist.md" \
  "$fixture_root/docs/v1-release-checklist.backup"
sed 's/Bundle identity, ad hoc signature, hardened runtime, architecture, version, entitlement allowlist, SBOM, and provenance are independently rechecked/Downloaded-artifact security rechecks removed/' \
  "$fixture_root/docs/v1-release-checklist.backup" \
  >"$fixture_root/docs/v1-release-checklist.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted missing downloaded-artifact security rechecks.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/v1-release-checklist.backup" \
  "$fixture_root/docs/v1-release-checklist.md"

for guide in docs/user-guide.md docs/user-guide-ja.md; do
  cp "$fixture_root/$guide" "$fixture_root/$guide.backup"
  sed 's/shasum -a 256 -c SHA256SUMS/shasum -a 256 "LectureBoard-AI-1.0.0-macos-arm64.zip"/' \
    "$fixture_root/$guide.backup" >"$fixture_root/$guide"
  if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
    printf 'The release-definition check accepted an obsolete archive verification command in %s.\n' \
      "$guide" >&2
    exit 1
  fi
  mv "$fixture_root/$guide.backup" "$fixture_root/$guide"
done

for guide in docs/user-guide.md docs/user-guide-ja.md; do
  cp "$fixture_root/$guide" "$fixture_root/$guide.backup"
  sed 's|cd -- "/absolute/path/to/downloaded-release-assets"|cd -- "/wrong/directory"|' \
    "$fixture_root/$guide.backup" >"$fixture_root/$guide"
  if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
    printf 'The release-definition check accepted checksum verification outside the downloaded-asset directory in %s.\n' \
      "$guide" >&2
    exit 1
  fi
  mv "$fixture_root/$guide.backup" "$fixture_root/$guide"
done

cp "$fixture_root/docs/no-fee-release-process.md" \
  "$fixture_root/docs/no-fee-release-process.backup"
sed 's/after both macOS `ditto` and `\/usr\/bin\/unzip` extraction\./after one extraction method./' \
  "$fixture_root/docs/no-fee-release-process.backup" \
  >"$fixture_root/docs/no-fee-release-process.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted removal of the dual-extractor signature gate.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/no-fee-release-process.backup" \
  "$fixture_root/docs/no-fee-release-process.md"

cp "$fixture_root/docs/no-fee-release-process.md" \
  "$fixture_root/docs/no-fee-release-process.backup"
sed 's/`compare-public` command is available only when the five public assets and both public metadata/Only one downloaded ZIP is compared/' \
  "$fixture_root/docs/no-fee-release-process.backup" \
  >"$fixture_root/docs/no-fee-release-process.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted removal of the five-asset public comparison.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/no-fee-release-process.backup" \
  "$fixture_root/docs/no-fee-release-process.md"

cp "$fixture_root/README.md" "$fixture_root/README.backup"
sed 's/正確な5件だけを添付した/個数不明のassetを添付した/' \
  "$fixture_root/README.backup" >"$fixture_root/README.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted missing Japanese test-evidence disclosure.\n' >&2
  exit 1
fi
mv "$fixture_root/README.backup" "$fixture_root/README.md"

cp "$fixture_root/ROADMAP.md" "$fixture_root/ROADMAP.backup"
sed 's/Run the unauthenticated `verify-public` transaction to retain public REST metadata and annotated-tag refs/Download only the public ZIP/' \
  "$fixture_root/ROADMAP.backup" >"$fixture_root/ROADMAP.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a ZIP-only public re-download roadmap.\n' >&2
  exit 1
fi
mv "$fixture_root/ROADMAP.backup" "$fixture_root/ROADMAP.md"

cp "$fixture_root/docs/v1-release-checklist.md" \
  "$fixture_root/docs/v1-release-checklist.backup"
sed 's/omits unneeded AppleDouble\/resource-fork\/extended-attribute entries/preserves archive metadata/' \
  "$fixture_root/docs/v1-release-checklist.backup" \
  >"$fixture_root/docs/v1-release-checklist.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted removal of the AppleDouble exclusion gate.\n' >&2
  exit 1
fi
mv "$fixture_root/docs/v1-release-checklist.backup" \
  "$fixture_root/docs/v1-release-checklist.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
sed 's/Deterministic stable-frame and significant visual\/content-change classification with unit tests/Deterministic stable-frame and slide-change detection with unit tests/' \
  "$fixture_root/CHANGELOG.backup" >"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted an overclaim of implemented slide-change detection.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
printf '\n- Deterministic stable-frame and slide-change detection with unit tests\n' \
  >>"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted an appended slide-change overclaim.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
sed 's/Metadata-only schema-11 latest-content-revision evidence with exact ordinal/Metadata-only revision evidence/' \
  "$fixture_root/CHANGELOG.backup" >"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted removal of the schema-11 changelog sentinel.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
sed 's/A shared bounded one-shot fresh-sample path for either an exact post-baseline coarse candidate or a pending dense candidate/A bounded one-shot fresh-sample path for a pending dense content-change candidate/' \
  "$fixture_root/CHANGELOG.backup" >"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted a dense-only changelog fresh-sample status.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
sed 's/The byte-identical 2026-09-01 checkpoint runtime preserved as `LectureBoard AI Schema 11 Decoder Hardened Verification.app`/Historical runtime evidence removed/' \
  "$fixture_root/CHANGELOG.backup" >"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted removal of the current live changelog sentinel.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
sed 's/that schema-8 attempt did not verify dynamic slides or mouse ink/dynamic slides and mouse ink remain unverified/' \
  "$fixture_root/CHANGELOG.backup" >"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted current-tense schema-8 history.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
sed 's/including a controlled post-erase candidate confirmed by that source/including a separately identified post-erase rerun/' \
  "$fixture_root/CHANGELOG.backup" >"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted an ambiguous planned erase checkpoint.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
sed 's/Build-specific historical synthetic PowerPoint evidence for static frame delivery, Vision execution, and pre-semantic dynamic calibration; not evidence for the current semantic build/Controlled synthetic PowerPoint runtime evidence for current static frame delivery and Vision execution/' \
  "$fixture_root/CHANGELOG.backup" >"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted historical runtime evidence as current-build evidence.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
printf '\n- Controlled synthetic PowerPoint runtime evidence for current static frame delivery and Vision execution\n' \
  >>"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted appended historical evidence as current evidence.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
sed 's/Owner validation of the visual-only workflow with an exact audience-facing PowerPoint slide-show window and natural lecture speech/Owner visual-only validation is complete/' \
  "$fixture_root/CHANGELOG.backup" >"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted removal of the unverified production identity-provider gate.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/CHANGELOG.md" "$fixture_root/CHANGELOG.backup"
printf '\n- PowerPoint slide identity is complete\n' >>"$fixture_root/CHANGELOG.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted an appended production-identity overclaim.\n' >&2
  exit 1
fi
mv "$fixture_root/CHANGELOG.backup" "$fixture_root/CHANGELOG.md"

cp "$fixture_root/docs/adr/0006-mit-license.md" \
  "$fixture_root/docs/adr/0006-mit-license.backup"
sed 's/Accepted for the initial public source repository; review remains required for materially changed v1.0.0 scope/Accepted for the alpha scaffold, pending institutional review before public publication/' \
  "$fixture_root/docs/adr/0006-mit-license.backup" \
  >"$fixture_root/docs/adr/0006-mit-license.md"
if "$fixture_root/scripts/check-release-definition.sh" >/dev/null 2>&1; then
  printf 'The release-definition check accepted the obsolete pre-publication review status.\n' >&2
  exit 1
fi

printf 'Release-definition regression fixtures passed.\n'
