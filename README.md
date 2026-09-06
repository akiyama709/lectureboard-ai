# LectureBoard AI

**A context-aware macOS companion intended to add concise text and diagrams to the unused space of live PowerPoint slides.**

LectureBoard AI is an open-source research and development project for university lectures and online teaching. It is intended to listen to a lecturer, observe the current slide, estimate what is educationally important from context, and render a restrained digital-ink annotation layer. The lecturer should not need to say commands such as “write this on the board.”

> Status: **pre-release development**. The current source implements a managed, windowed PowerPoint workflow that retains the exact Apple Event slide-show object, causally binds it to one ScreenCaptureKit window, reads exact slide IDs and indices, confirms a user-selected slide canvas, analyzes that crop, routes final local speech results through the grounded board engine, renders only confirmed output through a fail-closed overlay boundary, and exports public board scenes as JSON and SVG. These additions have deterministic Core and native-app coverage, including stale-callback, cancellation, restoration, identity, and export boundaries. They have not yet completed the release-artifact live workflow, so actual managed PowerPoint transitions, microphone input, user-canvas accuracy, visible overlay alignment, board usefulness, and release export remain explicitly unverified. Earlier schema-11 diagnostics are preserved as build-specific historical evidence and must not be generalized to this source. No application GitHub Release has been published.

> Completion means publication of the public, immutable, non-prerelease `v1.0.0` GitHub Release with exactly five attached assets: `LectureBoard-AI-v1.0.0-arm64.zip`, `LectureBoard-AI-v1.0.0-test-results.json`, `SBOM.spdx.json`, `SHA256SUMS`, and `provenance.json`. They must bind the verified arm64 application archive to the exact source commit and pass unauthenticated public-download verification. Release notes belong in the Release body, not a sixth asset. The project uses no paid or institutional Apple Developer membership, so the final archive will be ad hoc signed and explicitly not Developer ID signed or Apple notarized. No alpha, beta, or release-candidate application Release will be published. See the [no-fee release process](docs/no-fee-release-process.md), [`ROADMAP.md`](ROADMAP.md), and [ADR 0013](docs/adr/0013-no-fee-public-v1-distribution.md).

## Design principles

- **Context before commands.** Importance is inferred from slide content, recent speech, novelty, repetition, discourse structure, emphasis, and the existing board.
- **Grounded output.** The app should not add facts that are absent from the slide, speaker notes, or transcript.
- **Stable board.** Confirmed annotations remain still so students can read and take notes.
- **Human priority.** Existing PowerPoint ink and the lecturer’s pen input always take precedence over AI annotations.
- **Local-first architecture.** Cloud providers are optional adapters, not hard-coded dependencies.
- **Japanese and English first.** These are initial target languages; the data model uses BCP 47 language tags and is designed for multilingual extension.

## Initial platform scope

- macOS 26 or later
- Apple silicon first
- Microsoft PowerPoint for Mac
- Target presentation environments, not yet runtime-verified: Zoom, Microsoft Teams, Google Meet, and classroom projection
- Target languages: Japanese, English, and a staged path toward Japanese–English code-switching

Focusing on one operating system is deliberate. Screen capture, transparent overlays, privacy permissions, live audio, and pen-tablet behavior are deeply platform-specific. The project will establish a dependable macOS experience before considering other platforms.

## Implemented in the current source

