# Roadmap

The roadmap describes validation gates rather than promises of release dates.

The proposed near-term execution order, updated after the owner's failed live trial and explicit
within-utterance boarding requirement on 2026-09-06, is in
[`docs/development-plan-ja.md`](docs/development-plan-ja.md). It defines stages 0–8 from
ordinary app launch and streaming recognition through owner acceptance and final publication.
The conservative stable-partial path is now implemented and covered by deterministic tests, but
its real-speech behavior, end-to-visible-board latency, and architecture alternatives remain
unverified. A bounded synthetic live run has since completed the managed windowed-show binding,
explicit canvas calibration, Japanese/English semantic transitions, and normal cleanup. That run
used a diagnostic build and generated deck; it is not microphone, visible-board, representative
lecture, or owner-acceptance evidence.
The historical milestone evidence and final publication requirements below remain unchanged.

Project completion means publishing a public, immutable, non-prerelease `v1.0.0` GitHub Release with exactly five attached assets: `LectureBoard-AI-v1.0.0-arm64.zip`, `LectureBoard-AI-v1.0.0-test-results.json`, `SBOM.spdx.json`, `SHA256SUMS`, and `provenance.json`. They must bind the verified arm64 application archive to the exact source commit and pass unauthenticated public re-download verification. Release notes belong in the Release body, not a sixth asset. The project will not purchase an Apple Developer Program membership or publish under an institution, so the archive will be ad hoc signed and explicitly not Developer ID signed or Apple notarized. Creating the public source repository did not complete the product. No alpha, beta, or release-candidate GitHub Release will be published.

