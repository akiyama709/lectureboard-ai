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
- Compiled Vision text and rectangle analysis triggered by confirmed stable visual frames or content updates.
- A native RGB raster path, limited to a 640-pixel long edge, and deterministic `strokeCandidateRegions` that remain distinct from confirmed PowerPoint ink.
- Deterministic normalized occupied-region filtering, padding, and merging across text, rectangles, and stroke candidates.
- Capture-monitor analysis counts and occupied-region preview overlays.
- A deterministic slide-identity tracker that confirms a baseline or transition only after two consecutive matching samples, discards continuity across unavailable gaps, and does not count presentation-session changes as slide changes.
- An app-side identity-provider boundary with target, session, and sequence rejection; candidate-frame exclusion from visual analysis after delivery metrics are recorded; old scene and analysis invalidation at baseline or transition boundaries; and analysis resumption only for a `.new` frame whose ScreenCaptureKit `displayTime` is strictly later than the app's local mach-absolute acceptance time for the confirming observation.
- A local speech-result boundary that rejects final transcript results emitted before an identity boundary or while the app is still waiting for the post-boundary frame.
- A safe default identity provider that requests no Automation permission, sends no Apple Event, and emits one unavailable observation per accepted capture start.
- Metadata-only runtime reports at schema version 4, including slide-identity state, sample count, continuity-break count, content-revision count, and stroke-candidate count. Schema 1 through schema 3 remain decodable as historical formats with unavailable/zero identity metadata.
- Click-through transparent overlay prototype.
- Japanese or English Apple Speech prototype.
- Platform-neutral `LectureBoardCore` package.
- Contextual importance scoring and board-intent classification.
- Vector board-scene models and simple empty-region placement.
- Core unit tests and open-source repository documentation. The current source passes 90 Core tests and 103 native app tests on the development Mac.

Narrow runtime evidence from controlled synthetic PowerPoint runs:

- A historical schema-1 build completed a 40-second exact-window run with 372 frames, 6 stable snapshots, and 5 image-difference events then recorded as slide changes. Those five values are legacy heuristic classifications, not verified slide identities and not runtime evidence for the current semantic build.
- A later schema-2 but pre-semantic-correction build completed a separate 40-second exact-window run with 373 frames, 6 stable snapshots, the same 5 legacy heuristic change classifications, and 2 content revisions. The report SHA-256 is `704d9266bf1564161dd756a0be57c4a47d5459dfb9c9ae5cf0c103acc8320f41`. This is build-specific historical evidence for capture and metadata production; it must not be presented as verification of the current source or of slide identity.
- No live dynamic or mouse-ink result has yet been recorded for the current schema-4 build. A read-only PowerPoint probe observed Automation preflight status `0`, one slide-show window, and two Core Graphics windows, but PowerPoint's inherited `window.id` was `nil`; the semantic result therefore could not be bound to the exact captured window ID. No weaker name-, order-, or geometry-based fallback was adopted.
- Neither historical run establishes standalone LaunchServices authorization, recognition or coordinate accuracy, slide-canvas isolation, representative-deck coverage, or lecture-length reliability.

Not yet implemented or verified:

- Independent LaunchServices runtime validation of continuous PowerPoint frame capture.
- Live dynamic and same-slide mouse-ink validation with the current schema-4 build.
- A production PowerPoint slide-identity provider that can bind semantic slide information to the exact captured window. The deterministic tracker and fail-closed app integration are implemented, but actual PowerPoint transitions remain unverified and the safe default provider supplies no identities.
- Fresh-frame resynchronization or explicit timeout/state handling when a static slide yields only idle repeats after an identity boundary.
- Representative-deck, animation, reselection, and long-duration calibration of stable visual/content-update detection.
- OCR correctness and coordinate-accuracy calibration of Vision text, rectangle, and occupied-region analysis.
- Slide-canvas cropping and exclusion of PowerPoint controls or other window UI from analysis.
- Robust object, empty-space, and existing-ink analysis beyond detected text, rectangles, and raster stroke candidates.
- Existing PowerPoint ink detection.
- Real speaker-note and `.pptx` parsing.
- Reliable Japanese–English code switching.
- Production-grade contextual model adapters.
- Session export to JSON, SVG, PDF, and Markdown.
- Runtime validation of microphone transcription, the click-through overlay, and AI board rendering during a lecture.
- Developer ID distribution signing, hardened runtime, and notarization.

## Immediate next milestone

Implement and validate the observable lecture path in this order:

1. Continuously capture only the selected PowerPoint window with ScreenCaptureKit.
2. Produce stable visual snapshots and persistent content-update events.
3. Implement an exact-window-bound production PowerPoint slide-identity provider and validate actual transitions before making runtime claims.
4. Run Vision text, geometry, and raster candidate analysis on stable visual frames.
5. Crop to the slide canvas and build a normalized occupied-region map, including verified existing presenter ink.
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