- A native SwiftUI/AppKit application shell
- Screen-capture permission checking
- Discovery of visible PowerPoint windows with ScreenCaptureKit
- A compiled selected-window ScreenCaptureKit stream with stable-snapshot preview
- Fail-closed binding of the selected ScreenCaptureKit window ID, owning process ID, and exact PowerPoint bundle identifier through capture start
- Deterministic coarse luminance fingerprints and stable-frame/significant-visual-change classification
- Persistent content-update detection from dense 160-by-90 RGB fingerprints
- A shared bounded one-shot fresh-sample path for either an exact post-baseline coarse candidate or a pending dense candidate; initial coarse-baseline collection is excluded, each episode may request at most two actual samples roughly 100 milliseconds apart, and the same typed opaque detector token plus exact capture/window/canvas/identity/stream provenance is required; provider-busy deferral is bounded, and one-shot results never count as continuous deliveries, post-identity synchronization frames, or overlay-coordinate sources; deterministic tests pass, while the frozen 2026-09-01 live PowerPoint checkpoint did not exercise `boundedFreshSample`
- A user-confirmed slide-canvas boundary because public macOS and PowerPoint APIs do not expose the exact internal slide rectangle: the user drags around the visible slide on a frozen exact-window preview and confirms it explicitly
- Fail-closed binding of that confirmation to the capture operation, exact window ID, source pixel dimensions, and validated ScreenCaptureKit surface geometry, with invalidation after restart, mismatch, missing usable geometry after applying the narrow idle policy below, or geometry change
- Provisional idle-surface application policy, not an Apple guarantee: only for a verified `.idle` delivery with all three surface keys—`contentRect`, `scaleFactor`, and `contentScale`—absent, the app reuses the previously latched surface geometry to crop the unchanged visual payload; a complete current tuple is accepted only when it exactly matches that geometry; partial, malformed, conflicting, or non-idle evidence, missing prior geometry, and prior output dimensions that do not match the payload all fail closed and poison repeat geometry until a later `.new` frame; screen position is independent—a valid current `screenRect` wins, a present malformed value fails closed, and only an omitted key may carry forward the prior validated rectangle as a candidate that still needs a fresh exact-window eligibility match; one controlled fixed-path schema-9 diagnostic survived 18 live idle repeats, but the raw attachment form, idle-key omission, visible overlay, and behavior across other PowerPoint modes remain unverified
- Fail-closed ScreenCaptureKit status and continuity handling: only `.complete` and `.started` are new deliveries and only `.idle` is a repeat; missing, malformed, unknown, `.blank`, and `.suspended` statuses, invalid samples, and conversion failures clear repeatable content and require a later `.new` frame before visual processing resumes; `.stopped` is terminal; surface scale factor is accepted only in the SDK-documented inclusive range from 1 through 4
- A cropped visual pipeline in which stable/content fingerprints, Vision requests, raster candidates, occupied regions, and board-placement input are produced only from the confirmed canvas; before confirmation, only capture-delivery metrics advance
- Immediate invalidation of old analysis for coarse or dense visual candidates and for missing or invalid dense fingerprints; a confirmed coarse frame without a valid dense fingerprint does not start analysis, and baseline recovery remains closed to proposals until current-frame analysis completes
- Rejection of canvas rectangles smaller than 32 by 24 source pixels or 1,024 square pixels, plus a current-board-context boundary that prevents pre-boundary transcripts from being proposed after a semantic slide, canvas, or capture reset
- Fail-closed transcript-driven placement when visual analysis has no occupied regions, even if the analysis request itself completed
- Capture-end cleanup of the latest stable frame, analysis, and board scene
- A compiled Vision text/rectangle analyzer that runs on confirmed stable visual frames and content updates
- A native RGB raster path capped at a 640-pixel long edge, with deterministic `strokeCandidateRegions`
- Deterministic filtering, padding, and merging of normalized occupied regions across text, rectangles, and stroke candidates
- Capture-monitor counts and an occupied-region preview overlay
- A deterministic independent slide-identity tracker that requires two consecutive matching samples, discards continuity across interruptions, and does not infer transitions across presentation sessions
- An explicit managed slide-show transaction that retains the exact PowerPoint object returned by the start command, accepts only windowed slide-show mode, causally identifies one exact ScreenCaptureKit window by a reversible role challenge, restores the challenged state, and keeps the object, capture lease, and cleanup receipt alive until bounded cleanup completes; all other presentation modes and ambiguous evidence fail closed
- A managed PowerPoint identity provider that reads the exact slide ID and index from that retained object, rejects stale session, sequence, target, role, and capture evidence, and activates the App binding before polling can begin; this implementation has deterministic tests but no successful live managed-session evidence yet
- An app-side identity-provider boundary that rejects wrong-target, wrong-session, and out-of-order observations; excludes candidate-period frames from visual analysis after delivery metrics are recorded; clears old analysis and board scenes at confirmed boundaries; and resumes analysis only for a `.new` frame whose ScreenCaptureKit `displayTime` is strictly later than the app's local mach-absolute acceptance time for the confirming observation
- A local speech-result boundary that rejects final transcript results emitted before an identity boundary, before the app locally accepts the post-boundary frame, or while the app is still waiting for that frame
- Independent App and Apple-provider transcription generation guards; semantic-slide and temporary capture-content boundaries stop the current speech operation, reject old callbacks, and automatically resume a still-requested session only after current identity, canvas, frame synchronization, and visual analysis are ready; a manual stop, manual canvas boundary, or capture end cancels that request; live microphone behavior remains unverified
- A token-bound post-identity frame gate that exposes waiting, synchronized, and timed-out states; timeout remains fail-closed, and a later strictly newer `.new` frame can recover the gate
- A metadata-only schema-11 runtime-verification path: schema 6 adds slide-canvas state, schema 7 adds overlay-mapping state and fail-closed rejection reasons without coordinates or display identifiers, schema 8 distinguishes explicit `diagnosticFullFrame` confirmation from no diagnostic request, schema 9 adds bounded canvas-failure reasons, schema 10 adds nine bounded capture-failure sources plus 21 public `SCStreamError.Code` categories, and schema 11 adds a bounded latest-content-revision event with ordinal, first qualifying observation mach time, confirmation mach time, and one of five sources; a zero revision count requires no event, every nonzero current-schema count requires a matching nonzero non-reversed interval, and negative, malformed, unknown, missing, or inconsistent schema-11 evidence fails decoding; historical schema-1 through schema-10 reports remain decodable and ignore an injected schema-11 event; reports store no captured image, recognized text, coordinates, display ID, window title, raw error domain, raw numeric code, description, or `userInfo`
- ScreenCaptureKit `screenRect` parsing that accepts only validated rectangle representations and permits negative global display origins; a verified idle repeat uses its own valid current value, fails closed on a present malformed value, or—only when the key is absent—carries forward the prior validated rectangle as a candidate that cannot authorize display unless an independent current exact-window check still matches it
- A deterministic overlay mapper bound to the capture operation, exact window, exact surface geometry, output dimensions, and current frame sequence; it maps the confirmed crop through `contentRect`, `scaleFactor`, `contentScale`, and the frame-carried validated screen-position candidate, converts one unambiguous containing display from Quartz to AppKit coordinates, and otherwise hides the production overlay; a candidate carried through verified idle-key omission still requires a fresh exact-window bounds match before display
- A click-through transparent overlay window prototype that can render into the mapped production rectangle only after confirmed semantic identity and current visual grounding; frontmost exact-PowerPoint ownership, one exact layer-zero on-screen window, two-point edge agreement, front-to-back occlusion, manual suppression, content-unavailable and visual-change invalidation, focus and Space events, and an independently expiring lease all fail closed; the safe default unavailable identity provider cannot show production output; deterministic synthetic and app-integration tests cover these branches, but not live PowerPoint alignment or z-order
- A demo-scene boundary that clears demo content at capture start and disables demo generation while capture is active or capture-provider shutdown is in progress
- A deterministic public-scene boundary that composes only confirmed or pinned intents; proposed, deferred, and dismissed intents stay internal, and an unchanged public scene does not advance the board-scene generation or invoke overlay eligibility or rendering
- A selectable Japanese or English Apple Speech recognizer that requires supported on-device
  recognition and fails closed instead of sending lecture audio over the network; it rolls bounded
  eight-second recognition cycles, permits at most four seconds for each final result, preserves a
  bounded audio tail across cycles, applies bounded restart backoff, and exposes transcription state
  separately from application state; these paths have deterministic tests, while live microphone
  behavior remains unverified
- A privacy-bounded lecture-session exporter that writes public confirmed/pinned board scenes as JSON plus a sibling SVG, coalesces consecutive updates on one slide, preserves later revisits, and excludes transcript, OCR text, images, window metadata, runtime identifiers, and non-public intents; deterministic export and App integration tests pass, while a live release-artifact export remains unverified
- A pure-Swift `LectureBoardCore` package containing:
  - transcript and slide-context models
  - contextual importance scoring
  - grounded board-intent classification
  - vector board-scene models
  - empty-region layout planning
  - unit tests
- Japanese and English UI resources
- GitHub Actions core CI, issue templates, security policy, contribution guide, architecture decisions, and citation metadata

## What is not yet claimed to work

- Reliable recognition of Japanese and English within the same utterance
- Parsing every PowerPoint object and speaker note
- Live acquisition of actual PowerPoint slide identity through the implemented managed provider and validation against live transitions
- Automatic exact-window fresh-frame acquisition when a static slide produces only idle repeats after an identity boundary; explicit fail-closed timeout state is implemented and tested, but remains live-unverified with a production identity provider
- Reliable visual/content-update behavior across representative transitions and animations
- Live capture-failure classification introduced by schema 10 and retained by schema 11; its first-terminal-event routing, stale-operation rejection, reset behavior, normalization, privacy boundary, and final-JSON retention currently have automated coverage only
- Semantic and per-input same-slide mouse-ink or erase classification, existing-ink detection, and inspection of PowerPoint's internal ink state; the frozen 2026-09-01 decoder-hardened single-stroke diagnostic verifies only a visible red line, two aggregate visual revision events in separate ink and erase phases, and byte-identical visual restoration after erase
- Successful live `boundedFreshSample` confirmation through the shared exact-post-baseline-coarse or pending-dense one-shot path; the frozen 2026-09-01 live runs used only continuous sources, and the detectors still require three matching qualifying observations without weakened thresholds
- LaunchServices capture authorization, window reselection, and lecture-length reliability of continuous PowerPoint capture; a limited startup/arguments/no-request/fail-closed-report/automatic-exit check has passed, but it did not capture a window
- OCR correctness and coordinate accuracy of Vision text, rectangle, and occupancy analysis across representative decks
- Live accuracy of manual slide-canvas localization and PowerPoint-control exclusion across presentation modes, window sizes, displays, and representative decks; ScreenCaptureKit surface padding and `contentRect` mapping are also unverified
- Classifying raster stroke candidates as existing PowerPoint ink
- Robust empty-space segmentation on arbitrary slide designs
- Production-grade diagram generation
- Runtime microphone transcription, click-through overlay behavior, exact slide-canvas overlay alignment, and AI board rendering during a lecture; the coordinate path is implemented and deterministically tested, but its `screenRect` assumptions, visual accuracy, display behavior, z-order, and input non-interference remain live-unverified
- Cloud or local large-language-model integration
- Hardened-runtime, ad hoc-signed arm64 distribution with checksums, content-free test evidence, SBOM, provenance, and Apple's per-application Open Anyway instructions

