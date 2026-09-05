# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Planned

- Runtime calibration of PowerPoint capture and slide-state tracking with real presentations
- Live validation of the implemented exact-window-bound managed PowerPoint slide-identity provider before actual slide transitions are claimed
- Exact-window fresh-frame acquisition and live timeout calibration for a static slide after an identity boundary
- Live PowerPoint validation of `boundedFreshSample` itself through the shared exact-post-baseline-coarse or pending-dense path, including a controlled post-erase candidate confirmed by that source without weakening detector thresholds
- Runtime calibration of Vision recognition and occupied regions with real presentations
- Live PowerPoint calibration of manual canvas localization, UI exclusion, ScreenCaptureKit surface padding and `contentRect` mapping, slideshow modes, resizing, and display arrangements
- Live PowerPoint validation of the implemented confirmed-canvas overlay alignment, frontmost-window and occlusion policy, lease expiry, window movement and resizing, multi-display conversion, z-order, click-through behavior, and pen-input non-interference
- PowerPoint package parsing and speaker-note extraction
- Japanese–English code-switching transcription
- Contextual AI-provider adapters
- A hardened-runtime, ad hoc-signed `v1.0.0` application archive with checksums, SBOM, provenance, and public-download verification; no Developer ID or Apple-notarization claim

## [1.0.0] - 2026-09-06

### Added

- Local Codex handoff through `AGENTS.md` and `.codex/config.toml`
- macOS toolchain diagnostic and first-run scripts
- Japanese local-development and session-handoff documentation
- Selected-window ScreenCaptureKit stream for continuous PowerPoint frame capture
- An explicit managed PowerPoint transaction that retains the returned slide-show object, accepts only windowed show type, causally binds it to one exact ScreenCaptureKit window by a reversible role challenge, restores challenged state, activates App binding before identity polling, and keeps exact cleanup evidence alive until bounded drain completes
- Exact retained-object slide ID and index polling with one-shot, session, tombstone, cancellation, replacement, stale-callback, and deferred-cleanup guards; deterministic tests pass, while live managed Apple Event execution remains unverified
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
- A user-confirmed slide-canvas boundary for the exact captured-window preview, bound to capture operation, exact window ID, source pixel dimensions, and validated ScreenCaptureKit surface geometry, with fail-closed invalidation on restart, mismatch, missing usable geometry after the narrow idle policy, or geometry change
- A provisional idle-surface application policy, not an Apple guarantee: only a verified `.idle` delivery with `contentRect`, `scaleFactor`, and `contentScale` all absent may reuse previously latched surface geometry to crop the unchanged visual payload; a complete tuple must exactly match; partial, malformed, conflicting, non-idle, missing-prior, and prior-output-mismatch cases fail closed and poison repeat geometry until a later `.new` frame; the all-absent branch does not inherit or use `screenRect`, so overlay mapping remains closed
- Fail-closed ScreenCaptureKit frame-status parsing that drops missing, malformed, and unknown values, treats only complete/started as new and idle as repeat, and validates scale factor against the SDK-documented inclusive range from 1 through 4
- Canvas-only stable/content fingerprints, Vision requests, raster candidates, occupied regions, and board-placement input; capture delivery remains observable while the visual pipeline is closed before confirmation
- Immediate stale-analysis invalidation for coarse/dense visual candidates and missing or invalid dense fingerprints, with analysis suppressed for coarse confirmation without a valid dense fingerprint and proposals gated until current-frame analysis completes after baseline recovery
- Minimum canvas validation requiring at least 32 by 24 source pixels and 1,024 square pixels, current-board-context invalidation across semantic slide, canvas, and capture boundaries, capture-end visual/scene cleanup, and fail-closed board proposals when occupied-region analysis is empty
- Independent App and Apple-provider transcription generation guards, provider stop and stale-callback rejection at semantic-slide and temporary capture-content boundaries, and automatic resumption of a still-requested session only after current identity, canvas, frame synchronization, and visual analysis are ready; manual stop, canvas boundaries, and capture end cancel the request
- On-device-only Apple Speech requests with a fail-closed rejection when the selected locale
  cannot recognize without a network fallback
