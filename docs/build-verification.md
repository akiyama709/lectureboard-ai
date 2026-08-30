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
6. **The original default image-difference threshold missed measured synthetic visual transitions.** A failed dynamic run received 249 frames and confirmed 5 stable frames, but reported 0 changes even though complete-window differences reached approximately `0.027` to `0.040`; the run later ended with `captureFailed` when its slideshow window closed, so it is not treated as a successful run. The threshold was changed from `0.10` to `0.02`. Regression tests confirmed that a measured `7 / 255` visual difference exceeded the threshold while measured idle noise of approximately `0.000347` remained unchanged. A later semantic correction renamed this outcome `.significantVisualChange` and stopped treating it as independent evidence of slide identity.
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

### Historical schema-1 post-lifecycle-fix static direct-executable run

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

This verifies startup, selected-window delivery, the post-fix capture lifecycle's ordinary start and stop path, stable-frame confirmation, Vision execution, report writing, and orderly termination in that schema-1 executable. It does not verify the current semantic build, dynamically exercise a slide transition, or exercise any of the intentionally interleaved race sequences; those sequences are covered by the controllable unit tests.

A dynamic rerun was attempted only through the safe PowerPoint driver. The exact Core Graphics editing window was present, but PowerPoint exposed zero Accessibility windows with the exact synthetic title. The same check failed once more after PowerPoint was brought to the foreground. The driver stopped before posting any key event in both cases, so no post-lifecycle-fix dynamic slideshow report was produced and no dynamic success is claimed for the current executable.

### Historical schema-1 post-lifecycle-fix dynamic exact-window run

A later dynamic rerun succeeded on 2026-08-30 with the then-current post-lifecycle-fix schema-1 executable and the exact `--window-id` path. It used only a byte-identical copy of the seven-slide synthetic deck. This is build-specific historical evidence and not runtime evidence for the current schema-3 semantic build:

- Test copy: `LectureBoard-Runtime-Dynamic-Current-2026-08-30.pptx`
- Original and copy SHA-256 before and after the run: `c402aaace0678a03fca2c0d265e36a05de69f94af18179a563277d3fb0dbf159`
- The copy passed ZIP integrity verification, was closed with saving disabled, and no matching on-screen PowerPoint window remained. PowerPoint retained one off-screen Core Graphics record for the closed title; it was not selectable by the on-screen-only runtime or safety checks.

The local safety helper was extended with a dynamic mode before this run. It freezes one exact projected PowerPoint window by process identifier, Core Graphics window identifier, title, layer, bounds, and Accessibility element. It rejects modal windows and re-verifies the complete identity, frontmost window, and focused Accessibility element before and after every key. It never falls back to the weaker probe context after a projected window has been frozen. Its absolute-uptime schedule targeted right-arrow input at 4, 8, 12, 16, 20, and 24 seconds of a 40-second observation, leaving approximately 16 seconds after the final input. A delay greater than 0.5 seconds stops further input. Failure cleanup first stops the runtime and sends Escape only when the frozen identity is still completely safe.

The first revision of that dynamic helper was not used after an independent read-only review found that modal state could be bypassed during cleanup. Modal rejection was added to the probe cleanup path, fallback from an unsafe frozen identity was removed, and a second time-of-check/time-of-use fallback was removed. The schedule was changed from relative sleeps to absolute uptime deadlines. The final GUI-free helper self-test passed 29 selector, cleanup, focus, modal, schedule, restoration, and evidence-policy checks. An independent final review found no remaining P0 or P1 issue. The reviewed helper source SHA-256 was `56b0467f36e7daec2c8619c6d5a44723f58e58ff2f5cdc8500dc4406b3452fe5`.

Report filename in the external verification-artifact directory: `runtime-dynamic-current-final-2026-08-30.json`