Current status: the repository contains a pre-release development tree. Commit
`fa62c73eada6d94daf094ac92c8032135fdd1e72` passed 250 Core tests in 19 suites, 480
authoritative native App tests, and all 26 `make verify` stages. A bounded diagnostic build with
the same final role-evidence policy completed one generated single-document windowed PowerPoint
session through exact binding, explicit canvas confirmation, two semantic slide transitions, and
normal cleanup. An exact Hardened Runtime, arm64, ad hoc-signed owner-trial app was subsequently
frozen from code-bearing commit `c525ee468283bee333166cb301a3c9570fae0086`; ordinary
LaunchServices launch and fail-closed behavior without Screen Recording authorization passed.
That exact app still requires one owner-mediated authorization and has not completed its live
trial. Real microphone input, stable-partial timing, visible automatic board content, human-input
priority, live export, representative PPTX use, owner acceptance, installation, and public release
remain unverified. No application GitHub Release has been published.

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
- [x] Implement an exact-window-bound production PowerPoint slide-identity provider — the explicit managed workflow retains the exact object returned by PowerPoint, accepts only windowed slide-show mode, identifies one exact ScreenCaptureKit candidate through a reversible role challenge, restores the challenged property, activates the App binding before identity polling, and reads exact slide IDs and indices from the retained object; one-shot/session/tombstone guards and deferred cleanup reject stale or ambiguous evidence; the ordinary passive workflow remains Automation-free and unavailable; deterministic tests pass, and a bounded diagnostic build with the final role-evidence policy completed exact live managed binding and cleanup on a generated deck; the exact production distribution, representative decks, cancellation and interruption paths remain unverified
- [ ] Validate actual PowerPoint slide transitions — image-only `.significantVisualChange` remains a visual/content update rather than slide identity; the bounded generated-deck diagnostic advanced the exact retained object from slide ID 256 to 257 and 258, recorded two semantic changes, synchronized post-boundary frames, and resumed current analysis; the exact production distribution, backward navigation, interruption behavior, representative decks, and owner lecture remain unverified
- [x] Add fail-closed runtime diagnostics for the canvas, overlay, and capture-terminal paths — the explicit `--confirm-full-frame-canvas` flag is runtime-only and leaves normal user-confirmed behavior unchanged; schema 9 added bounded canvas-failure reasons; schema 10 added nine bounded capture-failure sources and 21 public `SCStreamError.Code` categories, accepts only the first terminal callback through one synchronous gate, rejects stale operations, resets telemetry on a new start or manual stop, and preserves the accepted result in the final runner JSON; raw error domains, numeric codes, descriptions, and `userInfo` are not retained; historical schema-1 through schema-9, completed, and non-capture-failure reports ignore the schema-10 fields, while missing, malformed, unknown, or inconsistent current-capture evidence normalizes to `unclassifiedCaptureFailure`; schema 11 retains this boundary, while live capture-failure classification remains unverified
- [x] Add fail-closed schema-11 content-revision interval metadata — the latest revision retains its exact ordinal, bounded source, first qualifying evidence mach-absolute time, and confirmation mach-absolute time; negative counts, count/event inconsistency, and malformed current intervals fail decoding, while schema 1 through schema 10 ignore the new field and preserve their historical counters; these intervals identify detector evidence windows and do not by themselves establish semantic slide identity or input causation; after the negative-count decoder regression was fixed, the synchronized 2026-09-01 checkpoint passed 153 Core tests in 15 suites, 259 native tests in 30 suites, and the complete 14-stage `make verify` gate at approximately 23:50–23:51 JST, with native result `DerivedData/AppTests/Logs/Test/Test-LectureBoardAI-2026.09.01_23-50-45-+0900.xcresult`; this is historical checkpoint evidence, not verification of the later release tree
- [x] Add a fail-closed, user-confirmed slide-canvas boundary — public macOS and PowerPoint APIs expose no exact internal slide-canvas rectangle, so the user drags and confirms it on the frozen preview of the exact captured window; the crop must be at least 32 by 24 source pixels and 1,024 square pixels; confirmation is bound to capture operation, exact window ID, source pixel dimensions, and validated ScreenCaptureKit surface geometry; restart, mismatch, missing usable geometry after the narrow idle policy, or geometry change invalidates it; without confirmation, only delivery metrics advance
- [ ] Validate slide-canvas localization, PowerPoint-UI exclusion, and overlay alignment on live PowerPoint — deterministic Core and native fixture tests cover normalized selection, outward pixel mapping, cropping, pipeline gating, invalidation, and fail-closed overlay-coordinate mapping; a bounded generated-deck diagnostic used authorized local pointer automation to drag and explicitly confirm the inner slide face while excluding black bars and chrome, then completed current Vision analysis; this was not manual owner confirmation and did not verify visible production overlay output; owner-confirmed localization, visible alignment, click-through behavior, production rendering, ScreenCaptureKit `screenRect` orientation and scaling, slideshow modes, multi-display arrangements, resize, z-order, and representative decks remain unverified
- [ ] Recognize slide text and geometry — Vision now receives only the confirmed cropped canvas and has synthetic native coverage, but current-build live OCR correctness and coordinate accuracy remain unverified
- [ ] Build normalized occupied regions from detected text, rectangles, and raster candidates — the current source produces a maximum-640-pixel RGB raster from the confirmed canvas and keeps `strokeCandidateRegions` separate from confirmed ink; live coordinate accuracy, existing-ink classification, and overlap-avoidance accuracy remain pending
- [ ] Detect existing PowerPoint ink as occupied space
- [ ] Route live transcript segments into the contextual board engine — final segments reach a current OCR-derived `SlideContext` and deterministic grounded engine after current identity, canvas, frame synchronization, and visual analysis are ready; the on-device provider uses bounded eight-second cycles, a four-second finalization deadline, bounded tail handoff, restart backoff, and callback retention, and now assigns one segment identity to all revisions in a recognition cycle; before a final result, one complete declarative unit may enter the same engine only after two consecutive partial revisions retain it with reliable finite confidence, emphasis, timing, and nondecreasing end time; questions, incomplete or short units, changed identities, low confidence, and out-of-order revisions fail closed; all existing visual-grounding, importance, public-scene, and overlay gates still apply, and the newest partial alone is never public; semantic-slide and temporary content-unavailable boundaries reject old callbacks and automatically resume a still-requested transcription only after readiness returns, while manual stop, canvas changes, and capture end cancel the request; deterministic Core and native integration tests pass, but real partial recognition, end-to-visible-board latency, and live microphone-to-visible-board behavior remain unverified
- [ ] Render stable text, boxes, arrows, and causal chains — demo content is cleared at capture start and disabled during active capture or capture-provider shutdown; this is a safety boundary, not live board-rendering evidence
- [x] Keep proposed, deferred, and dismissed intents out of the public board scene — only confirmed or pinned intents render; an unchanged public scene does not advance the board-scene generation or invoke overlay eligibility or rendering; deterministic tests cover this boundary, while live board rendering remains unverified
- [x] Implement fail-closed alignment of the click-through overlay with the confirmed slide canvas — the pure mapper requires the exact capture operation, window, surface geometry, output dimensions, and validated screen geometry, accepts exactly one containing display, converts the Quartz target to AppKit coordinates, and binds placement to the current frame sequence; a verified idle repeat uses its own valid `screenRect`, fails closed on a present malformed value, or only when the key is absent carries forward the prior validated rectangle as a candidate; production display and lease renewal independently require the current frontmost exact PowerPoint owner, one exact layer-zero on-screen window, two-point agreement with its freshly read bounds, no earlier intersecting window, confirmed semantic identity, and current visual grounding, so movement, resize, focus loss, disappearance, or occlusion cannot be authorized by the retained candidate; manual suppression, focus or Space changes, capture-content uncertainty, and visual uncertainty hide the panel; the safe default identity provider cannot show production output; deterministic native tests pass, while live idle-key omission, visible alignment, and z-order remain unverified
- [x] Save the public board session as JSON and SVG — the App exporter records only confirmed/pinned public scenes, coalesces consecutive same-slide updates, preserves revisits, resets at a new capture, retains the finished session after stop, and excludes transcript, OCR text, images, window metadata, capture identifiers, and non-public intents; deterministic Core and App tests pass, while live export from the release artifact remains unverified

