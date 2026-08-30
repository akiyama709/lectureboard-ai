# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Added

- Local Codex handoff through `AGENTS.md` and `.codex/config.toml`
- macOS toolchain diagnostic and first-run scripts
- Japanese local-development and session-handoff documentation
- Selected-window ScreenCaptureKit stream for continuous PowerPoint frame capture
- Deterministic stable-frame and slide-change detection with unit tests
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
- Controlled synthetic PowerPoint runtime evidence for current static frame delivery and Vision execution, plus separately identified pre-lifecycle dynamic calibration evidence

### Planned

- Runtime calibration of PowerPoint capture and slide-state tracking with real presentations
- Runtime calibration of Vision recognition and occupied regions with real presentations
- PowerPoint package parsing and speaker-note extraction
- Japanese–English code-switching transcription
- Contextual AI-provider adapters
- Signed and notarized alpha release

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