- Report SHA-256: `b2808f6cc83751a78fc32d352786f4659b25b6f2b83630d49442abeab28efd88`
- Observation: 12:02:19–12:03:00 JST, 40 requested seconds, 155 snapshots
- Result: `runStatus: completed`; no failure code or failure message
- Permission: no request was made; preflight before and after was `authorized`
- Selection: exactly one `com.microsoft.Powerpoint` window, Core Graphics window ID 6526
- Capture: 372 frames, comprising 17 new deliveries and 355 idle repeats; every recorded capture state was `capturing`
- Legacy stability fields: 6 confirmed stable frames and 5 image-difference events recorded in the old `slideChangeCount` field. These values are not independently identified PowerPoint slide changes.
- Scheduled input versus legacy image-difference events: 6 right-arrow attempts and 5 events. The old counter increments appeared at approximately 3.9, 7.8, 11.8, 15.7, and 23.8 seconds; no increment was recorded after the scheduled 20-second input.
- Vision states observed: `idle`, `analyzing`, and `completed`; a completed Vision state was recorded after the final legacy image-difference event
- Maximum observed counts: 10 text observations, 13 rectangle observations, and 8 occupied regions
- Maximum recorded difference from the stable frame: `0.04311002178649238`
- The runtime executable exited with status 0, the slide show exited, and the exact editing window was restored before the test copy was closed without saving.

The helper decoded and validated the complete report, including exact selection, permission-request absence, observation length, safe status values, monotonic frame, new, repeated, stable, and legacy change counters, `frame = new + repeated`, at least one image-difference event, and Vision completion after the final event. A separate `jq` semantic predicate independently accepted the JSON object and its key maxima.

This establishes dynamic selected-window delivery, stable-frame confirmation, execution of the legacy image-difference classifier, Vision execution, occupied-region generation, report writing, and orderly termination in that historical post-lifecycle-fix executable on one controlled two-display synthetic run. It does not establish slide identity or six-of-six transition recall, and one of six scheduled inputs had no corresponding legacy event. It also does not establish current-build behavior, OCR or coordinate correctness, animation handling, representative-deck coverage, LaunchServices authorization, or lecture-length reliability.

### Historical schema-2 pre-semantic-correction dynamic run

A later 40-second controlled run used a schema-2 build after persistent content and raster-candidate counters had been integrated but before image-only changes were semantically separated from actual slide identity. Its aggregate report remains canonical build-specific history; it is not evidence for the current schema-3 executable:

- Report: `runtime-dynamic-content-revision-2026-08-30.json`
- Report SHA-256: `704d9266bf1564161dd756a0be57c4a47d5459dfb9c9ae5cf0c103acc8320f41`
- Observation: 12:44:10–12:44:50 JST, 40 requested seconds, 154 snapshots
- Result: `runStatus: completed`; schema version 2; no Screen Recording request; preflight before and after was `authorized`
- Selection: exactly one `com.microsoft.Powerpoint` window, Core Graphics window ID 7355
- Capture: 373 frames, comprising 17 new deliveries and 356 idle repeats; every recorded capture state was `capturing`
- Historical counters: 6 stable snapshots, 5 image-difference events in the legacy `slideChangeCount` field, and 2 content revisions
- Analysis maxima: 10 text observations, 13 rectangles, 40 stroke-candidate regions, and 10 occupied regions
- Vision states observed: `idle`, `analyzing`, and `completed`; maximum recorded coarse difference from the stable frame was `0.04311002178649238`

The five legacy values are image-difference heuristic events, not independently identified PowerPoint slide transitions. The two content revisions do not identify whether their source was a slide change, animation, same-slide content, or PowerPoint UI, and the 40 raster regions are candidates rather than confirmed ink. A later audit also found that the local helper's per-input timing correlation for this run could carry a previously observed counter value into a later input window. Only the aggregate report fields above are retained as evidence. This run does not verify the current schema-3 semantics, current source, OCR or coordinate correctness, representative decks, or lecture-length reliability.

### Earlier controlled dynamic slideshow run