These are tracked in [`ROADMAP.md`](ROADMAP.md).

## Repository layout

```text
lectureboard-ai/
├── LectureBoardAI/                 # Native macOS application
├── Packages/LectureBoardCore/      # Platform-neutral models and logic
├── docs/                           # Requirements, architecture, privacy, ADRs
├── .github/                        # CI and issue templates
├── project.yml                     # XcodeGen project specification
└── Makefile
```

The documentation index is available at [`docs/README.md`](docs/README.md). Current verification limits are recorded in [`docs/build-verification.md`](docs/build-verification.md), and the exact evidence, packaging, and unauthenticated public-verification commands are in the [no-fee release process](docs/no-fee-release-process.md). Installation and first-lecture procedures are in the [English user guide](docs/user-guide.md) and [Japanese user guide](docs/user-guide-ja.md); the owner's required private-deck check is a separate [pre-publication acceptance](docs/user-acceptance-ja.md) and is still unperformed.

## Build

### Requirements

- macOS 26+
- Xcode 26+
- XcodeGen 2.46.0 (the locally verified version)

```bash
git clone https://github.com/akiyama709/lectureboard-ai.git
cd lectureboard-ai
make bootstrap
make test-core
make test-app
make build
make build-runtime
open LectureBoardAI.xcodeproj
```

`make build` is a compile-and-link check with code signing disabled; it does not produce the runtime artifact used for native behavior claims. `make test-app` runs the native app unit tests with local ad hoc signing. `make build-runtime` produces an arm64 Debug app with local ad hoc signing for controlled runtime checks. Ad hoc signing is neither Developer ID distribution signing nor notarization, and rebuilding can change the app's code identity even when its name and bundle identifier remain the same. macOS may therefore require Screen Recording permission again after a rebuild.

Direct executable runs under the Codex-authorized environment and an independently launched app through LaunchServices are separate verification paths. A limited LaunchServices check has verified startup, argument forwarding, no Screen Recording permission request, a `screenRecordingUnavailable` fail-closed report, and automatic exit. It did not verify Screen Recording authorization or any capture through LaunchServices. The public CI currently runs only the platform-neutral Core tests.

Two controlled dynamic reports remain as build-specific historical evidence. A schema-1 build recorded 372 frames and 5 image-difference events in the legacy `slideChangeCount` field. A later schema-2 but pre-semantic-correction build recorded 373 frames, the same 5 legacy heuristic events, and 2 content revisions; that report has SHA-256 `704d9266bf1564161dd756a0be57c4a47d5459dfb9c9ae5cf0c103acc8320f41`. Neither report verifies slide identity or the current semantic build, and neither should be interpreted as five independently identified slide transitions.

Schema 3 established the corrected meaning in which image differences are content revisions rather than slide identity. Schema 4 added identity state and counters, schema 5 added post-identity frame-sync state, schema 6 added slide-canvas state, schema 7 added metadata-only overlay-mapping state and rejection reasons, schema 8 added confirmation provenance, and schema 9 added bounded canvas-failure reasons. Schema 10 added nine bounded `captureFailureSource` values and 21 public `captureSCStreamErrorCode` values. A synchronous first-event gate prevents concurrent terminal callbacks from replacing one another; new starts and manual stops reset the telemetry, and stale operations are rejected. Missing, malformed, unknown, or inconsistent current-capture evidence normalizes to `unclassifiedCaptureFailure`. Schema 11 is the current source format and adds `latestContentRevisionEvent`: a matching revision ordinal, the first retained qualifying observation's mach-absolute time, the confirmation mach-absolute time, and one of five bounded sources. A zero current-schema count must have no event, every nonzero count must have a matching nonzero and non-reversed interval, and negative, missing, malformed, unknown, or inconsistent schema-11 evidence fails decoding. Historical schema-1-through-schema-10 reports remain decodable and ignore an injected schema-11 event. Reports retain no raw domain, numeric code, description, or `userInfo`, in addition to the existing image, text, coordinate, display, and title exclusions. Automated schema-11 tests pass, and the frozen 2026-09-01 decoder-hardened checkpoint produced the narrowly bounded live metadata reports described below. Those reports do not provide live semantic PowerPoint identity, bounded-fresh sampling, user-confirmed canvas accuracy, visible overlay alignment, or production rendering evidence for the later release tree.

The synchronized 2026-09-01 decoder-hardened automated gate result is `DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult`; its ad hoc arm64 runtime executable has SHA-256 `a6407496c7bd0044c3f30982e749a5556bd2b8e9a751ebd7ed476f59e9151cc9` and CDHash `7a60426b1fb628f6fd3dce9b1c3516092d5a799a`. The byte-identical executable is preserved separately as `LectureBoard AI Schema 11 Decoder Hardened Verification.app`. Automated-gate evidence and the fixed-path live evidence below remain distinct historical claims, even though they use the same executable bytes.

The fixed schema-8 evidence app completed one five-second direct-executable static diagnostic against exact PowerPoint window ID 13577 without requesting Screen Recording permission. It recorded 53 new frames, one stable frame, completed Vision analysis, `diagnosticFullFrame`, confirmed canvas state, metadata-only overlay state `mapped`, and identity `unavailable`, with zero content revisions and zero slide changes. This remains narrow build-specific evidence for direct exact-window static capture and metadata production only. The full captured window was confirmed automatically for diagnostics; no user-confirmed slide canvas or production overlay was rendered or visually aligned.

A strict helper subsequently selected the exact PowerPoint document through its unique Window menu item and passed exact-window focus and slideshow safety probes without adopting a weaker name-, order-, or approximate-geometry fallback. In a schema-8 attempt, the runtime received one new frame and two repeats, invalidated the diagnostic canvas, and stopped after about 535 milliseconds before the first scheduled slide or mouse input. This is historical fail-closed evidence, not verification of dynamic slides or same-slide mouse ink.

The later controlled schema-9 fixed-path report `LectureBoard-Runtime-Schema9-IdlePolicy-Dynamic-2026-08-31.json`, SHA-256 `390bee97a34dbde9dc434f876cdf2b05c0a4836effd0d36b528e6231db3ca7e2`, completed approximately 40.5 seconds with 154 snapshots and 33 delivered frames: 15 new frames plus 18 idle repeats. The first snapshot already recorded 1 new frame and 2 repeats with the diagnostic canvas confirmed, and the canvas remained confirmed in all 154 snapshots. The run reached 4 stable frames and four controlled inputs correlated with four content revisions. Maximum analysis counts were 11 recognized-text observations, 13 rectangles, 37 stroke candidates, and 11 occupied regions. Semantic identity remained unavailable and slide changes remained zero. Overlay mapping succeeded zero times: 7 snapshots reported `screenGeometryUnavailable` and 147 reported `canvasOutsideCapturedContent`. This narrowly verifies post-fix idle survival and visual content updates, not semantic slide transitions, OCR or coordinate correctness, a user-confirmed canvas, visible alignment, or production rendering.

