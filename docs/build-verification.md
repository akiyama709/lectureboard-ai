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
  - The build compiled the SwiftUI, AppKit, ScreenCaptureKit, Speech, and AVFoundation app target with Swift 6 and complete strict-concurrency checking enabled by the project settings.
  - Code signing was intentionally disabled by `CODE_SIGNING_ALLOWED=NO`, so this result verifies compilation and linking, not signing or notarization.
  - The generated app executable was inspected as a 64-bit `arm64` Mach-O binary with bundle identifier `io.github.akiyama709.LectureBoardAI`.
- `make verify` completed successfully after the documentation update.
  - Swift source-format lint passed.
  - All 10 core tests passed again.
  - The native app rebuilt with `** BUILD SUCCEEDED **`.
  - The tracked-build-output, common-secret-pattern, and lecture-data-extension checks passed.
  - Manual institutional intellectual-property and privacy review remains required before publication.

## Issue found and resolved during local setup

The first normal local `make local-setup` run passed all core tests but stopped because XcodeGen was not installed. XcodeGen 2.46.0 was installed with Homebrew. The existing `make doctor` prerequisite check then detected the installed version, and the complete `make local-setup` and `make build` sequence passed. No application source defect was encountered, so no product-code regression test was required for this environment-only fix.

A separate initial SwiftPM cache error occurred only inside the restricted Codex command sandbox. Re-running the unchanged command with normal local Mac access passed the core tests, confirming that this was not a repository or Swift source failure. No sandbox-specific workaround was added to the project.

## GitHub publication verification

The public repository `akiyama709/lectureboard-ai` was created on 2026-08-29 with `main` as the default branch. The initial push contained commit `8f0b6a3`.

The first `Core Swift CI` run failed because the unanchored `Models/` entry in `.gitignore` also excluded the four required Swift files under `Packages/LectureBoardCore/Sources/LectureBoardCore/Models`. Local tests had used those ignored working-tree files, while the clean GitHub Actions checkout did not contain them.

The ignore patterns for `Models`, `LectureData`, and `LocalData` were restricted to repository-root data directories. A new publication-source regression check now fails when any Swift file under the app or core source trees is absent from Git. The check reproduced the omission of all four model files before the fix and passed after they were added. The publication script now stages the candidate tree before running the strengthened seven-step verification.

After this fix, the seven-step `make verify` run passed locally:

- Swift format lint passed.
- All 10 core tests in 5 suites passed.
- The native `arm64` app build completed with `** BUILD SUCCEEDED **`.
- All Swift source files were confirmed as included in Git.
- The tracked-build-output, common-secret-pattern, and lecture-data-extension checks passed.

The follow-up `Core Swift CI` run for commit `f875693` passed in 25 seconds on a clean GitHub Actions checkout. The remaining Node.js 20 deprecation warning from `actions/checkout@v4` was resolved by updating the official action to `actions/checkout@v7`, as proposed by GitHub Dependabot. The subsequent run for commit `85f3604` passed in 30 seconds with no annotations.

## README language-boundary regression check

The English requirements list in `README.md` accidentally contained the Japanese text `XcodeGen（Xcode 26に対応する版）`. It was replaced with `XcodeGen 2.46.0 (the locally verified version)`.

The new `scripts/check-readme-language-boundary.sh` check requires exactly one Japanese-section marker and rejects Japanese-script characters before that marker. The check passed after the correction. The publication verification now contains eight steps and runs this regression check before examining tracked build output.

After this change, the final `make verify` run passed with normal local Mac access on 2026-08-30:

- The README language-boundary regression check passed.
- All 10 core tests in 5 suites passed.
- The native `arm64` app build completed with `** BUILD SUCCEEDED **`.
- All publication-source, tracked-build-output, common-secret-pattern, and lecture-data-extension checks passed.

An initial attempt from the restricted Codex sandbox could not write Swift's user-level module cache. Re-running the unchanged verification with normal local Mac access passed, so this was an execution-sandbox limitation rather than a product or test failure.

