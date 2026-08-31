# Build and verification status

Updated: 2026-08-31

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

### Public-v1 completion definition and PowerPoint identity hardening at 16:28 JST

The project completion definition was extended beyond the lecture-ready alpha gate. Completion now means a public `v1.0.0` GitHub Release that contains an installable macOS artifact with hardened runtime, Developer ID distribution signing, Apple notarization, and successful post-publication re-download verification. Repository creation, source availability, alpha, beta, and release-candidate builds remain intermediate gates. The authoritative checklist is `docs/v1-release-checklist.md`; ADR 0007 records the decision. The initial `scripts/publish-to-github.sh` and its associated publication checklists are now explicitly historical and must not be reused for branch updates or the final release.

A release-definition checker and negative fixture test were added. They require the public-v1 completion statement; alpha, beta, and release-candidate status as intermediate gates; the beta, release-candidate, and public-v1 milestones; hardened runtime; Developer ID signing; notarization; public-artifact re-download and independent re-verification; the Japanese and English definitions; the v1 checklist; corrected CHANGELOG language that does not claim independent slide identity or current-build runtime evidence; the completed initial-source-publication review and separate v1-scope reassessment in ADR 0006; and ADR 0007. The negative fixtures separately reject a missing v1 checklist, public-v1 milestone, README completion definition, prerelease-intermediate statement, hardened-runtime gate, public-artifact re-download gate, downloaded-artifact security rechecks, removal of the cautious visual/content-change wording, removal of the historical-evidence boundary, removal of the unverified production identity-provider gate, and corrected ADR 0006 status. Three additional fixtures preserve all required cautious wording while appending the specific known false claims that slide-change detection is implemented, historical runtime evidence verifies the current build, or PowerPoint slide identity is complete; the checker rejects each appended claim explicitly. This is a regression guard for those exact forbidden statements, not a general natural-language overclaim detector.

The historical initial-publication script now refuses to run inside an existing Git checkout or when the target GitHub repository already exists. It also fails closed when remote absence cannot be established, before `git init`, staging, or committing. Four fixtures cover an existing checkout, existing remote, indeterminate remote state, and a confirmed HTTP 404 that is allowed to reach initialization. The live current-repository check also stopped immediately at the existing-checkout guard without changing Git state. `make verify` runs this guard regression as stage 9, the release-definition fixture as stage 10, and the live release-definition consistency gate as stage 11 of 14.

The prior current-build dynamic attempt was also reclassified more precisely. Production window discovery and capture use ScreenCaptureKit and do not depend on Accessibility. The failed check occurred in an ignored local automation helper: Core Graphics saw the exact synthetic window, while PowerPoint's Accessibility `AXWindows` result did not expose a usable `AXWindow`. The helper therefore stopped before input. This is not evidence that the production ScreenCaptureKit scanner or capture path failed, and no Accessibility, AppleScript, HID, keyboard, or mouse fallback was added to production code.

The tracked production capture path was hardened independently of that helper:

- `PowerPointWindowIdentity` freezes the ScreenCaptureKit window identifier, owning process identifier, and exact case-sensitive `com.microsoft.Powerpoint` bundle identifier.
- The scanner no longer accepts an application-name fallback.
- Title and window-ID runtime selection apply the same owner policy.
- Capture start re-enumerates ScreenCaptureKit windows and proceeds only when the window identifier is unique and the complete frozen identity still matches.
- Reused identifiers, changed owner processes, wrong or missing bundles, duplicate descriptors, missing owners, missing targets, and stale cached identities fail closed.
- `AppModel` passes the frozen identity through start, stops when a refresh replaces the owner behind the same window identifier, and preserves the active session when the complete identity remains unchanged.

Native regressions cover all of the rejection paths above, the positive full-identity resolution path, the identity passed to capture, replacement during a suspended start, replacement during refresh, and preservation across a same-identity refresh. An independent read-only code audit found no remaining P0 or P1 issue; the audit's P2 requests for direct resolver coverage and a non-nil session-preservation assertion were added before final verification.

The required baseline commands were repeated. The first sandboxed `make local-setup` could not write Swift and Clang user cache paths and failed before tests; the unchanged command then succeeded in the ordinary local macOS context, where `make doctor` reported zero failures and zero warnings, GitHub CLI authentication as `akiyama709`, all 80 Core tests passed, and XcodeGen regenerated the project. This remains an execution-sandbox boundary rather than a source failure.

Two consecutive 13-stage `make verify` runs at 16:28 JST were successful intermediate checkpoints. Final audit then added the initial-publication guard, expanded the completion-definition regressions, corrected two CHANGELOG overclaims, and reconciled ADR 0006 with the completed initial source publication and the still-required v1-scope reassessment. After those changes, the final ordinary-context `make verify` run started at 16:42 JST, completed by 16:42:58 JST, and passed all 14 stages against the final staged source. It verified:

- Swift format lint for all app and Core sources and tests
- All 80 Core tests in 12 suites
- All 89 native app tests in 16 suites with local ad hoc signing
- The signing-disabled native arm64 compile-and-link build
- The arm64 ad hoc runtime build, English and Japanese resources, no debug-dylib dependency, and strict bundle-signature verification
- WindowServer preflight regressions and runtime launch smoke without requesting Screen Recording
- Publication-source fixture and live source-inclusion checks
- The four-path initial-publication fail-closed fixture
- README language boundary and the expanded release-definition fixtures and consistency gate
- No tracked build output, common secret pattern, or lecture-data extension

The final runtime executable SHA-256 was `512fd4febf52768d1248fdcd6975ad08ba241f09230c226964a95451fdbcc7cb`. Its ad hoc CDHash was `e1a87229d46e21ed110f42255f96b053cff24024`; `file` identified a Mach-O 64-bit arm64 executable, and the complete bundle passed strict signature verification. This is a local development artifact, not a hardened-runtime, Developer ID distribution-signed, notarized, beta, release-candidate, or `v1.0.0` artifact.

No live dynamic slideshow or mouse-ink input was sent during this work, and no current-build schema-3 runtime success report was created. Those gates remain unverified. No branch was pushed, no pull request or tag was created, and no GitHub Release was published.

At 16:33 JST, a read-only GitHub query confirmed that `akiyama709/lectureboard-ai` was `PUBLIC` with `main` as its default branch. `gh release list --repo akiyama709/lectureboard-ai --limit 100` returned no entries, and the local tag list was empty. This verifies only that no GitHub Release or local tag existed at that checkpoint; it does not verify a release artifact or any untested runtime behavior.

### Schema-4 independent-identity foundation and fail-closed PowerPoint probe at 17:24 JST

The current source now contains an independent slide-identity boundary without claiming that a production PowerPoint identity source exists. `SlideIdentityTracker` requires two consecutive observations with the same presentation-session token and positive PowerPoint slide ID before it establishes or changes its baseline. Initial establishment and recovery after an unavailable signal do not increment `slideChangeCount`; an actual counter increment requires a separately stabilized slide ID within the same presentation session. A session-token change, unavailable signal, invalid sample, duplicate delivery, or reversed delivery cannot infer a transition.

Runtime metadata moved to schema 4. Of identity data, each snapshot records only the identity state, accepted-observation count, and continuity-break count. The provider observation's presentation-session token, PowerPoint slide ID, slide index, complete target identity, and owner process ID are deliberately excluded. The existing top-level selected Core Graphics window ID and selected bundle identifier remain metadata in the report. Schema 1, 2, and 3 remain decodable with unavailable identity state and zero identity counters. Exact encoded-key and historical-decoding tests cover this boundary.

The native app has a `PowerPointSlideIdentityProviding` boundary and a default unavailable provider. For each accepted capture start, that provider does not request Automation permission, send Apple Events, retain a target after start, or manufacture an available identity sample; it emits one unavailable observation. App integration tests verify that it fails closed. Candidate identity changes quarantine visual frame analysis, final-transcript board proposals, and in-flight Vision results. Baseline establishment and a confirmed change both rebase the board to the reported slide index and clear prior board and analysis state. A changed index for the same confirmed slide ID updates the board's slide number without counting a transition or discarding its elements. Candidate-period frames still contribute to capture-delivery metrics but are excluded from visual analysis. After either boundary, visual stability can be re-established only by a `.new` delivery whose ScreenCaptureKit `SCFrameInfo.displayTime` is present, positive, and strictly later than the local `mach_absolute_time()` recorded when the app accepts the confirming observation. The provider cannot supply or override that local boundary. Missing, zero, equal, older, candidate-period, and idle-repeat frame times are rejected by deterministic tests. Apple Speech results now carry the local mach-absolute time sampled by the speech callback. A final result emitted before the identity boundary remains rejected even if its MainActor delivery occurs later, and all final results are rejected while the app is waiting for the post-boundary frame. Zero, older, equal, pre-frame, and newer speech-result boundaries plus accepted post-frame delivery are covered in the integration regression. Selection changes, stopped or restarted sessions, capture errors, duplicate and reversed observations, wrong target identities, pre-confirmation new frames, and old idle repeats reject stale results. Capture failure marks identity interrupted only when continuity was establishing or identified; a start failure or an error while identity was unavailable remains unavailable.