The controlled fixed-path schema-9 report `LectureBoard-Runtime-Schema9-MouseInk-2026-09-01.json`, SHA-256 `534a285e8f3830891c374746338aa361ab9ebf15cf1f4b199e686d1166b17cb7`, ran for 20 seconds and recorded 78 snapshots, 65 new frames, 15 repeats, four content revisions, and zero slide changes. Its before and after-erase images were byte-identical, while the after-ink image contained five connected components. This verifies visible mouse strokes and visual erase restoration only. A single-stroke run, SHA-256 `494eb356282f8c49c9a57d7d67ec2e56cb31a22326da69d373b556f047332d45`, and a five-stroke rerun, SHA-256 `7cadc164d28f534fe3620261eb26b14c20d7694b16216629d940d1c5e9870385`, also restored the image but did not record a separate post-erase revision. The detector contract remains `0.08` difference threshold, `0.001` changed-pixel fraction, zero persistence tolerance, and three matching qualifying observations. Thresholds were not weakened. The current source implements the shared bounded fresh-sample path for an exact post-baseline coarse candidate or a pending dense candidate with strict provenance and stale-result guards. Deterministic tests pass, and a later 2026-09-01 fixed checkpoint continuous path recorded a separate erase-phase revision, but live `boundedFreshSample` attachment and timing behavior, coarse one-shot confirmation, and semantic ink or erase classification remain unverified.

The schema-9 live audit also retains three important negative or limiting results. An early aggregate failure report, SHA-256 `44ed13c6b338a48fe5c92290c47a0ea8ae4fb105590ddddfa65a6a3d421eb5db`, stopped after approximately 12.068 seconds with 44 new frames, 16 repeats, and three revisions, but schema 9 did not preserve its terminal source. A 30-second no-content-mutation static control, SHA-256 `60deb22f7c3561ed2c4b105ea69c0a9e5f196a6d5b7f6c42e6f23eb399b8c0fc`, still recorded one content revision and is not false-positive-free evidence. The consolidated metadata audit has SHA-256 `a547704072066e63047abaffc8e4bec0149be39760901e852236158d103ceff2`, and the image audit has SHA-256 `38552053c77b46d6a9eccb0cbde8f1baeef6faadf74bee9f57247e8e110d95a9`.

The fixed schema-11 interval app completed a 30-second exact-window static diagnostic. `LectureBoard-Runtime-Schema11-Interval-Static-2026-09-01.json`, SHA-256 `bbe4cb946125aa255c1dae3b77052cadfd3b63b330f22f4bd267c47b0b5bfbfd`, records 117 snapshots, 48 frames (3 new and 45 repeats), 1 stable frame, 1 instantaneous `continuousDenseIdleRepeat` revision event, completed Vision analysis, unavailable semantic identity, and zero slide changes. This is build-specific diagnostic-full-frame static and interval-metadata evidence only. A six-advance stress run at four-second intervals, `LectureBoard-Runtime-Schema11-Interval-Dynamic-4s-Stress-Failed-2026-09-01.json`, SHA-256 `310461032606b6bb7a5ffd9b7e6090eb78bd64b499be53500feac0754a14aad1`, reached only one baseline plus five post-baseline revisions. The first post-baseline coarse interval crossed the second input boundary, so the strict helper rejected the run. This is bounded negative timing evidence, not six-input or current coarse-fresh success.

The coarse-fresh app frozen before the negative-count decoder correction is `LectureBoard AI Schema 11 Coarse Fresh Verification.app`; its executable SHA-256 is `d829b0fdc01df309657e75afa348c36491b073d2f05b505d878a9021ce15f11e`. Its impossible-title report `LectureBoard-Runtime-Schema11-CoarseFresh-FrozenApp-Preflight-2026-09-01.json`, SHA-256 `fdd52a2e132592236f9faba865537872289eb1b98de58d91c7aeb53047e8300e`, verifies only saved-path execution, authorized preflight without a permission request, safe `windowNotFound`, report creation, and automatic exit. Its first static checkpoint did not start while the console session was locked; no capture, input, or report occurred in that attempt. After unlock, the same older artifact completed build-specific static, six-input dynamic, and single-stroke diagnostics recorded in `docs/build-verification.md`. Those later results remain specific to its pre-decoder-hardening bytes and do not verify the current source.

The frozen 2026-09-01 decoder-hardened app's fixed-path preflight report has SHA-256 `36dce0ffe83c11edbfc3990b16eee645e608fb174777330131c453d766d376d8`. Its first static orchestration attempt stopped before runtime launch because a delayed slideshow window was reused; one exact safe Escape was sent, the bounded Core Graphics disappearance check timed out, and the helper then passively observed exact editing-window recovery. One bounded retry completed without broad or repeated input. The retained static report has SHA-256 `d018faf503ada46eefe0af0ac97f64cca7394cf690b6b2153b1614955ebc2a80` and its helper sidecar has SHA-256 `bd22de08bae4a7fafa3e4b37024b7eeca8b34f5184e0ddab3267075de47c02da`; it records 116 snapshots, 301 delivered frames including 2 new frames, 1 stable frame, zero content revisions, and final Vision state `completed`. This is exact-window, diagnostic-full-frame, fixed-build static evidence only.

The frozen 2026-09-01 decoder-hardened six-input dynamic report has SHA-256 `c7a73f7cb1bdcaa46ec216218883872d480630f7cf4ff177170f8d1906c14a3c` and its helper sidecar has SHA-256 `5c7b0c73a8f059187f9319c2e681995e2e6a91042c5163bb821bf30bd37e488f`. It records 230 snapshots, 599 delivered frames including 15 new frames, 6 stable frames, and exactly 6 revision intervals after 6 inputs spaced eight seconds apart. Five events were coarse-stream confirmations and one was `continuousDenseIdleRepeat`; final Vision state was `completed`, semantic slide identity remained unavailable, and `boundedFreshSample` was not exercised. Paired with the operator-captured helper sidecar, this supports input-window visual-revision attribution for that controlled build and schedule only. The sidecar is not cryptographically bound to the runtime report and is not release-grade provenance; the result does not verify semantic slide transitions or the live bounded-fresh path.

The frozen 2026-09-01 decoder-hardened single-stroke report has SHA-256 `70e5772d5d4e8ab8947c725b854749fe2743b38f9189434530de2f0ad9aa63a1` and its helper sidecar has SHA-256 `518c60746850c40a6e428704eda2af834eaa95240b9efcb2d117ebf8f69c1aed`. It records 116 snapshots, 301 delivered frames including 27 new frames, 2 content revisions, and final Vision state `completed`. A red line was visibly present after input; the before and after-erase images are byte-identical with SHA-256 `2dcc102c64a42bf50345e769c05528c16497a98ae60b9b421cc74324479e67f4`, while the after-ink image has SHA-256 `e0dbffd2e02423e64efb119ac62d31ea25b9503981589c1940308c790b865c91`. This verifies visible mouse input and visual restoration for that controlled run only. It does not classify the revisions semantically as ink or erase, verify existing-ink detection, AI rendering, a production or user-confirmed canvas, or per-input board semantics.

