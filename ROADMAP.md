# Roadmap

The roadmap describes validation gates rather than promises of release dates.

Project completion means publishing a public `v1.0.0` GitHub Release that includes an installable macOS artifact signed with Developer ID and accepted by Apple notarization. Creating the public source repository did not complete the product. Alpha, beta, and release-candidate builds are intermediate validation gates, even if a prerelease artifact is published for testing.

Current status: the repository contains an alpha scaffold. No alpha, beta, release-candidate, or `v1.0.0` GitHub Release has been published.

## Milestone 0 — Public repository foundation

- [x] macOS-only scope
- [x] Native app shell
- [x] Provider-neutral core architecture
- [x] Context-first design with no required voice commands
- [x] Grounded board-intent data model
- [x] Transparent-overlay prototype
- [x] CI and open-source governance files

**Exit criterion:** source, governance, and repeatable local verification are available in the public repository. This gate is complete, but it is not a product release or project completion.

## Milestone 1 — Observable lecture prototype

- [ ] Capture the selected PowerPoint window continuously with ScreenCaptureKit — selection and capture start now fail closed across the ScreenCaptureKit window ID, owning PID, and exact PowerPoint bundle identifier; only complete/started is new and only idle is repeat; missing, malformed, unknown, blank, or suspended status, invalid samples, and conversion failures break repeat continuity and require a later new frame, while stopped is terminal; scale factor is restricted to the SDK-documented range from 1 through 4; historical schema-1 through schema-11 runs remain separately identified; the decoder-hardened artifact `LectureBoard AI Schema 11 Decoder Hardened Verification.app`, executable SHA-256 `a6407496c7bd0044c3f30982e749a5556bd2b8e9a751ebd7ed476f59e9151cc9`, completed a 30-second exact-window static report, SHA-256 `d018faf503ada46eefe0af0ac97f64cca7394cf690b6b2153b1614955ebc2a80`, with 116 snapshots and 301 frames comprising 2 new and 299 repeats, authorized preflight without a permission request, final completed Vision analysis, unavailable identity, and zero slide changes; a first helper attempt and strict cleanup had already stopped before runtime because the slide-show lifecycle could not be verified, then one bounded retry succeeded after passive exact-window verification; this does not prove the failure's root cause; generality across PowerPoint modes, LaunchServices capture authorization, post-restart permission persistence, representative decks, window reselection, and long-duration reliability remain pending
- [ ] Confirm stable visual frames and persistent content updates — the current source has deterministic coarse luminance classification plus dense 160-by-90 RGB persistence detection and corresponding Core/App tests; coarse/dense candidates and missing or invalid dense fingerprints invalidate prior analysis, and current-frame analysis must complete after baseline recovery before proposals reopen; the detector contract remains a `0.08` difference threshold, `0.001` changed-pixel fraction, zero persistence tolerance, and three identical qualifying observations; thresholds were not weakened; either an exact post-baseline coarse candidate or a pending dense candidate may obtain at most two actual one-shot samples approximately 100 milliseconds apart, bound to one opaque candidate token and exact capture/window/canvas/identity/stream provenance, with bounded provider-busy deferral and no effect on continuous-delivery metrics, semantic identity, post-identity synchronization, or overlay provenance; initial coarse-baseline collection is excluded; deterministic replacement, reset, stale-time, mismatch, lifecycle, and overlay-suppression tests pass; the decoder-hardened 60-second report, SHA-256 `c7a73f7cb1bdcaa46ec216218883872d480630f7cf4ff177170f8d1906c14a3c`, recorded six non-reused interval-contained revision events, comprising five `coarseSignificantVisualChange` events and one `continuousDenseIdleRepeat`, with final Vision completion and no extra event; no event used `boundedFreshSample`, and semantic identity remained unavailable; the paired operator-captured helper sidecar, SHA-256 `5c7b0c73a8f059187f9319c2e681995e2e6a91042c5163bb821bf30bd37e488f`, supports input-window attribution for those events under the controlled eight-second schedule, but is not cryptographically bound to the report and is not release-grade provenance; a separate single-stroke report, SHA-256 `70e5772d5d4e8ab8947c725b854749fe2743b38f9189434530de2f0ad9aa63a1`, recorded two aggregate phase-correlated continuous-dense revisions, one visible red line, and byte-identical before/after-erase pixels, but does not verify semantic or per-input ink/erase classification; live bounded-fresh sampling, existing-ink detection, a user-confirmed crop, and representative calibration remain pending
- [x] Build the slide-identity tracking and integration foundation — Core requires two consecutive matching samples, discards interrupted continuity, and treats a new presentation session as a new baseline; the App rejects wrong-target, wrong-session, and out-of-order observations, excludes candidate-period frames from visual analysis after delivery metrics are recorded, clears old analysis and board scenes at confirmed boundaries, rejects stale or pre-frame final transcript results, and resumes analysis only for a `.new` frame whose ScreenCaptureKit `displayTime` is strictly later than the app's local mach-absolute acceptance time for the confirming observation
- [x] Make the post-identity frame wait explicit and fail-closed — the app reports waiting, synchronized, and timed-out states; timeout does not admit an idle or stale frame; stale timeout callbacks cannot alter a newer boundary or stopped session; a later strictly newer `.new` frame can recover; live timeout behavior with a production identity provider remains unverified
- [ ] Implement an exact-window-bound production PowerPoint slide-identity provider — on each accepted capture start, the safe default requests no Automation permission, sends no Apple Event, and reports unavailable once; a read-only probe found Automation preflight `0`, one slide-show window, and two Core Graphics windows, but PowerPoint's inherited `window.id` was `nil`, preventing exact window-ID binding; no weaker fallback is accepted; exact-window fresh-frame acquisition remains a separate future design
- [ ] Validate actual PowerPoint slide transitions — image-only `.significantVisualChange` remains a visual/content update rather than slide identity; runtime transition counts, current schema-11 identity and frame-sync metadata, and interruption behavior require live validation with the future production provider
- [x] Add fail-closed runtime diagnostics for the canvas, overlay, and capture-terminal paths — the explicit `--confirm-full-frame-canvas` flag is runtime-only and leaves normal user-confirmed behavior unchanged; schema 9 added bounded canvas-failure reasons; schema 10 added nine bounded capture-failure sources and 21 public `SCStreamError.Code` categories, accepts only the first terminal callback through one synchronous gate, rejects stale operations, resets telemetry on a new start or manual stop, and preserves the accepted result in the final runner JSON; raw error domains, numeric codes, descriptions, and `userInfo` are not retained; historical schema-1 through schema-9, completed, and non-capture-failure reports ignore the schema-10 fields, while missing, malformed, unknown, or inconsistent current-capture evidence normalizes to `unclassifiedCaptureFailure`; schema 11 retains this boundary, while live capture-failure classification remains unverified
- [x] Add fail-closed schema-11 content-revision interval metadata — the latest revision retains its exact ordinal, bounded source, first qualifying evidence mach-absolute time, and confirmation mach-absolute time; negative counts, count/event inconsistency, and malformed current intervals fail decoding, while schema 1 through schema 10 ignore the new field and preserve their historical counters; these intervals identify detector evidence windows and do not by themselves establish semantic slide identity or input causation; after the negative-count decoder regression was fixed, the synchronized current tree passed 153 Core tests in 15 suites, 259 native tests in 30 suites, and the complete 14-stage `make verify` gate at approximately 23:50–23:51 JST, with native result `DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult`; this result pointer is a post-gate documentation-only change, and targeted documentation and publication checks passed afterward before commit
- [x] Add a fail-closed, user-confirmed slide-canvas boundary — public macOS and PowerPoint APIs expose no exact internal slide-canvas rectangle, so the user drags and confirms it on the frozen preview of the exact captured window; the crop must be at least 32 by 24 source pixels and 1,024 square pixels; confirmation is bound to capture operation, exact window ID, source pixel dimensions, and validated ScreenCaptureKit surface geometry; restart, mismatch, missing usable geometry after the narrow idle policy, or geometry change invalidates it; without confirmation, only delivery metrics advance
- [ ] Validate slide-canvas localization, PowerPoint-UI exclusion, and overlay alignment on live PowerPoint — deterministic Core and native fixture tests cover normalized selection, outward pixel mapping, cropping, pipeline gating, invalidation, and fail-closed overlay-coordinate mapping; schema-8 direct static diagnostics recorded `diagnosticFullFrame`, confirmed canvas state, and metadata-only `mapped`, but the full captured window was selected automatically for instrumentation and semantic identity remained unavailable; the later schema-9 fixed-path diagnostic mapped zero snapshots, with 7 `screenGeometryUnavailable` and 147 `canvasOutsideCapturedContent` outcomes; user-confirmed localization, UI exclusion, visible alignment, production rendering, ScreenCaptureKit `screenRect` orientation and scaling, surface padding and `contentRect` mapping, slideshow modes, actual multi-display arrangements, window resizing, overlay z-order, and representative decks remain unverified
- [ ] Recognize slide text and geometry — Vision now receives only the confirmed cropped canvas and has synthetic native coverage, but current-build live OCR correctness and coordinate accuracy remain unverified
- [ ] Build normalized occupied regions from detected text, rectangles, and raster candidates — the current source produces a maximum-640-pixel RGB raster from the confirmed canvas and keeps `strokeCandidateRegions` separate from confirmed ink; live coordinate accuracy, existing-ink classification, and overlap-avoidance accuracy remain pending
- [ ] Detect existing PowerPoint ink as occupied space
- [ ] Route live transcript segments into the contextual board engine — App and Apple-provider generation guards now reject callbacks across semantic slide, canvas, and capture boundaries and require explicit user resumption, but live microphone behavior remains unverified
- [ ] Render stable text, boxes, arrows, and causal chains — demo content is cleared at capture start and disabled during active capture or capture-provider shutdown; this is a safety boundary, not live board-rendering evidence
- [x] Keep proposed, deferred, and dismissed intents out of the public board scene — only confirmed or pinned intents render; an unchanged public scene does not advance the board-scene generation or invoke overlay eligibility or rendering; deterministic tests cover this boundary, while live board rendering remains unverified
- [x] Implement fail-closed alignment of the click-through overlay with the confirmed slide canvas — each accepted delivery carries only its own ScreenCaptureKit `screenRect`; the pure mapper requires the exact capture operation, window, surface geometry, output dimensions, and current screen geometry, accepts exactly one containing display, converts the Quartz target to AppKit coordinates, and binds placement to the current frame sequence; production display additionally requires confirmed semantic identity and current visual grounding, frontmost exact PowerPoint ownership, one exact layer-zero on-screen window, two-point edge agreement, no earlier intersecting window, and a current independently expiring lease; manual suppression, focus or Space changes, capture-content uncertainty, and visual uncertainty hide the panel; the safe default identity provider cannot show production output; deterministic native tests pass, and diagnostic-full-frame static runs reached metadata-only `mapped`, but no production panel was authorized and no live visible-alignment claim is made
- [ ] Save the session as JSON and SVG — the runtime-verification metadata JSON is diagnostic evidence, not a lecture-session export