The ordinary local macOS checkpoints passed all 90 Core tests in 13 suites and all 103 native app tests in 18 suites. One earlier native test run reported the existing `AppContentChangeIntegrationTests` analysis timeout while this integration was being refined; the immediate complete rerun after the new-frame boundary fix passed all 103 tests. A later audit found that a delivery-side `Date` and a provider-supplied mach timestamp could not prove when a ScreenCaptureKit frame was displayed. The frame boundary was therefore changed to the WindowServer mach-absolute `SCFrameInfo.displayTime` compared with the app's local observation-acceptance time, and the provider timestamp was removed. The first rerun exposed only a test-fixture `Int`-to-`UInt64` compile mismatch; after the fixture was corrected, the complete native suite passed at 17:43 JST. After removing the provider timestamp and adding the nil, zero, older, equal, and newer boundary assertions, the complete native suite passed again at 17:47 JST with all 103 tests in 18 suites. The first restricted-shell attempt at 17:47 JST could not write the user's Swift and Clang cache directories; the unchanged command passed in the ordinary local context. An additional stale-transcript audit then added the local speech-callback boundary and pre-frame guard; the complete suite passed again at 17:52 JST with all 103 tests in 18 suites. A separate Core regression completed at 17:55 JST with all 90 tests in 13 suites. These restricted-versus-ordinary results are execution-sandbox boundaries rather than source defects.

A separate read-only probe examined whether PowerPoint's scripting model could bind its slide-show window to the exact Core Graphics window already selected by ScreenCaptureKit. It targeted only an already running exact PowerPoint process and bundle and called the Automation preflight without prompting. A byte-identical temporary copy of the controlled synthetic deck retained SHA-256 `c402aaace0678a03fca2c0d265e36a05de69f94af18179a563277d3fb0dbf159` but did not create a scripting slide-show window after a filename-only `.ppsx` change. The probe therefore used a second temporary package whose presentation main content type alone was changed to the PowerPoint slideshow content type in `[Content_Types].xml`; that package passed ZIP integrity and had SHA-256 `c92ef8c00a579c9a8ac35104b98434b26edb4cf5fa5166e6d26d0bbed3b875d4`. With that derived package, the probe observed Automation preflight status 0, two on-screen target Core Graphics windows, and one PowerPoint scripting slide-show window. However, the inherited scripting `window.id` was nil, so zero scripting windows matched an exact Core Graphics window ID and zero valid identity samples were available. The PowerPoint process and bundle remained unchanged, and no Apple Event error occurred.

No slide, keyboard, or mouse input was sent during this probe. It created no schema-4 runtime report and did not validate any transition. Because exact ScreenCaptureKit-window-to-PowerPoint-window binding was unavailable on this Mac and PowerPoint build, no production scripting provider was added. Title, bounds, Accessibility, frontmost-window, and approximate matching were not accepted as fallbacks. The tracked app therefore continues to use the unavailable provider, keeps `slideChangeCount` at zero, and exposes only the tested fail-closed boundary. A production identity adapter, its permission lifecycle, and live slide-transition evidence remain future work.

### Final staged schema-4 verification at 17:57 JST

A complete ordinary-context `make verify` run started at 17:57 JST on 2026-08-30 and completed before 17:59 JST against the staged implementation and documentation. All 14 stages passed:

- Swift format lint for the native app and Core sources and tests
- All 90 Core tests in 13 suites
- All 103 native app tests in 18 suites with local ad hoc signing
- The signing-disabled native arm64 compile-and-link build
- The arm64 ad hoc runtime build, English and Japanese resources, absence of the debug-dylib dependency, and strict bundle-signature verification
- Runtime schema-version parity preflight and launch smoke without requesting Screen Recording permission
- Publication-source fixtures and live source-inclusion checks
- The historical initial-publication fail-closed fixtures
- README language boundaries, release-definition fixtures, and the live release-definition gate
- Absence of tracked build output, common secret patterns, and lecture-data extensions

The resulting runtime executable SHA-256 was `cecd662f24ffb4699ba8e3244d3adf7e621671c7a96d4e54dd0effe1912ab220`; its ad hoc CDHash was `a110ad894dfe90dd818a35c841a541908496b926`. `file` identified a Mach-O 64-bit arm64 executable, and `codesign --verify --deep --strict` passed for the complete bundle. This remains a local development artifact with hardened runtime disabled; it is not Developer ID distribution signed, notarized, beta, release-candidate, or `v1.0.0` evidence.

This final verification-record section was the only repository change after that complete run. After the section was staged, staged-diff integrity, README language boundaries, publication-source inclusion, release-definition fixtures and consistency, tracked-build-output exclusion, common-secret-pattern exclusion, and lecture-data-extension exclusion were repeated and passed. No Swift or shell implementation changed after the complete 14-stage run. The check still reports that manual institutional intellectual-property and privacy review is required.

### Schema-5 fail-closed post-identity frame synchronization at 18:23–18:51 JST

The required baseline was repeated before this implementation. In the restricted execution context, `make doctor` completed with zero failures and one warning because GitHub CLI authentication was not visible, while the first `make local-setup` stopped before tests because Swift and Clang could not write their user cache directories. The unchanged `make local-setup` then passed in the ordinary local macOS context at 18:23 JST: `make doctor` reported zero failures and zero warnings, GitHub CLI authentication as `akiyama709`, the then-current 90 Core tests in 13 suites passed, and XcodeGen regenerated the project. This was an execution-sandbox boundary rather than a source defect.

A read-only public-API audit found no safe implementation path for the production PowerPoint slide-identity provider on the installed PowerPoint 16.112.2 and macOS 26.5 SDK. PowerPoint's scripting dictionary exposes an inherited window unique ID and a slide-show view leading to slide ID and index, but the earlier controlled probe returned `nil` for that inherited window ID. ScreenCaptureKit exposes the selected Core Graphics window ID but no PowerPoint slide semantics, and the public Accessibility SDK exposes no supported bridge from a foreign PowerPoint accessibility window to that exact ID. No title, bounds, order, frontmost-window, private-API, or approximate fallback was added, and the default provider still requests no Automation permission and sends no Apple Event. This audit did not create a runtime report or validate a live slide transition.

Instead, the static-slide liveness boundary was made explicit without weakening freshness. Core now owns a deterministic `PostIdentityBoundaryFrameGate` with `notRequired`, `waiting`, `synchronized`, and `timedOut` states. A confirmed identity boundary starts a two-second wait and returns an opaque boundary token. Timeout changes observable state but keeps analysis and final-transcript board proposals closed; idle repeats, missing or zero display times, and equal or older display times remain rejected. A strictly newer `.new` ScreenCaptureKit frame can recover the gate after timeout. New identity candidates, capture stop, capture error, and restart cancel the wait, and stale timeout completions cannot affect a newer boundary or session. ADR 0008 records why idle acceptance was rejected and why `SCStream` restart and `SCScreenshotManager` remain separate, unverified future designs.

An independent code audit then found a queued-callback race in the speech boundary: a final transcript generated during frame wait could have reached MainActor only after the frame synchronized and passed the earlier state-only check. The app now stores its local mach-absolute acceptance time for the qualifying post-boundary frame and requires the transcript callback timestamp to be strictly later than both the identity boundary and that frame-synchronization boundary. A controlled integration regression produces the transcript during the wait, delivers it after synchronization, and confirms rejection; a transcript produced after synchronization remains accepted. A second regression covers capture error, restart, resumption of the old timeout continuation, and rejection of that stale completion. The existing stop, newer-boundary, timeout, recovery, stale-frame, localization, and snapshot tests cover the remaining state transitions.

Runtime metadata moved to schema 5 by adding only `slideIdentityFrameSyncState`. Schema 1 through schema 4 reports remain decodable; a missing frame-sync field defaults to `notRequired`, while the earlier absent identity fields retain their unavailable and zero defaults. Exact encoded-key tests continue to exclude slide IDs, presentation tokens or paths, images, recognized text, window titles, and coordinates.

The ordinary local checkpoints after implementation passed all 98 Core tests in 14 suites and, after the race regressions, all 110 native app tests in 18 suites. The signing-disabled native arm64 compile-and-link build also succeeded. The first complete `make verify` attempt at 18:44 JST correctly stopped in stage 5 because the launch-smoke script still expected schema 4 while Core produced schema 5. The smoke expectation was changed to 5, and the existing runtime-launch preflight parity regression passed before the complete check was retried. A subsequent full checkpoint passed, but the independent speech-race audit changed the app afterward, so it is not treated as the final source verification.

