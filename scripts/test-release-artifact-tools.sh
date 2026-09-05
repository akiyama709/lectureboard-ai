#!/bin/bash -p
case "$-" in
  *p*) ;;
  *) /usr/bin/printf "Release shell entry requires Bash privileged mode.\n" >&2; exit 78 ;;
esac
set -euo pipefail
export LC_ALL=C
export PATH='/usr/bin:/bin:/usr/sbin:/sbin'

script_directory="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
tools_script="$script_directory/release-artifact-tools.sh"
temporary_parent="${TMPDIR:-/tmp}"
temporary_parent="${temporary_parent%/}"
temporary_root="$(/usr/bin/mktemp -d "$temporary_parent/lectureboard-artifact-tools-tests.XXXXXX")"

cleanup() {
  case "$temporary_root" in
    "$temporary_parent"/lectureboard-artifact-tools-tests.*)
      /usr/bin/find "$temporary_root" -depth -delete
      ;;
  esac
}
trap cleanup EXIT

/bin/bash -p -n "$tools_script" "$0"

tree_one="$temporary_root/tree-one"
tree_two="$temporary_root/tree-two"
/bin/mkdir -p "$tree_one/Contents/MacOS" "$tree_two/Contents/MacOS"
printf 'binary\n' >"$tree_one/Contents/MacOS/App"
printf 'binary\n' >"$tree_two/Contents/MacOS/App"
/bin/chmod 755 "$tree_one/Contents/MacOS/App" "$tree_two/Contents/MacOS/App"
/bin/bash -p "$tools_script" tree-manifest \
  --root "$tree_one" --output "$temporary_root/tree-one.manifest"
/bin/bash -p "$tools_script" tree-manifest \
  --root "$tree_two" --output "$temporary_root/tree-two.manifest"
/usr/bin/cmp -s "$temporary_root/tree-one.manifest" "$temporary_root/tree-two.manifest"

printf 'changed\n' >"$tree_two/Contents/MacOS/App"
/bin/bash -p "$tools_script" tree-manifest \
  --root "$tree_two" --output "$temporary_root/tree-two-changed.manifest"
if /usr/bin/cmp -s "$temporary_root/tree-one.manifest" "$temporary_root/tree-two-changed.manifest"; then
  printf 'Tree manifest did not detect a byte change.\n' >&2
  exit 1
fi
printf 'binary\n' >"$tree_two/Contents/MacOS/App"
/bin/chmod 644 "$tree_two/Contents/MacOS/App"
/bin/bash -p "$tools_script" tree-manifest \
  --root "$tree_two" --output "$temporary_root/tree-two-mode.manifest"
if /usr/bin/cmp -s "$temporary_root/tree-one.manifest" "$temporary_root/tree-two-mode.manifest"; then
  printf 'Tree manifest did not detect a mode change.\n' >&2
  exit 1
fi
/bin/ln -s App "$tree_two/Contents/MacOS/LinkedApp"
/bin/bash -p "$tools_script" tree-manifest \
  --root "$tree_two" --output "$temporary_root/tree-two-link.manifest"
/usr/bin/grep -Fq 'link|' "$temporary_root/tree-two-link.manifest"

/bin/unlink "$tree_two/Contents/MacOS/LinkedApp"
/bin/chmod 755 "$tree_two/Contents/MacOS/App"
/usr/bin/xattr -w io.github.akiyama709.LectureBoardFixture metadata \
  "$tree_two/Contents/MacOS/App"
/bin/bash -p "$tools_script" tree-manifest \
  --root "$tree_two" --output "$temporary_root/tree-two-xattr.manifest"
if /usr/bin/cmp -s "$temporary_root/tree-one.manifest" "$temporary_root/tree-two-xattr.manifest"; then
  printf 'Tree manifest did not detect an extended-attribute change.\n' >&2
  exit 1