**Exit criterion:** a ten-minute Japanese or English lecture can run without overlap on a controlled slide deck.

**Next implementation and live checkpoint:** preserve every separately named schema-8, schema-9, schema-10, and schema-11 fixed app, the PowerPoint test file, all runtime reports and helper sidecars, and all verification images without rebuilding, replacing, moving, or reinterpreting them. The decoder-hardened schema-11 artifact now has its own fixed-path preflight, static, six-input dynamic, and single-stroke/erase evidence, while the earlier locked-session and delayed slide-show-window failures remain negative history. No live event used `boundedFreshSample`, semantic identity remained unavailable, diagnostic full-frame confirmation was not a user-confirmed canvas, metadata-only `mapped` states did not authorize or visibly align a production overlay, and the visible red-line/erase pixels are not semantic ink or erase classification or AI rendering. The next implementation priority is an exact-window-bound production PowerPoint semantic identity provider. In parallel, deliberately exercise the current bounded fresh path, then validate user-confirmed canvas localization and production overlay alignment in window, full-screen, presenter, resize, and multi-display modes. Follow with OCR and existing-ink calibration, transcript and `.pptx` context, board rendering, JSON/SVG export, representative-deck and lecture-length reliability, and milestones 2 through 5. Developer ID signing, hardened runtime, notarization, clean-Mac installation and permission verification, explicit publication approval, and the public `v1.0.0` GitHub Release all remain. Write each future report and image to a unique system-temporary path, validate it there, and only then copy and compare it into the external verification directory.