The final ordinary-context `make verify` run started at 18:50:19 JST on 2026-08-30 and completed before 18:51 JST against the staged schema-5 source. All 14 stages passed:

- Swift format lint for native app and Core sources and tests
- All 98 Core tests in 14 suites
- All 110 native app tests in 18 suites with local ad hoc signing
- The signing-disabled native arm64 compile-and-link build
- The arm64 ad hoc runtime build, English and Japanese resources, absence of the debug-dylib dependency, and strict bundle-signature verification
- Runtime schema-version parity preflight and launch smoke without requesting Screen Recording permission
- Publication-source fixtures and live source-inclusion checks
- The historical initial-publication fail-closed fixtures
- README language boundaries, release-definition fixtures, and the live release-definition gate
- Absence of tracked build output, common secret patterns, and lecture-data extensions

The final runtime executable SHA-256 was `a0837c2908aeb1b502a5e70aff592279b4bc37a6fd4e3c2a35c3c0f45a82ffde`; its ad hoc CDHash was `50e9dea84eee50f98b8fc286823d188d7a52bda5`. `file` identified a Mach-O 64-bit arm64 executable, and `codesign --verify --deep --strict` passed for the complete bundle. This remains a local development artifact with hardened runtime disabled. It is not Developer ID distribution signed, notarized, beta, release-candidate, or `v1.0.0` evidence.

No live PowerPoint slide, keyboard, mouse, microphone, or pen-tablet input was sent during this schema-5 work. No schema-5 live PowerPoint capture report or retained runtime report was created. The launch smoke created only a temporary metadata-only safe-failure report with zero snapshots and removed it after validation. The frame gate, timeout, stale-callback rejection, and schema serialization are verified by deterministic tests and native compilation, not by a production identity provider or live PowerPoint transition. No branch was pushed, no pull request or tag was created, and no GitHub Release was published.

This schema-5 verification-record section was the only repository change after the complete 14-stage run. After it was staged, staged-diff integrity, publication-source fixtures and live inclusion, README language boundaries, historical initial-publication guard fixtures, release-definition fixtures and consistency, tracked-build-output exclusion, common-secret-pattern exclusion, and lecture-data-extension exclusion were repeated and passed. No Swift or shell implementation changed after the complete run.

### Schema-6 fail-closed user-confirmed slide-canvas boundary and final staged verification at 20:32–20:33 JST

The four required starting documents and the `make doctor` and `make local-setup` baseline had already been completed earlier in this same local development task. They were not rerun for the schema-6 increment, so this section does not claim a second baseline run. The unchanged repository continued from commit `464eb391efa0aeef7d9585d98c053b08f44ed4b2` on branch `codex/runtime-verification`.

A public-API audit did not find a supported exact rectangle for PowerPoint's internal rendered slide canvas that could be bound safely to the exact ScreenCaptureKit window. ScreenCaptureKit's `contentRect` describes placement in its capture surface rather than PowerPoint's internal slide subview. No title-, order-, approximate-geometry-, aspect-ratio-, Accessibility-, private-API-, or image-heuristic fallback was added. The app instead freezes a preview delivered by the exact accepted capture operation and requires the user to drag and confirm the visible slide region. This is an audit conclusion and deterministic implementation boundary, not live evidence that a user can localize every PowerPoint canvas accurately.

Core now owns a finite, nonempty, top-left normalized `SlideCanvasRegion` and deterministic outward pixel mapping. The native selection policy additionally requires at least 32 by 24 source pixels and 1,024 square pixels. A confirmation is bound to one capture operation, exact ScreenCaptureKit window ID, source pixel dimensions, and validated surface geometry (`contentRect`, `scaleFactor`, `contentScale`, and output dimensions). Capture restart, target mismatch, missing geometry, source-size change, or any bound-geometry change invalidates the confirmation and clears canvas-dependent analysis and board state. The default production path performs only capture-delivery accounting before confirmation. After confirmation, a typed `CapturedSlideCanvasFrame` is the only image type accepted by the stable-frame, dense-content, Vision, and raster paths, and its fingerprints are recomputed from the crop. The whole-frame shortcut is explicitly test-only.

Runtime metadata moved to schema 6 by adding only `slideCanvasState`. It does not retain the selected rectangle, surface coordinates, captured image, recognized text, slide ID, presentation token or path, or window title. Schema 1 through schema 5 remain decodable with safe defaults for absent canvas, frame-sync, and identity metadata. Exact encoded-key tests cover this content-exclusion boundary.

Independent safety reviews found the following issues during implementation. Each was corrected before the final staged verification and received a focused regression:

1. An idle delivery could have combined a reused visual payload with geometry inherited from an older sample. Idle handling now reparses the current sample attachments and marks the repeated payload geometry-valid only when current geometry exactly equals the last visual-payload geometry. Changed, missing, or invalid current geometry, or missing prior geometry, leaves the repeat without geometry; only delivery metrics advance, and the app invalidates the canvas before visual processing. An idle sample without an image buffer inherits only the fixed stream surface dimensions. Matching, changed, missing-current, and missing-prior geometry tests cover this behavior. Actual ScreenCaptureKit idle-attachment behavior remains live-unverified.
2. Missing, malformed, Boolean, and unknown `SCFrameStatus` values could have entered the new-frame path. The resolver now accepts only `.complete` and `.started` as new, `.idle` as repeat, and drops `.blank`, `.suspended`, `.stopped`, missing, malformed, Boolean, and unknown values. Direct status-resolution regressions cover all accepted and rejected classes.
3. A finite positive `scaleFactor` above the SDK-documented upper bound could have been accepted. Surface geometry now accepts only the inclusive range 1 through 4, with direct lower-bound, upper-bound, below-bound, above-bound, nonfinite, and malformed tests.
4. A queued Apple Speech callback or stopped recognition task could have crossed a slide, canvas, capture, or transcription-restart boundary despite the app-side time check. The app and Apple provider now use independent operation generations. Each semantic boundary stops transcription, clears the live segment, rejects every superseded callback and segment, and requires an explicit user restart. Regressions cover delayed callbacks, stopped-task delivery into a restarted operation, capture lifecycle changes, and every manual canvas boundary. These are controlled-provider tests; live microphone behavior remains unverified.
5. Previously ready occupancy and an in-flight Vision result could have remained eligible while a coarse visual transition, dense-content candidate, or missing or invalid dense fingerprint made the current image uncertain. Those states now increment the analysis generation, cancel or reject old work, clear ready analysis immediately, and keep transcript-driven board proposals closed until the current frame has been reanalyzed. Regressions cover coarse candidates returning to the old baseline, dense candidates and confirmed changes, missing and invalid dense fingerprints, replacement cancellation, and stale completion after stop.
6. Board-candidate evidence could have survived a semantic slide, canvas, or capture boundary, and an empty occupied-region result could have allowed placement without current visual grounding. `BoardCandidateContext` now resets at every such boundary; proposals additionally require a confirmed canvas, current `.ready` analysis, and nonempty occupied regions. Integration tests cover transcript non-replay after reselection and restart, confirmed slide transitions, and empty-occupancy rejection.
7. The bundled demo scene could have remained visible when capture started and could therefore be confused with capture-grounded output. Capture start now clears demo content, and demo generation is unavailable during active capture. The capture-start integration test verifies both cleanup and suppression.
8. A final review found that capture status could already be `.stopped` while asynchronous capture-provider shutdown was still in flight, briefly re-enabling the demo. An in-flight stop counter now keeps demo generation disabled until both capture providers finish stopping. A controlled continuation regression verifies that the demo remains blocked during the wait and becomes available only after shutdown completes.

The review-driven source changes were exercised incrementally. Development-only failures were also resolved rather than hidden: the first new safety-test compile lacked its `LectureBoardCore` import; the first capture-worker compile lacked an explicit `return`; one dense-fingerprint regression initially used the wrong capture sequence after a continuation resumed; and one fixture asserted scene-element count where the intended contract was analysis freshness. The import, return, sequence, and assertion were corrected, and the complete native suite then passed. Restricted-shell attempts that could not write Swift or Clang user caches were repeated unchanged in the ordinary Mac context and passed; these were execution-sandbox failures rather than product failures.

Before the final complete gate, all 107 Core tests in 15 suites and all 156 native app tests in 21 suites passed, and independent read-only audits reported no remaining P0, P1, or P2 finding in the changed safety boundaries. The final native result bundle is `DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.08.30_20-32-40-+0900.xcresult`; `xcresulttool` reports `Passed`, 156 total tests, zero failed, zero skipped, and zero expected failures. Its first restricted read failed only because `xcresulttool` could not write its own temporary `TestReport` directory; the unchanged read succeeded in the ordinary context.