The correction was published through PR #2. The required `LectureBoardCore tests` check passed in 23 seconds, and the pull request was squash-merged to `main` as commit `f63fe22` on 2026-08-30.

## Continuous selected-window capture implementation

The first observable-capture implementation was compiled on 2026-08-30. It adds:

- A ScreenCaptureKit stream restricted to the selected PowerPoint window.
- Ten-frame-per-second capture with a maximum 1,920-pixel edge, BGRA output, no cursor, no audio, and a three-frame queue.
- A 32-by-18 luminance fingerprint generated from each usable frame.
- Deterministic stable-frame confirmation and slide-change classification in `LectureBoardCore`.
- Cancellation generations and window identifiers that reject callbacks from a stopped or reselected window.
- A setup-window monitor showing frame count, confirmed stable snapshots, detected slide changes, and the latest stable preview.

Targeted verification completed before runtime testing:

- `make test-core` passed with 17 tests in 6 Swift Testing suites.
- The seven stable-frame tests cover consecutive confirmation, small-noise tolerance, transition deferral, animation frames, malformed fingerprints, configuration bounds, and reset behavior.
- `make build` completed with `** BUILD SUCCEEDED **` for the native `arm64` macOS target under Swift 6 strict concurrency.
- The final eight-step `make verify` run passed, including source-format lint, all Core tests, the native build, tracked-source verification, the README language-boundary regression check, and publication safety checks.

The commit-candidate verification was repeated after the changelog update at 00:47 JST on 2026-08-30. It again passed all 17 Core tests in 6 suites and completed the native `arm64` build with `** BUILD SUCCEEDED **`; all remaining publication checks also passed.

The initial required `LectureBoardCore tests` check for PR #3 passed in 28 seconds on a clean GitHub Actions checkout. This CI check exercises the platform-neutral Core package; it does not build or run the native ScreenCaptureKit app.

These results verify deterministic logic, compilation, and linking only. The app was not launched automatically because doing so could present screen-recording permission UI while the user was unavailable. Actual PowerPoint frame delivery, idle-frame behavior, window closure, window reselection, preview fidelity, and the default stability thresholds remain runtime-unverified.

## Stable-frame Vision and occupied-region implementation

The first Vision-analysis path was compiled on 2026-08-30. It adds:

- A Vision text-recognition request configured with the `.accurate` recognition level and automatic language detection on newly confirmed stable frames.
- Vision rectangle detection with bounded observation count and initial size, confidence, aspect-ratio, and quadrature thresholds.
- Conversion from Vision's lower-left normalized coordinates to the app's top-left normalized coordinates.
- Platform-neutral Core models and logic that trim and filter text, filter tiny or near-full-frame geometry, select a title candidate, pad occupied areas, and transitively merge touching regions.
- Analysis-generation guards that reject results from stopped captures, newer stable frames, or reselected windows, while clearing old regions before a newly stable frame is analyzed.
- Capture-monitor counts for text, rectangles, and occupied regions, plus a red occupied-region preview overlay.
- Use of the latest completed visual analysis when constructing the provisional `SlideContext` for final transcript segments.

Targeted verification completed before runtime testing:

- The first new Core test run exposed an exact floating-point equality assertion between `0.3` and the clamped representation `0.30000000000000004`. The test was corrected to compare normalized geometry with a one-millionth tolerance; no product workaround was added.
- The corrected Core run passed 23 tests in 7 Swift Testing suites. A JSON round-trip test for the new serializable analysis model was then added, bringing the commit candidate to 24 tests.
- Repeated `make build` runs completed with `** BUILD SUCCEEDED **` for the native `arm64` target under Swift 6 strict concurrency, including the modern asynchronous Vision request API, stable-frame integration, localization, and preview overlay.
- The first full `make verify` run stopped at the source-tracking gate because the two newly created Swift files had not yet been staged. After all intended files were staged, the unchanged source-tracking check passed, confirming that both files will be present in a clean checkout.
- A final review added cancellation of superseded Vision tasks while retaining generation and window-ID guards against stale results.