The latest reviewed ignored schema-11 helper source has SHA-256 `a91888a45f98414551bb96e6b38201e2faaa931f6462885f01024bdc9c319a2d`; the saved reviewed arm64 binary `DriveExactPowerPointInk-Schema11-MachIntervals-Reviewed-2026-09-01` has SHA-256 `0910f1115b420443a8938111a296c4a16652bc258bd0c9a793813d98dc6f5ae3`. It requires each schema-11 revision interval to fall strictly after one input completes and before the next starts, uses no snapshot-time fallback, and schedules six inputs eight seconds apart within a 60-second observation. Its GUI-free self-test, repeated checks, lint, Swift 6 strict type checking, compilation, and independent review passed; the dynamic and single-stroke runs above add narrowly bounded end-to-end evidence for that exact helper, artifact, deck, and schedule. A separate limited LaunchServices run verified startup, arguments, no permission request, a `screenRecordingUnavailable` report, and automatic exit only; capture authorization was not verified. The managed identity adapter is now implemented and deterministically tested, but its live execution remains unverified together with microphone behavior, manual canvas localization, visible overlay alignment and rendering, z-order, resizing, and click-through behavior. Multiple displays are outside the v1 support contract.

## Continue development locally with ChatGPT Codex

The repository includes `AGENTS.md`, conservative project-scoped Codex settings in `.codex/config.toml`, a local toolchain diagnostic, and a Japanese handoff document. On the Mac that will run the prototype:

```bash
make doctor
make local-setup
make open
make codex
```

Then open this repository as a local folder in **Codex** in the ChatGPT desktop app and begin with [`docs/local-codex-handoff-ja.md`](docs/local-codex-handoff-ja.md). Regular ChatGPT history and Codex history are separate, so the repository documents are the durable project context.

## Test only the platform-neutral core

```bash
swift test --package-path Packages/LectureBoardCore
```

## Privacy

Lecture audio and slide content may contain unpublished research, personal information, or student contributions. The architecture therefore separates capture, transcription, contextual reasoning, and rendering through provider protocols. No API key or lecture data is committed to the repository. See [`docs/privacy-and-security.md`](docs/privacy-and-security.md).

## Contributing

Contributions are welcome after the initial architecture stabilizes. Please read [`CONTRIBUTING.md`](CONTRIBUTING.md) and open an issue before starting a large architectural change.

## License

MIT License. See [`LICENSE`](LICENSE).

Microsoft PowerPoint and other product names are trademarks of their respective owners. This project is independent and is not affiliated with or endorsed by Microsoft, Apple, Zoom, Google, or OpenAI.

---

<a name="日本語"></a>
## 日本語

　**LectureBoard AIは，PowerPointを用いた講義中に，スライドの空いた領域へ文字や図形を自動板書することを目指す，macOS向けオープンソース研究試作です．**

　講師が「ここを板書してください」などの命令を発することなく使える構成を目指します．現在のスライド，発表者ノート，直前までの発話，反復，対比，因果関係，定義，発話上の強調，既存板書などから，何を学生に残すべきかを文脈的に判断する設計です．

　現段階は公開前の開発中です．現行sourceには，PowerPointが返した正確なslide-show objectを保持し，可逆的なrole challengeによって1件のScreenCaptureKit windowへ因果的に結び付け，そのobjectから正確なslide ID・indexを読むmanaged workflowを実装しました．利用者確認式canvas，局所Vision解析，final音声のgrounded board engineへの接続，fail-closed overlay，及び公開board sceneだけを保存するJSON／SVG exportも実装済みです．これらには決定論的testがありますが，現行release artifactによるmanaged PowerPoint遷移，microphone，canvas精度，可視alignment，板書の有用性及びexportの一連の実機動作はまだ未検証です．過去のschema 11診断はbuild固有の履歴証拠として保持し，現行sourceの成功へ一般化しません．application GitHub Releaseはまだ公開していません．

　公開macOS及びPowerPoint APIは内部の正確なスライド面矩形を公開しないため，利用者が正確な取得windowの静止preview上で表示中のスライド面を囲み，明示的に確定します．確定結果はcapture operation，正確なwindow ID，source pixel寸法及び検証済みScreenCaptureKit surface geometryへ固定し，再取得，不一致，下記の限定idle policy適用後も利用可能なgeometryがない場合，又はgeometry変更時に無効化します．切出しは幅32 pixel，高さ24 pixel及び面積1,024平方pixelを全て満たす必要があります．確定前はdelivery件数だけを記録し，確定後は切出し画像だけから全ての視覚指紋及び解析入力を生成します．

　overlay位置は，surface geometryとは別に，検証済みScreenCaptureKit `screenRect`候補から求めます．verified idle repeatでは，そのsample自身の有効な`screenRect`を優先し，keyが存在するのに不正ならfail closedとします．key自体が欠落する場合に限り，直前の検証済み矩形を候補として引き継ぎます．ただし，この候補だけでは表示できず，production eligibilityがfrontmostの正確なPowerPoint PID・bundle，1件だけのon-screen layer 0 exact window，その時点のCore Graphics boundsとの各辺2 point以内の一致及び手前の重複window不在を毎回独立に検査します．したがって，移動，resize，focus喪失，window消失又はocclusion後に古い位置だけで表示若しくはlease更新を許可しません．確認済み切出しは`contentRect`，`scaleFactor`，`contentScale`及び当該候補へ対応付け，対象を完全に含むdisplayが一意である場合だけQuartz座標からAppKit座標へ変換します．operation，window，surface，出力寸法若しくはframeが一致しない場合，又は位置証拠が欠落・矛盾・曖昧である場合は，production overlayだけを非表示にします．意味的slide identityとcurrent visual groundingも必須であり，明示的な非表示，content unavailable，視覚変化，focus・Space変更及びcapture cadenceから独立したlease失効でも閉じます．既定identity providerは`unavailable`であるためproduction表示を許可しません．これらは合成geometry及び制御可能なApp統合testで確認した実装証拠であり，実PowerPoint上の見た目の一致，idle時のkey欠落又はz-orderを確認した結果ではありません．

　idle surfaceの扱いはAppleが保証する仕様ではなく，暫定的なapplication policyです．検証済み`.idle`で`contentRect`，`scaleFactor`及び`contentScale`の3 keyが全て欠落する場合だけ，直前にlatchしたsurface geometryを不変のvisual payloadの切出しへ再利用します．3 keyが全て揃う場合は，直前geometryとの完全一致をcurrent geometryとして受理します．一部欠落，不正形式，矛盾，non-idle，直前geometry欠落，又は直前output寸法とpayload寸法の不一致はfail closedとし，後続の`.new` frameまでrepeat geometryのpoisonをlatchします．`screenRect`は上記の独立した候補規則を適用し，key欠落時の引継ぎだけでは表示を許可しません．`.complete`・`.started`だけをnew，`.idle`だけをrepeatとして扱います．`SCFrameStatus`の欠落，不正形式，未知値，`.blank`及び`.suspended`，不正sample並びに変換失敗はrepeat可能なpayloadを破棄し，Appへcontent unavailable境界を通知して，後続の`.new` frameまで視覚・板書経路を閉じます．`.stopped`は固定文言のterminal capture errorです．`scaleFactor`はSDK文書の範囲である1以上4以下だけを受理します．修正前reportは限定された失敗理由を確認し，修正後の固定path診断では18件のlive idle repeatを越えてcanvasが維持されました．ただし，実attachment形状，key欠落時の可視overlay及び他のPowerPoint modeへの一般化は未検証です．