The final ordinary-context `make verify` run started at 20:32 JST on 2026-08-30 and completed at 20:33 JST against the staged schema-6 source. All 14 stages passed:

- Recursive Swift format lint for native app and Core sources and tests
- All 107 Core tests in 15 suites
- All 156 native app tests in 21 suites with local ad hoc signing
- The signing-disabled native arm64 compile-and-link build
- The arm64 ad hoc runtime build, English and Japanese resources, absence of the debug-dylib dependency, and strict complete-bundle signature verification
- Runtime schema-version parity preflight and launch smoke without requesting Screen Recording permission
- Publication-source fixtures and live source-inclusion checks
- Historical initial-publication fail-closed fixtures
- README language boundaries, release-definition fixtures, and the live release-definition gate
- Absence of tracked build output, common secret patterns, and lecture-data extensions

The resulting runtime executable SHA-256 was `e65392452e67d79fc3eb056bc56e1a68fd2a988c6e7eefff67e1ef98eb3b13f0`; its ad hoc CDHash was `1c1837109851e6033bc7a3efe9f92c668da27a35`. `file` identified a Mach-O 64-bit arm64 executable, and `codesign --verify --deep --strict` passed for the complete bundle. This remains a local development artifact with hardened runtime disabled. It is not Developer ID distribution signed, notarized, beta, release-candidate, or `v1.0.0` evidence.

No live PowerPoint slide, keyboard, mouse, microphone, pen-tablet, or user canvas-selection input was sent during this schema-6 increment. No live schema-6 report was retained. The launch smoke created only a temporary metadata-only safe-failure report with zero snapshots, removed it after checking, and did not request Screen Recording. The synthetic crop, geometry, status, analysis-freshness, speech-generation, board-grounding, and demo-isolation regressions do not establish live PowerPoint canvas accuracy, PowerPoint-control exclusion, live resize behavior, ScreenCaptureKit idle-attachment behavior, microphone recognition, overlay alignment, or lecture reliability. No branch was pushed, no pull request or tag was created, and no GitHub Release was published.

The complete verification run regenerated the checked-in Xcode project and added the already tested `AppSlideCanvasIntegrationTests.swift` source entry that had been absent from the earlier generated-project snapshot. The isolated app-test project had already included and run that test file, and the subsequent native build used the regenerated project. After the final generated project, this verification record, and the handoff wording were staged, recursive Swift format lint, staged-diff integrity, publication-source fixtures and live inclusion, README language boundaries, historical initial-publication guard fixtures, release-definition fixtures and consistency, tracked-build-output exclusion, common-secret-pattern exclusion, and lecture-data-extension exclusion were repeated and passed. No Swift or shell implementation changed after the complete 14-stage run.

### Fail-closed production-overlay coordinate and eligibility boundary at 01:28–01:30 JST on 2026-08-31

The four required starting documents were read in full before this increment. The required baseline was then repeated. In the restricted execution context, `make doctor` completed with zero failures and one warning because GitHub CLI authentication was not visible. The restricted `make local-setup` stopped before source tests because Swift and Clang could not write their user cache directories. The unchanged commands succeeded in the ordinary local macOS context: `make doctor` reported zero failures and zero warnings with GitHub CLI authenticated as `akiyama709`; `make local-setup` passed all 107 Core tests in 15 suites and regenerated the Xcode project. The cache and authentication differences were execution-context boundaries, not source fixes.

This increment implemented a deterministic bridge from a user-confirmed output-pixel canvas to a production AppKit panel rectangle. Each accepted capture delivery parses only its own ScreenCaptureKit `screenRect`, accepting a direct `CGRect`, exact rectangle `NSValue`, or dictionary representation. It permits finite negative global origins but rejects raw non-positive dimensions before `CGRect` can normalize them. Idle delivery can reuse an image payload only under the existing exact surface-geometry rule; it never inherits an older screen position. The pure mapper requires the active capture operation, exact window ID, exact surface geometry, output dimensions, current frame sequence, and production ScreenCaptureKit provenance. It checks surface padding and `contentRect`, `scaleFactor`, and `contentScale` consistency within one output pixel, requires the confirmed canvas to remain inside captured content, maps it through the current global `screenRect`, requires exactly one containing display, and converts that display from Quartz top-left coordinates to AppKit bottom-left coordinates. Missing, stale, contradictory, cross-display, or multiply contained evidence returns no placement. The full-display path remains demo-only and is not a production fallback.

Independent reviews found several fail-open paths after the initial mapper passed its focused tests. Each was corrected and given a regression before the final run:

1. A manually hidden panel could have returned on the next frame. Manual suppression is now latched until an explicit new capture or demo request; the integration test verifies that later production deliveries do not undo it.
2. Eligibility was initially rechecked only when capture delivered a sample. A production display now receives a short, independently scheduled lease that only an eligible current capture delivery can renew. Expiry, application activation or deactivation, active-Space change, manual hide, capture end, semantic quarantine, content unavailability, or visual uncertainty hides the panel. Injectable lease and safety-event fakes verify expiry without wall-clock flakiness and require a new eligible frame for recovery.
3. A panel could have appeared over another application, a PowerPoint dialog, or the wrong exact window. The current policy requires the frozen PowerPoint PID and exact bundle to be frontmost, exactly one matching on-screen layer-zero Core Graphics window with the frozen owner, agreement between every window edge and the current `screenRect` within two points, and no earlier on-screen window at any layer with a positive-area intersection. The app's own process is excluded so the panel does not reject itself. Ordered window-list fixtures cover wrong frontmost state, bundle, PID, owner, layer, onscreen state, duplicates, missing or malformed evidence, tolerance edges, same- and other-process occluders, optional onscreen metadata, and self exclusion.
4. The safe default identity provider reports unavailable, yet the first production-render integration could still display. Production rendering now requires confirmed `.identified` semantic state and the synchronized post-boundary frame. Board proposal generation remains available for prototype inspection, but the default unavailable provider cannot authorize production display. Identity integration tests cover confirmed baseline, candidate quarantine, abandoned candidate, transition, and default-unavailable behavior.
5. An old board scene could have remained visible while a same-slide visual change, including mouse-ink-like input, was still being classified. Visual candidates now clear the production scene, candidate context, and lease immediately and bind any later scene to the completed current analysis generation. Final speech results generated before that local visual-freshness mach-time boundary are rejected even if their MainActor callback arrives after reanalysis. The speech provider itself is not stopped for every visual candidate; existing semantic slide, canvas, and capture boundaries retain their explicit stop behavior. Synthetic image-change tests verify immediate hiding, stale-callback rejection, no unintended provider stop, fresh analysis, a new current-frame lease, and recovery only from new evidence.
6. Recoverable capture failures could leave the last payload eligible for a later idle repeat. New frames and content-unavailable events now share one monotonic sequence. Missing, malformed, unknown, `.blank`, and `.suspended` status, invalid sample buffers, missing image buffers on new-frame deliveries, fingerprint failure, and image-conversion failure clear repeat continuity and notify the app. An idle delivery without its own image buffer can reuse the immediately preceding payload only under the separately tested exact surface-geometry rule. The app closes transcription and all visual, analysis, board, placement, and lease state until a later ordered `.new` delivery. An idle sample cannot revive a payload across that gap. `.stopped` is a terminal fixed-message capture error and follows complete capture cleanup. Resolver, continuity, ordering, stale-session, terminal-error, and recovery regressions cover these branches.
7. Identical capture deliveries could repeatedly update the physical panel despite an unchanged scene and target. Render state is now deduplicated while eligibility and lease renewal are still evaluated for every accepted current delivery. A focused integration test checks both counts independently.

Development-only failures were not hidden. The initial rectangle parser used an unnecessary conditional cast that Swift 6 rejected; dictionary handling was changed to an explicit Foundation/Core Foundation bridge. Ambiguous unqualified `nan` and `infinity` fixtures were made explicit. A negative-size test exposed `CGRect` normalization and led to raw-size validation. Early demo, transcript, and mapper fixtures used an overstrict hide count, a transcript that did not exercise the board engine, or exact floating-point rectangle equality; each fixture was corrected to test the intended contract. The first safety-provider build found a Swift 6 nonisolated-deinitializer access to a non-Sendable observer array; observer shutdown was moved to the explicit MainActor-owned lifecycle. The first 58-test safety run had two fixture failures because its supposed visual change was pixel-identical and its unavailable-content recovery omitted the new current frame required for a lease. The first full native run then found three existing content-change assertions broken by requiring identity for proposal generation; the requirement was narrowed to physical production display. Two identity-candidate expectations additionally established that candidate state hides output without prematurely destroying recoverable internal scene data. Failed Xcode sessions waited while retrying or finalizing after these assertions; they were interrupted only after failure output was captured. The corrected focused suites passed before the clean complete run.

