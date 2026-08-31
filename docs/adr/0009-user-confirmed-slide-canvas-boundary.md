# ADR 0009: Require a user-confirmed slide-canvas boundary

- Status: Accepted
- Date: 2026-08-30

## Context

ScreenCaptureKit can capture an exact selected PowerPoint window, but the captured window can include PowerPoint controls, surrounding chrome, letterboxing, or other material outside the rendered slide. Stability detection, OCR, raster occupancy, and board placement must not treat that surrounding UI as slide content.

The public macOS and PowerPoint interfaces available to this project do not expose an exact internal slide-canvas rectangle that can be safely bound to the selected ScreenCaptureKit window. ScreenCaptureKit's surface `contentRect` is not the rectangle of PowerPoint's internal slide subview. PowerPoint scripting exposes presentation and window information but not a usable internal rendered-canvas rectangle bound to the selected exact window. Public Accessibility data also provides no supported exact bridge for this purpose.

Aspect-ratio fitting, title matching, window order, approximate bounds, Accessibility heuristics, and image or Vision inference can produce candidates, but none proves the exact slide canvas across editing, windowed slideshow, full-screen, presenter, animation, letterboxed, and multi-display modes. Automatically treating such a candidate as confirmed geometry would allow PowerPoint UI into the visual pipeline or could crop real slide content.

## Decision

The default app requires the user to explicitly confirm the slide canvas before visual processing begins.

- The app freezes a preview from the current accepted exact-window capture operation.
- The user drags around the visible slide and confirms the rectangle explicitly.
- The normalized top-left rectangle must map to at least 32 by 24 source pixels and 1,024 square pixels, and it is bound to the capture operation, exact ScreenCaptureKit window ID, source pixel dimensions, and validated ScreenCaptureKit surface geometry.
- Capture restart, window mismatch, source-size mismatch, missing usable surface geometry after the narrow idle policy below, or a change in the relevant ScreenCaptureKit surface geometry invalidates the confirmation and clears dependent visual and board state.
- Idle surface handling is a provisional application policy rather than an Apple guarantee. For a verified `.idle` delivery only, when `contentRect`, `scaleFactor`, and `contentScale` are all absent, the app reuses the previously latched surface geometry solely to crop the unchanged visual payload. A complete current tuple is accepted only when it exactly matches the latched geometry. Partial, malformed, conflicting, or non-idle evidence, missing prior geometry, and prior output dimensions that do not match the visual payload all fail closed and poison repeat geometry until a later `.new` frame. The all-absent branch does not inherit or use `screenRect`, so overlay mapping remains closed.
- Missing, malformed, and unknown `SCFrameStatus` values are dropped. Only `.complete` and `.started` produce new deliveries; only `.idle` produces a repeat. Surface scale factor must fall in the SDK-documented inclusive range from 1 through 4.
- Without a current confirmation, capture-delivery metrics may advance, but stable-frame detection, dense content-change detection, Vision, raster occupancy, occupied-region assembly, transcript-driven board placement, and board output remain closed.
- With a current confirmation, the rectangle is outward-rounded to bounded source pixels. The coarse stability fingerprint, 160-by-90 RGB content fingerprint, Vision input, maximum-640-pixel raster, occupied regions, and board-placement input all derive from the cropped canvas.
- Semantic slide changes, canvas selection or invalidation, and capture lifecycle boundaries invalidate the current board context. Transcript segments accumulated before that boundary cannot be proposed again afterward.
- Independent App and Apple-provider generations guard transcription. Each semantic slide, canvas, or capture boundary stops transcription and invalidates old callbacks; transcription remains closed until the user explicitly resumes it.
- A completed visual analysis with no occupied regions does not authorize board placement; transcript-driven proposals remain closed until the current context has a nonempty occupied-region result.
- A coarse or dense visual-change candidate, or a missing or invalid dense fingerprint, immediately invalidates prior analysis. A confirmed coarse frame without a valid dense fingerprint cannot start analysis, and baseline recovery does not reopen proposals until current-frame analysis completes.
- Capture end clears the latest stable frame, visual analysis, and board scene.
- Capture start clears demo content. Demo generation is disabled while capture is active or capture-provider shutdown is in progress.
- The app does not silently confirm a rectangle from titles, enumeration order, approximate geometry, aspect ratio, Accessibility, Vision, or image heuristics.