fi
/usr/bin/xattr -d io.github.akiyama709.LectureBoardFixture \
  "$tree_two/Contents/MacOS/App"
/usr/bin/chflags hidden "$tree_two/Contents/MacOS/App"
/bin/bash -p "$tools_script" tree-manifest \
  --root "$tree_two" --output "$temporary_root/tree-two-flags.manifest"
if /usr/bin/cmp -s "$temporary_root/tree-one.manifest" "$temporary_root/tree-two-flags.manifest"; then
  printf 'Tree manifest did not detect a BSD-flags change.\n' >&2
  exit 1
fi
/usr/bin/chflags nohidden "$tree_two/Contents/MacOS/App"
/bin/chmod +a 'everyone deny delete' "$tree_two/Contents/MacOS/App"
/bin/bash -p "$tools_script" tree-manifest \
  --root "$tree_two" --output "$temporary_root/tree-two-acl.manifest"
if /usr/bin/cmp -s "$temporary_root/tree-one.manifest" "$temporary_root/tree-two-acl.manifest"; then
  printf 'Tree manifest did not detect an ACL change.\n' >&2
  exit 1
fi
/bin/chmod -N "$tree_two/Contents/MacOS/App"

unsafe_manifest_tree="$temporary_root/unsafe-manifest-tree"
/bin/mkdir "$unsafe_manifest_tree"
printf 'unsafe\n' >"$unsafe_manifest_tree/name|with-delimiter"
if /bin/bash -p "$tools_script" tree-manifest \
  --root "$unsafe_manifest_tree" --output "$temporary_root/unsafe.manifest" \
  >/dev/null 2>&1; then
  printf 'Tree manifest accepted a path that cannot be represented safely.\n' >&2
  exit 1
fi
if [[ -e "$temporary_root/unsafe.manifest" || -L "$temporary_root/unsafe.manifest" ]]; then
  printf 'Tree manifest committed partial output after a producer failure.\n' >&2
  exit 1
fi

git_source_repository="$temporary_root/git-source-repository"
/bin/mkdir "$git_source_repository"
/usr/bin/git -C "$git_source_repository" init -q
printf '%s\n' 'literal $Format:%H$ payload' >"$git_source_repository/payload.txt"
printf '%s\n' 'stable' >"$git_source_repository/stable.txt"
/usr/bin/git -C "$git_source_repository" add payload.txt stable.txt
/usr/bin/git -C "$git_source_repository" \
  -c user.name='LectureBoard Fixture' \
  -c user.email='fixture@example.invalid' \
  commit -q -m fixture
git_source_commit="$(/usr/bin/git -C "$git_source_repository" rev-parse HEAD)"
git_source_clean="$temporary_root/git-source-clean"
/bin/mkdir "$git_source_clean"
/usr/bin/git -C "$git_source_repository" archive --format=tar "$git_source_commit" \
  | /usr/bin/tar -xf - -C "$git_source_clean"
/bin/bash -p "$tools_script" verify-extracted-git-tree \
  --repository "$git_source_repository" --commit "$git_source_commit" \
  --source "$git_source_clean"

printf '%s\n' 'payload.txt export-subst' \
  >"$git_source_repository/.git/info/attributes"
git_source_attributed="$temporary_root/git-source-attributed"
/bin/mkdir "$git_source_attributed"
/usr/bin/git -C "$git_source_repository" archive --format=tar "$git_source_commit" \
  | /usr/bin/tar -xf - -C "$git_source_attributed"
if /bin/bash -p "$tools_script" verify-extracted-git-tree \
  --repository "$git_source_repository" --commit "$git_source_commit" \
  --source "$git_source_attributed" >/dev/null 2>&1; then
  printf 'Extracted Git-tree verifier accepted info/attributes byte rewriting.\n' >&2
  exit 1
fi