## Milestone 2 — Contextual board quality

- [ ] Import `.pptx` text, geometry, and speaker notes
- [ ] Add evidence-linked AI summarization adapters
- [ ] Evaluate uncertainty classification and confirmation behavior in representative lectures
- [ ] Validate names, numbers, dates, quotations, and equations
- [ ] Add board-density and diagram-frequency controls
- [ ] Evaluate false-positive and false-negative board decisions

**Exit criterion:** independent reviewers judge most annotations useful and grounded on a representative lecture set.

## Milestone 3 — Japanese–English mixed lectures

- [ ] Detect short-span language changes
- [ ] Preserve original terminology
- [ ] Support important-term bilingual display
- [ ] Maintain a session glossary
- [ ] Add Japanese and English evaluation corpora with consent

**Exit criterion:** Japanese–English code-switching works without repeated manual language changes.

## Milestone 4 — Lecture-ready alpha gate

- [ ] Presenter control window
- [ ] Online-sharing composite window
- [ ] Recovery after PowerPoint restart or display reconnection
- [ ] Privacy-preserving lecture export
- [ ] Accessibility review
- [ ] Alpha packaging for controlled testers, clearly marked as unfinished

**Exit criterion:** repeated controlled use in real lectures with documented fallback procedures. Passing this gate does not mean the product is complete.