The final commit-candidate verification completed at 01:04 JST on 2026-08-30:

- All 24 Core tests in 7 suites passed.
- The native `arm64` app build completed with `** BUILD SUCCEEDED **`.
- Swift format lint, tracked-source verification, the README language-boundary check, tracked-build-output, common-secret-pattern, and lecture-data-extension checks passed.
- Both English and Japanese localization files passed `plutil -lint`.

The initial required `LectureBoardCore tests` check for PR #4 passed in 22 seconds on a clean GitHub Actions checkout. This CI check covers the 24 platform-neutral Core tests; it does not compile or run the native Vision and ScreenCaptureKit adapters.

These checks verify deterministic filtering and occupancy assembly plus native compilation and linking. The app was not launched while the user was unavailable. No claim is made yet about actual OCR text, rectangle quality, title selection, coordinate alignment, preview alignment, latency, or suitability of the initial thresholds on real PowerPoint slides.

## Controlled native runtime verification on 2026-08-30

### Scope and data boundary

The runtime work used only a seven-slide synthetic deck created for this check:

- Deck filename in the external verification-artifact directory: `LectureBoard-Runtime-Verification.pptx`
- SHA-256 before and after the controlled runs: `c402aaace0678a03fca2c0d265e36a05de69f94af18179a563277d3fb0dbf159`
- No private lecture deck, lecture audio, microphone input, student data, or unpublished research content was used.
- The runtime report stores timestamps, permission state, window and bundle identifiers, state labels, and numeric counters only. It does not store frame images, OCR strings, window titles, recognized coordinates, or occupied-region coordinates.

The user authorized screen recording and use of PowerPoint for this verification. Virus Buster had previously blocked some launches, and the user allowed the task-specific app. Virus Buster was not disabled globally.

### Problems reproduced and fixes added