valid_uuid='01234567-89AB-CDEF-0123-456789ABCDEF'
printf 'UUID: %s (arm64) /fixture/App\n' "$valid_uuid" >"$temporary_root/valid-uuid.txt"
[[ "$(/bin/bash -p "$tools_script" parse-arm64-uuid --input "$temporary_root/valid-uuid.txt")" == "$valid_uuid" ]]
for invalid_uuid_fixture in zero multiple wrong-arch malformed; do
  case "$invalid_uuid_fixture" in
    zero) : >"$temporary_root/$invalid_uuid_fixture.txt" ;;
    multiple)
      printf 'UUID: %s (arm64) /fixture/App\nUUID: 11111111-1111-1111-1111-111111111111 (arm64) /fixture/App\n' \
        "$valid_uuid" >"$temporary_root/$invalid_uuid_fixture.txt"
      ;;
    wrong-arch)
      printf 'UUID: %s (x86_64) /fixture/App\n' "$valid_uuid" \
        >"$temporary_root/$invalid_uuid_fixture.txt"
      ;;
    malformed)
      printf 'UUID: not-a-uuid (arm64) /fixture/App\n' \
        >"$temporary_root/$invalid_uuid_fixture.txt"
      ;;
  esac
  if /bin/bash -p "$tools_script" parse-arm64-uuid \
    --input "$temporary_root/$invalid_uuid_fixture.txt" >/dev/null 2>&1; then
    printf 'UUID parser accepted %s input.\n' "$invalid_uuid_fixture" >&2
    exit 1
  fi
done

reviewed_source="$temporary_root/reviewed-source"
/bin/mkdir -p "$reviewed_source/LectureBoardAI.xcodeproj"
/bin/cp "$script_directory/../project.yml" "$reviewed_source/project.yml"
/bin/cp "$script_directory/../LectureBoardAI.xcodeproj/project.pbxproj" \
  "$reviewed_source/LectureBoardAI.xcodeproj/project.pbxproj"
/bin/bash -p "$tools_script" verify-reviewed-xcode-source --root "$reviewed_source"
for reviewed_source_mutation in pre-command post-command include project-version generated-project-version array-path compiler-flags; do
  /bin/cp "$script_directory/../project.yml" "$reviewed_source/project.yml"
  /bin/cp "$script_directory/../LectureBoardAI.xcodeproj/project.pbxproj" \
    "$reviewed_source/LectureBoardAI.xcodeproj/project.pbxproj"
  case "$reviewed_source_mutation" in
    pre-command)
      printf '\npreGenCommand: /usr/bin/false\n' >>"$reviewed_source/project.yml"
      ;;
    post-command)
      printf '\npostGenCommand: /usr/bin/false\n' >>"$reviewed_source/project.yml"
      ;;
    include)
      printf '\ninclude: /tmp/unreviewed.yml\n' >>"$reviewed_source/project.yml"
      ;;
    project-version)
      /usr/bin/sed -i '' \
        's/MARKETING_VERSION: 1.0.0/MARKETING_VERSION: 1.0.1/' \
        "$reviewed_source/project.yml"
      ;;
    generated-project-version)
      /usr/bin/sed -i '' \
        's/MARKETING_VERSION = 1.0.0;/MARKETING_VERSION = 1.0.1;/' \
        "$reviewed_source/LectureBoardAI.xcodeproj/project.pbxproj"
      ;;
    array-path)
      printf '\nHEADER_SEARCH_PATHS = (\n  "/external",\n);\n' \
        >>"$reviewed_source/LectureBoardAI.xcodeproj/project.pbxproj"
      ;;
    compiler-flags)
      printf '\nOTHER_SWIFT_FLAGS = "-load-plugin-executable /tmp/plugin";\n' \
        >>"$reviewed_source/LectureBoardAI.xcodeproj/project.pbxproj"
      ;;
  esac
  if /bin/bash -p "$tools_script" verify-reviewed-xcode-source \
    --root "$reviewed_source" >/dev/null 2>&1; then
    printf 'Reviewed Xcode source verifier accepted %s mutation.\n' \
      "$reviewed_source_mutation" >&2
    exit 1
  fi