The final ordinary-context `make verify` run started at 01:28:58 JST on 2026-08-31 and completed before 01:30 JST against the staged source. All 14 stages passed:

- Recursive Swift format lint for native app and Core sources and tests
- All 107 Core tests in 15 suites
- All 192 native app tests in 23 suites with local ad hoc signing
- The signing-disabled native arm64 compile-and-link build
- The arm64 ad hoc runtime build, English and Japanese resources, absence of the debug-dylib dependency, and strict complete-bundle signature verification
- Runtime schema-version parity preflight and launch smoke without requesting Screen Recording permission
- Publication-source fixtures and live source-inclusion checks
- Historical initial-publication fail-closed fixtures
- README language boundaries, release-definition fixtures, and the live release-definition gate
- Absence of tracked build output, common secret patterns, and lecture-data extensions

The final native result bundle is `DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.08.31_01-28-58-+0900.xcresult`. `xcresulttool` reports `Passed`, 192 total tests, zero failed, zero skipped, and zero expected failures. Its per-device counter is 194 because two parameterized tests produced four runs; the result bundle's authoritative total test count remains 192. The runtime executable SHA-256 is `dddfbd787c995194c8c6d667ee44ad239e0bfc696f594396eb7e686a7b3fc092`; its ad hoc CDHash is `4a358039e3eb531abfe6dbfb2ea64f6d99611450`. `file` identifies a Mach-O 64-bit arm64 executable, and `codesign --verify --deep --strict` passes for the complete bundle. Team identifier is not set and hardened runtime is disabled. This is a local development artifact, not Developer ID distribution signing, notarization, beta, release-candidate, or `v1.0.0` evidence. Runtime report schema remains 6; the overlay boundary did not add persisted content or metadata.

A separate read-only display snapshot did not exercise the overlay. `NSScreen.screens` exposed display IDs 1 and 3, both with Quartz and AppKit frames `(0, 0, 2560, 1440)`, 2560-by-1440 pixels, and scale 1.0. `CGGetOnlineDisplayList` also returned two online IDs with the same bounds, while both reported inactive and neither reported the other as its mirror. This duplicated containment is intentionally ambiguous to the mapper and is not a successful single- or multi-display alignment result. No display setting was changed, and no inference was made about a usable mirror topology.

No PowerPoint window was launched or controlled during this increment. No screen-recording permission was requested, and no PowerPoint slide, keyboard, mouse, microphone, or pen-tablet input was sent. No live schema-6 capture or overlay report was created. The coordinate, frontmost, window-list, occlusion, lease, visual-grounding, and continuity results are deterministic synthetic and native-integration evidence only. They do not establish live PowerPoint `screenRect` orientation, actual bounds agreement, window-list z-order, manual canvas accuracy, visible overlay alignment, movement or resize, full-screen or presenter mode, multiple-display behavior, click-through input, mouse or pen priority, OCR, or lecture reliability. The safe default identity provider still cannot authorize production overlay display.

The Vault-root development note was preserved without overwriting the current note and moved into the designated `007GitHub/LectureBoard AI` Obsidian directory as `260829：LectureBoard AI 開発ノート（Vault直下旧版）.md`; its SHA-256 remained `9c219223d692063d1cb46db01aff181b033a7f6c3ff3ad9f7b3e4dbc267e9ec6`, and no LectureBoard file remains at the Vault root. No branch was pushed, no pull request or tag was created, and no GitHub Release was published.

### Schema-8 metadata provenance and exact-window static diagnostic on 2026-08-31

The four required starting documents were read in full before this increment. The required baseline was repeated. In the restricted execution context, `make doctor` completed with zero failures and one warning because GitHub CLI authentication was not visible, and `make local-setup` stopped before source tests because Swift and Clang could not write their user cache directories. The unchanged commands succeeded in the ordinary local macOS context: `make doctor` reported zero failures and zero warnings with GitHub CLI authenticated as `akiyama709`, and `make local-setup` passed the then-current 107 Core tests in 15 suites and regenerated the Xcode project. These restricted-context results were sandbox boundaries rather than product failures.

The runtime report schema is now 8. It records a metadata-only slide-canvas overlay mapping outcome, including a bounded rejection reason when mapping fails, without retaining coordinates, display identifiers, recognized text, slide content, images, or window titles. It also records report-level slide-canvas confirmation provenance. The explicit `--confirm-full-frame-canvas` runtime-verification flag is classified as `diagnosticFullFrame`; it exercises the normal selection and confirmation boundary against the entire currently delivered frame, but it is not represented as a user confirmation. Duplicate requests are rejected, and the flag has no effect when runtime verification is not active. Schema 1 through schema 7 reports remain decodable; legacy reports keep absent confirmation provenance explicitly absent, and absent snapshot overlay state decodes as `unavailable`.

The first complete `make verify` attempt did not pass. Its lint stage reported 14 Swift-format warnings, and the run later stopped at `[7/14]` because the publication-source check correctly detected three required new files that were not yet tracked. Four affected test files were formatted, after which the lint reported zero warnings, and the three new files were added to the Git index. These findings were corrected rather than suppressed.

The unchanged verification gate was then rerun in the ordinary local macOS context and all 14 stages passed:

- Recursive Swift-format lint with zero warnings
- All 115 Core tests in 15 suites
- All 203 native app tests in 25 suites with local ad hoc signing
- The signing-disabled native arm64 compile-and-link build
- The arm64 ad hoc runtime build, bundle checks, strict signature verification, and runtime launch smoke without requesting Screen Recording permission
- Publication-source checker fixtures and the live tracked-source check
- README language boundaries
- Historical initial-publication fail-closed guard fixtures
- `v1.0.0` completion-definition fixtures and the live release-definition gate
- Absence of tracked build output, common secret patterns, and lecture-data extensions

Independent review then found stale schema and test-count wording in the public README and architecture document, plus newly added Mac-specific absolute paths in tracked verification documentation. Those descriptions were corrected without changing the implementation or the retained external artifacts. The complete `make verify` gate was run again after those documentation corrections, and all 14 stages passed a second time.

The final native result bundle is `DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.08.31_08-41-45-+0900.xcresult`. `xcresulttool` reports `Passed`, 203 total tests, zero failed, zero skipped, and zero expected failures. Its per-device passed counter is 205 because two parameterized tests produced four runs; the result bundle's authoritative total test count remains 203. The final verification runtime executable remained byte-identical to the `LectureBoard AI` executable inside `LectureBoard AI Schema 8 Verification.app` in the external verification directory, with SHA-256 `316ee7aada2359155097eaa726a86c911bdfc1b3d9e3a34e32bb5d2f87c83260` and ad hoc CDHash `e989a694c94daac85db9b4cd31de5179965da384`. The artifact is not Developer ID distribution signed or notarized and is not beta, release-candidate, or `v1.0.0` evidence. The automated gate also explicitly leaves manual institutional intellectual-property and privacy review outstanding; passing `make verify` is not publication approval or project completion.

A controlled 15-second static diagnostic then selected exactly one on-screen PowerPoint window by ScreenCaptureKit window ID `13577` and exact bundle identifier `com.microsoft.Powerpoint`. The retained schema-8 report is `LectureBoard-Runtime-Schema8-ExactWindow-Static-2026-08-31.json` in the external verification directory, with SHA-256 `593cc70cd666498c8d68cd9f3b8156b617c45d066cc955992106c5c1e18a8b84`. It records `authorized` Screen Recording preflight both before and after the run, `permissionWasRequested: false`, one matched window, `slideCanvasConfirmationMode: diagnosticFullFrame`, 59 snapshots, and a completed run. The final snapshot records 152 delivered frames, all classified as new and none as repeats, one stable frame, zero content revisions, and zero slide changes. Vision reached `completed` and recorded counts of 39 recognized-text observations, 14 rectangle observations, 69 stroke-candidate regions, and 3 occupied regions. These are pipeline and count observations only; no recognition text or coordinate accuracy was audited.

The same report records the diagnostic full-frame canvas as `confirmed` and the coordinate mapper as `mapped`. This establishes that the implemented metadata-bound mapping path accepted this exact static capture's current geometry. It does not establish that a person localized the visible PowerPoint slide canvas, that the full captured window is an accurate slide-canvas crop, or that an overlay was visibly aligned. Slide identity remained `unavailable`; consequently this run does not establish semantic transition tracking or production-overlay rendering eligibility. No dynamic slide change, animation, mouse ink, keyboard input, microphone input, pen-tablet input, click-through interaction, or lecture-length behavior was exercised.

