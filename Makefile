SHELL := /bin/bash
PROJECT := LectureBoardAI.xcodeproj
SCHEME := LectureBoardAI

.PHONY: bootstrap doctor local-setup generate test test-core test-app test-app-script build build-runtime test-build-runtime-script test-runtime-launch-script test-runtime-launch-smoke test-publication-sources-script test-initial-publication-script test-release-definition-script open codex verify clean


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

test-release-definition-script:
	./scripts/test-check-release-definition.sh

open:
	./scripts/open-in-xcode.sh

codex:
	./scripts/open-in-codex.sh

verify:
	./scripts/prepublish-check.sh

clean:
	rm -rf $(PROJECT) DerivedData .build
	swift package --package-path Packages/LectureBoardCore clean
