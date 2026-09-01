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
- A fail-closed slide-canvas boundary for the visual pipeline. Public macOS and PowerPoint APIs do not expose the exact internal slide-canvas rectangle, so the user drags and explicitly confirms the visible slide area on a frozen preview of the exact captured window. The confirmation is bound to the capture operation, exact window ID, source pixel dimensions, and validated ScreenCaptureKit surface geometry; capture restart, window mismatch, size mismatch, missing usable geometry after applying the narrow idle policy below, or geometry change invalidates it.
- Idle surface handling is an application policy, not an Apple guarantee. For a verified `.idle` delivery whose `contentRect`, `scaleFactor`, and `contentScale` keys are all absent, the app provisionally reuses the previously latched surface geometry only to crop the unchanged visual payload. A complete current tuple is accepted only when it exactly matches that geometry. Partial, malformed, conflicting, or non-idle evidence, missing prior geometry, and prior output dimensions that do not match the visual payload fail closed and poison repeat geometry until a later `.new` frame. The all-absent branch neither inherits nor uses `screenRect`, so overlay mapping remains closed. A pre-fix schema-9 live report bounded the failure to `idleRepeatSurfaceGeometryUnavailableOrMismatched`. A later controlled fixed-path schema-9 diagnostic showed the post-fix policy surviving 18 live idle repeats while retaining confirmed diagnostic canvas state. The raw idle attachment form, behavior across other PowerPoint modes, and production overlay mapping remain unverified.
- A separate current-frame screen-position boundary parses ScreenCaptureKit `screenRect` attachments represented as `CGRect`, exact rectangle `NSValue`, or dictionary representation. Negative global origins are valid, but non-finite or non-positive dimensions are rejected. Outside the all-absent idle-surface branch, an idle repeat can use only that idle sample's current `screenRect`; a prior screen position is never inherited.
- ScreenCaptureKit delivery status is parsed fail closed: only `.complete` and `.started` are new deliveries and only `.idle` is a repeat. Missing, malformed, unknown, `.blank`, and `.suspended` statuses, invalid samples, and conversion failures break repeat continuity, notify the app that content is unavailable, and require a later `.new` frame before visual processing can resume. `.stopped` is a terminal capture error with a fixed localized message. Surface scale factor must be within the SDK-documented inclusive range from 1 through 4.
- Terminal capture failures are routed through one synchronous first-event gate. Runtime schema 10 records one of nine bounded failure-source categories and, only where applicable, one of 21 public `SCStreamError.Code` categories. Concurrent or later terminal callbacks, stale capture operations, and callbacks after a new start or manual stop cannot replace the accepted result. Unknown, malformed, missing, or inconsistent current-capture evidence normalizes to `unclassifiedCaptureFailure`; raw error domains, numeric codes, descriptions, and `userInfo` are not retained.
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
- Metadata-only runtime reports at schema version 10. Schema 6 added slide-canvas state, schema 7 added overlay-mapping state and specific fail-closed rejection reasons, schema 8 added `slideCanvasConfirmationMode`, schema 9 added bounded canvas-failure reasons, and schema 10 adds bounded `captureFailureSource` and `captureSCStreamErrorCode` values. Reports retain no image, recognized text, coordinates, display identifier, window title, raw error domain, raw numeric code, description, or `userInfo`. Schema 1 through schema 9 remain decodable as historical formats and ignore the schema-10 fields; completed and non-capture-failure reports also normalize them to `nil`. A current schema-10 capture failure with missing, malformed, unknown, or inconsistent bounded fields normalizes fail closed to `unclassifiedCaptureFailure`.
- A runtime-only `--confirm-full-frame-canvas` diagnostic path that waits for an actual delivered frame before explicitly confirming that frame's full bounds. The flag is absent by default and does not change normal user-confirmed canvas behavior. A no-frame timeout reports the dedicated fixed-message failure `captureFrameUnavailable`; other confirmation failures remain distinct.
- A deterministic, fail-closed overlay-coordinate mapper for confirmed production canvas selections. It binds placement to the capture operation, exact window, exact surface geometry, output dimensions, and current frame sequence; maps the confirmed output-pixel crop through `contentRect`, `scaleFactor`, `contentScale`, and the current frame's `screenRect`; and converts from Quartz global coordinates to AppKit coordinates only when exactly one validated display contains the result. Missing, stale, inconsistent, cross-display, or ambiguous coordinate evidence hides the overlay while leaving an otherwise valid canvas confirmation available for a later current frame.
- A click-through transparent overlay prototype that renders into the mapper-produced AppKit target rectangle only while semantic slide identity and current visual grounding are confirmed. A separate eligibility boundary requires the frozen PowerPoint PID and exact bundle to be frontmost, one exact on-screen layer-zero Core Graphics window with matching owner and bounds within a two-point edge tolerance, and no earlier intersecting on-screen window. Manual hiding remains latched, visual or capture-content uncertainty hides immediately, and a capture-cadence-independent lease plus focus and Space notifications prevents stale display. The safe default identity provider therefore cannot show production output. These branches have deterministic native-test coverage only.
- Japanese or English Apple Speech prototype.
- Platform-neutral `LectureBoardCore` package.
- Contextual importance scoring and board-intent classification.
- Vector board-scene models and simple empty-region placement.
- A deterministic public-scene boundary that keeps proposed, deferred, and dismissed intents internal and composes only confirmed or pinned intents. When composition leaves the public scene unchanged, the app neither advances `boardSceneAnalysisGeneration` nor invokes overlay eligibility or rendering. These branches have deterministic test coverage only; live board rendering remains unverified.
- Demo board content and any visible full-display demo panel are cleared at capture start. Demo content cannot be generated while capture is active or while capture-provider shutdown is in progress.
- Core unit tests and open-source repository documentation. The current schema-10 source passes 137 Core tests in 15 suites, 228 complete native app tests in 27 suites, and the complete 14-stage `make verify` gate on the development Mac. The final documentation-inclusive rerun at 14:50–14:51 JST on 2026-09-01 produced `DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_14-50-49-+0900.xcresult`, with 228 total tests, zero failures, zero skips, and zero expected failures. The ad hoc arm64 runtime passed strict bundle-signature verification; it is not Developer ID signed, hardened, or notarized. A separately named schema-9 idle-policy app is frozen and strictly signature-verified; its controlled diagnostics are build-specific evidence and do not verify live schema-10 capture-failure classification.