1. **Repeated Screen Recording prompts despite an enabled System Settings row.** The standard view previously called PowerPoint discovery automatically, and its general permission button requested Screen Recording, microphone, and Speech access together. Rebuilt ad hoc apps can also have a different code identity even when the visible name and bundle identifier are unchanged. The standard view now performs discovery only when Screen Recording preflight already succeeds; manual refresh and capture start are guarded both in the view policy and inside `AppModel`; only the explicit Screen Recording button calls the request API. Microphone and Speech requests are no longer coupled to that button. The dedicated runtime mode also requests access only when `--request-screen-recording` is explicitly supplied. The final controlled runs did not supply that flag, and their reports record `permissionWasRequested: false`.
2. **A runtime process could idle without a report when SwiftUI created no window.** Runtime startup was moved to an application-delegate state machine that starts once after both launch and configuration, independent of `WindowGroup`. Invalid runtime arguments now also terminate after launch instead of waiting for a window. The launch-policy tests cover both event orders and duplicate events. A subprocess smoke test additionally verifies invalid-argument termination and a valid no-match run that writes JSON and exits without requesting Screen Recording.
3. **The initial runtime Debug bundle depended on Xcode's debug dylib layout.** The isolated runtime build now sets `ENABLE_DEBUG_DYLIB=NO` and verifies the standalone executable, arm64 architecture, English and Japanese resources, bundle signature, and absence of the debug dylib dependency.
4. **Localization files were not copied by the generated project.** `project.yml` now assigns the localization directory to the resources build phase. Native app tests check both localizations and the final runtime build validates them with `plutil`.
5. **Idle ScreenCaptureKit delivery was indistinguishable from new content.** Capture delivery now records new frames and idle repeats separately while retaining the total sequence count. Unit tests cover classification and reset.
6. **The original default slide-change threshold missed measured synthetic transitions.** A failed dynamic run received 249 frames and confirmed 5 stable frames, but reported 0 changes even though complete-slide differences reached approximately `0.027` to `0.040`; the run later ended with `captureFailed` when its slideshow window closed, so it is not treated as a successful run. The default threshold was changed from `0.10` to `0.02`. Regression tests confirm that a measured `7 / 255` change is classified as a slide change while measured idle noise of approximately `0.000347` remains unchanged.
7. **External framework error text could have entered a JSON failure report.** Each failure code now maps to a fixed safe report sentence; untrusted error details are discarded. A regression test passes a sentinel containing a private window title and PowerPoint path through all six failure codes and confirms that neither the report object nor encoded JSON retains it.
8. **The first launch-smoke harness produced a false failure through incorrect `jq -e empty` use.** The application had exited and written valid JSON. The harness was corrected, its non-standard `jq` dependency was removed, and the final test uses macOS `plutil` plus a fixed metadata-key allowlist.
9. **Capture start, stop, error, refresh, and selection changes could race across actor suspension points.** A superseded start could overwrite or stop a newer stream, while a late stop or error completion could overwrite newer UI state. The capture actor now receives monotonic operation identifiers, rejects out-of-order operations, rechecks ownership after every external suspension, and disposes only its own stale local stream. `AppModel` publishes stop and error state before asynchronous cleanup, independently versions window refreshes, rejects selected identifiers absent from the latest window list, and rechecks the captured session before a delayed selection callback can stop it. Eleven lifecycle tests use controllable fakes to reproduce old-start/new-start, late-stop, immediate-error, concurrent-refresh, stale-refresh-error, missing-window, and delayed-selection sequences.
10. **The optional Developer-signing check did not prove that the designated requirement itself was bound to the supplied team.** Signature metadata and a generic Apple certificate constraint were checked separately, which could have accepted an insufficiently specific future requirement. A side-effect-free shell policy now requires the designated requirement to contain an exact quoted or unquoted `certificate leaf[subject.OU]` constraint for the explicitly supplied 10-character team. Regression fixtures accept both valid forms and reject a missing binding, another team, a misplaced team string, and a longer OU value with the expected prefix. No real LectureBoard Developer-signed build was produced.
11. **The first exact-team policy checked for the expected OU clause as a substring rather than validating its surrounding Boolean structure.** A requirement that allowed the expected team or a second team could therefore have been reported as team-bound. The policy now permits exactly one leaf-OU predicate, requires its complete quoted or unquoted value to equal the supplied team, and conservatively rejects disjunction and negation operators. Regression fixtures cover a valid parenthesized clause, a second-team disjunction, a disjunction with a non-OU condition, and textual and symbolic negation. No real LectureBoard Developer-signed build was produced.
12. **The Boolean-structure fix still searched raw requirement text and could mistake predicate-shaped data for a real OU constraint.** For example, another predicate's quoted string could contain the text of the expected team clause. The policy now scans quoted strings and block comments before matching syntax, preserves only a complete quoted team value, and excludes all other quoted or commented text from predicate recognition. Regression fixtures reject both a quoted fake clause and a commented fake clause; canonical requirements from this Mac's quoted-OU ChatGPT signature and unquoted-OU Microsoft PowerPoint signature were accepted. No real LectureBoard Developer-signed build was produced.

Targeted runs after these fixes passed 41 `LectureBoardCore` tests in 10 Swift Testing suites and 43 native app tests in 12 suites. The native tests include permission request isolation, preflight-gated appearance/refresh/start behavior, capture-control and delivery policies, capture lifecycle ordering, concurrent refresh behavior, runtime argument and permission policy, window selection, snapshot projection, launch ordering, and localization. Separate shell regression tests cover the native test/build script configuration, signing modes, Boolean structure, quoted and commented fake predicates, and the team-bound designated-requirement policy.

The final integrated `make verify` run completed successfully at 10:37 JST on 2026-08-30. Its ten stages verified:

- Swift format lint for app sources, app tests, Core sources, and Core tests
- All 41 Core tests in 10 suites
- All 43 native app tests in 12 suites
- The native compile-and-link build with signing disabled
- The arm64, English/Japanese, ad hoc-signed runtime build and strict bundle-signature verification
- Invalid-argument and no-match subprocess launch smoke tests without a Screen Recording request
- Git inclusion of every Swift source, README language boundaries, absence of tracked build output, common secret patterns, and lecture-data extensions

