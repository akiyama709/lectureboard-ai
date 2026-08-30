# Architecture

## Decision summary

LectureBoard AI uses a native macOS shell, a pure-Swift core package, a provider boundary around transcription and AI reasoning, and a vector scene graph for board output.

```mermaid
flowchart LR
    PPT[PowerPoint window] --> CAP[ScreenCaptureKit observer]
    PPTX[Imported .pptx and notes] --> CTX[Lecture context store]
    MIC[Microphone] --> ASR[Transcription provider]
    CAP --> CANVAS[User-confirmed slide-canvas boundary]
    CAP --> SCREEN[Frame-local screen geometry]
    CANVAS --> SLIDE[Slide and occupied-space analysis]
    CANVAS --> MAP[Fail-closed overlay mapper]
    SCREEN --> MAP
    ASR --> CTX
    SLIDE --> CTX
    CTX --> IMP[Contextual importance engine]
    IMP --> PLAN[Grounded text/diagram planner]
    PLAN --> LAYOUT[Empty-space layout]
    LAYOUT --> SCENE[Vector board scene]
    SCENE --> OVERLAY[Click-through overlay]
    MAP --> OVERLAY
    SCENE --> EXPORT[JSON / SVG / PDF export]
```

## Runtime separation

### Native application layer

SwiftUI and AppKit provide the setup window, presenter controls, transparent overlay, permissions, menu commands, and lifecycle.

### Capture and observation layer

ScreenCaptureKit discovers and captures only the selected PowerPoint window. Selection freezes the ScreenCaptureKit window identifier, owning process identifier, and exact PowerPoint bundle identifier. Capture start re-enumerates ScreenCaptureKit windows and proceeds only when the identifier is unique and the complete frozen identity still matches; reused identifiers, changed processes, wrong bundles, duplicates, and missing owners fail closed. The native adapter produces immutable exact-window frames and delivery metrics. Frame-status parsing is fail closed: only `.complete` and `.started` create a new delivery, and only `.idle` creates a repeat. Missing, malformed, unknown, `.blank`, and `.suspended` statuses, invalid samples, and conversion failures clear repeatable content, notify an ordered content-unavailable boundary, and require a later `.new` delivery before visual processing resumes. `.stopped` is terminal and uses a fixed localized capture error. Surface scale factor is accepted only in the SDK-documented inclusive range from 1 through 4. Those whole-window deliveries are not admitted to visual stability, content-update, Vision, raster, occupancy, or board-placement processing until the slide canvas has been explicitly confirmed.

Public macOS and PowerPoint APIs do not expose an exact rectangle for the internal rendered slide canvas. ScreenCaptureKit's `contentRect` describes the captured surface, not PowerPoint's internal slide subview, and the public PowerPoint scripting and Accessibility surfaces do not provide a safely bindable exact canvas rectangle. The app therefore freezes a preview from the exact accepted capture operation and asks the user to drag around the visible slide and confirm it. The resulting top-left normalized region must map to at least 32 by 24 source pixels and 1,024 square pixels, and it is bound to that capture operation, exact ScreenCaptureKit window ID, source pixel dimensions, and validated ScreenCaptureKit surface geometry. Capture restart, window mismatch, pixel-dimension mismatch, missing surface geometry, or a change in `contentRect`, scale factor, or content scale invalidates the confirmation and clears visual state. An idle delivery marks the repeated visual payload as surface-geometry-valid only when `contentRect`, scale factor, and content scale re-read from the current sample attachments exactly match the last visual payload's surface geometry. Changed, missing, or invalid current surface geometry, or missing last-payload surface geometry, leaves the repeat without surface geometry so that only delivery metrics advance and the canvas is invalidated before visual processing. If the idle sample has no image buffer, only the fixed stream surface dimensions are inherited from the last frame. The app does not silently infer a replacement from titles, window order, geometry, aspect ratio, or image heuristics. Live ScreenCaptureKit idle-attachment behavior remains unverified.

