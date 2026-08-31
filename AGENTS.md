# AGENTS.md

## Project purpose

LectureBoard AI is a macOS-first, open-source research prototype intended to observe a live PowerPoint lecture, infer what is educationally important from context, and add concise text or simple diagrams to unused slide space as digital ink.

The lecturer must not need to memorize or use voice commands. The system should remain quiet, defer uncertain decisions, and avoid interrupting the lecture.

## Product decisions already fixed

- Initial platform: macOS only, Apple silicon first.
- Initial presentation application: Microsoft PowerPoint for Mac.
- Initial target lecture languages: Japanese, English, and staged Japanese–English mixing.
- Default rendering style: clean digital ink.
- Alternate rendering style: more handwritten, with adjustable strength.
- Human pen input always has priority over AI output.
- The original PowerPoint file must not be modified during a lecture.
- AI board content must be grounded in the slide, speaker notes, transcript, or lecturer input.
- Confirmed board elements should remain stable so students can read and take notes.
- Local processing is preferred; cloud providers must remain optional adapters.
- Public GitHub repository: `akiyama709/lectureboard-ai`.
- Project completion means a public `v1.0.0` GitHub Release with a verified, signed, notarized, installable macOS artifact. Repository creation, source availability, alpha, beta, and release-candidate builds are intermediate milestones rather than completion.

## Current implementation state

The repository is an alpha scaffold rather than a lecture-ready release.

Implemented:

