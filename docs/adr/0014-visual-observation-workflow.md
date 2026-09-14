# ADR 0014: Use a visual-only observation workflow for public v1

- Status: Accepted
- Date: 2026-09-07

## Context

Public v1 needs to work with an ordinary PowerPoint slide show without controlling PowerPoint or
depending on an exact semantic bridge between a PowerPoint slide and a ScreenCaptureKit window.
PowerPoint does not expose a supported public API that provides that bridge without Automation.

## Decision

Public v1 will use a visual-only workflow:

1. The user starts a normal full-screen or windowed PowerPoint slide show, either before or after
   launching LectureBoard AI.
2. The user refreshes the available windows and selects the exact PowerPoint window to observe
   through ScreenCaptureKit. If PowerPoint creates a new slide-show surface after selection, the
   user refreshes and reselects that surface.
3. For the selected audience slide-show window, the first valid ScreenCaptureKit frame is used to
   derive the captured-content pixel bounds. Surface padding is excluded, the normalized crop must
   round-trip to the same pixel rectangle, and that validated crop is confirmed automatically as
   the production canvas. Manual canvas selection remains available only as a diagnostic or
   fallback path.
4. An explicit transcription-start request starts on-device speech recognition immediately. Board
   generation remains fail closed until the production canvas and current visual grounding are
   ready; speech capture itself does not wait for those visual prerequisites.
5. Stable visual changes within that confirmed canvas create local slide epochs. These epochs
   scope on-device speech recognition, visual analysis, board planning, and the local overlay.

The supported workflow is single-display. LectureBoard AI will not send Apple Events, request
Automation permission, or start, stop, edit, or save a PowerPoint presentation. It will not claim
exact PowerPoint semantic slide IDs and will not read speaker notes.

Presenter View and multidisplay presentation workflows are outside the public-v1 support contract.

The automatic-canvas and immediate-transcription contracts have deterministic coverage in 90
focused tests and the complete 520-test native app suite. Live microphone recognition and a
visible PowerPoint overlay remain unverified.

## Consequences

The public workflow observes PowerPoint without controlling or modifying it, and users may choose
the normal slide-show mode that fits their lecture. The original presentation remains under the
lecturer's control.

A local slide epoch is a visual continuity boundary, not a PowerPoint slide identity. Visually
indistinguishable slides cannot be distinguished, and changes that occur too rapidly or do not
remain stable long enough may be missed. Animations or ink may also create a new local epoch even
when PowerPoint remains on the same semantic slide.

ADR 0012 remains a record of the managed semantic-binding design, but that Apple
Events/Automation workflow is not part of public v1.

## Alternatives considered

### Manage the slide show through PowerPoint Automation

Rejected for public v1. It adds permission and lifecycle risk and is unnecessary for the supported
visual-only workflow.

### Infer exact slide identity or notes from captured pixels

Rejected. Pixels cannot uniquely identify visually identical slides or authorize access to hidden
speaker notes.