A byte-identical frozen copy of the tested final build was saved as `LectureBoard AI Schema 8 Verification.app` in the external verification directory, without overwriting the historical verification apps. Its executable SHA-256 is `316ee7aada2359155097eaa726a86c911bdfc1b3d9e3a34e32bb5d2f87c83260`, its ad hoc CDHash is `e989a694c94daac85db9b4cd31de5179965da384`, its bundle identifier is `io.github.akiyama709.LectureBoardAI`, and `file` identifies a thin Mach-O arm64 executable. A byte comparison with the final build executable found no difference, and `codesign --verify --deep --strict` passed. It remains a local ad hoc development artifact.

The executable inside that fixed external app path was then invoked directly for a separate five-second run against exact PowerPoint window ID `13577`, with diagnostic full-frame confirmation and without requesting Screen Recording permission. The first attempt supplied the sibling Documents verification directory as its report destination, but no report file was produced there. Capture and clean-termination OS log entries from that attempt are not substituted for report evidence, so it is not counted as a successful runtime verification. Direct report creation from the frozen app into that sibling Documents directory remains unverified.

The same frozen executable was rerun with its output at a unique path in the system temporary directory and completed successfully. After validation, the report was copied with a byte-identical comparison to `LectureBoard-Runtime-Schema8-FrozenApp-Static-2026-08-31.json` in the external verification directory; its SHA-256 is `1758fda4429cc5ba3b1ed46c14069c8b104fb0d425103907362cd8e49d41f1c5`. It records schema 8, `authorized` preflight before and after, `permissionWasRequested: false`, one exact match for window ID `13577` and bundle `com.microsoft.Powerpoint`, `diagnosticFullFrame` confirmation provenance, 21 snapshots, and a completed run. Its final snapshot records 53 delivered new frames, zero repeats, one stable frame, zero content revisions, zero slide changes, completed Vision processing, 44 recognized-text observations, 14 rectangle observations, 106 stroke-candidate regions, and 3 occupied regions. Canvas state is `confirmed`, overlay mapping state is `mapped`, and slide identity remains `unavailable`.

This second report verifies direct execution, Screen Recording preflight, exact-window capture, diagnostic full-frame processing, and metadata-bound mapping from the frozen app's saved executable path. The same limits as the 15-second DerivedData run apply: the counts do not establish OCR or coordinate accuracy; diagnostic full-frame confirmation is not user canvas selection; `mapped` does not establish visible overlay alignment or rendering; and unavailable identity does not authorize production display. The currently verified report-handling procedure is to write to a unique path in the system temporary directory, validate there, and copy the validated bytes to the external verification directory.

The exact-input helper was subsequently hardened further. Its final source SHA-256 is `823d96053b81fe539489a5edc1214494184df94d19cb29c28130316df67ffd01`, and the compiled binary SHA-256 is `a08dc9fe2043d9b9e184e50061b220f4b50406f1d1082e6d0dc94a5f8c3aadea`. Its GUI-free self-test reports 72 hardening outcomes, 60 exact-window-menu outcomes, and 34 slideshow-policy outcomes. Strict lint, Swift 6 strict-concurrency type checking with warnings as errors, a fresh compile, and independent review all passed. Live exact window-menu selection, separate exact focus and re-verification, and a separate slideshow probe then succeeded without a title-, order-, or approximate-geometry fallback.

A no-permission-request LaunchServices invocation of the fixed schema-8 app produced `LectureBoard-Runtime-Schema8-LaunchServices-Preflight-2026-08-31.json` in the external verification directory, SHA-256 `ad18b286fa5b4e14f3c15aa92a4672665a65edf3c54102c495383e161bec67f4`. It verified LaunchServices start, argument delivery, fail-closed metadata-report production, and automatic exit. The report records schema 8, `permissionWasRequested: false`, `noneRequested`, zero matched windows, no snapshots, and failure `screenRecordingUnavailable`. It did not reach target selection or capture. This is not evidence of LaunchServices Screen Recording authorization, frame delivery, canvas confirmation, overlay mapping, dynamic input, or ink.

After the strict helper gates passed, a controlled schema-8 slideshow attempt produced `LectureBoard-Runtime-Schema8-Slideshow-Canvas-Invalidated-2026-08-31.json` in the external verification directory, SHA-256 `93c5fd28598bf9d11b3cbb086a2fe05e413e834ea920106bcb2ea274da026956`. Screen Recording preflight was authorized without a request, one exact PowerPoint target was selected, and the run received one new frame and two repeats. It failed closed with `slideCanvasConfirmationFailed` after approximately 535 milliseconds because the diagnostic full-frame canvas became invalidated. No scheduled slide advance or mouse input was sent. The report records no stable frame, content revision, slide change, or successful dynamic result. Schema 8 did not retain a bounded invalidation reason, so this report alone cannot distinguish the invalidation path.

### Schema-9 bounded canvas-invalidation diagnostics on 2026-08-31

Runtime metadata is now schema 9. It adds optional root `slideCanvasFailureReason` and snapshot `slideCanvasInvalidationReason` values. The values are bounded classifications only and retain no image, recognized text, coordinates, display identifier, or window title. The existing generic canvas failure code and message remain unchanged. Schema 1 through schema 8 reports remain decodable; missing schema-9 fields decode as `nil`. A schema-9 canvas-failure report missing its root reason is normalized fail closed to `unclassifiedInvalidation`.

Regression coverage was added for a valid new delivery followed by an idle repeat with unavailable geometry through both the App boundary and runner report, selection and payload rejection classification, a terminal snapshot written before observation-end canvas failure, and fail-closed decoding of a schema-9 canvas failure with a missing root reason. Independent review found no P0–P2 defect and identified one P3 test gap for runner-side fallback reasons. Two additional end-to-end report tests now cover a policy-rejected 16-by-16 frame producing `selectionConfirmationRejected` and capture end after confirmation producing `confirmationLostDuringObservation`, including the fixed generic failure message and terminal snapshot state. The Core run passed 119 tests in 15 suites. The first targeted native run passed 46 tests in 4 suites; the focused runner suite then passed 7 tests in 1 suite. The final complete native run passed 209 tests in 25 suites; its result bundle is `DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.08.31_15-20-19-+0900.xcresult`. The runtime-launch script, `bash -n`, Swift-format lint, and `git diff --check` also passed. These automated results do not create a schema-9 artifact or live runtime evidence.

The fixed `LectureBoard AI Schema 8 Verification.app` remains historical evidence and must not be rebuilt, replaced, or moved. The next checkpoint is to save and verify a separately named schema-9 artifact, then use the same strict helper to obtain the bounded reason for the live canvas invalidation. Any behavioral correction must be test-first and fully verified before another controlled dynamic or mouse-ink attempt.

### Schema-9 provisional idle-surface continuity policy and frozen artifact on 2026-08-31

A separately frozen pre-correction schema-9 build was first exercised with the same exact PowerPoint and slideshow helper. The retained report is `LectureBoard-Runtime-Schema9-Slideshow-IdleGeometry-Invalidated-2026-08-31.json` in the external verification directory, with SHA-256 `edc97ebb2588771318676d1c0ffcf4c55f4f02e1cdb556649eededd8f1f372f8`. It records authorized Screen Recording preflight before and after the run, `permissionWasRequested: false`, one exact PowerPoint match, schema 9, one snapshot, one new frame, two idle repeats, a diagnostic-full-frame canvas that became invalidated, and both root and snapshot reason `idleRepeatSurfaceGeometryUnavailableOrMismatched`. The runtime exited after approximately 469 milliseconds, before the helper's first scheduled input. No slide advance, keyboard, mouse, ink, microphone, or pen-tablet input was sent. This bounded result identifies the idle-repeat failure class; it does not distinguish all-three surface attachments being absent from a malformed, partial, or conflicting tuple.

The active SDK and Apple's public ScreenCaptureKit documentation define `.idle` as a delivery for which the display did not change and no new frame was generated. They do not specify that `contentRect`, `scaleFactor`, `contentScale`, or `screenRect` must be present on an idle sample, nor that absent attachments are semantically inherited. The following correction is therefore a narrow provisional application policy rather than an Apple-platform guarantee. Only a sample that is independently classified exactly as `.idle`, has all three surface keys absent, follows an immediately latched payload with valid surface geometry, and has output dimensions equal to the reused image may reuse that prior surface geometry for cropping the unchanged visual payload. A complete current tuple is accepted only when it is valid and exactly equal to the prior tuple. A partial, malformed, conflicting, non-idle, missing-prior, or output-size-mismatched delivery clears surface geometry and latches that fail-closed result until a later valid new frame. In the all-three-absent branch, `screenRect` is neither inherited nor accepted from the idle sample, so production overlay mapping closes even though the confirmed canvas and unchanged board scene may remain available.

