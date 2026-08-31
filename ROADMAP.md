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

- [ ] Capture the selected PowerPoint window continuously with ScreenCaptureKit — selection and capture start now fail closed across the ScreenCaptureKit window ID, owning PID, and exact PowerPoint bundle identifier; only complete/started is new and only idle is repeat; missing, malformed, unknown, blank, or suspended status, invalid samples, and conversion failures break repeat continuity and require a later new frame, while stopped is terminal; scale factor is restricted to the SDK-documented range from 1 through 4; historical direct-executable builds delivered 372 frames in one schema-1 run and 373 frames in a separate schema-2 pre-semantic run; a schema-7 locked-session diagnostic selected one exact window but received zero frames and correctly reported `captureFrameUnavailable`; the schema-8 DerivedData runtime executable subsequently completed one 15-second direct static exact-window diagnostic with 152 new frames; the byte-identical fixed-path copy then completed a separate five-second direct static diagnostic with no permission request, authorized preflight before and after capture, and 53 new frames; a separate schema-8 LaunchServices run verified start, arguments, no permission request, fail-closed report production, and auto-exit but failed before capture; a schema-8 controlled slideshow attempt received one new frame and two repeats before canvas invalidation stopped it before input; a pre-fix schema-9 rerun bounded that failure to `idleRepeatSurfaceGeometryUnavailableOrMismatched`; the provisional application policy now reuses latched surface geometry only for a verified idle delivery with all three surface keys absent, while closing overlay mapping and poisoning any invalid repeat until a new frame; post-fix live recovery, actual idle attachment shape, LaunchServices capture authorization, live dynamic delivery, post-restart permission persistence, representative decks, window reselection, and long-duration reliability remain pending
- [ ] Confirm stable visual frames and persistent content updates — the current source has deterministic coarse luminance classification plus dense 160-by-90 RGB persistence detection and corresponding Core/App tests; coarse/dense candidates and missing or invalid dense fingerprints invalidate prior analysis, and current-frame analysis must complete after baseline recovery before proposals reopen; the fixed-path schema-8 static diagnostic observed one stable frame, completed Vision, and zero content revisions while using an explicit diagnostic full-frame canvas; no successful current-build dynamic or mouse-ink result, user-confirmed crop, or representative calibration exists
- [x] Build the slide-identity tracking and integration foundation — Core requires two consecutive matching samples, discards interrupted continuity, and treats a new presentation session as a new baseline; the App rejects wrong-target, wrong-session, and out-of-order observations, excludes candidate-period frames from visual analysis after delivery metrics are recorded, clears old analysis and board scenes at confirmed boundaries, rejects stale or pre-frame final transcript results, and resumes analysis only for a `.new` frame whose ScreenCaptureKit `displayTime` is strictly later than the app's local mach-absolute acceptance time for the confirming observation
- [x] Make the post-identity frame wait explicit and fail-closed — the app reports waiting, synchronized, and timed-out states; timeout does not admit an idle or stale frame; stale timeout callbacks cannot alter a newer boundary or stopped session; a later strictly newer `.new` frame can recover; live timeout behavior with a production identity provider remains unverified
- [ ] Implement an exact-window-bound production PowerPoint slide-identity provider — on each accepted capture start, the safe default requests no Automation permission, sends no Apple Event, and reports unavailable once; a read-only probe found Automation preflight `0`, one slide-show window, and two Core Graphics windows, but PowerPoint's inherited `window.id` was `nil`, preventing exact window-ID binding; no weaker fallback is accepted; exact-window fresh-frame acquisition remains a separate future design
- [ ] Validate actual PowerPoint slide transitions — image-only `.significantVisualChange` remains a visual/content update rather than slide identity; runtime transition counts, current schema-9 identity and frame-sync metadata, and interruption behavior require live validation with the future production provider
- [x] Add fail-closed runtime diagnostics for the canvas and overlay path — the explicit `--confirm-full-frame-canvas` flag is runtime-only and leaves normal user-confirmed behavior unchanged; it waits for a delivered frame, records `diagnosticFullFrame` provenance separately from no request, reports metadata-only overlay mapping state or a specific rejection reason without coordinates or display identifiers, and returns `captureFrameUnavailable` when no frame arrives; schema 9 adds bounded root and snapshot canvas-invalidation reasons without images, recognized text, coordinates, display identifiers, or window titles while preserving the generic failure code/message; schema 1 through schema 8 remain decodable with absent new fields as `nil`, while a malformed schema-9 canvas failure without a root reason normalizes fail closed to `unclassifiedInvalidation`; 119 Core tests in 15 suites, 57 targeted idle-surface native tests in 2 suites, and 217 full native tests in 25 suites pass
- [x] Add a fail-closed, user-confirmed slide-canvas boundary — public macOS and PowerPoint APIs expose no exact internal slide-canvas rectangle, so the user drags and confirms it on the frozen preview of the exact captured window; the crop must be at least 32 by 24 source pixels and 1,024 square pixels; confirmation is bound to capture operation, exact window ID, source pixel dimensions, and validated ScreenCaptureKit surface geometry; restart, mismatch, missing usable geometry after the narrow idle policy, or geometry change invalidates it; without confirmation, only delivery metrics advance
- [ ] Validate slide-canvas localization, PowerPoint-UI exclusion, and overlay alignment on live PowerPoint — deterministic Core and native fixture tests cover normalized selection, outward pixel mapping, cropping, pipeline gating, invalidation, and fail-closed overlay-coordinate mapping; schema-8 direct static diagnostics recorded `diagnosticFullFrame`, confirmed canvas state, and metadata-only `mapped`, but the full captured window was selected automatically for instrumentation and semantic identity remained unavailable; user-confirmed localization, UI exclusion, visible alignment, production rendering, ScreenCaptureKit `screenRect` orientation and scaling, surface padding and `contentRect` mapping, slideshow modes, actual multi-display arrangements, window resizing, overlay z-order, and representative decks remain unverified
- [ ] Recognize slide text and geometry — Vision now receives only the confirmed cropped canvas and has synthetic native coverage, but current-build live OCR correctness and coordinate accuracy remain unverified
- [ ] Build normalized occupied regions from detected text, rectangles, and raster candidates — the current source produces a maximum-640-pixel RGB raster from the confirmed canvas and keeps `strokeCandidateRegions` separate from confirmed ink; live coordinate accuracy, existing-ink classification, and overlap-avoidance accuracy remain pending
- [ ] Detect existing PowerPoint ink as occupied space
- [ ] Route live transcript segments into the contextual board engine — App and Apple-provider generation guards now reject callbacks across semantic slide, canvas, and capture boundaries and require explicit user resumption, but live microphone behavior remains unverified
- [ ] Render stable text, boxes, arrows, and causal chains — demo content is cleared at capture start and disabled during active capture or capture-provider shutdown; this is a safety boundary, not live board-rendering evidence
- [x] Implement fail-closed alignment of the click-through overlay with the confirmed slide canvas — each accepted delivery carries only its own ScreenCaptureKit `screenRect`; the pure mapper requires the exact capture operation, window, surface geometry, output dimensions, and current screen geometry, accepts exactly one containing display, converts the Quartz target to AppKit coordinates, and binds placement to the current frame sequence; production display additionally requires confirmed semantic identity and current visual grounding, frontmost exact PowerPoint ownership, one exact layer-zero on-screen window, two-point edge agreement, no earlier intersecting window, and a current independently expiring lease; manual suppression, focus or Space changes, capture-content uncertainty, and visual uncertainty hide the panel; the safe default identity provider cannot show production output; deterministic native tests pass, and diagnostic-full-frame static runs reached metadata-only `mapped`, but no production panel was authorized and no live visible-alignment claim is made
- [ ] Save the session as JSON and SVG — the runtime-verification metadata JSON is diagnostic evidence, not a lecture-session export

