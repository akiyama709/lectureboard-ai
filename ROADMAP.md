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

- [ ] Capture the selected PowerPoint window continuously with ScreenCaptureKit — selection and capture start now fail closed across the ScreenCaptureKit window ID, owning PID, and exact PowerPoint bundle identifier; historical direct-executable builds delivered 372 frames in one schema-1 run and 373 frames in a separate schema-2 pre-semantic run; a current-build dynamic attempt stopped before input because the ignored local automation helper could not establish a usable Accessibility window, which is not evidence that production ScreenCaptureKit capture failed; live validation of the current semantic build, independent LaunchServices launch, representative decks, window reselection, and long-duration reliability remain pending
- [ ] Confirm stable visual frames and persistent content updates — the current source has deterministic coarse luminance classification plus dense 160-by-90 RGB persistence detection and corresponding Core/App tests; no successful live dynamic or mouse-ink result has yet been recorded for this semantic build
- [ ] Identify actual slide transitions — image-only `.significantVisualChange` is now counted as a stable visual/content update, not slide identity; `slideChangeCount` remains zero until an independent identity signal is implemented and tested
- [ ] Recognize slide text and geometry — Vision has run in historical controlled builds, but the current semantic build and OCR correctness remain unverified; coordinate accuracy is also pending
- [ ] Build normalized occupied regions from detected text, rectangles, and raster candidates — the current source produces a maximum-640-pixel RGB raster and keeps `strokeCandidateRegions` separate from confirmed ink; slide-canvas cropping, PowerPoint UI exclusion, coordinate accuracy, and overlap-avoidance accuracy remain pending
- [ ] Detect existing PowerPoint ink as occupied space
- [ ] Route live transcript segments into the contextual board engine
- [ ] Render stable text, boxes, arrows, and causal chains
- [ ] Save the session as JSON and SVG — the runtime-verification metadata JSON is diagnostic evidence, not a lecture-session export

**Exit criterion:** a ten-minute Japanese or English lecture can run without overlap on a controlled slide deck.

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