The runtime-report format moves to schema 6 by adding only `slideCanvasState`. It does not record the selected rectangle, surface geometry, captured images, recognized text, coordinates, slide IDs, or presentation paths or tokens. Schema 1 through schema 5 remain decodable, with missing canvas state interpreted as unavailable.

## Alternatives considered

### Treat the entire selected window as the slide

Rejected for the default app. PowerPoint controls and surrounding UI could influence stability, OCR, raster occupancy, empty-space selection, and board placement.

### Infer the canvas automatically from aspect ratio or image analysis

Rejected as a confirmation source. A deck can use a custom slide size, and visual boundaries can be ambiguous. Such methods may later suggest a candidate, but the candidate must remain visibly unconfirmed until a user accepts it and its provenance is bound to the exact capture.

### Derive the canvas from ScreenCaptureKit `contentRect`

Rejected. The rectangle describes the captured surface rather than PowerPoint's internal slide subview. It is retained as provenance that can invalidate a confirmation when the captured surface changes, not as proof of slide-canvas location.

### Use PowerPoint Automation or Accessibility geometry

Rejected as the current default. No public exact-window-bound internal canvas rectangle was found, and weaker name-, ordering-, approximate-bounds-, or frontmost-window matching is not accepted.

## Consequences

The visual pipeline now fails closed instead of analyzing PowerPoint UI by default. It introduces one explicit setup action after capture starts and whenever the bound capture or surface geometry changes. Capture delivery remains observable while the app waits, so the missing confirmation is diagnosable without admitting image content to downstream analysis.

Deterministic Core and native tests cover normalized-region and minimum source-pixel validation, outward pixel mapping, cropping, exact provenance matching, the all-absent idle policy, complete-tuple matching, poison latching until a new frame, frame-status and scale validation, pre-confirmation gating, invalidation, current-board-context rejection, double-generation transcription rejection, dense-fingerprint analysis invalidation, empty-occupancy proposal rejection, demo isolation, and exclusion of synthetic material outside the confirmed region. A pre-fix schema-9 live report recorded `idleRepeatSurfaceGeometryUnavailableOrMismatched`, which bounds the failure class but does not distinguish absent from mismatched attachments. These tests and that report do not establish post-fix live recovery, the raw ScreenCaptureKit idle-attachment form, live PowerPoint localization accuracy, PowerPoint-UI exclusion accuracy, ScreenCaptureKit padding or `contentRect` mapping, resize behavior, slideshow-mode coverage, display-scale behavior, live microphone behavior, overlay alignment, representative-deck performance, OCR coordinate accuracy, or lecture reliability.

The transparent overlay is still full-screen. Canvas cropping establishes analysis coordinates only; it does not establish screen-coordinate alignment for rendering. Exact overlay alignment is a separate follow-up unit and must not be inferred from this decision.

## Follow-up actions

1. Validate manual canvas localization and invalidation on controlled live PowerPoint windowed, full-screen, and presenter modes, including resizing and multiple displays.
2. Measure ScreenCaptureKit surface padding, `contentRect`, scale, and source-image mapping before making coordinate-accuracy claims.
3. Map confirmed canvas coordinates to the overlay's screen coordinates with an independently tested, fail-closed geometry boundary.
4. Calibrate live OCR, raster candidates, occupied regions, existing ink, and board placement only after the canvas boundary is verified for the tested mode.

## Follow-up — 2026-08-31

The full-screen-overlay consequence and follow-up item 3 above record the state when this ADR was accepted. [ADR 0010](0010-fail-closed-production-overlay-boundary.md) subsequently accepts an implemented fail-closed production mapper from the confirmed canvas and current ScreenCaptureKit geometry to one exact AppKit target rectangle. Full-display rendering is now a separate demo-only path rather than a production fallback.

This follow-up changes the implementation status, not the evidence boundary of this ADR. The mapper and its production-display safety gates have deterministic synthetic and native integration coverage only. Live PowerPoint alignment, window-list z-order, multiple displays, resize and movement, click-through behavior, and pen-input non-interference remain unverified.
