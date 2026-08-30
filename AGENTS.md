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

## Current implementation state

The repository is an alpha scaffold rather than a lecture-ready release.

Implemented:

- Native SwiftUI/AppKit application shell.
- PowerPoint-window discovery prototype with ScreenCaptureKit.
- Compiled ScreenCaptureKit adapter for continuous capture of the selected PowerPoint window.
- Deterministic frame fingerprints, stable-frame confirmation, and slide-change classification.
- Compiled Vision text and rectangle analysis triggered by confirmed stable frames.
- Deterministic normalized occupied-region filtering, padding, and merging.
- Capture-monitor analysis counts and occupied-region preview overlays.
- Click-through transparent overlay prototype.
- Japanese or English Apple Speech prototype.
- Platform-neutral `LectureBoardCore` package.
- Contextual importance scoring and board-intent classification.
- Vector board-scene models and simple empty-region placement.
- Core unit tests and open-source repository documentation.

Narrow runtime evidence from controlled synthetic PowerPoint runs:

- The current post-lifecycle-fix executable was launched directly under the Codex-authorized environment, not through LaunchServices. A five-second static run delivered 50 frames, confirmed one stable frame, and reached completed Vision analysis with observed maxima of 35 text observations, 9 rectangles, and 4 occupied regions.
- An earlier pre-lifecycle-fix executable completed one dynamic slideshow run with 220 frames, 5 stable frames, and 4 classified slide changes. That run remains threshold-calibration evidence, but it is not runtime evidence for the current executable.
- Neither run establishes standalone LaunchServices authorization, recognition or coordinate accuracy, representative-deck coverage, or lecture-length reliability.

Not yet implemented or verified:

- Independent LaunchServices runtime validation of continuous PowerPoint frame capture.
- Dynamic slideshow validation of slide-change delivery with the current post-lifecycle-fix executable.
- Representative-deck, animation, reselection, and long-duration calibration of stable slide-change detection.
- OCR correctness and coordinate-accuracy calibration of Vision text, rectangle, and occupied-region analysis.
- Robust object, empty-space, and existing-ink analysis beyond detected text and rectangles.
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
2. Produce stable frame snapshots and detect slide transitions.
3. Run Vision text and geometry analysis on stable frames.
4. Build a normalized occupied-region map, including existing presenter ink.
5. Feed real `SlideContext` data and final transcript segments into `ContextualBoardEngine`.
6. Render stable text, boxes, arrows, and causal chains without overlap.
7. Persist a minimal lecture session as JSON and SVG.

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
