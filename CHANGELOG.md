# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- Local Codex handoff through `AGENTS.md` and `.codex/config.toml`
- macOS toolchain diagnostic and first-run scripts
- Japanese local-development and session-handoff documentation
- Selected-window ScreenCaptureKit stream for continuous PowerPoint frame capture
- Deterministic stable-frame and significant visual/content-change classification with unit tests
- In-app capture controls, counters, and a latest-stable-frame preview
- Stable-frame Vision text and rectangle analysis using the native macOS framework
- Deterministic normalized occupied-region assembly with unit tests
- Analysis counters, title candidates, and occupied-region preview overlays
- Native macOS app unit tests and a local prepublication test gate
- A metadata-only runtime-verification mode for controlled PowerPoint capture checks
- New-frame and idle-repeat delivery metrics for ScreenCaptureKit streams
- Explicit Screen Recording permission controls that do not scan or start capture while preflight access is unavailable
- A local ad hoc-signed runtime build with signature diagnostics and a no-permission-request launch smoke test
- Monotonic capture-operation ownership and regression tests for overlapping starts, stops, errors, refreshes, and selection changes
- Exact whole-requirement team binding checks, including disjunction and negation regressions, for the optional Developer-signing path
- Fixed-message runtime failure reports that discard untrusted framework error details
- Build-specific historical synthetic PowerPoint evidence for static frame delivery, Vision execution, and pre-semantic dynamic calibration; not evidence for the current semantic build
- Deterministic independent slide-identity tracking with two-sample confirmation, interruption-safe baselines, and presentation-session separation
- Fail-closed app integration for identity target, session, and sequence checks; candidate-frame exclusion from visual analysis; stale final-transcript rejection; boundary cleanup; and post-boundary new-frame gating
- A no-side-effect default identity provider that performs no Automation permission request or Apple Event
- A token-bound post-identity frame gate with explicit waiting, synchronized, and fail-closed timeout states, plus stale-timeout rejection and recovery by a strictly newer ScreenCaptureKit frame
- Metadata-only runtime schema 5 frame-sync and identity state with schema-1-through-schema-4 decoding compatibility
- A user-confirmed slide-canvas boundary for the exact captured-window preview, bound to capture operation, exact window ID, source pixel dimensions, and validated ScreenCaptureKit surface geometry, with fail-closed invalidation on restart, mismatch, missing geometry, or geometry change
- Current-sample attachment geometry for idle deliveries, geometry provenance retained only when it exactly matches the last visual payload geometry, fail-closed invalidation before visual processing on changed, missing, or invalid current geometry or missing last geometry, and last-frame inheritance limited to fixed stream surface dimensions when an idle sample has no image buffer
- Fail-closed ScreenCaptureKit frame-status parsing that drops missing, malformed, and unknown values, treats only complete/started as new and idle as repeat, and validates scale factor against the SDK-documented inclusive range from 1 through 4
- Canvas-only stable/content fingerprints, Vision requests, raster candidates, occupied regions, and board-placement input; capture delivery remains observable while the visual pipeline is closed before confirmation
- Immediate stale-analysis invalidation for coarse/dense visual candidates and missing or invalid dense fingerprints, with analysis suppressed for coarse confirmation without a valid dense fingerprint and proposals gated until current-frame analysis completes after baseline recovery
- Minimum canvas validation requiring at least 32 by 24 source pixels and 1,024 square pixels, current-board-context invalidation across semantic slide, canvas, and capture boundaries, capture-end visual/scene cleanup, and fail-closed board proposals when occupied-region analysis is empty
- Independent App and Apple-provider transcription generation guards, provider stop and stale-callback rejection at semantic slide/canvas/capture boundaries, and explicit user resumption after each safety stop
- Demo-scene cleanup at capture start and demo suppression during active capture or capture-provider shutdown
- Metadata-only runtime schema 6 slide-canvas state with schema-1-through-schema-5 decoding compatibility

### Planned

- Runtime calibration of PowerPoint capture and slide-state tracking with real presentations
- An exact-window-bound production PowerPoint slide-identity provider and live validation before actual slide transitions are claimed
- Exact-window fresh-frame acquisition and live timeout calibration for a static slide after an identity boundary
- Runtime calibration of Vision recognition and occupied regions with real presentations
- Live PowerPoint calibration of manual canvas localization, UI exclusion, ScreenCaptureKit surface padding and `contentRect` mapping, slideshow modes, resizing, and display arrangements
- Exact confirmed-canvas alignment for the currently full-screen overlay
- PowerPoint package parsing and speaker-note extraction
- Japanese–English code-switching transcription
- Contextual AI-provider adapters
- Developer ID-signed and notarized release-candidate and `v1.0.0` distribution artifacts

## [0.1.0-alpha] - 2026-08-29

### Added

- Initial public-repository scaffold
- Native macOS application shell
- PowerPoint-window discovery prototype
- Transparent overlay prototype
- Apple Speech single-language transcription prototype
- Contextual importance and board-intent core
- Empty-region layout prototype
- Unit tests, CI, documentation, privacy policy, and issue templates