Onscreen placement is a separate, dynamic boundary. Every new or idle delivery parses its own ScreenCaptureKit `.screenRect`; an idle delivery may reuse the prior visual payload but never inherits the prior onscreen position. A missing, malformed, nonfinite, or non-positive current `screenRect` therefore leaves the frame without screen geometry. This does not by itself change the confirmed canvas crop, whose provenance is the captured surface, but it clears the overlay placement and hides the production overlay until a later accepted frame supplies valid current geometry.

The overlay-coordinate mapper is deterministic and side-effect free. It accepts only a production ScreenCaptureKit canvas confirmation whose capture operation, exact window ID, complete `CaptureSurfaceGeometry`, and output dimensions match the current accepted frame. It checks that `contentRect` scaled by `scaleFactor` remains within the output surface, that `screenRect` scaled by `contentScale` agrees with the captured content within one output pixel of rounding tolerance, and that the outward-rounded canvas crop lies wholly inside the content support rather than surface padding. It then maps the canvas from output pixels into ScreenCaptureKit's global Quartz screen rectangle, requires exactly one validated display to contain the entire target, and converts that target through the paired `CGDisplayBounds` and `NSScreen.frame` snapshot into AppKit's bottom-left window coordinates. Missing, contradictory, cross-display, or multiply contained geometry returns no placement; there is no main-display, window-descriptor, title, ordering, or last-known-position fallback.

App integration adds a second freshness check: a placement is usable only when its capture operation, window ID, and frame sequence equal the active capture and latest eligible frame. Production rendering requires confirmed semantic identity and fresh completed visual grounding. It also requires the frozen PowerPoint PID and exact bundle to be frontmost, exactly one matching on-screen layer-zero Core Graphics window, agreement between that window's bounds and the current `screenRect` within a two-point edge tolerance, no earlier on-screen window intersecting the target, and exactly one current `NSScreen` containing the AppKit target. Any failed mapping, lifecycle or semantic boundary, missing current position, capture-content or visual uncertainty, manual suppression, focus or Space change, stale placement, or independently expiring eligibility lease hides the overlay. Only an eligible current capture delivery renews the lease; unchanged physical renders are deduplicated without bypassing eligibility. Moving screen geometry can produce a new placement without invalidating an otherwise unchanged confirmed surface crop. Capture start clears and hides a loaded full-screen demo panel so that demonstration output cannot leak into production capture rendering. The safe default identity provider cannot show production output. The pure mapper and these app boundaries have deterministic synthetic native coverage. Their behavior with actual PowerPoint windows, real window-list z-order, multi-display arrangements, window resizing, and overlay alignment has not yet been runtime-verified.

After confirmation, the app outward-rounds the normalized rectangle to bounded source pixels and crops each matching exact-window delivery. The coarse stability fingerprint, fixed 160-by-90 RGB content fingerprint, Vision input, maximum-640-pixel raster, occupied regions, and board-placement input all derive from this cropped canvas. `LectureBoardCore` confirms coarse stability only after consecutive matching fingerprints. A confirmed large image difference is named `.significantVisualChange`; it is not a statement that the PowerPoint slide identity changed. A coarse or dense visual-change candidate immediately invalidates prior analysis. A missing or invalid dense fingerprint does the same; a confirmed coarse frame without a valid dense fingerprint cannot start analysis. After the detector returns to baseline, proposals remain closed until analysis of the current frame completes. The app counts both coarse stable visual changes and persistent dense-RGB changes as content revisions rather than slide changes. Until confirmation, capture counts remain observable but stable-frame count, content-revision count, Vision analysis, raster analysis, and board placement remain closed.