　粗い視覚差分又はdense内容更新が候補状態へ入った時点，若しくはdense fingerprintが欠落・不正となった時点で旧解析を無効化します．valid dense fingerprintのないcoarse confirmed frameでは解析を開始せず，baseline復帰後もcurrent frameの再解析完了まで板書提案を閉じます．意味的なslide，canvas又はcapture境界では旧発話と板書候補を新しい文脈で再提案せず，占有領域が空の解析結果も板書配置を許可しません．提案状態は内部に保持し，公開board sceneへは`confirmed`又は`pinned`だけを追加します．公開sceneが変わらないproposedだけではgeneration更新，overlay判定又は描画を起動しません．この境界は決定論的testで確認済みであり，live board renderingの証拠ではありません．capture終了時には最新安定frame，解析及び板書sceneを消去します．capture開始時にはdemo sceneを消去し，capture中又はcapture provider停止処理中はdemo生成を許可しません．

　初期coarse baselineを除く正確なpost-baseline coarse候補又はpending dense内容更新候補が連続streamだけでは確定しない場合，現行sourceは候補種別付きの同じopaque candidate tokenへ限定して，最大2回のone-shot sampleを約100 ms間隔で取得できます．capture operation，正確なwindow identity，canvas，slide identity及びstream anchorのいずれかが変われば結果を拒否し，provider busyも最大10回の再待機で終了します．one-shot sampleを通常delivery件数，semantic identity，post-identity同期又はoverlay座標根拠へ流用せず，fresh sampleだけで完了した解析からoverlayを再表示しません．これらはCore及びAppの決定論的testで確認済みですが，実PowerPointにおける`boundedFreshSample`のstatus・geometry attachment，取得timing及びone-shot確定は未検証です．現行continuous経路では別個の消去phase revisionを確認しましたが，意味的又は入力ごとのink／erase分類，既存ink検出及びAI renderingの証拠ではありません．

　文字起こしはAppとApple providerの二重generation guardを用います．端末内認識を8秒以内のcycleで更新し，各cycleのfinalを最大4秒待ち，次cycleへ渡す音声tail，callback queue及び再開backoffを有界に保ちます．意味的slide又は一時的なcapture-content境界では現在のoperationと旧callbackを無効化し，利用者が開始したsessionを，正確なidentity，canvas，post-boundary frame同期及びcurrent解析が揃った後だけ自動再開します．手動停止，手動canvas境界及びcapture終了では再開要求も取り消します．これらは決定論的testの結果であり，実microphoneの連続認識又は講義中の可視板書を検証したものではありません．managed production identity providerは実装済みですが，実PowerPointでの動作は未検証です．schema 6はcanvas状態，schema 7はoverlay mapping状態及び拒否理由，schema 8は確認provenance，schema 9はcanvas失敗理由，schema 10は9種類の`captureFailureSource`及び21種類の公開`captureSCStreamErrorCode`を追加します．schema 11は最新revisionのordinal，最初のqualifying observationのmach時刻，確定mach時刻及び5種類の限定sourceを追加します．現行schemaではcount 0にeventがあってはならず，正数countにはordinalが一致する非zero・非逆転intervalが必要です．負数count並びにeventの欠落，不正，未知又は矛盾はdecode失敗とします．schema 1からschema 10は引き続きdecodeでき，注入されたschema 11 eventを無視します．画像，認識文字列，座標，display ID，window title，raw domain，raw numeric code，description及び`userInfo`は保存しません．過去の限定live metadata reportは，現行managed identity，利用者確認式canvasの精度，可視overlay alignment又はproduction renderingの証拠ではありません．

　2026年9月1日のdecoder-hardened checkpointを対象とする自動gate resultは`DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult`，そのad hoc arm64 runtime executableのSHA-256は`a6407496c7bd0044c3f30982e749a5556bd2b8e9a751ebd7ed476f59e9151cc9`，CDHashは`7a60426b1fb628f6fd3dce9b1c3516092d5a799a`です．byte-identicalなexecutableを`LectureBoard AI Schema 11 Decoder Hardened Verification.app`として別に固定しました．同じbytesであっても，自動gate証拠と下記fixed-path live証拠は異なる履歴上の主張として扱います．

　本プロジェクトの完成は，`LectureBoard-AI-v1.0.0-arm64.zip`，`LectureBoard-AI-v1.0.0-test-results.json`，`SBOM.spdx.json`，`SHA256SUMS`及び`provenance.json`の正確な5件だけを添付した，immutableかつ非prereleaseの正式な公開`v1.0.0` GitHub Releaseの成立を意味します．5件は正確なsource commitへ結合され，公開後の認証なし再取得検証に合格しなければなりません．Release noteは第6 assetではなくRelease本文へ置きます．有料又は教育機関名義のApple Developer membershipは使用しないため，最終archiveはad hoc署名であり，Developer ID署名又はApple notarization済みとは表示しません．α版，β版又はRelease Candidateのapplication Releaseは公開しません．手順は[無償公開手順](docs/no-fee-release-process.md)，検証gateは[`ROADMAP.md`](ROADMAP.md)に示します．

　導入，権限，初回講義，停止，export，更新及び削除は[日本語利用案内](docs/user-guide-ja.md)にまとめています．秋山さん自身のPPTX複製物による[公開前ユーザー受入](docs/user-acceptance-ja.md)は，正確な公開候補ができた後に実施する未完了gateです．

### 当面の対象

- macOS 26以降
- Apple silicon搭載Macを優先
- Microsoft PowerPoint for Mac
- 対象予定であり，実行時未検証の環境：Zoom，Microsoft Teams，Google Meet，教室投影
- 初期の対象言語：日本語，英語，および段階的な日英混在対応

### 基本原則

- 音声コマンドではなく，講義文脈から重要性を判断する．
- スライド，発表者ノート，発話に根拠のない事実を付け加えない．
- 一度確定した板書をむやみに動かさない．
- 講師によるPowerPoint上の手書きをAIより優先する．
- ローカル処理を基本とし，クラウドAIは交換可能な任意アダプターとする．
- 日本語と英語を初期の対象言語とし，内部ではBCP 47言語タグを用いる．

### 制御された実行時検証の限界

　過去のschema 1ビルドでは，40秒間に372フレームと画像差分イベント5件を旧`slideChangeCount`欄へ記録しました．その後のschema 2対応済み・意味修正前ビルドでは，別の40秒間に373フレーム，旧方式の画像差分イベント5件及び内容更新2件を記録しました．後者のレポートSHA-256は`704d9266bf1564161dd756a0be57c4a47d5459dfb9c9ae5cf0c103acc8320f41`です．いずれも特定ビルドに限る履歴証拠であり，スライド同一性又は現行の意味修正後ビルドを検証した結果ではありません．5件を確認済みスライド切替と表現してはなりません．

