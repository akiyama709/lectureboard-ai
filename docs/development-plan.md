# Development plan

## Completion and release status

Project completion is the public `v1.0.0` GitHub Release, containing an installable macOS artifact that is signed with Developer ID and accepted by Apple notarization. The existing public source repository is the development venue, not the completed product. Alpha, beta, and release-candidate builds are intermediate evidence gates.

Current status: this repository is an alpha scaffold. No alpha, beta, release-candidate, or `v1.0.0` GitHub Release has been published.

## Phase A — repository and deterministic baseline

The current scaffold establishes a testable core, native application shell, permissions, PowerPoint-window discovery, speech-permission and provider scaffolding, and transparent overlay.

## Phase B — live observation

- Continuous ScreenCaptureKit stream
- Stable-frame and slide-change detection
- Deterministic fail-closed mapping from a user-confirmed captured canvas to one exact AppKit overlay rectangle is implemented; live PowerPoint alignment, window movement and resizing, multi-display conversion, z-order, and click-through behavior remain unverified
- Production-overlay eligibility is fail-closed across exact PowerPoint identity, foreground ownership, Core Graphics window bounds and occlusion, manual suppression, visual-content availability, and an independently expiring lease; the full-display panel is demo-only and is not a production fallback
- Vision text boxes and occupied-space mask
- Detection of added PowerPoint ink

## Phase C — grounded semantic planning

- `.pptx` package reader
- Speaker-note extraction
- Provider protocol for local and cloud semantic models
- Evidence-linked structured output
- Strict validator for names, numbers, dates, quotations, and formulas

## Phase D — bilingual quality

- Japanese and English session glossaries
- Short-span language identification
- Code-switching transcription experiments
- Term-preservation rules
- Important-term bilingual display

## Phase E — alpha integration and controlled lecture validation

- Controlled dry runs
- Ten-minute lecture trials
- Full-classroom pilots with consent and fallback procedures
- Reliability, usefulness, cognitive-load, and privacy evaluation
- Explicit separation of current-build evidence from historical-build evidence
- Live validation of the implemented confirmed-canvas overlay mapping and eligibility boundary before any alignment, click-through, or pen-input claim
- Alpha packaging that is clearly marked as unfinished

**Gate:** the observable lecture path works end to end under controlled conditions. Alpha is not project completion.

## Phase F — beta validation

- Representative Japanese, English, and staged mixed-language decks
- Repeated classroom trials on supported Mac and display configurations
- OCR, coordinate, occupancy, annotation-quality, recovery, and long-duration calibration
- Privacy, accessibility, dependency-license, and third-party-notice review
- Complete known-limitations and tester fallback documentation

**Gate:** invited testers can repeatedly use a feature-complete build and all material failures are tracked. Beta is not project completion.

## Phase G — release candidate

- Freeze the `v1.0.0` scope and supported environment
- Resolve release-blocking defects
- Produce the reproducible distribution artifact
- Apply hardened runtime and Developer ID distribution signing
- Submit the installable artifact for Apple notarization and staple the result where applicable
- Verify installation, Gatekeeper acceptance, first launch, permissions, and the core lecture path on a clean supported Mac
- Finalize installation, privacy, security, troubleshooting, and release documentation

**Gate:** the exact candidate artifact satisfies every pre-publication item in [`v1-release-checklist.md`](v1-release-checklist.md). A release candidate is not project completion.

## Phase H — public v1.0.0 release

- Verify the exact release commit and artifact
- Obtain explicit approval immediately before external publication
- Publish the `v1.0.0` tag and public GitHub Release
- Attach the signed and notarized installable macOS artifact, release notes, and SHA-256 checksum
- Re-download the public artifact and verify its checksum, signature, notarization, installation, and launch
- Record the release URL and final evidence

**Completion gate:** the public `v1.0.0` GitHub Release and its re-downloaded artifact pass the complete release checklist.