An earlier successful controlled run used the ad hoc-signed arm64 Debug app built at 09:25 JST, before the capture-lifecycle race fixes. Its executable CDHash was `24ec560dfa5da2f07fb5514d92c7a4a0f4cd72a8`. PowerPoint was driven only after one exact Core Graphics window and one exact Accessibility window matched the synthetic editing-window title. The safe driver started the slideshow, advanced it eight times, sent Escape, and verified the return to the exact editing window.

Report filename in the external verification-artifact directory: `runtime-slideshow-final.json`

- Report SHA-256: `ae7bf68c269599d1c2175352ff18aa9b19466a6e2f3663b940390f111c06bc1d`
- Observation: 09:29:05–09:29:28 JST, 22 requested seconds, 86 snapshots
- Result: `runStatus: completed`; no failure code or failure message
- Permission: no request was made; preflight before and after was `authorized`
- Selection: exactly one matching window, bundle identifier `com.microsoft.Powerpoint`
- Capture: 220 frames, 13 new frames, 207 idle repeats; every recorded capture state was `capturing`
- Legacy stability fields: 5 confirmed stable frames and 4 image-difference events recorded as slide changes by that earlier implementation
- Vision states observed: `idle`, `analyzing`, and `completed`
- Maximum observed counts: 10 text observations, 13 rectangle observations, and 8 occupied regions
- Maximum recorded difference from the stable frame: `0.04085648148148148`
- The synthetic deck hash was unchanged, and no `LectureBoard AI` process remained afterward.

This earlier run verifies that selected-window frame delivery, idle-repeat accounting, stable-frame confirmation, four legacy image-difference classifications, Vision execution, and occupied-region generation ran together in one controlled synthetic slideshow on this Mac. It remains evidence for the measured threshold and the pre-lifecycle implementation, but it is not evidence of independently identified slide transitions and is not runtime evidence for the current executable. It also does not verify the correctness of OCR strings, rectangle or occupied-region coordinates, detection recall for every transition, animation handling, representative lecture decks, or lecture-length reliability.

At orderly shutdown, Vision printed `RecognizeTextRequest was cancelled` for one request that was still in flight near the observation boundary. The report had already observed repeated `completed` Vision states and the run exited with status 0. An additional attempt to move the final slide transition farther from shutdown is not counted as a success: PowerPoint did not create a slideshow window, the safe driver stopped, and `runtime-slideshow-final-stable-boundary.json` correctly recorded `windowNotFound` with zero snapshots. A single retry then stopped before posting keys because the exact editing window could not be verified as focused. These failures leave automated slideshow driving itself only partially reliable; they do not alter the successful run above.

### Screen Recording identity boundary

`make build-runtime` uses ad hoc signing by default. On this Mac its designated requirement is a per-build `cdhash`; therefore rebuilding can require macOS Screen Recording authorization again. The script reports this limitation. It uses a certificate- and team-bound stable-signing path only when both `LECTUREBOARD_CODE_SIGN_IDENTITY` and `LECTUREBOARD_DEVELOPMENT_TEAM` are explicitly supplied; the configuration and requirement policy are covered by shell tests, but no Developer-signed runtime has been executed in this work.

That historical schema-1 post-lifecycle-fix executable launched directly from the Codex-authorized environment, reported Screen Recording preflight as `authorized`, and completed static capture without requesting access. A separate prior LaunchServices `open` attempt reported preflight as `unknown` and failed with `screenRecordingUnavailable` without making a permission request. These are different launch contexts. The historical direct result must not be described as standalone LaunchServices authorization or current schema-3 runtime evidence, and its frozen copy at an external path was not independently launched. No reboot was performed, so post-restart permission persistence is not verified.

### Exact-window mouse-ink verification

This follow-up used a byte-identical copy of the synthetic deck only:

- Original: `LectureBoard-Runtime-Verification.pptx`
- Test copy: `LectureBoard-Runtime-Ink-Verification-2026-08-30.pptx`
- SHA-256 of both files before and after the work: `c402aaace0678a03fca2c0d265e36a05de69f94af18179a563277d3fb0dbf159`
- The test copy was closed with saving disabled after the final run, and no matching PowerPoint window remained.
- No private slides, microphone input, lecture audio, student data, or unpublished research content was used.