　schema 8の固定証拠Appは，保存先のexecutableを直接起動する5秒の静的診断において，画面収録許可を要求せず，正確なPowerPoint window ID 13577からnew frame 53件，stable frame 1件及び完了したVision解析を記録しました．reportは`diagnosticFullFrame`，canvas `confirmed`，metadata-only overlay mapping `mapped`，identity `unavailable`，content revision 0件及びslide change 0件でした．これは，direct executable文脈における静的exact-window取得とmetadata生成だけの特定buildに限る証拠です．取得window全体を診断用に自動確認しており，利用者確認式canvas又はproduction overlayの表示・目視整列を確認した結果ではありません．

　その後，厳格な補助programは，一意なWindow menu項目による正確なPowerPoint文書選択，正確なwindow focus及びslide show安全probeに成功しました．名称，列挙順又は概略座標による弱いfallbackは採用していません．ただし，schema 8の動的試行ではnew frame 1件及びrepeat 2件を受信した後に診断用canvasが無効化され，約535 msで最初の予定slide操作又はmouse入力より前に停止しました．これはfail-closed動作の証拠であり，動的slide又は同一slide上のmouse手書きが動作した証拠ではありません．

　LaunchServices経由の別試行で確認したのは，起動，引数伝達，画面収録許可を要求しないこと，`screenRecordingUnavailable`を記録してfail closedとなること及び自動終了だけです．LaunchServices文脈の画面収録authorization又はwindow取得は未検証です．修正前schema 9 report `LectureBoard-Runtime-Schema9-Slideshow-IdleGeometry-Invalidated-2026-08-31.json`は，new frame 1件及びrepeat 2件の後，入力前に`idleRepeatSurfaceGeometryUnavailableOrMismatched`で停止しました．これは限定された失敗classの証拠であり，attachment欠落と不一致を区別しません．その後，固定した修正後schema 9 Appによるreport `LectureBoard-Runtime-Schema9-IdlePolicy-Dynamic-2026-08-31.json`，SHA-256 `390bee97a34dbde9dc434f876cdf2b05c0a4836effd0d36b528e6231db3ca7e2`は，約40.5秒，154 snapshots及び33 delivered frames，すなわち15 new framesと18 idle repeatsを記録しました．最初のsnapshotは既にnew 1件とrepeat 2件を含みながらcanvas `confirmed`を保持し，以後も全154 snapshotsでconfirmedのままでした．4 stable frames及び4回の制御入力に対応する4 content revisionsへ到達し，解析最大値は認識文字11件，矩形13件，stroke candidates 37件及びoccupied regions 11件でした．semantic identityは`unavailable`，slide changeは0件でした．overlay mapping成功は0件で，拒否理由は`screenGeometryUnavailable` 7件及び`canvasOutsideCapturedContent` 147件でした．したがって，post-fix idle継続とvisual content updateだけの限定的証拠であり，実スライド切替，OCR又は座標の正確性，利用者確認式canvas，可視alignment若しくはproduction renderingを検証した結果ではありません．

　固定schema 9 Appの`LectureBoard-Runtime-Schema9-MouseInk-2026-09-01.json`，SHA-256 `534a285e8f3830891c374746338aa361ab9ebf15cf1f4b199e686d1166b17cb7`は，20秒間に78 snapshots，65 new frames，15 repeats，4 content revisions及びslide change 0件を記録しました．手書き前と消去後の画像はbyte-identicalであり，手書き後は5 connected componentsでした．これは，見えるmouse strokeと消去後の視覚的復元だけの証拠です．single-stroke run及びfive-stroke rerunでも画像は復元しましたが，別個のpost-erase revisionは記録されませんでした．detectorはdifference threshold `0.08`，changed-pixel fraction `0.001`，persistence tolerance `0`及び同一候補3 observationの契約を維持し，thresholdを弱めていません．post-baseline coarse又はpending denseの候補だけで共有する，最大2回・約100 ms間隔の厳格なprovenance及びstale result guard付きone-shot fresh-sample経路は現行sourceへ実装し，自動testに合格しています．2026年9月1日に固定したcheckpointのcontinuous経路では後続の別個なerase phase revisionまで確認しましたが，実PowerPoint上の`boundedFreshSample` attachment及びtiming，coarse one-shot確定並びにink／eraseの意味分類は未検証です．

　schema 9 live auditには限界も記録しています．約12.068秒で停止したearly aggregate failureは44 new frames，16 repeats及び3 revisionsを記録しましたが，schema 9ではterminal sourceを保持していないため原因不明です．content-mutation inputを送らない30秒static controlも1 content revisionを記録したため，false-positive-freeの証拠ではありません．統合metadata auditのSHA-256は`a547704072066e63047abaffc8e4bec0149be39760901e852236158d103ceff2`，image auditは`38552053c77b46d6a9eccb0cbde8f1baeef6faadf74bee9f57247e8e110d95a9`です．

　固定schema 11 interval Appによる30秒static report `LectureBoard-Runtime-Schema11-Interval-Static-2026-09-01.json`，SHA-256 `bbe4cb946125aa255c1dae3b77052cadfd3b63b330f22f4bd267c47b0b5bfbfd`は，117 snapshots，48 frames，すなわちnew 3件及びrepeat 45件，stable frame 1件，瞬時の`continuousDenseIdleRepeat` revision event 1件，完了したVision解析，identity `unavailable`及びslide change 0件を記録しました．これは診断用full-frame確認を使った固定build固有のstatic・interval metadata証拠だけです．同Appの4秒間隔6入力stress report `LectureBoard-Runtime-Schema11-Interval-Dynamic-4s-Stress-Failed-2026-09-01.json`，SHA-256 `310461032606b6bb7a5ffd9b7e6090eb78bd64b499be53500feac0754a14aad1`は，baseline 1件とpost-baseline revision 5件に留まり，最初のcoarse intervalが第2入力境界をまたいだため厳格helperが不合格としました．これは限定された負のtiming証拠であり，6入力又は現行coarse-fresh成功の証拠ではありません．

　負数countのdecoder修正前に固定した`LectureBoard AI Schema 11 Coarse Fresh Verification.app`のexecutable SHA-256は`d829b0fdc01df309657e75afa348c36491b073d2f05b505d878a9021ce15f11e`です．impossible-title report `LectureBoard-Runtime-Schema11-CoarseFresh-FrozenApp-Preflight-2026-09-01.json`，SHA-256 `fdd52a2e132592236f9faba865537872289eb1b98de58d91c7aeb53047e8300e`が確認したのは，保存pathからの起動，permission要求なしのauthorized preflight，安全な`windowNotFound`，report生成及び自動終了だけです．最初のstatic checkpointはconsole sessionがlock中であったため開始せず，その試行ではcapture，入力及びreportを生成しませんでした．session解除後，同じ旧artifactはbuild固有のstatic，6入力dynamic及びsingle-stroke診断を完了し，詳細を`docs/build-verification.md`へ記録しました．decoder hardening後の現行sourceとは別buildであるため，これらを現行sourceの実行証拠へ一般化しません．

