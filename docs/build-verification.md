# Build and verification status

Updated: 2026-08-29

## Verified in the preparation environment

- Swift toolchain available
- `swift test --package-path Packages/LectureBoardCore`
- 10 tests in 5 Swift Testing suites passed
- Shell scripts pass `bash -n`
- JSON documents and schemas parse successfully
- No common API-key or private-key patterns were found in the publication tree

The preparation environment was Linux and did not include Xcode or Apple frameworks. The native app target was not compiled there.

## Verified on the local Apple silicon Mac

Environment:

- Apple silicon (`arm64`)
- macOS 26.6.2
- Xcode 26.6 (Build 17F113)
- Apple Swift 6.3.3
- XcodeGen 2.46.0

Checks completed on 2026-08-29:

- `make doctor` completed with 0 failures and 0 warnings when run with normal local access.
- `make local-setup` completed successfully.
  - The 10 `LectureBoardCore` tests in 5 Swift Testing suites passed.
  - `LectureBoardAI.xcodeproj` was generated successfully.
- `make build` completed with `** BUILD SUCCEEDED **` for the native `arm64` macOS destination.
  - The build compiled the SwiftUI，AppKit，ScreenCaptureKit，Speech，and AVFoundation app target with Swift 6 and complete strict-concurrency checking enabled by the project settings.
  - Code signing was intentionally disabled by `CODE_SIGNING_ALLOWED=NO`，so this result verifies compilation and linking，not signing or notarization.
  - The generated app executable was inspected as a 64-bit `arm64` Mach-O binary with bundle identifier `io.github.akiyama709.LectureBoardAI`.
- `make verify` completed successfully after the documentation update.
  - Swift source-format lint passed.
  - All 10 core tests passed again.
  - The native app rebuilt with `** BUILD SUCCEEDED **`.
  - The tracked-build-output，common-secret-pattern，and lecture-data-extension checks passed.
  - Manual institutional intellectual-property and privacy review remains required before publication.

## Issue found and resolved during local setup

The first normal local `make local-setup` run passed all core tests but stopped because XcodeGen was not installed. XcodeGen 2.46.0 was installed with Homebrew. The existing `make doctor` prerequisite check then detected the installed version，and the complete `make local-setup` and `make build` sequence passed. No application source defect was encountered，so no product-code regression test was required for this environment-only fix.

A separate initial SwiftPM cache error occurred only inside the restricted Codex command sandbox. Re-running the unchanged command with normal local Mac access passed the core tests，confirming that this was not a repository or Swift source failure. No sandbox-specific workaround was added to the project.

## Not yet runtime-verified on this Mac

The successful native build does not verify runtime behavior. The app has not yet been launched as part of this verification session，and the following checks remain outstanding:

- Screen-recording permission request and post-restart state
- PowerPoint-window discovery
- Transparent overlay position，size，and click-through behavior
- Japanese and English microphone transcription
- Multi-display behavior
- Non-interference with PowerPoint pen-tablet input
- Continuous PowerPoint frame capture and stable slide-change detection
- Vision-based slide，geometry，empty-space，and existing-ink analysis
- Signing and notarization

These items must remain described as prototypes or unverified behavior until each one is exercised and recorded on the lecture Mac.

## Local macOS handoff

The repository includes `AGENTS.md`，`.codex/config.toml`，`make doctor`，`make local-setup`，and Japanese local-development and handoff documentation. The native compilation gate is now verified on the local Mac，while the runtime validation gates listed above remain open.