Narrow runtime evidence from controlled synthetic PowerPoint runs:

- A historical schema-1 build completed a 40-second exact-window run with 372 frames, 6 stable snapshots, and 5 image-difference events then recorded as slide changes. Those five values are legacy heuristic classifications, not verified slide identities and not runtime evidence for the current semantic build.
- A later schema-2 but pre-semantic-correction build completed a separate 40-second exact-window run with 373 frames, 6 stable snapshots, the same 5 legacy heuristic change classifications, and 2 content revisions. The report SHA-256 is `704d9266bf1564161dd756a0be57c4a47d5459dfb9c9ae5cf0c103acc8320f41`. This is build-specific historical evidence for capture and metadata production; it must not be presented as verification of the current source or of slide identity.
- A controlled schema-7 diagnostic attempt selected one exact PowerPoint window but received zero capture frames and failed closed with `captureFrameUnavailable`. This verifies exact-window selection and the no-frame diagnostic only. The requested diagnostic full-frame confirmation never began, and the attempt is not evidence of live frame capture, a user-confirmed canvas, overlay mapping, alignment, or rendering for schema 7 or any later source.
- The schema-8 runtime executable was launched directly from DerivedData and completed a 15-second live static exact-window diagnostic with 152 new frames, 1 stable frame, completed Vision analysis, 39 text observations, 14 rectangles, 69 stroke candidates, and 3 occupied regions. The report records `diagnosticFullFrame`, confirmed canvas state, mapped overlay metadata, unavailable semantic identity, zero content revisions, and zero slide changes. The report `LectureBoard-Runtime-Schema8-ExactWindow-Static-2026-08-31.json` in the external verification directory has SHA-256 `593cc70cd666498c8d68cd9f3b8156b617c45d066cc955992106c5c1e18a8b84`. This verifies that narrow direct-verifier static path and metadata production only: the whole captured frame was confirmed by an explicit diagnostic flag, not by the user, and no canvas-localization accuracy, visible overlay alignment, production rendering, dynamic transition, or ink result follows from it.
- A byte-identical schema-8 arm64 app, `LectureBoard AI Schema 8 Verification.app`, was subsequently copied to the external verification directory. Its executable has SHA-256 `316ee7aada2359155097eaa726a86c911bdfc1b3d9e3a34e32bb5d2f87c83260`, ad hoc CDHash `e989a694c94daac85db9b4cd31de5179965da384`, and passes strict bundle-signature verification. That fixed copy's executable was then launched directly from its saved path, without requesting permission, for a five-second diagnostic against exact PowerPoint window ID 13577. Screen Recording preflight was authorized before and after capture, `permissionWasRequested` was false, and the run recorded 21 snapshots, 53 new frames, zero repeats, 1 stable frame, completed Vision analysis, 44 text observations, 14 rectangles, 106 stroke candidates, 3 occupied regions, confirmed diagnostic-full-frame canvas state, mapped overlay metadata, unavailable semantic identity, zero content revisions, and zero slide changes. The verified report `LectureBoard-Runtime-Schema8-FrozenApp-Static-2026-08-31.json` in the external verification directory has SHA-256 `1758fda4429cc5ba3b1ed46c14069c8b104fb0d425103907362cd8e49d41f1c5`. This verifies direct fixed-path preflight and capture, not independent LaunchServices launch. Rebuilding, replacing, or moving the app can change or disrupt its authorization identity.
- A separate schema-8 LaunchServices run produced `LectureBoard-Runtime-Schema8-LaunchServices-Preflight-2026-08-31.json`, SHA-256 `ad18b286fa5b4e14f3c15aa92a4672665a65edf3c54102c495383e161bec67f4`. It verifies LaunchServices start, argument delivery, no permission request, fail-closed metadata report production, and automatic exit only. It failed with `screenRecordingUnavailable` before capture, so it is not authorization, frame-delivery, canvas, overlay, dynamic, or ink evidence.
- An earlier hardened exact-input helper revision had source and binary SHA-256 values `823d96053b81fe539489a5edc1214494184df94d19cb29c28130316df67ffd01` and `a08dc9fe2043d9b9e184e50061b220f4b50406f1d1082e6d0dc94a5f8c3aadea`. Its GUI-free self-test reported 72 hardening, 60 exact-window-menu, and 34 slideshow-policy outcomes; strict lint, Swift 6 type checking, compilation, and independent review passed. Exact menu selection, focus re-verification, and the separate slideshow probe then passed without weakening the identity boundary. The latest reviewed helper revision is recorded below.
- A subsequent schema-8 slideshow attempt produced `LectureBoard-Runtime-Schema8-Slideshow-Canvas-Invalidated-2026-08-31.json`, SHA-256 `93c5fd28598bf9d11b3cbb086a2fe05e413e834ea920106bcb2ea274da026956`. It received one new frame and two repeats, then failed closed after about 535 milliseconds because the diagnostic canvas became invalidated before scheduled input. No slide advance or mouse input was sent; this is negative canvas-lifecycle evidence, not dynamic or ink success.
- A pre-fix schema-9 rerun produced `LectureBoard-Runtime-Schema9-Slideshow-IdleGeometry-Invalidated-2026-08-31.json`, SHA-256 `edc97ebb2588771318676d1c0ffcf4c55f4f02e1cdb556649eededd8f1f372f8`. It again received one new frame and two repeats, failed before input, and recorded `idleRepeatSurfaceGeometryUnavailableOrMismatched` at both report and snapshot level. This confirms only that bounded failure class; it does not distinguish absent from mismatched attachments or verify post-fix recovery, dynamic slides, or ink.
- The post-fix app is frozen separately as `LectureBoard AI Schema 9 Idle Policy Verification.app`. Its executable SHA-256 is `a0a7a57de80509fd9904332f0d1aa97262957db65ce3794acf00653155c4e5b6`, its ad hoc CDHash is `a37601577a00e36c5365e4a3d1f5248913baad5b`, and strict bundle-signature verification passes. A direct saved-path run without a permission request recorded authorized preflight, zero matches for an impossible title, zero snapshots, and safe `windowNotFound`; the copied report `LectureBoard-Runtime-Schema9-IdlePolicy-FrozenApp-Preflight-2026-08-31.json` has SHA-256 `2d1043a8ba0bf5c3a2a3a0559c87a3e0c9d60380457b2431f8f7934e62402255`. This is fixed-path preflight and report evidence only, not capture or idle-delivery evidence.
- A later fixed-path schema-9 dynamic diagnostic produced `LectureBoard-Runtime-Schema9-IdlePolicy-Dynamic-2026-08-31.json` in the external verification directory, SHA-256 `390bee97a34dbde9dc434f876cdf2b05c0a4836effd0d36b528e6231db3ca7e2`. Over approximately 40.5 seconds it recorded 154 snapshots and 33 delivered frames: 15 new frames plus 18 idle repeats. The first recorded snapshot already contained 1 new frame and 2 idle repeats with the diagnostic canvas still confirmed, and every later snapshot also retained confirmed canvas state. The run reached 4 stable frames and four controlled inputs correlated with four content revisions. Maximum analysis counts were 11 recognized-text observations, 13 rectangles, 37 stroke candidates, and 11 occupied regions. Semantic identity remained unavailable and slide changes remained zero. Overlay mapping succeeded zero times: 7 snapshots reported `screenGeometryUnavailable` and 147 reported `canvasOutsideCapturedContent`. This is narrow post-fix idle-survival and visual-content-update evidence only, not verified semantic slide transitions, OCR or coordinate correctness, a user-confirmed slide canvas, visible overlay alignment, or production rendering.
- A controlled fixed-path schema-9 five-stroke diagnostic produced `LectureBoard-Runtime-Schema9-MouseInk-2026-09-01.json`, SHA-256 `534a285e8f3830891c374746338aa361ab9ebf15cf1f4b199e686d1166b17cb7`. Over 20 seconds it recorded 78 snapshots and 80 frames: 65 new plus 15 repeats, four content revisions, and zero slide changes. The before and after-erase images were byte-identical, while the after-ink image contained five connected components. This verifies only visible mouse strokes and visual restoration after erase in that fixed schema-9 synthetic diagnostic. It does not verify semantic or per-input classification, existing-ink detection, a production canvas, the current schema-10 runtime, or a separate post-erase content revision.
- A separate early schema-9 run failed after approximately 12.068 seconds with 60 frames—44 new and 16 repeat—and three content revisions; its report SHA-256 is `44ed13c6b338a48fe5c92290c47a0ea8ae4fb105590ddddfa65a6a3d421eb5db`. Schema 9 retained only an aggregate capture failure, so its terminal source is unknown and must not be inferred from internal ScreenCaptureKit logging. A 30-second no-content-mutation static control, SHA-256 `60deb22f7c3561ed2c4b105ea69c0a9e5f196a6d5b7f6c42e6f23eb399b8c0fc`, recorded 41 frames—4 new and 37 repeat—and one content revision; it is therefore not evidence of a false-positive-free detector.
- A single-stroke schema-9 run, SHA-256 `494eb356282f8c49c9a57d7d67ec2e56cb31a22326da69d373b556f047332d45`, recorded 30 frames—15 new and 15 repeat—one content revision, one connected component, and byte-identical before and after-erase images. A separate five-stroke rerun, SHA-256 `7cadc164d28f534fe3620261eb26b14c20d7694b16216629d940d1c5e9870385`, recorded 81 frames—66 new and 15 repeat—four revisions, five components, and the same visual restoration. Neither run recorded a distinct post-erase content revision. The consolidated metadata audit `LectureBoard-Runtime-Schema9-Live-Checkpoint-Audit-2026-09-01.json` has SHA-256 `a547704072066e63047abaffc8e4bec0149be39760901e852236158d103ceff2`; the corresponding image audit has SHA-256 `38552053c77b46d6a9eccb0cbde8f1baeef6faadf74bee9f57247e8e110d95a9`.
- The dense detector contract remains unchanged at difference threshold `0.08`, minimum changed-pixel fraction `0.001`, persistence tolerance `0`, and three required identical qualifying deliveries. The erase candidate therefore needed a third qualifying delivery that the live runs did not provide. Thresholds were not weakened. A bounded one-shot fresh-sample path—at most two samples about 100 milliseconds apart while a dense change is pending, with strict operation/window/canvas/identity/candidate-generation guards and exclusion from capture metrics, identity, and overlay provenance—is planned but not implemented.
- The latest reviewed ignored helper source has SHA-256 `37e07382857c0a72cdfc08e8bb30b52162837409b004ced6d6f34e8bef2f7aaf`; its separately saved reviewed arm64 binary, `DriveExactPowerPointInk-Schema10-Reviewed-2026-09-01`, has SHA-256 `e7d5b1d01fa6929834526766fc606c1deb2fc78f4558cd0a990e65a62dd9a15d`. Its GUI-free self-test passed 20 of 20 cases; Swift-format lint, Swift 6 strict type checking, compilation, and independent review also passed. This verifies only the helper's tested policy. Live all-Spaces switching, post-Escape WindowServer behavior, Accessibility focus mutation, and end-to-end input remain live-unverified.
- No successful user-confirmed slide-canvas, visibly aligned-overlay, or board-rendering result has yet been recorded for the current semantic source. A read-only PowerPoint probe observed Automation preflight status `0`, one slide-show window, and two Core Graphics windows, but PowerPoint's inherited `window.id` was `nil`; the semantic result therefore could not be bound to the exact captured window ID. No weaker name-, order-, or geometry-based fallback was adopted.
- Neither historical run establishes standalone LaunchServices authorization, recognition or coordinate accuracy, slide-canvas isolation, representative-deck coverage, or lecture-length reliability.