done

printf '%s\n' \
  'Load command 10' \
  '      cmd LC_BUILD_VERSION' \
  ' platform MACOS' \
  '    minos 26.0' \
  '      sdk 26.6' >"$temporary_root/valid-build-version.txt"
[[ "$(/bin/bash -p "$tools_script" parse-macos-min-version \
  --input "$temporary_root/valid-build-version.txt")" == '26.0' ]]
for invalid_build_version_fixture in missing-platform wrong-platform multiple-minos malformed-minos; do
  case "$invalid_build_version_fixture" in
    missing-platform) printf 'minos 26.0\n' ;;
    wrong-platform) printf 'platform IOS\nminos 26.0\n' ;;
    multiple-minos) printf 'platform MACOS\nminos 26.0\nminos 26.1\n' ;;
    malformed-minos) printf 'platform MACOS\nminos latest\n' ;;
  esac >"$temporary_root/$invalid_build_version_fixture.txt"
  if /bin/bash -p "$tools_script" parse-macos-min-version \
    --input "$temporary_root/$invalid_build_version_fixture.txt" >/dev/null 2>&1; then
    printf 'Build-version parser accepted %s input.\n' \
      "$invalid_build_version_fixture" >&2
    exit 1
  fi
done

valid_project="$temporary_root/valid.pbxproj"
printf '%s\n' \
  'path = LectureBoardAI;' \
  'path = "Packages/LectureBoardCore";' \
  'sourceTree = SOURCE_ROOT;' >"$valid_project"
/bin/bash -p "$tools_script" verify-project-containment --path "$valid_project"

for invalid_project_fixture in absolute quoted-absolute parent nested-parent absolute-tree build-parent-braced build-parent-parenthesized build-parent-deep relative-setting-parent local-package-parent absolute-setting home-setting modified-root modified-home shell-phase build-rule legacy-target external-tool remote-package xcconfig compiler-override; do
  case "$invalid_project_fixture" in
    absolute) printf 'path = /tmp/Injected.swift;\n' ;;
    quoted-absolute) printf 'path = "/Users/example/Injected.swift";\n' ;;
    parent) printf 'path = ../Injected.swift;\n' ;;
    nested-parent) printf 'path = "Sources/../../Injected.swift";\n' ;;
    absolute-tree) printf 'sourceTree = "<absolute>";\n' ;;
    build-parent-braced) printf 'SETTING = "${SRCROOT}/../Injected";\n' ;;
    build-parent-parenthesized) printf 'SETTING = "$(PROJECT_DIR)/../Injected";\n' ;;
    build-parent-deep) printf 'SETTING = "$(PROJECT_DIR)/Sources/../../Injected";\n' ;;
    relative-setting-parent) printf 'INFOPLIST_FILE = ../../outside/Info.plist;\n' ;;
    local-package-parent) printf 'relativePath = ../outside;\n' ;;
    absolute-setting) printf 'SWIFT_EXEC = /Applications/EvilCompiler;\n' ;;
    home-setting) printf 'HEADER_SEARCH_PATHS = "$(HOME)/Injected";\n' ;;
    modified-root) printf 'HEADER_SEARCH_PATHS = "$(SRCROOT:dir)/Injected";\n' ;;
    modified-home) printf 'HEADER_SEARCH_PATHS = "$(HOME:standardizepath)/Injected";\n' ;;
    shell-phase) printf 'isa = PBXShellScriptBuildPhase;\n' ;;
    build-rule) printf 'isa = PBXBuildRule;\n' ;;
    legacy-target) printf 'isa = PBXLegacyTarget; buildToolPath = scripts/tool;\n' ;;
    external-tool) printf 'isa = PBXExternalBuildToolExecution;\n' ;;
    remote-package) printf 'isa = XCRemoteSwiftPackageReference;\n' ;;
    xcconfig) printf 'baseConfigurationReference = 12345 /* Release.xcconfig */;\n' ;;
    compiler-override) printf 'SWIFT_EXEC = Tools/InjectedCompiler;\n' ;;
  esac >"$temporary_root/$invalid_project_fixture.pbxproj"
  if /bin/bash -p "$tools_script" verify-project-containment \
    --path "$temporary_root/$invalid_project_fixture.pbxproj" >/dev/null 2>&1; then
    printf 'Project containment accepted %s escape.\n' "$invalid_project_fixture" >&2
    exit 1
  fi