Before changing the selection path, `make doctor` completed with zero failures and zero warnings. `make local-setup` then passed the existing 41 Core tests in 10 suites and regenerated `LectureBoardAI.xcodeproj` successfully.

PowerPoint created two substantial layer-zero windows when the synthetic presentation began: a 2,560-by-1,440 projected slide-show window and a 1,512-by-982 Presenter View window. A diagnostic run observed each candidate three times with stable Core Graphics identity and found exactly one Accessibility window with the same title and bounds for each. It sent no mouse input, launched no LectureBoard process, wrote no image, and verified the return to the exact editing window.

The first ink-driver attempt correctly stopped before drawing when it found two substantial candidates, but its early-failure cleanup had not retained enough context to close the slide show. The slide show was closed by addressing the exact synthetic presentation, and both deck hashes remained unchanged. The helper now freezes the complete candidate set and permits cleanup Escape only when the same PowerPoint process and candidate set remain present and the focused Accessibility element is the unique window for one candidate title. Its GUI-free selector and cleanup regression checks cover one-of-two exact selection, zero and duplicate exact matches, safe and unsafe candidate-set cleanup, and focused-Accessibility uniqueness.

The production runtime previously accepted only a title query. A new `--window-id` selection path now accepts one nonzero ASCII-decimal `UInt32`, is mutually exclusive with title selection, rejects unknown long options and duplicate or malformed values, and selects only one exact descriptor owned by application name `Microsoft PowerPoint` and bundle identifier `com.microsoft.Powerpoint`. Duplicate identifiers fail closed even if one descriptor has the expected ownership. The runtime driver passes only the already frozen Core Graphics window identifier, eliminating the title re-selection boundary for this check. The added parser, selector, report-message, and launch-smoke regressions brought the targeted results to 46 Core tests in 10 suites and 49 native app tests in 12 suites. The arm64 ad hoc runtime build and strict signature check also passed. That build's executable SHA-256 is `b7aa0311f49ee6de4ac66c353cbf53fa3d338a34e29e6df662f8db1a2d4906c9`, with CDHash `ff276fc848cc875d152d1a269cc7eb5b978e1df7`.

One otherwise complete ink run then returned a helper failure because the post-Escape check required the original editing window to be already frontmost. Its runtime report and three images were retained as failed-at-restoration evidence, not as the final successful run. The helper now waits for the saved Core Graphics and Accessibility editing-window identities to reappear independently of focus, refuses restoration when a modal, dialog, or sheet is present, raises and focuses only that saved Accessibility element without posting another key or mouse event, and then repeats the complete identity and focus verification. Four GUI-free restoration-policy branches increased the helper's local self-test total to 12. An independent read-only review found no remaining P0-P2 issue in the helper. The final helper source and binary SHA-256 values were `abcd58140f07d4d74523bb58fa61a7ed26b3b0df9be1988dbabe2f8e787a5e65` and `1f1d00f4606aaf38d088a90cf81cfb1493a33ad35966900dd52543c19f940c4b`; the helper remains ignored local verification tooling rather than a publication source file.

The final end-to-end helper run succeeded against the exact projected window:

- Runtime report: `runtime-ink-final-2026-08-30.json`
- Report SHA-256: `6819ec2cc0f3a08c2e88e2f26b12eaa8dff33aa283ce3b972fe5d670329b772f`
- Observation: 12 requested seconds, 47 snapshots, selected window ID 6021, and exactly one matching `com.microsoft.Powerpoint` window
- Permission: no Screen Recording request; preflight before and after was `authorized`
- Result: `runStatus: completed`, no failure code or message, and runtime exit status 0
- Capture: 107 frames, 30 new frames, and 77 idle repeats; every recorded capture state was `capturing`
- Stability: one stable frame and no classified slide change
- Vision states: `idle`, `analyzing`, and `completed`; maxima of 4 text observations, 8 rectangles, and 6 occupied regions
- Driver result: five mouse-drag attempts completed, three exact-window images were saved, Shift-E was posted after re-verifying the frozen window, the slide show exited, and the exact editing window was restored