- Demo-scene cleanup at capture start and demo suppression during active capture or capture-provider shutdown
- Metadata-only runtime schema 6 slide-canvas state with schema-1-through-schema-5 decoding compatibility
- Metadata-only schema-7 overlay diagnostics and schema-8 confirmation provenance, plus narrow direct static exact-window capture evidence that does not validate user-confirmed canvas, visible overlay alignment, semantic identity, dynamic slides, mouse ink, or LaunchServices launch
- Metadata-only schema-9 bounded canvas-failure reasons at root `slideCanvasFailureReason` and snapshot `slideCanvasInvalidationReason`, with no captured image, recognized text, coordinates, display ID, or window title; unchanged generic failure code/message; and schema-1-through-schema-8 compatibility that decodes missing fields as `nil`
- Metadata-only schema-10 capture-terminal diagnostics with nine bounded failure sources and 21 public ScreenCaptureKit error categories; synchronous first-terminal-event acceptance across sample, delegate, inactive-stream, and start-failure paths; stale-operation rejection; reset on new start and manual stop; final-runner JSON retention; schema-1-through-schema-9, completed, and non-capture-failure compatibility; fail-closed normalization of missing, malformed, unknown, or inconsistent current-capture evidence; and exclusion of raw domains, numeric codes, descriptions, and `userInfo`
- Metadata-only schema-11 latest-content-revision evidence with exact ordinal, first retained qualifying-observation mach time, confirmation mach time, and five bounded sources; zero-count/no-event and nonzero-count/exact-interval consistency; fail-closed decoding for negative counts and missing, malformed, unknown, or inconsistent current-schema evidence; and schema-1-through-schema-10 compatibility that ignores an injected schema-11 event
- A limited LaunchServices check covering startup, argument forwarding, no Screen Recording permission request, fail-closed `screenRecordingUnavailable` reporting, and automatic exit; capture authorization and capture through LaunchServices remain unverified
- Strict exact PowerPoint Window-menu selection, exact-window focus, and slideshow safety probes, followed by a schema-8 dynamic attempt that received one new frame and two repeats before canvas invalidation and stopped before any scheduled slide or mouse input; that schema-8 attempt did not verify dynamic slides or mouse ink
- A pre-fix schema-9 live report that recorded `idleRepeatSurfaceGeometryUnavailableOrMismatched` after one new frame and two repeats, bounding the failure class without distinguishing absent from mismatched attachments; a later fixed-path diagnostic narrowly verified post-fix survival across 18 idle repeats
- Fixed-path schema-9 live evidence for visible synthetic mouse strokes and byte-identical visual restoration after erase: one five-stroke report recorded 65 new frames, 15 repeats, four content revisions, zero slide changes, and five connected components after ink; separate single-stroke and five-stroke reruns restored the image but did not record a distinct post-erase revision; the current decoder-hardened checkpoint below adds narrow schema-11 interval and single-stroke evidence but still does not verify semantic/per-input ink classification, existing-ink detection, or production canvas behavior
- A schema-9 static control and early aggregate failure retained as limiting evidence: the no-content-mutation control still recorded one revision, and schema 9 could not identify the aggregate terminal source
- A reviewed schema-11 exact-input helper with source SHA-256 `a91888a45f98414551bb96e6b38201e2faaa931f6462885f01024bdc9c319a2d` and saved arm64 binary SHA-256 `0910f1115b420443a8938111a296c4a16652bc258bd0c9a793813d98dc6f5ae3`; it requires each revision interval strictly after one input completion and before the next input start without a snapshot-time fallback, schedules six inputs eight seconds apart within 60 seconds, and passed GUI-free self-test repetitions, lint, Swift 6 strict type check, compilation, and independent review; the current dynamic and single-stroke runs add narrowly bounded end-to-end evidence for that exact helper, artifact, deck, and schedule
- A shared bounded one-shot fresh-sample path for either an exact post-baseline coarse candidate or a pending dense candidate: initial coarse-baseline collection is excluded; each episode obtains at most two actual samples roughly 100 milliseconds apart; typed candidate tokens plus strict capture-operation/exact-window/canvas/identity/stream guards and bounded provider-busy deferral reject stale or mismatched results; continuous-capture metrics, semantic identity, post-identity synchronization, and overlay provenance remain isolated; detector thresholds are unchanged, deterministic coverage passes, and the current live checkpoint did not exercise `boundedFreshSample`
- A fixed schema-11 interval app static report, SHA-256 `bbe4cb946125aa255c1dae3b77052cadfd3b63b330f22f4bd267c47b0b5bfbfd`, that recorded 117 snapshots, 3 new frames, 45 repeats, 1 stable frame, 1 instantaneous revision event, completed Vision analysis, unavailable semantic identity, and zero slide changes; this is diagnostic-full-frame, build-specific static and interval-metadata evidence only
- A retained four-second schema-11 six-input stress report, SHA-256 `310461032606b6bb7a5ffd9b7e6090eb78bd64b499be53500feac0754a14aad1`, that the strict helper rejected because the first post-baseline coarse revision interval crossed the next input boundary; this is bounded negative timing evidence, not six-input or coarse-fresh success
- A pre-decoder-hardening frozen coarse-fresh schema-11 app whose report SHA-256 `fdd52a2e132592236f9faba865537872289eb1b98de58d91c7aeb53047e8300e` verifies only saved-path execution, authorized preflight without a permission request, safe `windowNotFound`, report creation, and automatic exit; its first static checkpoint did not start while the console session was locked, while later unlocked static, six-input dynamic, and single-stroke results remain build-specific and must not be represented as live verification of the current decoder-hardened source
- Current decoder-hardened automated verification on the development Mac: 153 Core tests in 15 suites, 259 native app tests in 30 suites, and the complete 14-stage `make verify` gate; that gate is automated evidence rather than live behavior, while the separately frozen byte-identical artifact in the following bullets supplies the narrowly bounded live evidence
- A byte-identical current runtime preserved as `LectureBoard AI Schema 11 Decoder Hardened Verification.app`, executable SHA-256 `a6407496c7bd0044c3f30982e749a5556bd2b8e9a751ebd7ed476f59e9151cc9` and CDHash `7a60426b1fb628f6fd3dce9b1c3516092d5a799a`, with a fixed-path authorized preflight report at SHA-256 `36dce0ffe83c11edbfc3990b16eee645e608fb174777330131c453d766d376d8`
- A current decoder-hardened static report at SHA-256 `d018faf503ada46eefe0af0ac97f64cca7394cf690b6b2153b1614955ebc2a80` with helper sidecar SHA-256 `bd22de08bae4a7fafa3e4b37024b7eeca8b34f5184e0ddab3267075de47c02da`: 116 snapshots, 301 delivered frames including 2 new frames, 1 stable frame, zero revisions, and final Vision `completed`; the first orchestration stopped before runtime after detecting delayed slideshow-window reuse, one exact safe Escape was followed by a bounded disappearance timeout and passive exact editing recovery, and one bounded retry passed; this is fixed-build diagnostic-full-frame static evidence only
- A current decoder-hardened dynamic report at SHA-256 `c7a73f7cb1bdcaa46ec216218883872d480630f7cf4ff177170f8d1906c14a3c` with helper sidecar SHA-256 `5c7b0c73a8f059187f9319c2e681995e2e6a91042c5163bb821bf30bd37e488f`: 230 snapshots, 599 delivered frames including 15 new frames, 6 stable frames, and exactly 6 revision intervals for 6 inputs eight seconds apart, comprising 5 coarse-stream events and 1 `continuousDenseIdleRepeat`; final Vision completed, semantic identity remained unavailable, and `boundedFreshSample` was not exercised; the paired operator-captured sidecar supports input-window attribution for that artifact, deck, helper, and schedule but is not cryptographically bound to the runtime report and is not release-grade provenance
- A current decoder-hardened single-stroke report at SHA-256 `70e5772d5d4e8ab8947c725b854749fe2743b38f9189434530de2f0ad9aa63a1` with helper sidecar SHA-256 `518c60746850c40a6e428704eda2af834eaa95240b9efcb2d117ebf8f69c1aed`: 116 snapshots, 301 delivered frames including 27 new frames, 2 revisions, final Vision completed, a visible red line, and byte-identical before/after-erase images at SHA-256 `2dcc102c64a42bf50345e769c05528c16497a98ae60b9b421cc74324479e67f4`; the after-ink image SHA-256 is `e0dbffd2e02423e64efb119ac62d31ea25b9503981589c1940308c790b865c91`; this does not semantically classify ink or erase, detect existing ink, verify AI rendering, or verify a production or user-confirmed canvas
- Fail-closed production-overlay mapping from the confirmed output-pixel canvas through the exact current ScreenCaptureKit surface and `screenRect` into one uniquely containing AppKit display, bound to the capture operation, exact window, output dimensions, and current frame sequence, with no full-display or approximate fallback
- Production-overlay eligibility checks for the frozen PowerPoint process and bundle being frontmost, one matching on-screen layer-zero Core Graphics window, window-bound agreement within two points, and no earlier intersecting on-screen window, plus a persistent manual-hide latch, visual/content-unavailable hiding, and an independently expiring eligibility lease
- A separate full-display demo-overlay path that is never used as a production-coordinate fallback
- A privacy-bounded JSON and SVG session exporter containing only confirmed or pinned public board scenes, with consecutive same-slide coalescing, revisit preservation, new-capture reset, post-stop retention, and explicit exclusion of transcript, OCR text, images, window metadata, runtime identifiers, and non-public intents
- An authoritative no-fee `v1.0.0` build and packaging path for an arm64 hardened-runtime, ad hoc-signed application ZIP with exact entitlement verification, checksum, SBOM, commit-bound provenance, and public-download verification; this path makes no Developer ID or notarization claim

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