**Exit criterion:** a ten-minute Japanese or English lecture can run without overlap on a controlled slide deck.

**Next implementation and live checkpoint:** preserve all historical fixed apps and evidence without replacing or reinterpreting them. The earlier owner-trial app at `/Users/akiyama/Documents/LectureBoard AI Verification/Mock-Lecture-c525ee4/LectureBoard AI.app` remains frozen historical evidence but is no longer the acceptance candidate: its existing Screen Recording row was removed with owner authorization, the row was not restored, and the owner directed that repeated permission work for that app stop. One bounded transcription attempt reached start/stop without a crash but did not display either predetermined fragment from a local synthetic spoken sentence, so real microphone recognition and pre-final board output remain unverified. The next candidate must be generated exactly once from the final clean release commit at a new fixed path after the automated evidence transaction. The owner may skip another permission exercise, but a skipped Screen Recording grant cannot satisfy the core lecture or owner-acceptance gate. If acceptance proceeds, grant Screen Recording once to that exact final candidate and use only it with a working copy of a self-selected PPTX. The acceptance must observe ordinary launch, real microphone partials, conservative pre-final promotion, actual visible board output and latency, exact managed binding, owner-confirmed canvas, mouse-input priority, overlay alignment and click-through behavior, JSON/SVG export, normal stop, and original-file immutability. Cancellation, permission denial, window closure and interruption cleanup remain separate supported-path checks. Full-screen, Presenter View, multiple displays, code switching, a physical pen tablet, speaker-note import, and cloud adapters are explicit post-v1 work and must not be inferred from this gate. Run the final automated gate against the clean exact commit, build and locally verify the five-asset ad hoc-signed archive, then complete the remaining live and clean-install gates before requesting publication approval that names the exact commit and archive SHA-256.

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