All three images are 2,560-by-1,440 sRGBA captures of the same frozen slide-show window:

- Before: `runtime-ink-final-before-2026-08-30.png`, SHA-256 `64c87bbec9891947f85262383982fa431ef0c8839c1275226e0e0cf2d839a019`
- After drawing: `runtime-ink-final-after-draw-2026-08-30.png`, SHA-256 `c904067a6fe8cb94b0f2b629f9ce82e6b95b7e7071a60f5ff11e0aa69934acb8`
- After erasing: `runtime-ink-final-after-erase-2026-08-30.png`, SHA-256 `36ef203174da21e23fe4f781e6119ed5110edaebbca7d501d2dda3ff76b9c852`

An independent pixel check found 7,178 pixels changed between the before and after-drawing images. A fixed red-like color predicate found 0 pixels before drawing, 3,465 pixels after drawing, and 0 pixels after erasing. Connected-component analysis of the red-like mask found exactly five non-background components, matching the five intended mouse strokes, and visual inspection confirmed their presence and subsequent absence. The before and after-erasing images were not whole-frame identical: 2,771 pixels differed, so complete frame restoration is not claimed. The remaining visual difference was confined to PowerPoint's presentation controls and pen-mode state; no red stroke remained under the fixed predicate or visual inspection.

This historical run verifies a narrow two-display case in which PowerPoint mouse ink was rendered on the projected slide, the same exact window was streamed by that pre-persistent-content-integration LectureBoard runtime while the ink appeared and was erased, and the runtime completed without requesting Screen Recording access. It does not establish that LectureBoard recognized, classified, or mapped the ink and is not runtime evidence for the current semantic build. The stable-frame counter remained at one and the slide-change counter at zero, so the then-current sparse fingerprint and Vision pipeline did not produce a new stable ink-aware analysis during this run. Existing-ink detection, pen-tablet non-interference, human-ink priority, thin-stroke sensitivity, representative layouts, and long-duration reliability remain unverified.

The final integrated `make verify` run completed successfully at 11:37 JST after the implementation, tests, and substantive verification record above were present. All ten stages passed: Swift format lint, 46 Core tests in 10 suites, 49 native app tests in 12 suites, the native compile-and-link build, the arm64 ad hoc runtime build and strict signature verification, launch smoke tests without a Screen Recording request, source-tracking and README-language checks, and the publication safety checks. The rebuilt executable reproduced SHA-256 `b7aa0311f49ee6de4ac66c353cbf53fa3d338a34e29e6df662f8db1a2d4906c9` and CDHash `ff276fc848cc875d152d1a269cc7eb5b978e1df7`.

A byte-identical copy of that final build was saved without replacing the earlier frozen app as `LectureBoard AI Runtime Window ID 2026-08-30.app` in the external verification-artifact directory. A recursive comparison found no difference from the final build product. The copy is an arm64 executable with the same SHA-256, valid English and Japanese resources, and a valid strict ad hoc bundle signature. It was not launched independently through LaunchServices, so standalone Screen Recording authorization for this new copy is not claimed.

### Core groundwork for persistent content changes and stroke candidates

The mouse-ink evidence above showed that the existing 32-by-18 center-point luminance fingerprint reported a difference of exactly zero while five visible red strokes were present. The new-frame delivery counter did not mean that those frames had different fingerprints. The existing coarse fingerprint and calibrated slide-change thresholds were therefore left unchanged.

Two separate platform-neutral paths were added instead:

- `StableContentChangeDetector` compares a denser RGB-cell fingerprint by per-cell maximum channel difference, confirms only persistent sparse changes, and updates its baseline after confirmation. It reports a content revision and does not decide whether that revision came from same-slide input, animation, PowerPoint UI, or an actual slide transition. Deterministic tests cover initial baseline confirmation, persistent sparse drawing, erasure back to the original pixels, one-frame noise, moving animation candidates, malformed and mismatched fingerprints, configuration bounds, reset, and a dense-RGB change deliberately missed by a simulated 32-by-18 center-point luminance fingerprint.
- `RasterOccupancyDetector` applies deterministic integer local-color differences and connected components to a top-left RGB8 raster. Its output is deliberately named `strokeCandidateRegions`; it does not assert that a candidate is PowerPoint ink. Tests cover uniform white, black, and colored backgrounds; dark, light, and differently colored thin lines; isolated noise; five separated lines; erasure; a smooth gradient; conservative checkerboard occupancy; slide-edge clamping; and deterministic ordering.

`SlideVisualAnalysis` now preserves stroke candidates separately from Vision rectangles while merging their padded regions with text and rectangles for placement occupancy. Legacy JSON without the new key decodes it as an empty array. Tests cover candidate clamping, empty-candidate rejection, separation from `graphicRegions`, transitive text-to-stroke-to-graphic merging, legacy decoding, and new-format round-trip.

The normal-access `make test-core` run completed at 12:08 JST with all 71 tests in 12 suites passing. At this checkpoint, the new logic was Core-only: no native CGImage rasterizer, capture-frame fingerprint production, AppModel trigger, runtime counter, or live PowerPoint ink recognition had yet been integrated. The passing Core fixtures must not be described as runtime ink detection.

### Native integration, schema 3, and launch-safety regressions

The persistent-content groundwork was subsequently integrated into the native capture and analysis path. `CGImageRasterizer` now produces a fixed 160-by-90 dense RGB fingerprint for new ScreenCaptureKit deliveries and an sRGB top-left RGB8 analysis raster whose long edge is limited to 640 pixels. Transparent input is composited over white. Idle-repeat frames reuse the exact last image and both fingerprints rather than rerasterizing it. `AppModel` rejects duplicate and out-of-order sequence numbers, separates persistent dense-RGB changes from coarse `.significantVisualChange` updates, rebases or resets the dense detector at coarse state boundaries, and starts Vision plus raster-candidate analysis for each accepted stable visual or persistent content revision. The independent `slideChangeCount` remains zero because no independent slide-identity signal exists.

Native and Core regressions were added for the integration boundaries rather than relying on the earlier PowerPoint images:

- Native raster tests verify RGB channel order, top-left row order, landscape and portrait scaling, non-enlargement below the raster cap, 160-by-90 fingerprint production, alpha compositing, capture-style BGRA conversion, dimension and allocation bounds, and the production new-frame factory.
- The capture factory has separate production paths for a newly delivered image and an idle repeat. Tests require a new delivery to contain the coarse and dense fingerprints, and require the repeat to preserve the same image identity and both fingerprints.
- App integration tests cover initial stability, sparse persistent updates, coarse visual updates without slide-count inflation, detector rebasing, stop/restart, duplicate and out-of-order frames, capture-error restart, a transition that returns to the original visual, current versus superseded cancellation, and rejection of analysis results after a newer revision or stop.
- Vision integration tests require raster candidates to remain distinct while contributing to assembled occupancy and require a pre-cancelled request to stop before native Vision work.
- Runtime schema-3 tests cover exact encoded root and snapshot key sets, content-revision and stroke-candidate counts, nonzero count projection, the producer's forced schema-3 label, and schema-1 and schema-2 historical decoding. Separate spatial-ordering tests require a strict lexicographic comparator. Image-only changes now increment `contentRevisionCount`; they do not increment `slideChangeCount`.