done

xcode_project_root="$temporary_root/LectureBoardAI.xcodeproj"
/usr/bin/ditto "$script_directory/../LectureBoardAI.xcodeproj" "$xcode_project_root"
/bin/bash -p "$tools_script" verify-xcode-project-support --root "$xcode_project_root"
printf 'unexpected\n' >"$xcode_project_root/xcshareddata/xcschemes/Unexpected.xcscheme"
if /bin/bash -p "$tools_script" verify-xcode-project-support \
  --root "$xcode_project_root" >/dev/null 2>&1; then
  printf 'Xcode-project support verifier accepted an extra scheme.\n' >&2
  exit 1
fi
/bin/unlink "$xcode_project_root/xcshareddata/xcschemes/Unexpected.xcscheme"
printf '<ShellScriptAction/>\n' \
  >>"$xcode_project_root/xcshareddata/xcschemes/LectureBoardAI.xcscheme"
if /bin/bash -p "$tools_script" verify-xcode-project-support \
  --root "$xcode_project_root" >/dev/null 2>&1; then
  printf 'Xcode-project support verifier accepted a modified shared scheme.\n' >&2
  exit 1
fi
/usr/bin/ditto "$script_directory/../LectureBoardAI.xcodeproj/xcshareddata/xcschemes/LectureBoardAI.xcscheme" \
  "$xcode_project_root/xcshareddata/xcschemes/LectureBoardAI.xcscheme"
printf '<FileRef location="container:../Outside.xcodeproj"/>\n' \
  >"$xcode_project_root/project.xcworkspace/contents.xcworkspacedata"
if /bin/bash -p "$tools_script" verify-xcode-project-support \
  --root "$xcode_project_root" >/dev/null 2>&1; then
  printf 'Xcode-project support verifier accepted an external workspace reference.\n' >&2
  exit 1
fi

package_root="$temporary_root/package-root"
/bin/mkdir -p "$package_root/Packages/LectureBoardCore"
/bin/cp "$script_directory/../Packages/LectureBoardCore/Package.swift" \
  "$package_root/Packages/LectureBoardCore/Package.swift"
/bin/bash -p "$tools_script" verify-package-manifests --root "$package_root"
for banned_package_feature in package plugin macro binaryTarget systemLibrary unsafeFlags path; do
  case "$banned_package_feature" in
    package) feature='.package(url: "https://example.invalid/repo.git", from: "1.0.0")' ;;
    plugin) feature='.plugin(name: "Plugin", capability: .buildTool())' ;;
    macro) feature='.macro(name: "Macro")' ;;
    binaryTarget) feature='.binaryTarget(name: "Binary", path: "Binary.xcframework")' ;;
    systemLibrary) feature='.systemLibrary(name: "System")' ;;
    unsafeFlags) feature='.unsafeFlags(["-load-plugin-executable"])' ;;
    path) feature='.target(name: "Outside", path: "../outside")' ;;
  esac
  printf '%s\n' "$feature" >"$package_root/Packages/LectureBoardCore/Package.swift"
  if /bin/bash -p "$tools_script" verify-package-manifests \
    --root "$package_root" >/dev/null 2>&1; then
    printf 'Package-manifest verifier accepted %s.\n' "$banned_package_feature" >&2
    exit 1
  fi