## Milestone 4 — Supported-workflow acceptance

- [ ] Complete the managed single-document, windowed-slide-show, single-display lecture flow
- [ ] Verify user-confirmed canvas, visible overlay alignment, click-through mouse priority, and public-scene export
- [ ] Verify normal stop, cancellation, permission denial, window closure, and capture-interruption cleanup
- [ ] Verify the original PowerPoint file remains unchanged
- [ ] Accessibility review
- [ ] Complete privacy, licensing, known-limitations, installation, first-lecture, and fallback documentation

**Exit criterion:** the supported workflow completes repeatedly with documented evidence and fallback procedures. Passing this internal gate does not publish or complete the product.

## Milestone 5 — Representative-use validation

- [ ] Exercise representative Japanese and English lecture sets in separate sessions
- [ ] Calibrate OCR, geometry, occupancy, and annotation usefulness with recorded evidence
- [ ] Validate repeated managed start, normal stop, cancellation, and supported recovery paths
- [ ] Validate microphone, transparent overlay, and mouse-input non-interference
- [ ] Complete privacy, accessibility, license, and third-party-notice review
- [ ] Complete user instructions and a known-limitations list

**Exit criterion:** the feature-frozen build works repeatedly in the documented supported environment, and all material failures and limitations are tracked. This remains an internal validation gate, not project completion.

## Milestone 6 — Exact v1.0.0 publication candidate

- [ ] Freeze the `v1.0.0` feature set and supported environment
- [ ] Resolve all release-blocking defects and triage every remaining known issue
- [ ] Produce a reproducible distribution build
- [ ] Apply the hardened runtime and an ad hoc signature without expanding the entitlement allowlist
- [ ] Run `evidence` against the clean exact commit, retain its private gate log and frozen `.xcresult`, and publish only its content-free JSON test evidence
- [ ] Produce the application ZIP, SHA-256 checksum manifest, content-free test evidence, SBOM, and commit-bound provenance without claiming Developer ID or notarization
- [ ] Verify the expected Gatekeeper warning, Apple's per-application Open Anyway path, installation, first launch, permissions, and core lecture flow on a clean supported Mac
- [ ] Complete release notes, installation, privacy, security, troubleshooting, and fallback documentation

**Exit criterion:** the exact candidate artifact satisfies every pre-publication item in [`docs/v1-release-checklist.md`](docs/v1-release-checklist.md). It is not project completion until the public release and post-publication gate succeed.

## Milestone 7 — Public v1.0.0 GitHub Release

- [ ] Run all required CI and local release verification against the exact release commit
- [ ] Obtain explicit approval for the external publication action
- [ ] Create and push the annotated `v1.0.0` tag from the approved release commit
- [ ] Publish an immutable, non-draft, non-prerelease GitHub Release with exactly five attached assets—the ad hoc-signed application archive, checksum manifest, content-free test evidence, SBOM, and provenance—and put the release notes in the GitHub Release body
- [ ] Run the unauthenticated `verify-public` transaction to retain public REST metadata and annotated-tag refs, require the exact five names and byte equality, and independently recheck the archive checksum, bundle identity, ad hoc signature, architecture, version, and provenance
- [ ] Verify installation, permissions, launch, and the supported workflow from that downloaded public archive
- [ ] Record the public release URL and final evidence in the verification documentation

**Exit criterion and definition of completion:** the public, immutable, non-prerelease `v1.0.0` GitHub Release is available from `akiyama709/lectureboard-ai`, its supported functionality has passed the release gate, and the downloaded public application archive passes the final verification checklist. The absence of Developer ID and Apple notarization is stated explicitly and is not presented as an unfinished product stage.

## Later exploration

- Keynote and PDF presentation support
- Personal writing-style adaptation with explicit opt-in
- More languages
- Student-side optional translated board views
- Windows and Linux only after the macOS implementation is dependable