Two launch-harness problems were also fixed after the 12:41 and 12:42 crash reports shown by the user. Both reports show `SIGABRT` during AppKit application registration, before LectureBoard's runtime state machine began. A shell process check could not establish whether its own execution context could access the WindowServer. The launch smoke test now runs a read-only Core Graphics window-list probe first and stops without launching the app if that probe fails. Its regression accepts a successful injected probe, rejects a failed one, and confirms that the default wrapper preserves the real probe's exit status. The smoke harness also requires previously unused output paths, verifies that invalid arguments cannot leave a report, and checks the no-match report's root keys against a fixed allowlist; that failure report has no snapshots. Separate Core regressions verify the exact root and nonempty snapshot key sets, preventing unexpected metadata shape from being treated as current schema-3 output.

The publication-source gate previously checked only production Swift files. It now checks app and Core sources, their tests, and every top-level script. A temporary Git-fixture regression confirms that untracked app tests, Core tests, the WindowServer probe, its wrapper, and its test are all rejected, then confirms acceptance after those exact files are staged.

The normal-access verification checkpoints after these fixes were:

- `make test-core`: all 80 tests in 12 suites passed at 13:34 JST.
- `make test-app`: all 71 tests in 15 suites passed after the production new-frame and idle-repeat factory paths were wired at 13:47 JST.
- `make build`: the native arm64 compile-and-link build succeeded at 13:35 JST.
- `make build-runtime`: the arm64 ad hoc-signed runtime bundle, strict signature verification, English and Japanese resources, and no-debug-dylib check succeeded after the final capture-factory change at 13:50 JST.
- The publication-source and WindowServer-preflight regression scripts passed. In the restricted shell context the real WindowServer probe stopped the launch smoke before opening the app, as designed. Re-running that same smoke test in the ordinary logged-in macOS context passed without requesting Screen Recording permission.

At this checkpoint the runtime executable SHA-256 was `3ee3e83ee69386891d41c9f8890c14cb6b30f18524fd5858181eb579efcfd439`, its ad hoc CDHash was `6ad10a5e800ac45a5d1779196cd5bc547dd34e35`, and `file` identified it as a Mach-O 64-bit arm64 executable. These are checkpoint values before the final integrated `make verify`; final values are recorded separately below if they remain reproducible.

### Current schema-3 dynamic attempt stopped before input

A current-build dynamic check was prepared against the byte-identical synthetic copy `LectureBoard-Runtime-Dynamic-Content-2026-08-30.pptx`. Its SHA-256 was `c402aaace0678a03fca2c0d265e36a05de69f94af18179a563277d3fb0dbf159`, matching the original synthetic deck, and ZIP integrity passed before the attempt.

The ignored local GUI helper was first extended with a dynamic-only fallback that would use PowerPoint semantic scripting commands rather than keyboard or mouse events when Accessibility enumeration was unavailable. The candidate helper compiled with Swift 6 strict concurrency and warnings as errors, and its 76 GUI-free selector, report, timing, identity, and evidence-policy self-tests passed. A read-only `--verify-only` invocation then stopped with an exact Accessibility match count of zero before starting a slide show, launching LectureBoard, writing a report, or sending any input.

A separate sanitized read-only diagnostic explained why the fallback did not qualify. Screen and process access were available, and Core Graphics exposed exactly one exact on-screen synthetic editing window. PowerPoint's `AXWindows` attribute returned one element, but that element reported role `AXApplication`, no readable bounds, no matching title, no window subrole, and an unreadable `AXModal` attribute. It was therefore not a usable Accessibility window and could not establish that no dialog or sheet would interfere.

The scripting fallback was not used. Independent review found two additional P1 safety defects in the unused candidate:

- its identity query and the semantic `run slide show`, `go to next slide`, and exit commands were separate Apple events, while the command transaction itself did not revalidate the frozen presentation name and full path; and
- its application target was a fixed PowerPoint application path rather than the already resolved process identifier and bundle URL, so a process change between checks could have addressed or launched another PowerPoint instance.