done
/bin/cp "$script_directory/../Packages/LectureBoardCore/Package.swift" \
  "$package_root/Packages/LectureBoardCore/Package.swift"
printf 'unexpected\n' \
  >"$package_root/Packages/LectureBoardCore/Package@swift-6.0.swift"
if /bin/bash -p "$tools_script" verify-package-manifests \
  --root "$package_root" >/dev/null 2>&1; then
  printf 'Package-manifest verifier accepted a version-specific manifest.\n' >&2
  exit 1
fi

layout_root="$temporary_root/layout"
valid_app="$layout_root/LectureBoard AI.app"
main_executable="$valid_app/Contents/MacOS/LectureBoard AI"
/bin/mkdir -p "$valid_app/Contents/MacOS" "$valid_app/Contents/Resources"
printf '#!/bin/sh\nexit 0\n' >"$main_executable"
/bin/chmod 755 "$main_executable"
printf 'resource\n' >"$valid_app/Contents/Resources/data.txt"
/bin/bash -p "$tools_script" verify-app-code-layout \
  --app "$valid_app" --main "$main_executable"

symbolic_app="$layout_root/Symbolic.app"
/usr/bin/ditto "$valid_app" "$symbolic_app"
/bin/ln -s data.txt "$symbolic_app/Contents/Resources/link.txt"
if /bin/bash -p "$tools_script" verify-app-code-layout \
  --app "$symbolic_app" --main "$symbolic_app/Contents/MacOS/LectureBoard AI" \
  >/dev/null 2>&1; then
  printf 'Code-layout verifier accepted a symbolic link.\n' >&2
  exit 1
fi

root_symbolic_app="$layout_root/RootSymbolic.app"
/usr/bin/ditto "$valid_app" "$root_symbolic_app"
/bin/ln -s Contents "$root_symbolic_app/RootLink"
if /bin/bash -p "$tools_script" verify-app-code-layout \
  --app "$root_symbolic_app" --main "$root_symbolic_app/Contents/MacOS/LectureBoard AI" \
  >/dev/null 2>&1; then
  printf 'Code-layout verifier accepted an app-root symbolic link.\n' >&2
  exit 1
fi

root_executable_app="$layout_root/RootExecutable.app"
/usr/bin/ditto "$valid_app" "$root_executable_app"
printf '#!/bin/sh\nexit 0\n' >"$root_executable_app/RootHelper"
/bin/chmod 755 "$root_executable_app/RootHelper"
if /bin/bash -p "$tools_script" verify-app-code-layout \
  --app "$root_executable_app" --main "$root_executable_app/Contents/MacOS/LectureBoard AI" \
  >/dev/null 2>&1; then
  printf 'Code-layout verifier accepted an app-root executable.\n' >&2
  exit 1
fi

root_macho_app="$layout_root/RootMachO.app"
/usr/bin/ditto "$valid_app" "$root_macho_app"
/bin/cp /bin/echo "$root_macho_app/RootMachO"
/bin/chmod 644 "$root_macho_app/RootMachO"
if /bin/bash -p "$tools_script" verify-app-code-layout \
  --app "$root_macho_app" --main "$root_macho_app/Contents/MacOS/LectureBoard AI" \
  >/dev/null 2>&1; then
  printf 'Code-layout verifier accepted app-root undeclared Mach-O code.\n' >&2
  exit 1
fi

nested_app="$layout_root/Nested.app"
/usr/bin/ditto "$valid_app" "$nested_app"
/bin/mkdir "$nested_app/Contents/Resources/Unexpected.bundle"
if /bin/bash -p "$tools_script" verify-app-code-layout \
  --app "$nested_app" --main "$nested_app/Contents/MacOS/LectureBoard AI" \
  >/dev/null 2>&1; then
  printf 'Code-layout verifier accepted a nested code bundle.\n' >&2
  exit 1
fi