- Native SwiftUI/AppKit application shell.
- PowerPoint-window discovery prototype with ScreenCaptureKit.
- Compiled ScreenCaptureKit adapter for continuous capture of the selected PowerPoint window.
- Fail-closed capture identity binding across the ScreenCaptureKit window identifier, owning process identifier, and exact PowerPoint bundle identifier from selection through capture start.
- Deterministic coarse luminance fingerprints and stable-frame or significant-visual-change classification. Image difference alone is not treated as slide identity.
- Persistent visual-content updates from dense 160-by-90 RGB fingerprints.
- A fail-closed slide-canvas boundary for the visual pipeline. Public macOS and PowerPoint APIs do not expose the exact internal slide-canvas rectangle, so the user drags and explicitly confirms the visible slide area on a frozen preview of the exact captured window. The confirmation is bound to the capture operation, exact window ID, source pixel dimensions, and validated ScreenCaptureKit surface geometry; capture restart, window mismatch, size mismatch, missing geometry, or geometry change invalidates it.
- Idle deliveries re-read geometry from the current ScreenCaptureKit sample attachments and mark the repeated visual payload as geometry-valid only when the current geometry exactly matches that payload's geometry. Changed, missing, or invalid current geometry, or missing last-payload geometry, leaves the repeat without geometry and invalidates the canvas fail closed before visual processing. If the idle sample has no image buffer, only the fixed stream surface dimensions are inherited from the last frame. Live ScreenCaptureKit idle-attachment behavior remains unverified.
- A separate current-frame screen-position boundary parses ScreenCaptureKit `screenRect` attachments represented as `CGRect`, exact rectangle `NSValue`, or dictionary representation. Negative global origins are valid, but non-finite or non-positive dimensions are rejected. An idle repeat uses only that idle sample's current `screenRect`; a prior screen position is never inherited.
- ScreenCaptureKit delivery status is parsed fail closed: only `.complete` and `.started` are new deliveries and only `.idle` is a repeat. Missing, malformed, unknown, `.blank`, and `.suspended` statuses, invalid samples, and conversion failures break repeat continuity, notify the app that content is unavailable, and require a later `.new` frame before visual processing can resume. `.stopped` is a terminal capture error with a fixed localized message. Surface scale factor must be within the SDK-documented inclusive range from 1 through 4.
- Stable-frame and dense content fingerprints, Vision requests, raster candidates, occupied regions, and board-placement input are produced only from the confirmed cropped canvas. Without confirmation, capture-delivery metrics continue but the visual and board-placement pipeline remains closed.
- A coarse or dense visual-change candidate immediately invalidates prior analysis. Missing or invalid dense fingerprints also invalidate prior analysis; a confirmed coarse frame without a valid dense fingerprint does not start analysis. After a detector returns to baseline, proposals remain closed until analysis of the current frame completes.
- A current-board-context boundary that prevents transcript segments accumulated before a semantic slide, canvas, or capture boundary from being proposed again afterward. Canvas confirmation requires at least 32 by 24 source pixels and 1,024 square pixels, and transcript-driven board proposals remain closed when visual analysis has no occupied regions. Capture end clears the latest stable frame, analysis, and board scene.
- Compiled Vision text and rectangle analysis triggered by confirmed stable visual frames or content updates.
- A native RGB raster path, limited to a 640-pixel long edge, and deterministic `strokeCandidateRegions` that remain distinct from confirmed PowerPoint ink.
- Deterministic normalized occupied-region filtering, padding, and merging across text, rectangles, and stroke candidates.
- Capture-monitor analysis counts and occupied-region preview overlays.
- A deterministic slide-identity tracker that confirms a baseline or transition only after two consecutive matching samples, discards continuity across unavailable gaps, and does not count presentation-session changes as slide changes.
- An app-side identity-provider boundary with target, session, and sequence rejection; candidate-frame exclusion from visual analysis after delivery metrics are recorded; old scene and analysis invalidation at baseline or transition boundaries; and analysis resumption only for a `.new` frame whose ScreenCaptureKit `displayTime` is strictly later than the app's local mach-absolute acceptance time for the confirming observation.
- App-side and Apple-provider generation guards reject stale transcription callbacks. A semantic slide, canvas, or capture boundary stops transcription, invalidates prior callbacks and segments, and leaves transcription closed until the user explicitly resumes it. The identity-frame timestamp boundary remains an additional guard. Live microphone behavior remains unverified.
- A deterministic post-identity frame gate with observable waiting, synchronized, and timed-out states. Timeout remains fail-closed, stale timeout completions are rejected by boundary token, and a later strictly newer ScreenCaptureKit frame can recover the gate.
- A safe default identity provider that requests no Automation permission, sends no Apple Event, and emits one unavailable observation per accepted capture start.
- Metadata-only runtime reports at schema version 8. Schema 6 added slide-canvas state, schema 7 added overlay-mapping state and specific fail-closed rejection reasons without coordinates or display identifiers, and schema 8 adds `slideCanvasConfirmationMode` so an explicit diagnostic full-frame request cannot be mistaken for user confirmation. Schema 1 through schema 7 remain decodable as historical formats with safe defaults for absent metadata.
- A runtime-only `--confirm-full-frame-canvas` diagnostic path that waits for an actual delivered frame before explicitly confirming that frame's full bounds. The flag is absent by default and does not change normal user-confirmed canvas behavior. A no-frame timeout reports the dedicated fixed-message failure `captureFrameUnavailable`; other confirmation failures remain distinct.
- A deterministic, fail-closed overlay-coordinate mapper for confirmed production canvas selections. It binds placement to the capture operation, exact window, exact surface geometry, output dimensions, and current frame sequence; maps the confirmed output-pixel crop through `contentRect`, `scaleFactor`, `contentScale`, and the current frame's `screenRect`; and converts from Quartz global coordinates to AppKit coordinates only when exactly one validated display contains the result. Missing, stale, inconsistent, cross-display, or ambiguous coordinate evidence hides the overlay while leaving an otherwise valid canvas confirmation available for a later current frame.
- A click-through transparent overlay prototype that renders into the mapper-produced AppKit target rectangle only while semantic slide identity and current visual grounding are confirmed. A separate eligibility boundary requires the frozen PowerPoint PID and exact bundle to be frontmost, one exact on-screen layer-zero Core Graphics window with matching owner and bounds within a two-point edge tolerance, and no earlier intersecting on-screen window. Manual hiding remains latched, visual or capture-content uncertainty hides immediately, and a capture-cadence-independent lease plus focus and Space notifications prevents stale display. The safe default identity provider therefore cannot show production output. These branches have deterministic native-test coverage only.
- Japanese or English Apple Speech prototype.
- Platform-neutral `LectureBoardCore` package.
- Contextual importance scoring and board-intent classification.
- Vector board-scene models and simple empty-region placement.
- Demo board content and any visible full-display demo panel are cleared at capture start. Demo content cannot be generated while capture is active or while capture-provider shutdown is in progress.
- Core unit tests and open-source repository documentation. The current source passes 115 Core tests in 15 suites and 203 native app tests in 25 suites on the development Mac. The signing-disabled native build, arm64 ad hoc runtime build with strict bundle-signature verification, and no-permission-request launch smoke also pass.

Narrow runtime evidence from controlled synthetic PowerPoint runs:

- A historical schema-1 build completed a 40-second exact-window run with 372 frames, 6 stable snapshots, and 5 image-difference events then recorded as slide changes. Those five values are legacy heuristic classifications, not verified slide identities and not runtime evidence for the current semantic build.
- A later schema-2 but pre-semantic-correction build completed a separate 40-second exact-window run with 373 frames, 6 stable snapshots, the same 5 legacy heuristic change classifications, and 2 content revisions. The report SHA-256 is `704d9266bf1564161dd756a0be57c4a47d5459dfb9c9ae5cf0c103acc8320f41`. This is build-specific historical evidence for capture and metadata production; it must not be presented as verification of the current source or of slide identity.
- A controlled schema-7 diagnostic attempt selected one exact PowerPoint window but received zero capture frames and failed closed with `captureFrameUnavailable`. This verifies exact-window selection and the no-frame diagnostic only. The requested diagnostic full-frame confirmation never began, and the attempt is not evidence of live frame capture, a user-confirmed canvas, overlay mapping, alignment, or rendering for schema 7 or the current schema-8 source.
- The schema-8 runtime executable was launched directly from DerivedData and completed a 15-second live static exact-window diagnostic with 152 new frames, 1 stable frame, completed Vision analysis, 39 text observations, 14 rectangles, 69 stroke candidates, and 3 occupied regions. The report records `diagnosticFullFrame`, confirmed canvas state, mapped overlay metadata, unavailable semantic identity, zero content revisions, and zero slide changes. The report `LectureBoard-Runtime-Schema8-ExactWindow-Static-2026-08-31.json` in the external verification directory has SHA-256 `593cc70cd666498c8d68cd9f3b8156b617c45d066cc955992106c5c1e18a8b84`. This verifies that narrow direct-verifier static path and metadata production only: the whole captured frame was confirmed by an explicit diagnostic flag, not by the user, and no canvas-localization accuracy, visible overlay alignment, production rendering, dynamic transition, or ink result follows from it.
- A byte-identical schema-8 arm64 app, `LectureBoard AI Schema 8 Verification.app`, was subsequently copied to the external verification directory. Its executable has SHA-256 `316ee7aada2359155097eaa726a86c911bdfc1b3d9e3a34e32bb5d2f87c83260`, ad hoc CDHash `e989a694c94daac85db9b4cd31de5179965da384`, and passes strict bundle-signature verification. That fixed copy's executable was then launched directly from its saved path, without requesting permission, for a five-second diagnostic against exact PowerPoint window ID 13577. Screen Recording preflight was authorized before and after capture, `permissionWasRequested` was false, and the run recorded 21 snapshots, 53 new frames, zero repeats, 1 stable frame, completed Vision analysis, 44 text observations, 14 rectangles, 106 stroke candidates, 3 occupied regions, confirmed diagnostic-full-frame canvas state, mapped overlay metadata, unavailable semantic identity, zero content revisions, and zero slide changes. The verified report `LectureBoard-Runtime-Schema8-FrozenApp-Static-2026-08-31.json` in the external verification directory has SHA-256 `1758fda4429cc5ba3b1ed46c14069c8b104fb0d425103907362cd8e49d41f1c5`. This verifies direct fixed-path preflight and capture, not independent LaunchServices launch. Rebuilding, replacing, or moving the app can change or disrupt its authorization identity.
- No live dynamic, mouse-ink, user-confirmed slide-canvas, visibly aligned-overlay, or board-rendering result has yet been recorded for the current schema-8 build. A read-only PowerPoint probe observed Automation preflight status `0`, one slide-show window, and two Core Graphics windows, but PowerPoint's inherited `window.id` was `nil`; the semantic result therefore could not be bound to the exact captured window ID. No weaker name-, order-, or geometry-based fallback was adopted.
- Neither historical run establishes standalone LaunchServices authorization, recognition or coordinate accuracy, slide-canvas isolation, representative-deck coverage, or lecture-length reliability.

Not yet implemented or verified:

- Independent LaunchServices and post-restart validation beyond the narrow direct-executable schema-8 static diagnostics.
- Live dynamic and same-slide mouse-ink validation with the current schema-8 build.
- A production PowerPoint slide-identity provider that can bind semantic slide information to the exact captured window. The deterministic tracker and fail-closed app integration are implemented, but actual PowerPoint transitions remain unverified and the safe default provider supplies no identities.
- Automatic fresh-frame resynchronization when a static slide yields only idle repeats after an identity boundary. Explicit fail-closed timeout state is implemented and tested, but its live behavior with a production identity provider remains unverified.
- Representative-deck, animation, reselection, and long-duration calibration of stable visual/content-update detection.
- OCR correctness and coordinate-accuracy calibration of Vision text, rectangle, and occupied-region analysis.
- Live accuracy of the user-confirmed slide-canvas rectangle and PowerPoint-UI exclusion across slideshow modes, display arrangements, representative decks, and window resizing. ScreenCaptureKit surface padding and `contentRect` mapping also remain unverified.
- Live PowerPoint validation of the deterministic overlay mapping, including `screenRect` orientation and attachment behavior, Quartz-to-AppKit conversion, multiple displays and scale factors, window movement and resizing, full-screen and presenter modes, display reconnects, panel z-order, and exact visual alignment.
- Robust object, empty-space, and existing-ink analysis beyond detected text, rectangles, and raster stroke candidates.
- Existing PowerPoint ink detection.
- Real speaker-note and `.pptx` parsing.
- Reliable Japanese–English code switching.
- Production-grade contextual model adapters.
- Session export to JSON, SVG, PDF, and Markdown.
- Runtime validation of microphone transcription, the click-through overlay, and AI board rendering during a lecture. The overlay now has a deterministic confirmed-canvas coordinate path, but only synthetic geometry and app-integration tests have exercised it.
- Developer ID distribution signing, hardened runtime, and notarization.