The implementation was strengthened after independent review so repeat construction and continuity latching use one atomic production seam. The test-first red run failed to compile only because that new seam did not yet exist. After implementation, 57 targeted tests in 2 suites passed. The complete native app run then passed 217 tests in 25 suites; `xcresulttool` reports 217 authoritative tests, zero failed, zero skipped, and zero expected failures, while the per-device counter is 219 because two parameterized tests produced four runs. Its result bundle is `DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.08.31_16-06-27-+0900.xcresult`. Table-driven coverage includes all six nonempty proper subsets of the three surface keys, malformed and null values for each key, conflict in each field, malformed and non-idle status, width-only and height-only output mismatch, invalid-repeat poisoning, recovery only on a valid new frame, and the app transition from mapped and visible overlay state to immediate hidden state on a metadata-empty verified idle repeat. Swift-format strict lint and `git diff --check` also passed. These tests verify the application policy and fail-closed transitions, not Apple's live attachment behavior.

The current policy build was saved without replacing any prior artifact as `LectureBoard AI Schema 9 Idle Policy Verification.app` in the external verification directory. Its executable is a thin arm64 Mach-O with SHA-256 `a0a7a57de80509fd9904332f0d1aa97262957db65ce3794acf00653155c4e5b6`, ad hoc CDHash `a37601577a00e36c5365e4a3d1f5248913baad5b`, and bundle identifier `io.github.akiyama709.LectureBoardAI`. The saved app and build output compare byte-for-byte, the complete app directories have no content difference, and `codesign --verify --deep --strict` passes. This is a local development artifact without Developer ID distribution signing, hardened runtime, or notarization.

That fixed executable was invoked directly from its saved path with an impossible unique window-title substring, a one-second requested observation, and no permission-request or canvas-confirmation flag. It exited automatically and produced a metadata-only schema-9 report through the verified temporary-path-then-copy workflow. The retained `LectureBoard-Runtime-Schema9-IdlePolicy-FrozenApp-Preflight-2026-08-31.json` has SHA-256 `2d1043a8ba0bf5c3a2a3a0559c87a3e0c9d60380457b2431f8f7934e62402255` and is byte-identical to its validated temporary source. It records authorized Screen Recording preflight before and after, `permissionWasRequested: false`, `slideCanvasConfirmationMode: noneRequested`, zero matched windows, zero snapshots, and the expected `windowNotFound` failure. No process remained afterward. This verifies fixed-path execution, preflight, safe target rejection, report creation, and automatic exit only; it is not capture or idle-delivery evidence.

A post-correction live dynamic retry was not started. The strict helper's passive and focus-and-verify checks both stopped before input because a required Accessibility window attribute was unavailable. A temporary screen capture showed only the desktop background, and a read-only console-session query then reported `CGSSessionScreenIsLocked: Yes`. No attempt was made to cross the password boundary, and no PowerPoint input was sent. Consequently, live all-surface-keys-absent continuity, post-correction idle recovery, dynamic slide transitions, and mouse ink remain unverified until the user session is unlocked and the full exact-window boundary can be re-established. The historical fixed schema-8 executable remains unchanged at SHA-256 `316ee7aada2359155097eaa726a86c911bdfc1b3d9e3a34e32bb5d2f87c83260` and still passes strict bundle-signature verification.

The complete `make verify` gate was then run against the current implementation, tests, and documentation at 16:17 JST. All 14 stages passed: Swift-format lint, all 119 Core tests in 15 suites, all 217 native app tests in 25 suites, the signing-disabled native build, the arm64 ad hoc runtime build and strict signature verification, the no-permission-request runtime launch smoke, publication-source fixtures and live inclusion, README language boundaries, historical publication and release-definition fixtures and gates, tracked-build-output exclusion, common-secret-pattern exclusion, and lecture-data-extension exclusion. The final native result bundle is `DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.08.31_16-17-38-+0900.xcresult`; `xcresulttool` reports `Passed`, 217 total, zero failed, zero skipped, and zero expected failures, with the 219 per-device counter explained by four runs from two parameterized tests. The final verification runtime executable remained byte-identical to the separately frozen idle-policy app, with SHA-256 `a0a7a57de80509fd9904332f0d1aa97262957db65ce3794acf00653155c4e5b6` and ad hoc CDHash `a37601577a00e36c5365e4a3d1f5248913baad5b`. The gate still requires manual institutional intellectual-property and privacy review and does not establish distribution signing, notarization, live dynamic behavior, or project completion.

Only current-state documentation and this verification record changed after that complete gate. The publication-source live check, README language-boundary check, historical publication fail-closed fixtures, release-definition fixtures and live gate, and `git diff --check` were repeated afterward and passed. No Swift or shell implementation changed after the complete 14-stage run.

Two earlier schema-7 reports in the external verification directory are retained only as historical negative evidence from pre-provenance builds. The direct 15-second report `LectureBoard-Runtime-Schema7-Locked-NoFrame-2026-08-31.json`, SHA-256 `9fad1147a5f329ee3439cd2a75744b23a280a045fb22b987863e4504e74aed43`, matched exact window ID `13577` and recorded an authorized snapshot without requesting permission, but received zero frames and failed with `captureFrameUnavailable`; its canvas remained `waitingForFrame`, overlay state `unavailable`, and identity state `unavailable`. A read-only session probe reported the screen locked at that time. That condition is consistent with the zero-frame result but is not proven to have been its only cause. The separate LaunchServices report `LectureBoard-Runtime-Schema7-EditingWindow-LaunchServices-2026-08-31.json`, SHA-256 `847dc25d9a8bc1eb28c7a52f5b02c66120a683e61f6b569764942afd0e7b7452`, reported preflight as unknown, did not request permission, and failed with `screenRecordingUnavailable` before selecting a target or collecting a snapshot. Neither schema-7 result is evidence for current schema-8 behavior or standalone LaunchServices authorization.

### Schema-9 fixed-path dynamic checkpoint and confirmed-only public-scene gate on 2026-08-31

The frozen `LectureBoard AI Schema 9 Idle Policy Verification.app` subsequently completed a controlled run from its saved executable path. The retained metadata-only report is `LectureBoard-Runtime-Schema9-IdlePolicy-Dynamic-2026-08-31.json`, SHA-256 `390bee97a34dbde9dc434f876cdf2b05c0a4836effd0d36b528e6231db3ca7e2`. It contains 154 snapshots and reaches 33 delivered frames: 15 new frames and 18 idle repeats. The maxima are 4 stable frames and 4 content revisions, with each of the four controlled inputs correlated with one content revision. Every snapshot retains canvas state `confirmed`; slide identity remains `unavailable`, slide changes remain zero, and overlay mapping succeeds zero times.

This is current-schema fixed-path evidence that the provisional post-fix idle policy survived live idle repeats and that the visual-content pipeline recorded four controlled input changes. It does not identify those changes as semantic PowerPoint slide transitions. The full-frame canvas was confirmed by diagnostic instrumentation rather than by the user, and the unavailable identity and zero successful mappings mean that the run does not verify a production slide-identity provider, user-confirmed canvas accuracy, visible overlay alignment, or production board rendering. The report also does not preserve enough attachment detail to establish whether each accepted idle sample used the all-three-keys-absent branch or an exactly matching complete tuple.

The current deterministic source now passes 123 Core tests in 15 suites and 218 complete native app tests in 25 suites. The additional public-scene tests preserve the uncertainty gate: only `confirmed` or `pinned` board intents enter the public scene, while `proposed`, `deferred`, and `dismissed` intents remain internal. When composition leaves the public scene unchanged, the app does not advance `boardSceneAnalysisGeneration` or invoke overlay rendering. These automated tests establish deterministic state and side-effect boundaries, not live board rendering. The complete 14-stage `make verify` run recorded at 16:17 above remains valid evidence for its earlier 119-Core-test and 217-App-test source state. A later attempt after the changes stopped while planning the Core package manifest because the sandbox denied writes to the Swift module cache. That attempt remains an incomplete negative checkpoint and is not counted as success. The unchanged gate subsequently passed in the normal local macOS context as recorded below.

The first current-schema mouse-ink attempt stopped safely before sending any stroke because `screencapture` produced empty output. It created no runtime report and no verification images, so it provides no mouse-ink result. The ignored local safety helper was then hardened. Its source SHA-256 is `47d43abcb8dec2a0d6724c2bf3d2f81fa29c60bb00514747fa6b99b89dba523d`, and its compiled binary SHA-256 is `90b14a40b138924d404202af28e9fd3a98e48139c75a6ca7031cb0adf84daebc`. Its GUI-free self-test, strict lint, Swift 6 strict-concurrency type checking, compilation, 20-iteration repetition check, and independent read-only review passed; the review found no P0, P1, P2, or P3 issue. These results verify the helper's tested safety boundaries only. The next end-to-end mouse-ink run has not yet produced a result and remains unverified.