executable_app="$layout_root/Executable.app"
/usr/bin/ditto "$valid_app" "$executable_app"
printf '#!/bin/sh\nexit 0\n' >"$executable_app/Contents/Resources/helper"
/bin/chmod 755 "$executable_app/Contents/Resources/helper"
if /bin/bash -p "$tools_script" verify-app-code-layout \
  --app "$executable_app" --main "$executable_app/Contents/MacOS/LectureBoard AI" \
  >/dev/null 2>&1; then
  printf 'Code-layout verifier accepted an undeclared executable.\n' >&2
  exit 1
fi

macho_app="$layout_root/MachO.app"
/usr/bin/ditto "$valid_app" "$macho_app"
/bin/cp /bin/echo "$macho_app/Contents/Resources/hidden-data"
/bin/chmod 644 "$macho_app/Contents/Resources/hidden-data"
if /bin/bash -p "$tools_script" verify-app-code-layout \
  --app "$macho_app" --main "$macho_app/Contents/MacOS/LectureBoard AI" \
  >/dev/null 2>&1; then
  printf 'Code-layout verifier accepted undeclared Mach-O code.\n' >&2
  exit 1
fi

nonexecutable_app="$layout_root/NonExecutable.app"
/usr/bin/ditto "$valid_app" "$nonexecutable_app"
/bin/chmod 644 "$nonexecutable_app/Contents/MacOS/LectureBoard AI"
if /bin/bash -p "$tools_script" verify-app-code-layout \
  --app "$nonexecutable_app" --main "$nonexecutable_app/Contents/MacOS/LectureBoard AI" \
  >/dev/null 2>&1; then
  printf 'Code-layout verifier accepted a non-executable main binary.\n' >&2
  exit 1
fi

deep_main_app="$layout_root/DeepMain.app"
/usr/bin/ditto "$valid_app" "$deep_main_app"
/bin/mkdir "$deep_main_app/Contents/MacOS/Nested"
printf '#!/bin/sh\nexit 0\n' >"$deep_main_app/Contents/MacOS/Nested/App"
/bin/chmod 755 "$deep_main_app/Contents/MacOS/Nested/App"
if /bin/bash -p "$tools_script" verify-app-code-layout \
  --app "$deep_main_app" --main "$deep_main_app/Contents/MacOS/Nested/App" \
  >/dev/null 2>&1; then
  printf 'Code-layout verifier accepted a nested main executable path.\n' >&2
  exit 1
fi

output_root="$temporary_root/output-root"
/bin/mkdir "$output_root"
/usr/bin/ditto "$valid_app" "$output_root/LectureBoard AI.app"
/usr/bin/ditto "$valid_app" "$output_root/LectureBoard AI.app.dSYM"
printf 'incomplete\n' >"$output_root/.lectureboard-release-incomplete"
/bin/bash -p "$tools_script" verify-output-layout --root "$output_root"
expected_output_root="$temporary_root/expected-output-root"
/bin/mkdir "$expected_output_root"
/usr/bin/ditto "$valid_app" "$expected_output_root/LectureBoard AI.app"
/usr/bin/ditto "$valid_app" "$expected_output_root/LectureBoard AI.app.dSYM"
/bin/bash -p "$tools_script" tree-manifest \
  --root "$expected_output_root" --output "$temporary_root/expected-output.manifest"
/bin/bash -p "$tools_script" verified-output-manifest \
  --root "$output_root" --output "$temporary_root/verified-output.manifest"
/usr/bin/cmp -s \
  "$temporary_root/expected-output.manifest" "$temporary_root/verified-output.manifest"
printf 'unexpected\n' >"$output_root/unexpected.txt"
if /bin/bash -p "$tools_script" verify-output-layout --root "$output_root" \
  >/dev/null 2>&1; then
  printf 'Output-layout verifier accepted an unexpected root entry.\n' >&2
  exit 1
fi

printf 'Release artifact helper tests passed.\n'