　2026年9月1日に固定したdecoder-hardened Appのfixed-path preflight reportのSHA-256は`36dce0ffe83c11edbfc3990b16eee645e608fb174777330131c453d766d376d8`です．最初のstatic orchestration試行は，遅れて出現したslide show windowを再利用したためruntime起動前に停止しました．正確で安全なEscapeを1回だけ送り，限定Core Graphics disappearance checkはtimeoutとなりましたが，その後は入力を反復せず，helperが正確なediting windowへの復帰を受動的に確認しました．1回だけの限定retryは完了しました．static reportのSHA-256は`d018faf503ada46eefe0af0ac97f64cca7394cf690b6b2153b1614955ebc2a80`，helper sidecarは`bd22de08bae4a7fafa3e4b37024b7eeca8b34f5184e0ddab3267075de47c02da`です．116 snapshots，301 delivered frames中new 2件，stable frame 1件，content revision 0件及び最終Vision `completed`を記録しました．これはexact-window，diagnostic full-frame及び固定buildに限るstatic証拠です．

　2026年9月1日に固定したdecoder-hardened Appの6入力dynamic reportのSHA-256は`c7a73f7cb1bdcaa46ec216218883872d480630f7cf4ff177170f8d1906c14a3c`，helper sidecarは`5c7b0c73a8f059187f9319c2e681995e2e6a91042c5163bb821bf30bd37e488f`です．230 snapshots，599 delivered frames中new 15件，stable frame 6件及び8秒間隔の6入力後に正確に6 revision intervalsを記録しました．5件はcoarse stream confirmation，1件は`continuousDenseIdleRepeat`であり，最終Visionは`completed`，semantic slide identityは`unavailable`でした．`boundedFreshSample`は使われていません．operator-captured helper sidecarと組み合わせることで，当該固定build及びscheduleにおける入力window内のvisual revision attributionを支持します．ただし，sidecarはruntime reportへ暗号的に結合されておらず，release-grade provenanceではありません．semantic slide transition又はlive bounded-fresh pathの証拠でもありません．

　2026年9月1日に固定したdecoder-hardened Appのsingle-stroke reportのSHA-256は`70e5772d5d4e8ab8947c725b854749fe2743b38f9189434530de2f0ad9aa63a1`，helper sidecarは`518c60746850c40a6e428704eda2af834eaa95240b9efcb2d117ebf8f69c1aed`です．116 snapshots，301 delivered frames中new 27件，content revisions 2件及び最終Vision `completed`を記録しました．入力後には赤線を目視でき，入力前及び消去後の画像は同一SHA-256 `2dcc102c64a42bf50345e769c05528c16497a98ae60b9b421cc74324479e67f4`でbyte-identicalでした．ink後画像のSHA-256は`e0dbffd2e02423e64efb119ac62d31ea25b9503981589c1940308c790b865c91`です．これは当該runにおける見えるmouse入力及び視覚的復元だけの証拠です．revisionを意味的にink又はeraseへ分類せず，既存ink検出，AI rendering，production又は利用者確認式canvas及び入力ごとのboard semanticsを検証していません．

　最新のreview済みignored schema 11 helper sourceのSHA-256は`a91888a45f98414551bb96e6b38201e2faaa931f6462885f01024bdc9c319a2d`，保存したreview済みarm64 binary `DriveExactPowerPointInk-Schema11-MachIntervals-Reviewed-2026-09-01`のSHA-256は`0910f1115b420443a8938111a296c4a16652bc258bd0c9a793813d98dc6f5ae3`です．各schema 11 revision intervalが一つの入力完了後かつ次入力開始前に完全に収まることを要求し，snapshot時刻fallbackを用いず，60秒間に8秒間隔で6入力を配置します．GUI-free self-test，反復check，lint，Swift 6 strict typecheck，compile及び独立reviewに合格しました．上記dynamic及びsingle-stroke runは，この正確なhelper，artifact，deck及びscheduleに限るend-to-end証拠を追加します．

　現行実装は，利用者が確認したスライド面だけを対象とする160×90のRGB指紋，長辺640ピクセル以下のRGBラスタ，`strokeCandidateRegions`，及び確認済みスライド面から透明overlay矩形へのfail-closedな座標変換を備えます．ただし，筆跡候補は既存PowerPointインクの確定分類ではありません．切出し，無効化及びoverlay座標変換には合成画像・geometry fixtureと制御可能なfakeによる実装証拠があります．しかし，実PowerPoint上の利用者確認式スライド面特定，操作UI除外，ScreenCaptureKit surface padding，`contentRect`，`contentScale`及び`screenRect`の対応，表示mode，window移動・resize，複数display，overlayの見た目の一致・z-order・click-through入力，OCR文字列，矩形・占有領域の座標精度，代表的な実用deck，animation，長時間実行，window再選択並びにLaunchServices経由のcapture authorizationは未検証です．現行診断で確認した入力境界内visual revision，mouse stroke及び視覚的消去復元を，semantic slide identity，意味的ink分類，既存ink検出，AI板書の講義中表示又はproduction canvasへ一般化してはなりません．

### ビルド

```bash
git clone https://github.com/akiyama709/lectureboard-ai.git
cd lectureboard-ai
make bootstrap
make test-core
make test-app
make build
make build-runtime
open LectureBoardAI.xcodeproj
```

　`make build`は，署名を無効にしたコンパイル・リンク検査であり，ネイティブ動作確認に用いるアプリを生成する手順ではありません．`make test-app`は，ローカルのアドホック署名を用いてmacOSアプリの単体テストを実行します．`make build-runtime`は，制御された動作確認用としてarm64 Debugアプリをアドホック署名で生成します．アドホック署名はDeveloper ID配布署名又はnotarizationではありません．

　同じアプリ名及びbundle identifierであっても，再ビルドによりコードIDが変化し，macOSから画面収録の再許可を求められる場合があります．Codexの許可下で実行ファイルを直接起動する経路と，LaunchServicesを介して独立起動する経路は別の検証対象です．LaunchServices経由では限定的な起動，引数伝達，no-request，`screenRecordingUnavailable` report及び自動終了だけを確認しており，画面収録authorization及び取得は未検証です．公開CIが現在実行するのは，プラットフォーム非依存のCoreテストだけです．

### Mac上でローカル開発を継続する

```bash
make doctor
make local-setup
make open
make codex
```

　その後，新しいChatGPTデスクトップアプリのCodexで本フォルダを開き，[`docs/local-codex-handoff-ja.md`](docs/local-codex-handoff-ja.md)を最初に読ませます．通常のChatGPT履歴とCodex履歴は別であるため，`AGENTS.md`と引継ぎ文書を継続開発の正本とします．

### 現在の実装範囲と未実装範囲

　現在含まれる内容と，まだ完成を主張しない内容は，上記英語版及び[`ROADMAP.md`](ROADMAP.md)に明示しています．講義音声や未発表スライドを扱うため，プライバシー設計は[`docs/privacy-and-security.md`](docs/privacy-and-security.md)にまとめています．