**Exit criterion:** a ten-minute Japanese or English lecture can run without overlap on a controlled slide deck.

**Next live checkpoint:** preserve both fixed copies, `LectureBoard AI Schema 8 Verification.app` and `LectureBoard AI Schema 9 Idle Policy Verification.app`, without rebuilding, replacing, or moving them. The pre-fix schema-9 rerun identified `idleRepeatSurfaceGeometryUnavailableOrMismatched` after one new frame and two repeats, before input. The post-fix app passes strict signature verification and a saved-path no-permission-request preflight, but the locked macOS session prevented exact PowerPoint re-verification and no post-fix capture or input occurred. After unlock, rerun exact window-menu selection, focus, and slideshow checks from the beginning and observe live idle recovery. Only a successful safe recovery may proceed to controlled dynamic slide input and then a separate mouse-ink run. The schema-8 LaunchServices result verifies start and fail-closed exit only, not capture authorization. Write each future report to a unique path in the system temporary directory, validate it there, and only then copy and compare it into the external verification directory. Keep diagnostic full-frame confirmation distinct from user-confirmed canvas and production overlay evidence.

## Milestone 2 — Contextual board quality

- [ ] Import `.pptx` text, geometry, and speaker notes
- [ ] Add evidence-linked AI summarization adapters
- [ ] Defer uncertain content instead of interrupting the lecturer
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