The independent identity foundation is deterministic and provider-neutral. Core confirms an initial baseline or a slide change only after two consecutive samples with the same presentation-session token and slide ID. An unavailable gap discards continuity; recovery establishes a baseline instead of inferring a transition across the gap. A presentation-session change likewise establishes a new baseline. An index update for the same slide ID updates the board number without counting a change or clearing its elements. The app accepts provider observations only when their selected-window target, capture session, and sequence remain current. Frames received while an identity candidate is being confirmed still contribute to delivery metrics but are excluded from visual analysis. At baseline establishment or a confirmed transition, old analysis and board scenes are discarded; analysis resumes only for a `.new` frame whose ScreenCaptureKit `displayTime` is strictly later than the app's local mach-absolute acceptance time for the confirming observation. Apple Speech results carry a local mach-absolute callback time. Independent App-side and Apple-provider generations reject stale callbacks. A semantic slide, canvas, or capture boundary stops transcription, invalidates prior segments and callbacks, and leaves transcription closed until the user explicitly resumes it. A final result also cannot create a board proposal if it was emitted before the identity boundary, before the app locally accepted the post-boundary frame, or while that frame is still required; delayed MainActor delivery does not relax either timestamp boundary. The post-boundary gate exposes `waiting`, `synchronized`, and `timedOut` states. Timeout remains fail-closed and cannot admit an idle, missing-time, equal-time, older, or otherwise stale frame. Boundary tokens prevent delayed timeout callbacks from changing a newer boundary or stopped session, and a later strictly newer `.new` frame can recover after timeout. These transcription boundaries are covered by controllable providers, not live microphone input. The frame gate makes a static-slide pause diagnosable, but it does not implement or runtime-verify automatic fresh-frame acquisition.

The default identity provider is deliberately side-effect free: for each accepted capture start, it requests no Automation permission, sends no Apple Event, and emits one unavailable observation. A read-only PowerPoint probe observed Automation preflight status `0`, one slide-show window, and two Core Graphics windows, but PowerPoint's inherited `window.id` was `nil`. The semantic slide result therefore could not be bound to the exact ScreenCaptureKit/Core Graphics window ID. A production provider remains unimplemented, and no weaker name-, order-, or geometry-based fallback is accepted.

For each accepted stable visual frame or content update from the confirmed canvas, the native analyzer creates an sRGB RGB8 raster whose long edge is at most 640 pixels. It runs Vision text recognition and rectangle detection and separately runs deterministic raster occupancy analysis. The raster output is deliberately named `strokeCandidateRegions`; candidates may include text, diagram edges, or other visible material inside the confirmed region and are not confirmed PowerPoint ink. Vision's lower-left coordinates are converted to the app's top-left normalized canvas coordinate system before deterministic Core logic filters low-confidence, tiny, and near-full-frame detections, pads text, rectangles, and stroke candidates, and transitively merges touching occupied regions. The app observes PowerPoint rather than modifying the source presentation in the first implementation.

Semantic slide changes, canvas selection or invalidation, and capture lifecycle boundaries advance a current-board-context generation and discard earlier transcript and board candidates. A transcript segment collected before such a boundary cannot be proposed again in the new context. Transcript-driven board proposals additionally require a ready visual analysis with at least one occupied region; an empty result keeps placement fail-closed rather than treating an unverified blank map as safe space. Capture end clears the latest stable frame, visual analysis, and board scene. These are deterministic safety boundaries, not evidence of live PowerPoint correctness.

The bundled demo scene is isolated from live capture state. Capture start clears it, and demo generation is disabled while capture is active or capture-provider shutdown is in progress. This prevents demonstration content from being mistaken for capture-grounded board output; it does not validate live rendering.

The metadata-only runtime report uses schema version 6. It adds only `slideCanvasState` to the schema-5 identity, frame-sync, and analysis metadata while excluding the selected rectangle, slide IDs, presentation paths or tokens, captured images, recognized text, window titles, and coordinates. Schema-1 through schema-5 reports remain decodable; absent canvas metadata defaults to unavailable, absent frame-sync metadata defaults to `notRequired`, and absent identity metadata defaults to unavailable and zero. Historical schema-1 and pre-semantic-correction schema-2 `slideChangeCount` values still represent the older image-difference heuristic rather than verified slide identity.

### LectureBoardCore

The independent Swift package owns serializable models, validated normalized slide-canvas regions and outward pixel mapping, stable-frame and significant-visual-change classification, persistent RGB-content-change detection, deterministic slide-identity tracking, RGB raster models, stroke-candidate analysis, slide-observation filtering, normalized occupied-region assembly, runtime-report models, importance scoring, grounded intent classification, empty-space layout, and scene composition. It does not import AppKit, ScreenCaptureKit, Vision, Speech, or any cloud SDK.

