# Build and verification status

Updated: 2026-08-30

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

## GitHub publication verification

The public repository `akiyama709/lectureboard-ai` was created on 2026-08-29 with `main` as the default branch. The initial push contained commit `8f0b6a3`.

The first `Core Swift CI` run failed because the unanchored `Models/` entry in `.gitignore` also excluded the four required Swift files under `Packages/LectureBoardCore/Sources/LectureBoardCore/Models`. Local tests had used those ignored working-tree files，while the clean GitHub Actions checkout did not contain them.

The ignore patterns for `Models`，`LectureData`，and `LocalData` were restricted to repository-root data directories. A new publication-source regression check now fails when any Swift file under the app or core source trees is absent from Git. The check reproduced the omission of all four model files before the fix and passed after they were added. The publication script now stages the candidate tree before running the strengthened seven-step verification.

After this fix，the seven-step `make verify` run passed locally:

- Swift format lint passed.
- All 10 core tests in 5 suites passed.
- The native `arm64` app build completed with `** BUILD SUCCEEDED **`.
- All Swift source files were confirmed as included in Git.
- The tracked-build-output，common-secret-pattern，and lecture-data-extension checks passed.

The follow-up `Core Swift CI` run for commit `f875693` passed in 25 seconds on a clean GitHub Actions checkout. The remaining Node.js 20 deprecation warning from `actions/checkout@v4` was resolved by updating the official action to `actions/checkout@v7`，as proposed by GitHub Dependabot. The subsequent run for commit `85f3604` passed in 30 seconds with no annotations.

## README language-boundary regression check

The English requirements list in `README.md` accidentally contained the Japanese text `XcodeGen（Xcode 26に対応する版）`. It was replaced with `XcodeGen 2.46.0 (the locally verified version)`.

The new `scripts/check-readme-language-boundary.sh` check requires exactly one Japanese-section marker and rejects Japanese-script characters before that marker. The check passed after the correction. The publication verification now contains eight steps and runs this regression check before examining tracked build output.

After this change，the final `make verify` run passed with normal local Mac access on 2026-08-30:

- The README language-boundary regression check passed.
- All 10 core tests in 5 suites passed.
- The native `arm64` app build completed with `** BUILD SUCCEEDED **`.
- All publication-source，tracked-build-output，common-secret-pattern，and lecture-data-extension checks passed.

An initial attempt from the restricted Codex sandbox could not write Swift's user-level module cache. Re-running the unchanged verification with normal local Mac access passed，so this was an execution-sandbox limitation rather than a product or test failure.

The correction was published through PR #2. The required `LectureBoardCore tests` check passed in 23 seconds，and the pull request was squash-merged to `main` as commit `f63fe22` on 2026-08-30.

## Continuous selected-window capture implementation

The first observable-capture implementation was compiled on 2026-08-30. It adds:

- A ScreenCaptureKit stream restricted to the selected PowerPoint window.
- Ten-frame-per-second capture with a maximum 1,920-pixel edge，BGRA output，no cursor，no audio，and a three-frame queue.
- A 32-by-18 luminance fingerprint generated from each usable frame.
- Deterministic stable-frame confirmation and slide-change classification in `LectureBoardCore`.
- Cancellation generations and window identifiers that reject callbacks from a stopped or reselected window.
- A setup-window monitor showing frame count，confirmed stable snapshots，detected slide changes，and the latest stable preview.

Targeted verification completed before runtime testing:

- `make test-core` passed with 17 tests in 6 Swift Testing suites.
- The seven stable-frame tests cover consecutive confirmation，small-noise tolerance，transition deferral，animation frames，malformed fingerprints，configuration bounds，and reset behavior.
- `make build` completed with `** BUILD SUCCEEDED **` for the native `arm64` macOS target under Swift 6 strict concurrency.
- The final eight-step `make verify` run passed，including source-format lint，all Core tests，the native build，tracked-source verification，the README language-boundary regression check，and publication safety checks.

The commit-candidate verification was repeated after the changelog update at 00:47 JST on 2026-08-30. It again passed all 17 Core tests in 6 suites and completed the native `arm64` build with `** BUILD SUCCEEDED **`; all remaining publication checks also passed.

The initial required `LectureBoardCore tests` check for PR #3 passed in 28 seconds on a clean GitHub Actions checkout. This CI check exercises the platform-neutral Core package; it does not build or run the native ScreenCaptureKit app.

These results verify deterministic logic，compilation，and linking only. The app was not launched automatically because doing so could present screen-recording permission UI while the user was unavailable. Actual PowerPoint frame delivery，idle-frame behavior，window closure，window reselection，preview fidelity，and the default stability thresholds remain runtime-unverified.

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
