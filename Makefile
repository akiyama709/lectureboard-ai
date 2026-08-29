SHELL := /bin/bash
PROJECT := LectureBoardAI.xcodeproj
SCHEME := LectureBoardAI

.PHONY: bootstrap doctor local-setup generate test test-core build open codex verify clean


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

build: generate
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build

open:
	./scripts/open-in-xcode.sh

codex:
	./scripts/open-in-codex.sh

verify:
	./scripts/prepublish-check.sh

clean:
	rm -rf $(PROJECT) DerivedData .build
	swift package --package-path Packages/LectureBoardCore clean