The ignored local helper was then returned to an explicit fail-closed state. Fallback resolution and every semantic command bridge now reject immediately, so the unsafe candidate cannot reach runtime launch, HID input, semantic commands, or fallback cleanup. The final helper source SHA-256 was `49c10689eb2763e6f4a1fdd1c49f278f442a1ace5aeb4daf2c7f04eb8d463ac5`; its compiled binary SHA-256 was `fe95eabf577a77b66197139c01ed6e8b0ee80dc2d56748da844647ca06e6818e`. It compiled with Swift 6 strict concurrency and warnings as errors, and all 75 GUI-free self-tests passed. This verifies that the fallback is disabled, not that semantic PowerPoint control works.

No attempt was made to weaken those boundaries merely to obtain a runtime result. The helper sent no slide, keyboard, or mouse input; it produced no current schema-3 dynamic report or screenshot; and current-build dynamic behavior remains unverified. Current-build mouse-ink automation was also not attempted because it still requires a uniquely matched real Accessibility window.

The dynamic synthetic copy was closed without saving. Its SHA-256 remained `c402aaace0678a03fca2c0d265e36a05de69f94af18179a563277d3fb0dbf159`, ZIP integrity still passed, and its PowerPoint lock file was absent. The only LectureBoard crash reports remained the two AppKit-registration reports at 12:41 and 12:42; no later crash report was created by the preflight, helper, build, test, or smoke work.

### Final integrated verification at 14:17 JST

The final `make verify` run completed all 11 stages successfully on 2026-08-30:

- Swift format lint passed for app and Core sources and tests.
- All 80 Core tests in 12 suites passed.
- All 71 native app tests in 15 suites passed with local ad hoc signing.
- The signing-disabled native arm64 compile-and-link build succeeded.
- The arm64 ad hoc runtime build succeeded with English and Japanese resources, no debug-dylib dependency, and a strict valid bundle signature.
- The WindowServer preflight regressions and the ordinary logged-in-context launch smoke passed; the smoke did not request Screen Recording.
- The publication-source fixture and live source-inclusion gate passed after the 13 intended new sources and tests were staged explicitly.
- README language boundaries, tracked-build-output, common-secret-pattern, and lecture-data-extension checks passed.

The final runtime executable reproduced checkpoint SHA-256 `3ee3e83ee69386891d41c9f8890c14cb6b30f18524fd5858181eb579efcfd439` and ad hoc CDHash `6ad10a5e800ac45a5d1779196cd5bc547dd34e35`. `file` again identified a Mach-O 64-bit arm64 executable, and `codesign --verify --deep --strict` passed. The bundle is not Developer ID distribution signed or notarized.

## Still unverified on this Mac

- Independent LaunchServices capture of a current schema-3 build and post-restart permission persistence
- Live dynamic and mouse-ink behavior of the current schema-3 semantic build; the attempted dynamic check stopped before input and produced no report
- An independent actual-slide identity signal; historical image-difference builds recorded five legacy events from six scheduled inputs, which is not slide-transition verification for the current executable
- PowerPoint window closure, reselection, PowerPoint restart, and display reconnection recovery
- Representative Japanese, English, mixed-language, animated, and long-duration lecture decks
- OCR text correctness, title selection, rectangle coordinates, occupied-region coordinates, and overlay alignment
- Robust empty-space analysis and existing PowerPoint ink detection
- Transparent overlay position, size, click-through behavior, and non-interference with pen-tablet input
- Japanese and English microphone transcription and Japanese–English code switching
- Representative multi-display arrangements, display swap or reconnection, and online-sharing composition beyond the one fixed two-display case above
- Contextual AI board rendering and session export during a lecture
- Developer ID distribution signing, hardened runtime, and notarization

These items must remain described as prototypes or unverified behavior until each one is exercised and recorded on the lecture Mac.

## Local macOS handoff

The repository includes `AGENTS.md`, `.codex/config.toml`, `make doctor`, `make local-setup`, native Core and app test targets, an ad hoc runtime build, a no-permission-request launch smoke test, and Japanese local-development and handoff documentation. Native compilation and the explicitly identified historical controlled runtime paths above are verified on this Mac; the current schema-3 dynamic and mouse-ink gates remain listed separately.
