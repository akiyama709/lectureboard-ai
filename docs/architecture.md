# Architecture

## Decision summary

LectureBoard AI uses a native macOS shell, a pure-Swift core package, a provider boundary around transcription and AI reasoning, and a vector scene graph for board output.

```mermaid
flowchart LR
    PPT[PowerPoint window] --> CAP[ScreenCaptureKit observer]
    PPTX[Imported .pptx and notes] --> CTX[Lecture context store]
    MIC[Microphone] --> ASR[Transcription provider]
    CAP --> SLIDE[Slide and occupied-space analysis]
    ASR --> CTX
    SLIDE --> CTX
    CTX --> IMP[Contextual importance engine]
    IMP --> PLAN[Grounded text/diagram planner]
    PLAN --> LAYOUT[Empty-space layout]
    LAYOUT --> SCENE[Vector board scene]
    SCENE --> OVERLAY[Click-through overlay]
    SCENE --> EXPORT[JSON / SVG / PDF export]
```

## Runtime separation

### Native application layer

SwiftUI and AppKit provide the setup window, presenter controls, transparent overlay, permissions, menu commands, and lifecycle.

### Capture and observation layer

ScreenCaptureKit discovers and captures only the selected PowerPoint window. Selection freezes the ScreenCaptureKit window identifier, owning process identifier, and exact PowerPoint bundle identifier. Capture start re-enumerates ScreenCaptureKit windows and proceeds only when the identifier is unique and the complete frozen identity still matches; reused identifiers, changed processes, wrong bundles, duplicates, and missing owners fail closed. The native adapter produces immutable preview frames, a coarse luminance fingerprint, and, when rasterization succeeds, a fixed 160-by-90 RGB content fingerprint. `LectureBoardCore` confirms coarse stability only after consecutive matching fingerprints. A confirmed large image difference is named `.significantVisualChange`; it is not a statement that the PowerPoint slide identity changed. The app counts both coarse stable visual changes and persistent dense-RGB changes as content revisions rather than slide changes.

The independent identity foundation is deterministic and provider-neutral. Core confirms an initial baseline or a slide change only after two consecutive samples with the same presentation-session token and slide ID. An unavailable gap discards continuity; recovery establishes a baseline instead of inferring a transition across the gap. A presentation-session change likewise establishes a new baseline. An index update for the same slide ID updates the board number without counting a change or clearing its elements. The app accepts provider observations only when their selected-window target, capture session, and sequence remain current. Frames received while an identity candidate is being confirmed still contribute to delivery metrics but are excluded from visual analysis. At baseline establishment or a confirmed transition, old analysis and board scenes are discarded; analysis resumes only for a `.new` frame whose ScreenCaptureKit `displayTime` is strictly later than the app's local mach-absolute acceptance time for the confirming observation. Apple Speech results carry a local mach-absolute callback time. A final result cannot create a board proposal if it was emitted before the identity boundary, before the app locally accepted the post-boundary frame, or while that frame is still required; delayed MainActor delivery does not relax either timestamp boundary. The post-boundary gate exposes `waiting`, `synchronized`, and `timedOut` states. Timeout remains fail-closed and cannot admit an idle, missing-time, equal-time, older, or otherwise stale frame. Boundary tokens prevent delayed timeout callbacks from changing a newer boundary or stopped session, and a later strictly newer `.new` frame can recover after timeout. This makes a static-slide pause diagnosable, but it does not implement or runtime-verify automatic fresh-frame acquisition.

The default identity provider is deliberately side-effect free: for each accepted capture start, it requests no Automation permission, sends no Apple Event, and emits one unavailable observation. A read-only PowerPoint probe observed Automation preflight status `0`, one slide-show window, and two Core Graphics windows, but PowerPoint's inherited `window.id` was `nil`. The semantic slide result therefore could not be bound to the exact ScreenCaptureKit/Core Graphics window ID. A production provider remains unimplemented, and no weaker name-, order-, or geometry-based fallback is accepted.

For each accepted stable visual frame or content update, the native analyzer creates an sRGB RGB8 raster whose long edge is at most 640 pixels. It runs Vision text recognition and rectangle detection and separately runs deterministic raster occupancy analysis. The raster output is deliberately named `strokeCandidateRegions`; candidates may include text, diagram edges, PowerPoint controls, or other window content and are not confirmed PowerPoint ink. Vision's lower-left coordinates are converted to the app's top-left normalized coordinate system before deterministic Core logic filters low-confidence, tiny, and near-full-frame detections, pads text, rectangles, and stroke candidates, and transitively merges touching occupied regions. The current analyzer receives the whole selected window rather than a cropped slide canvas. The app observes PowerPoint rather than modifying the source presentation in the first implementation.

The metadata-only runtime report uses schema version 5. It adds `slideIdentityFrameSyncState` to the schema-4 identity state and counters while excluding slide IDs, presentation paths or tokens, captured images, recognized text, window titles, and coordinates. Schema-1 through schema-4 reports remain decodable; absent frame-sync metadata defaults to `notRequired`, while absent identity metadata defaults to unavailable and zero. Historical schema-1 and pre-semantic-correction schema-2 `slideChangeCount` values still represent the older image-difference heuristic rather than verified slide identity.

### LectureBoardCore

The independent Swift package owns serializable models, stable-frame and significant-visual-change classification, persistent RGB-content-change detection, deterministic slide-identity tracking, RGB raster models, stroke-candidate analysis, slide-observation filtering, normalized occupied-region assembly, runtime-report models, importance scoring, grounded intent classification, empty-space layout, and scene composition. It does not import AppKit, ScreenCaptureKit, Vision, Speech, or any cloud SDK.

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

- The overlay prototype is a separate window intended to be click-through and immediately hideable; its runtime position, sizing, click-through behavior, and pen-tablet non-interference are unverified.
- PowerPoint remains the authoritative lecture application.
- The speech prototype does not modify or control PowerPoint; end-to-end runtime behavior during transcription failure is unverified.
- The deterministic classifier supports a deferred outcome for uncertain semantic input; end-to-end display gating is not yet implemented or verified.
- Session persistence is not implemented. When added, it is intended to be optional and transactional.

## Initial implementation compromises

- The first speech path handles one selected language at a time.
- The initial context engine is deterministic and heuristic, serving as a testable baseline.
- The first overlay uses the selected display rather than exact PowerPoint-window coordinate mapping.
- The current schema-5 source passes 98 Core tests and 110 native app tests, but it has not yet completed a live dynamic or mouse-ink run. Historical schema-1 and pre-semantic schema-2 runs are build-specific evidence only.
- Image content is not an independent slide-identity signal. The tracker and app safety boundaries are implemented, but the production PowerPoint provider and live transition validation are not. The default provider therefore cannot establish actual slide identity.
- Explicit fail-closed timeout/state handling after an identity boundary is implemented and deterministically tested. Automatic exact-window fresh-frame acquisition and live timeout behavior with a production identity provider remain unimplemented or unverified.
- The current capture and analysis path uses the whole selected PowerPoint window. Slide-canvas cropping and exclusion of PowerPoint controls or other window UI are not implemented.
- Vision and raster candidate paths compile and are covered by deterministic tests, but OCR accuracy, coordinate fidelity, false detections, candidate thresholds, and representative-deck behavior remain unverified.
- `strokeCandidateRegions` are occupancy candidates, not verified existing PowerPoint ink. Existing-ink classification, thin or semitransparent stroke calibration, and pen-tablet behavior remain unverified.
- Independent LaunchServices authorization, window reselection, and lecture-length reliability remain unverified.