Not yet implemented or verified:

- Independent LaunchServices capture authorization and post-restart permission persistence beyond the narrow schema-8 start-and-fail report and direct-executable static diagnostics.
- Representative dynamic calibration and semantic same-slide mouse-ink validation with the current build. One fixed schema-9 diagnostic verifies visible mouse strokes and visual erase restoration only; semantic/per-input classification, a separate post-erase revision, existing-ink recognition, and schema-10 live behavior remain unverified.
- Live validation of schema-10 capture-failure source classification. Its bounded first-terminal-event diagnostics currently have deterministic automated coverage only.
- A bounded one-shot fresh-sample path for a pending dense content-change candidate, followed by a live rerun that records a distinct post-erase revision without weakening the detector thresholds.
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

Keep both `LectureBoard AI Schema 8 Verification.app` and `LectureBoard AI Schema 9 Idle Policy Verification.app` fixed in place; do not rebuild, replace, or move either. Keep the PowerPoint test file unchanged as historical evidence. The full schema-10 publication and local verification gate is complete. Next implement the bounded one-shot fresh-sample path described above without weakening detector thresholds, add deterministic tests for every new guard and stale-result branch, and rerun a separately identified schema-10 mouse-ink/erase checkpoint to seek a distinct post-erase revision and bounded capture-failure evidence. Only after those gates pass should work proceed to a user-confirmed live slide canvas, visible overlay alignment, and exact-window semantic identity. Write every report and verification image first to a unique system-temporary path, validate it, then copy and compare it into the external verification directory. Diagnostic full-frame confirmation remains instrumentation evidence, not user-confirmed canvas or production overlay validation.

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