### Exit-safe helper and locked-session mouse-ink preflight checkpoint on 2026-08-31

The ignored local helper was hardened again to make existing-slide-show exit handling explicit and fail closed. Its source SHA-256 is `a5866aaed585dd6ce5a92e740be6fe28274b2d105185d3bc350b86f6ed3fc388`. The arm64 Mach-O binary at `/private/tmp/DriveExactPowerPointInk-schema9-exit-final.yjE7XK/DriveExactPowerPointInk` has SHA-256 `7df7a10ad977afbcd2740d9619ec078ab81e2d25e8e9cbf2f32e381e552d790e`. Its GUI-free self-test passed 79 explicit existing-slide-show exit outcomes. Five local repetitions passed; a separate worker passed 20 repetitions, and independent read-only review found no P0, P1, P2, or P3 issue. These checks establish only the helper branches exercised by those tests.

The next live preflight remained fail closed. Passive exact-editing-focus verification failed first. A focus-only operation then succeeded, exact menu selection succeeded for editing window ID `19218`, and a second focus-only operation succeeded. The slide-show probe then stopped because it could not establish a stable substantial new or changed window. A read-only probe immediately afterward observed exact slide-show window ID `19229` at 1,512 by 982 points and exact editing window ID `19218` at 1,512 by 900 points. The console session then reported `IOConsoleLocked = Yes`. No Escape key, mouse event, LectureBoard runtime, runtime report, or verification image was attempted or produced after that boundary, and the existing slide show was left in place. This is evidence of the helper's fail-closed preflight and non-interference at the lock boundary, not evidence of current-schema mouse ink or capture behavior.

### Current normal-context full-gate checkpoint at 23:02–23:03 JST on 2026-08-31

The latest normal-context `make doctor` completed with zero failures and zero warnings. The latest `make local-setup` completed successfully and included all 123 Core tests in 15 suites. The current-source `make verify` then completed successfully in the normal local macOS context, with all 14 stages passing. The gate covered recursive Swift-format lint, all 123 Core tests in 15 suites, all 218 native app tests in 25 suites, the signing-disabled native arm64 build, the arm64 ad hoc runtime build and strict complete-bundle signature verification, the no-permission-request runtime launch smoke, publication-source fixtures and live tracking, README language boundaries, historical initial-publication fail-closed fixtures, release-definition fixtures and live consistency, tracked-build-output exclusion, common-secret-pattern exclusion, and lecture-data-extension exclusion.

The native result bundle is `DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.08.31_23-03-00-+0900.xcresult`. The normal-context `xcresulttool` summary reports `Passed`, authoritative total 218, failed 0, skipped 0, and expected failure 0. Its per-device passed counter is 220 because two dynamically parameterized tests produced four runs. A restricted read attempt could not create its temporary `TestReport` directory; the unchanged normal-context read succeeded, so that restriction is not a test failure.

The resulting runtime executable is a Mach-O 64-bit arm64 file with SHA-256 `1d2089d0169bbb16929acf0aabb6b27fe24dda048bf3b2ba9119ddda054ed4b3` and ad hoc CDHash `f072b4e144e15f99f454366f2b50df55d6527e02`. Its identifier is `io.github.akiyama709.LectureBoardAI`, its team identifier is not set, and `codesign --verify --deep --strict` passes for the complete bundle. Hardened runtime remains disabled. This current build differs from the separately frozen schema-9 verification app and does not replace or generalize that build-specific live evidence. The gate is current-source build and automated-test evidence only; it is not Developer ID signing, notarization, a successful live mouse-ink result, semantic PowerPoint slide identity, visible overlay alignment, or `v1.0.0` completion.

After the result above was recorded in the current documentation, the complete unchanged 14-stage gate was repeated at 23:09–23:10 JST so that the documented state itself was included in the verified tree. All stages passed again. The final native result bundle is `DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.08.31_23-09-45-+0900.xcresult`; its normal-context summary again reports `Passed`, authoritative total 218, failed 0, skipped 0, and expected failure 0, with a per-device passed counter of 220 from the same two dynamically parameterized tests. The regenerated runtime executable retained the same SHA-256, CDHash, arm64 architecture, ad hoc signature, and strict complete-bundle verification recorded above. Only this verification paragraph and corresponding current-state pointers were changed afterward; `git diff --check`, README language boundaries, release-definition fixtures and live consistency, and publication-source tracking were then repeated.

## Still unverified on this Mac

- LaunchServices Screen Recording authorization, capture, and post-restart permission persistence; the schema-8 LaunchServices run verified start, arguments, no request, fail-closed reporting, and auto-exit only, then failed before target selection
- Direct report creation by the frozen app in the sibling external verification directory; the first attempt produced no report, and the verified procedure currently writes to a unique path in the system temporary directory before validating and copying the bytes
- Same-slide mouse-ink behavior of the current semantic build; one schema-9 fixed-path diagnostic survived live idle repeats and correlated four controlled inputs with four content revisions, but identity remained unavailable, the first later mouse-ink attempt stopped before strokes, and the newest exit-safe preflight stopped before runtime or input and was followed by a locked console session
- A production PowerPoint slide-identity provider with exact ScreenCaptureKit-window binding; the read-only probe returned no exact scripting window ID, and historical image-difference builds do not verify slide transitions
- Automatic exact-window fresh-frame acquisition after a semantic identity boundary and live waiting, timeout, and recovery behavior with a production identity provider; the static schema-8 diagnostic delivered frames without a production identity, and the historical schema-7 zero-frame timeout does not verify this path
- User-confirmed slide-canvas localization accuracy, exclusion of PowerPoint controls, slideshow and presenter modes, live resize invalidation, display-scale changes, ScreenCaptureKit surface padding and `contentRect` mapping, and actual idle-sample attachment behavior; the schema-8 full-frame confirmation was explicitly diagnostic rather than user-confirmed
- PowerPoint window closure, reselection, PowerPoint restart, and display reconnection recovery
- Representative Japanese, English, mixed-language, animated, and long-duration lecture decks
- OCR text correctness, title selection, rectangle coordinates, occupied-region coordinates, and visible overlay alignment; the schema-8 report records only counts and a successful metadata-bound mapping result
- Robust empty-space analysis and existing PowerPoint ink detection
- Transparent overlay position, size, Core Graphics z-order and bounds policy, lease timing, click-through behavior, and non-interference with mouse or pen-tablet input; `mapped` metadata does not verify visible rendering, and the safe default identity provider cannot authorize production display
- Japanese and English microphone transcription and Japanese–English code switching
- Representative multi-display arrangements, display swap or reconnection, and online-sharing composition beyond the historical capture-only two-display case above; the current duplicated-bounds read-only snapshot did not exercise overlay mapping
- Contextual AI board rendering and session export during a lecture
- Developer ID distribution signing, hardened runtime, and notarization

These items must remain described as prototypes or unverified behavior until each one is exercised and recorded on the lecture Mac.

## Local macOS handoff

The repository includes `AGENTS.md`, `.codex/config.toml`, `make doctor`, `make local-setup`, native Core and app test targets, an ad hoc runtime build, a no-permission-request launch smoke test, and Japanese local-development and handoff documentation. Native compilation and the explicitly identified controlled schema-8 runtime paths above are verified on this Mac. Schema 9 adds bounded canvas-invalidation diagnostics, a provisionally tested idle-surface continuity policy, a separately frozen current artifact, and fixed-path no-permission-request preflight evidence. The pre-correction live report verifies the bounded idle-repeat failure class. The later fixed-path schema-9 diagnostic verifies narrow post-fix idle continuity and four controlled content revisions, while its unavailable identity, zero slide changes, and zero successful overlay mappings prevent interpreting it as semantic slide-transition, user-canvas, visible-alignment, or production-rendering evidence. The frozen schema-8 and schema-9 report workflows use unique paths in the system temporary directory followed by validation and a byte-identical copy. The current deterministic source passes 123 Core tests in 15 suites, 218 app tests in 25 suites, and the complete current-source 14-stage gate, including the confirmed-or-pinned-only public-scene boundary. The latest normal `make doctor` and `make local-setup` checks also passed; the prior sandboxed `make verify` attempt remains an incomplete negative checkpoint rather than a product failure. The latest exit-safe mouse-ink helper passed its deterministic checks, while live preflight stopped before runtime or input and the console subsequently locked. Production slide identity, automatic fresh-frame acquisition after an identity boundary, user canvas localization, visible overlay alignment, microphone behavior, current-schema mouse ink, LaunchServices capture authorization, and release distribution remain listed separately.