### Provider layer

Transcription and slide identity conform to narrow native-app protocols. The initial repository includes an Apple Speech single-language prototype and a no-side-effect unavailable slide-identity provider. The latter is a safe boundary default, not a production PowerPoint adapter. A semantic-planning provider boundary is still future work. Future transcription and planning providers may use SpeechAnalyzer, whisper.cpp, a local language model, or an explicitly configured cloud API.

## Intended core data flow

The following is the target end-to-end lecture flow, not a statement that every stage is implemented or runtime-verified. The current Core contains heuristic importance scoring, grounded intent classification, empty-space layout, vector scene composition, and evidence-bearing models. A dedicated factual validator, complete live context-store wiring, and stable live renderer animation remain unimplemented or unverified.

1. Final transcript segments enter the context store.
2. The importance scorer compares each segment with slide text and recent speech.
3. The classifier selects a board form without inventing new content.
4. A validator attaches source evidence and rejects unsupported names, numbers, dates, quotations, and formulas.
5. The layout engine chooses a free normalized region.
6. The scene composer emits vector elements.
7. The renderer animates only newly confirmed elements and leaves existing elements still.

## Scene graph

Board output is stored as text blocks, rounded rectangles, ellipses, lines, arrows, normalized positions, style roles, source intent identifiers, and language tags. This allows resolution-independent display and later SVG/PDF export.

## Failure-containment design

These are design constraints and prototype boundaries rather than a claim of complete runtime validation:

- The overlay prototype is a separate window configured to be click-through; its production frame is computed from the current exact-window delivery and confirmed canvas. Mapping and stale-placement rejection are implemented and deterministically tested, but actual PowerPoint position and sizing, multiple-display behavior, resize handling, z-order, click-through behavior, and pen-tablet non-interference remain runtime-unverified.
- PowerPoint remains the authoritative lecture application.
- The speech prototype does not modify or control PowerPoint; end-to-end runtime behavior during transcription failure is unverified.
- The deterministic classifier supports a deferred outcome for uncertain semantic input; end-to-end display gating is not yet implemented or verified.
- Session persistence is not implemented. When added, it is intended to be optional and transactional.

## Initial implementation compromises

- The first speech path handles one selected language at a time.
- The initial context engine is deterministic and heuristic, serving as a testable baseline.
- The production overlay now uses a fail-closed mapping from the exact current frame's screen geometry to the confirmed slide canvas. The separate demo path still intentionally uses a selected full display. Live coordinate correctness and z-order remain unverified.
- The current schema-6 source passes 107 Core tests in 15 suites and 192 native app tests in 23 suites, but it has not yet completed a live dynamic, mouse-ink, microphone, manual canvas-localization, or aligned-overlay run. Historical schema-1 and pre-semantic schema-2 runs are build-specific evidence only.
- Image content is not an independent slide-identity signal. The tracker and app safety boundaries are implemented, but the production PowerPoint provider and live transition validation are not. The default provider therefore cannot establish actual slide identity.
- Explicit fail-closed timeout/state handling after an identity boundary is implemented and deterministically tested. Automatic exact-window fresh-frame acquisition and live timeout behavior with a production identity provider remain unimplemented or unverified.
- The visual pipeline is fail-closed until the user confirms a slide-canvas rectangle and then uses only that crop. Selection, pixel mapping, cropping, invalidation, and pipeline gating have deterministic Core and native fixture coverage. Live PowerPoint localization and UI-exclusion accuracy, ScreenCaptureKit surface padding and `contentRect` mapping, presentation modes, resizing, and display arrangements remain unverified.
- Vision and raster candidate paths compile and are covered by deterministic tests on cropped synthetic images, but live OCR accuracy, coordinate fidelity, false detections, candidate thresholds, and representative-deck behavior remain unverified.
- `strokeCandidateRegions` are occupancy candidates, not verified existing PowerPoint ink. Existing-ink classification, thin or semitransparent stroke calibration, and pen-tablet behavior remain unverified.
- Independent LaunchServices authorization, window reselection, and lecture-length reliability remain unverified.