The final 10:37 post-lifecycle-fix runtime rebuild reproduced executable CDHash `ae80168e385b779183adf1b718f57b2057646ac8` and executable SHA-256 `268a17d0fc41c4924e623712f9e7d9087b849a05974136c852ba83ae9fe36f7b`. The arm64 bundle again passed `codesign --verify --deep --strict`; it contains English and Japanese resources and no debug-dylib dependency.

A frozen copy of that post-lifecycle-fix bundle was saved outside the repository as `LectureBoard AI Runtime 2026-08-30.app`, without replacing the earlier `LectureBoard AI.app`. A final recursive comparison found no difference from the 10:37 verified build product; its executable SHA-256, arm64 architecture, English and Japanese resources, bundle identifier, CDHash, and strict signature verification also matched. The frozen copy was not independently launched through LaunchServices, so its standalone Screen Recording preflight remains unverified.

### Current post-lifecycle-fix static direct-executable run

The byte-identical executable first produced by the 10:12 verification was launched directly from the Codex-authorized environment for five seconds against the exact synthetic PowerPoint editing-window title. The final 10:37 rebuild reproduced the same executable SHA-256 and CDHash but was not separately launched. The runtime arguments did not include `--request-screen-recording`.

Report filename in the external verification-artifact directory: `runtime-capture-lifecycle-final-static.json`

- Report SHA-256: `1663e609dae603853cfd6fcffb044df38965d790e46394cf0f26420b096608df`
- Observation: 10:13:06–10:13:11 JST, 5 requested seconds, 20 snapshots
- Result: `runStatus: completed`; no failure code or failure message
- Permission: no request was made; preflight before and after was `authorized`
- Selection: exactly one matching window, bundle identifier `com.microsoft.Powerpoint`
- Capture: 50 frames, all classified as new frames; every recorded capture state was `capturing`
- Stability: one confirmed stable frame and no slide change, as expected for the unchanged editing window
- Vision states observed: `idle`, `analyzing`, and `completed`
- Maximum observed counts: 35 text observations, 9 rectangle observations, and 4 occupied regions
- The synthetic deck SHA-256 remained unchanged, and no `LectureBoard AI` process remained afterward.

This verifies startup, selected-window delivery, the post-fix capture lifecycle's ordinary start and stop path, stable-frame confirmation, Vision execution, report writing, and orderly termination in the current executable. It does not dynamically exercise a slide transition or any of the intentionally interleaved race sequences; those sequences are covered by the controllable unit tests.

A dynamic rerun was attempted only through the safe PowerPoint driver. The exact Core Graphics editing window was present, but PowerPoint exposed zero Accessibility windows with the exact synthetic title. The same check failed once more after PowerPoint was brought to the foreground. The driver stopped before posting any key event in both cases, so no post-lifecycle-fix dynamic slideshow report was produced and no dynamic success is claimed for the current executable.

### Earlier controlled dynamic slideshow run

An earlier successful controlled run used the ad hoc-signed arm64 Debug app built at 09:25 JST, before the capture-lifecycle race fixes. Its executable CDHash was `24ec560dfa5da2f07fb5514d92c7a4a0f4cd72a8`. PowerPoint was driven only after one exact Core Graphics window and one exact Accessibility window matched the synthetic editing-window title. The safe driver started the slideshow, advanced it eight times, sent Escape, and verified the return to the exact editing window.

Report filename in the external verification-artifact directory: `runtime-slideshow-final.json`