## Immediate next milestone

The fixed-path schema-8 executable inside `LectureBoard AI Schema 8 Verification.app` in the external verification directory has now passed a no-permission-request direct static capture, but independent LaunchServices launch remains unverified. Keep that copy in place and do not rebuild, replace, or move it. The dynamic helper's 80 non-input self-tests pass, but its read-only Accessibility verification most recently failed the exact focus/reverification boundary and therefore sent no input. Re-run that strict verification and send controlled input only if it succeeds; do not weaken the boundary to obtain a result. Validate LaunchServices separately without requesting permission. For subsequent runtime reports, write to a unique path in the system temporary directory, verify the completed report, then copy and compare it into the external verification directory: a direct attempt to create a new sibling report there did not produce a report file and is not success evidence. The diagnostic full-frame flag is instrumentation evidence and must never be described as a user-confirmed canvas or production overlay validation.

After that checkpoint, validate the confirmed-canvas and overlay-coordinate path on live PowerPoint across display and window modes, while continuing to pursue a production semantic slide-identity provider that can bind to the exact captured window without a weaker fallback.

Implement and validate the observable lecture path in this order:

1. Continuously capture only the selected PowerPoint window with ScreenCaptureKit.
2. Produce stable visual snapshots and persistent content-update events.
3. Implement an exact-window-bound production PowerPoint slide-identity provider and validate actual transitions before making runtime claims.
4. Run Vision text, geometry, and raster candidate analysis on stable visual frames.
5. Validate the user-confirmed slide-canvas crop and the implemented fail-closed overlay alignment on live PowerPoint window, full-screen, presenter, resize, and multi-display modes, then extend the normalized occupied-region map to verified existing presenter ink.
6. Feed real `SlideContext` data and final transcript segments into `ContextualBoardEngine`.
7. Render stable text, boxes, arrows, and causal chains without overlap.
8. Persist a minimal lecture session as JSON and SVG.

Do not jump to cloud LLM integration before the capture, slide-state, occupancy, and grounding path is observable and testable.

## Engineering rules

- Use Swift 6 strict concurrency.
- Keep Apple-framework code in the macOS app target and deterministic logic in `LectureBoardCore`.
- Prefer protocols at external-provider boundaries.
- Add or update tests for every behavior change in `LectureBoardCore`.
- Preserve evidence links from board output to transcript or slide source identifiers.
- Never commit API keys, tokens, lecture recordings, unpublished slides, student data, model files, signing material, or local paths.
- Avoid destructive Git operations unless the user explicitly requests them.
- Do not claim a native macOS behavior has been verified unless it was built and run on macOS.
- Update `docs/build-verification.md` after each verified build or test run.

## Commands

```bash
make doctor          # Inspect the local Mac toolchain without changing it
make local-setup     # Run checks, core tests, and generate the Xcode project
make test-core       # Run platform-neutral tests
make test-app        # Run native macOS app unit tests with local ad hoc signing
make build           # Compile and link the native target with signing disabled
make build-runtime   # Build an arm64 Debug app with local ad hoc signing
make open            # Generate and open the Xcode project
make codex           # Open this repository in ChatGPT desktop Codex
make verify          # Run publication and local verification checks
```

## Style and language

- Source code and identifiers: English.
- Technical documentation: English or Japanese as appropriate.
- Japanese prose should use `，` and `．` as punctuation.
- User-facing Japanese should be formal, clear, and suitable for university teaching.
- Avoid overstating capabilities. Distinguish prototypes, verified behavior, and future plans.

## Starting a local Codex task

Read this file, `docs/local-codex-handoff-ja.md`, `ROADMAP.md`, and `docs/build-verification.md` before changing code. Then run `make doctor` and `make local-setup`. Report exact failures and fix them one at a time, beginning with native macOS compilation.
