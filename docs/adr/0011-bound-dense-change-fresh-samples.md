# ADR 0011: Bound one-shot samples to the current dense-change candidate

- Status: Accepted
- Date: 2026-09-01

## Context

The dense 160-by-90 RGB detector requires three matching qualifying observations before it confirms a same-slide content revision. This prevents a transient image from immediately changing the board context. A controlled schema-9 PowerPoint mouse-ink run visually restored the original slide after erase, but the stream did not provide the third qualifying post-erase delivery needed to record a distinct revision. Weakening the detector thresholds would reduce the persistence guarantee and would turn a missing-delivery problem into a classification-policy change.

ScreenCaptureKit provides `SCScreenshotManager` for one-shot capture of a content filter. Such a screenshot is separate from `SCStream`: it has no stream sequence, no stream `displayTime`, and no current screen-position provenance. Treating it as an ordinary stream delivery would incorrectly alter capture metrics, semantic slide synchronization, or overlay coordinates.

The app therefore needs a narrowly scoped way to request additional visual evidence for an already pending dense candidate without allowing a stale screenshot to cross capture, window, canvas, slide-identity, or candidate boundaries.

## Decision

When one accepted continuous-stream canvas frame creates a dense content-change candidate, the app may request at most two one-shot samples approximately 100 milliseconds apart. The detector thresholds remain unchanged.

Each episode is bound to an opaque token created by `StableContentChangeDetector` for that exact pending candidate. A one-shot fingerprint can only add evidence to the matching token; malformed, dimensionally inconsistent, different, foreign, replaced, reset, rebased, discarded, or already confirmed candidates are rejected without mutating detector state.

Before each request and again before accepting its result, the app requires all of the following to remain unchanged:

- active capture operation;
- exact ScreenCaptureKit window ID, owning process ID, and PowerPoint bundle identifier;
- selected window and latest accepted stream sequence;
- absence of a capture-content gap;
- confirmed canvas selection and canvas generation;
- slide-identity generation, state, quarantine state, and post-identity frame-gate state;
- dense-candidate token.

The capture actor re-enumerates the selected window both before and after the one-shot operation and accepts only one unique exact identity match. It permits only one OS screenshot request at a time, retains that busy boundary across stop and restart until the older callback returns, applies the same output-configuration policy as continuous capture to the fresh filter, and accepts only a valid BGRA sample classified as `.complete` or `.started` with a complete validated surface-geometry tuple. A mismatch or missing value fails closed.

A provider-busy response does not consume either of the candidate's two actual capture attempts. It is deferred through the same 100-millisecond waiter and is separately bounded to ten deferrals. Other provider errors exhaust the current episode. A new stream delivery cancels the current request before processing that delivery; if the same candidate remains pending, its already consumed attempt count is retained. Invalid dense or comparable-coarse evidence discards the pending detector candidate so that the same token cannot obtain a new budget.

The one-shot image is cropped only through the already confirmed canvas. Full-frame coarse comparison re-rasterizes the accepted stream canvas image and the one-shot image through the same deterministic CGImage path. Production canvas selection requires identical surface geometry; synthetic whole-frame tests require identical source dimensions. A rejected one-shot sample does not invalidate an otherwise valid user canvas.

One-shot samples never enter the normal stream-frame receiver. They do not increment capture, new-frame, repeat, stable-frame, semantic identity, or slide-change metrics; do not satisfy a post-identity stream-frame gate; do not replace stream geometry; and do not create overlay mapping or lease provenance. A confirmed dense revision may start Vision analysis, but that analysis alone cannot render or renew the production overlay. A later eligible continuous-stream frame is required before display can resume.

The task awaiting the OS callback captures the provider separately and retains the app model only for synchronous preflight and post-result handling. Stop, deallocation, or another boundary can therefore release the model even if the OS callback does not return. The capture actor still rejects any eventual stale completion.

## Alternatives considered

### Lower the dense detector threshold or required observation count

Rejected. The live limitation was insufficient qualifying evidence, not a validated reason to weaken the persistence contract.

### Count an idle repeat as a newly acquired screenshot

Rejected. An idle stream delivery reuses prior visual payload and does not prove a new independent observation.

### Feed the screenshot through the normal stream receiver

Rejected. It lacks a stream sequence, `displayTime`, and current `screenRect`, and would contaminate capture metrics, semantic synchronization, and overlay provenance.

### Reuse the one-shot path to open the post-identity frame gate

Rejected. ADR 0008 requires a strictly newer `.new` stream frame with qualifying `displayTime`. A one-shot screenshot does not carry that provenance.

### Queue an unbounded number of requests while the provider is busy

Rejected. A missing OS callback could create an unbounded retry or memory-lifetime path. Busy deferrals and actual screenshot attempts are bounded separately.

## Consequences

The implementation can seek the two additional observations needed by the existing three-observation dense detector while preserving exact-window and fail-closed boundaries. It deliberately gives up after bounded provider contention, malformed evidence, a stale boundary, or a mismatched result. The normal stream remains the authoritative source for delivery metrics, semantic timing, coordinate mapping, and overlay display.

Deterministic Core and native tests cover candidate-token invalidation, stale and foreign tokens, exact identity and surface checks, crop and fingerprint production, one-provider-at-a-time lifecycle, sample-buffer conversion, successful two-sample confirmation, stale result rejection, stop and restart, provider and geometry failures, coarse mismatch, bounded busy deferral, stream recovery, model lifetime, and exclusion from stream and overlay provenance.

These tests and compilation do not establish that `SCScreenshotManager` supplies the required status and geometry attachments in live PowerPoint, that two one-shot captures will detect erase reliably, or that current schema-10 PowerPoint behavior is correct. A separately identified fixed-build live checkpoint is required before any such claim.

## Follow-up actions

- [x] Run the full local verification gate and record the exact automated evidence in [`docs/build-verification.md`](../build-verification.md).
- [ ] Freeze a separately named schema-10 app without moving the schema-8 or schema-9 evidence apps.
- [ ] Validate one static exact-window sample before sending any PowerPoint input.
- [ ] Run controlled mouse-ink and erase input only after the static boundary passes, and record whether a distinct post-erase revision occurs.
- [ ] Keep this path separate from future exact-window post-identity recovery, user-confirmed canvas accuracy, visible overlay alignment, and semantic ink classification.