- Report SHA-256: `ae7bf68c269599d1c2175352ff18aa9b19466a6e2f3663b940390f111c06bc1d`
- Observation: 09:29:05–09:29:28 JST, 22 requested seconds, 86 snapshots
- Result: `runStatus: completed`; no failure code or failure message
- Permission: no request was made; preflight before and after was `authorized`
- Selection: exactly one matching window, bundle identifier `com.microsoft.Powerpoint`
- Capture: 220 frames, 13 new frames, 207 idle repeats; every recorded capture state was `capturing`
- Stability: 5 confirmed stable frames and 4 classified slide changes
- Vision states observed: `idle`, `analyzing`, and `completed`
- Maximum observed counts: 10 text observations, 13 rectangle observations, and 8 occupied regions
- Maximum recorded difference from the stable frame: `0.04085648148148148`
- The synthetic deck hash was unchanged, and no `LectureBoard AI` process remained afterward.

This earlier run verifies that selected-window frame delivery, idle-repeat accounting, stable-frame confirmation, four slide-change classifications, Vision execution, and occupied-region generation ran together in one controlled synthetic slideshow on this Mac. It remains evidence for the measured threshold and the pre-lifecycle implementation, but it is not runtime evidence for the current executable. It also does not verify the correctness of OCR strings, rectangle or occupied-region coordinates, detection recall for every transition, animation handling, representative lecture decks, or lecture-length reliability.

At orderly shutdown, Vision printed `RecognizeTextRequest was cancelled` for one request that was still in flight near the observation boundary. The report had already observed repeated `completed` Vision states and the run exited with status 0. An additional attempt to move the final slide transition farther from shutdown is not counted as a success: PowerPoint did not create a slideshow window, the safe driver stopped, and `runtime-slideshow-final-stable-boundary.json` correctly recorded `windowNotFound` with zero snapshots. A single retry then stopped before posting keys because the exact editing window could not be verified as focused. These failures leave automated slideshow driving itself only partially reliable; they do not alter the successful run above.

### Screen Recording identity boundary

`make build-runtime` uses ad hoc signing by default. On this Mac its designated requirement is a per-build `cdhash`; therefore rebuilding can require macOS Screen Recording authorization again. The script reports this limitation. It uses a certificate- and team-bound stable-signing path only when both `LECTUREBOARD_CODE_SIGN_IDENTITY` and `LECTUREBOARD_DEVELOPMENT_TEAM` are explicitly supplied; the configuration and requirement policy are covered by shell tests, but no Developer-signed runtime has been executed in this work.

The current post-lifecycle-fix executable launched directly from the Codex-authorized environment reported Screen Recording preflight as `authorized` and completed static capture without requesting access. A separate prior LaunchServices `open` attempt reported preflight as `unknown` and failed with `screenRecordingUnavailable` without making a permission request. These are different launch contexts. The direct result must not be described as standalone LaunchServices authorization, and the frozen copy at its external path was not independently launched. No reboot was performed, so post-restart permission persistence is not verified.

## Still unverified on this Mac

- Independent LaunchServices capture with the frozen final app and post-restart permission persistence
- Dynamic slide-change capture with the current post-lifecycle-fix executable
- PowerPoint window closure, reselection, PowerPoint restart, and display reconnection recovery
- Representative Japanese, English, mixed-language, animated, and long-duration lecture decks
- OCR text correctness, title selection, rectangle coordinates, occupied-region coordinates, and overlay alignment
- Robust empty-space analysis and existing PowerPoint ink detection
- Transparent overlay position, size, click-through behavior, and non-interference with pen-tablet input
- Japanese and English microphone transcription and Japanese–English code switching
- Multi-display behavior and online-sharing composition
- Contextual AI board rendering and session export during a lecture
- Developer ID distribution signing, hardened runtime, and notarization

These items must remain described as prototypes or unverified behavior until each one is exercised and recorded on the lecture Mac.

## Local macOS handoff

The repository includes `AGENTS.md`, `.codex/config.toml`, `make doctor`, `make local-setup`, native Core and app test targets, an ad hoc runtime build, a no-permission-request launch smoke test, and Japanese local-development and handoff documentation. Native compilation and the narrow controlled runtime path above are verified on this Mac; the remaining runtime gates are listed separately.
