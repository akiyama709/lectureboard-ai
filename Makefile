override SHELL := $(abspath .)/scripts/release-make-shell.sh
override .SHELLFLAGS := -c
PROJECT := LectureBoardAI.xcodeproj
SCHEME := LectureBoardAI

.PHONY: bootstrap doctor local-setup generate test test-core test-app test-app-script build build-runtime test-build-runtime-script test-runtime-launch-script test-runtime-launch-smoke test-publication-sources-script test-initial-publication-script check-permission-contract test-permission-contract-script check-version-consistency test-version-consistency-script test-release-definition-script test-release-artifact-tools-script test-build-release-app-script test-release-exclusive-rename-script check-release-package-evidence-tools-script test-package-release-dmg-script test-no-fee-release-v1-script test-release-shell-security-script release-preflight test-release-preflight-script verify-release-code test-verify-release-code-script open codex verify clean


doctor:
	./scripts/local-doctor.sh

local-setup:
	./scripts/local-first-run.sh

bootstrap:
	@command -v xcodegen >/dev/null 2>&1 || { echo "XcodeGen is required. Install it with: brew install xcodegen"; exit 1; }
	xcodegen generate

generate:
	xcodegen generate

test: test-core build

test-core:
	swift test --package-path Packages/LectureBoardCore

test-app: test-app-script
	./scripts/test-local-app.sh

test-app-script:
	./scripts/test-test-local-app.sh

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

build-runtime: test-build-runtime-script
	./scripts/build-local-runtime.sh

test-build-runtime-script:
	./scripts/test-build-local-runtime.sh

test-runtime-launch-script:
	./scripts/test-runtime-launch-preflight.sh

test-runtime-launch-smoke: test-runtime-launch-script
	./scripts/test-runtime-launch-smoke.sh

test-publication-sources-script:
	./scripts/test-check-publication-sources.sh

test-initial-publication-script:
	./scripts/test-publish-to-github.sh

check-permission-contract:
	./scripts/check-permission-contract.sh

test-permission-contract-script:
	./scripts/test-check-permission-contract.sh

check-version-consistency:
	./scripts/check-version-consistency.sh

test-version-consistency-script:
	./scripts/test-check-version-consistency.sh

test-release-definition-script:
	./scripts/test-check-release-definition.sh

test-release-artifact-tools-script:
	./scripts/test-release-artifact-tools.sh

test-build-release-app-script:
	./scripts/test-build-release-app.sh

test-release-exclusive-rename-script:
	./scripts/test-release-exclusive-rename.sh

check-release-package-evidence-tools-script:
	@test -f scripts/release-package-evidence-tools.sh || { echo "Release package evidence helper is missing."; exit 1; }
	/bin/bash -p -n scripts/release-package-evidence-tools.sh

test-package-release-dmg-script:
	./scripts/test-package-release-dmg.sh

test-no-fee-release-v1-script:
	./scripts/test-no-fee-release-v1.sh

test-release-shell-security-script:
	./scripts/test-release-shell-security.sh

release-preflight:
	./scripts/release-preflight.sh

test-release-preflight-script:
	./scripts/test-release-preflight.sh

verify-release-code:
	@test -n "$(KIND)" -a -n "$(ARTIFACT)" || { echo "Use KIND=app|dmg ARTIFACT=/absolute/path."; exit 64; }
	./scripts/verify-release-code.sh --kind "$(KIND)" --path "$(ARTIFACT)"

test-verify-release-code-script:
	./scripts/test-verify-release-code.sh

open:
	./scripts/open-in-xcode.sh

codex:
	./scripts/open-in-codex.sh

verify:
	./scripts/prepublish-check.sh

clean:
	rm -rf $(PROJECT) DerivedData .build
	swift package --package-path Packages/LectureBoardCore clean