## Milestone 5 — Beta gate

- [ ] Exercise representative Japanese, English, and staged mixed-language lecture sets
- [ ] Calibrate OCR, geometry, occupancy, and annotation usefulness with recorded evidence
- [ ] Validate PowerPoint restart, display reconnection, window reselection, and session recovery
- [ ] Validate microphone, transparent overlay, pen-tablet non-interference, and online-sharing composition
- [ ] Complete privacy, accessibility, license, and third-party-notice review
- [ ] Publish beta testing instructions and a known-limitations list

**Exit criterion:** invited testers can repeatedly use a feature-complete build on supported Macs, and all material failures and limitations are tracked. Beta remains an intermediate gate, not project completion.

## Milestone 6 — Release candidate

- [ ] Freeze the `v1.0.0` feature set and supported environment
- [ ] Resolve all release-blocking defects and triage every remaining known issue
- [ ] Produce a reproducible distribution build
- [ ] Apply Developer ID distribution signing and hardened runtime
- [ ] Submit the installable macOS artifact for Apple notarization and staple the ticket where applicable
- [ ] Verify Gatekeeper acceptance, installation, first launch, permissions, and core lecture flow on a clean supported Mac
- [ ] Complete release notes, installation, privacy, security, troubleshooting, and fallback documentation

**Exit criterion:** the exact candidate artifact satisfies every pre-publication item in [`docs/v1-release-checklist.md`](docs/v1-release-checklist.md). A release candidate is still not the completed public release.

## Milestone 7 — Public v1.0.0 GitHub Release

- [ ] Run all required CI and local release verification against the exact release commit
- [ ] Obtain explicit approval for the external publication action
- [ ] Create and push the annotated `v1.0.0` tag from the approved release commit
- [ ] Publish the public GitHub Release with the signed and notarized installable macOS artifact, release notes, and SHA-256 checksum
- [ ] Re-download the public artifact and independently verify its checksum, signature, notarization, installation, and launch
- [ ] Record the public release URL and final evidence in the verification documentation

**Exit criterion and definition of completion:** the public `v1.0.0` GitHub Release is available from `akiyama709/lectureboard-ai`, its installable macOS artifact is Developer ID signed and notarized, and the downloaded public artifact passes the final verification checklist.

## Later exploration

- Keynote and PDF presentation support
- Personal writing-style adaptation with explicit opt-in
- More languages
- Student-side optional translated board views
- Windows and Linux only after the macOS implementation is dependable
