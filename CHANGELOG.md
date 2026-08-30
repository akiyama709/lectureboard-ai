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
- Metadata-only runtime schema 4 identity state, sample count, and continuity-break count with schema-1-through-schema-3 decoding compatibility

### Planned

- Runtime calibration of PowerPoint capture and slide-state tracking with real presentations
- An exact-window-bound production PowerPoint slide-identity provider and live validation before actual slide transitions are claimed
- Fresh-frame resynchronization or an explicit timeout/state for a static slide after an identity boundary
- Runtime calibration of Vision recognition and occupied regions with real presentations
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
