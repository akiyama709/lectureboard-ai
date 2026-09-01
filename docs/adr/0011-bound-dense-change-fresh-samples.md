# ADR 0011: Bound one-shot samples to the current visual-change candidate

- Status: Accepted
- Date: 2026-09-01

## Context

The coarse stability detector and dense 160-by-90 RGB detector each require three matching qualifying observations before confirming a changed visual state. This prevents a transient image from immediately changing the board context. A controlled schema-9 PowerPoint mouse-ink run visually restored the original slide after erase, but the stream did not provide the third qualifying post-erase delivery needed to record a distinct revision. Weakening the detector thresholds would reduce the persistence guarantee and would turn a missing-delivery problem into a classification-policy change.

A later schema-11 dynamic run exposed the same delivery-cadence gap in the coarse path. After the first controlled slide input, the stream supplied candidate observations at approximately 4.245 and 5.283 seconds but supplied no third confirming delivery until approximately 8.140 seconds, after the next input. The schema-11 evidence interval therefore crossed that second input and the strict helper correctly rejected the run. The existing bounded fresh-sample path did not help because it was connected only to a pending dense candidate, while the coarse detector remained in `collecting` or `transitioning`. This was a source-policy gap, not a reason to lower either detector threshold.

ScreenCaptureKit provides `SCScreenshotManager` for one-shot capture of a content filter. Such a screenshot is separate from `SCStream`: it has no stream sequence, no stream `displayTime`, and no current screen-position provenance. Treating it as an ordinary stream delivery would incorrectly alter capture metrics, semantic slide synchronization, or overlay coordinates.

The app therefore needs a narrowly scoped way to request additional visual evidence for an already pending post-baseline coarse or dense candidate without allowing a stale screenshot to cross capture, window, canvas, slide-identity, or candidate boundaries.

## Decision

When one accepted continuous-stream canvas frame creates either a post-baseline coarse visual-change candidate or a dense content-change candidate, the app may request at most two one-shot samples approximately 100 milliseconds apart. Initial coarse-baseline collection does not request fresh evidence. The detector thresholds remain unchanged.

Each episode is bound to a typed opaque token created by `StableFrameDetector` or `StableContentChangeDetector` for that exact pending candidate. A one-shot fingerprint can only add evidence to the matching token. For a coarse candidate, the app first compares the accepted stream canvas and one-shot canvas through the same deterministic CGImage raster path, then asks `StableFrameDetector` to confirm the exact original detector fingerprint and token. For a dense candidate, the dense fingerprint confirms only the exact pending dense token. Malformed, dimensionally inconsistent, different, foreign, replaced, reset, rebased, discarded, or already confirmed candidates are rejected without replacing or advancing detector state.

Before each request and again before accepting its result, the app requires all of the following to remain unchanged:

- active capture operation;
- exact ScreenCaptureKit window ID, owning process ID, and PowerPoint bundle identifier;
- selected window and latest accepted stream sequence;
- absence of a capture-content gap;
- confirmed canvas selection and canvas generation;
- slide-identity generation, state, quarantine state, and post-identity frame-gate state;
- typed coarse- or dense-candidate token and the token-appropriate detector evidence.

The capture actor re-enumerates the selected window both before and after the one-shot operation and accepts only one unique exact identity match. It permits only one OS screenshot request at a time, retains that busy boundary across stop and restart until the older callback returns, applies the same output-configuration policy as continuous capture to the fresh filter, and accepts only a valid BGRA sample classified as `.complete` or `.started` with a complete validated surface-geometry tuple. A mismatch or missing value fails closed.

A provider-busy response does not consume either of the candidate's two actual capture attempts. It is deferred through the same 100-millisecond waiter and is separately bounded to ten deferrals. Other provider errors exhaust the current episode. A new stream delivery cancels the current request before processing that delivery; if the same candidate remains pending, its already consumed attempt count is retained. Invalid dense or comparable-coarse evidence discards the pending detector candidate so that the same token cannot obtain a new budget. Candidate replacement, detector reset, capture stop, canvas invalidation, semantic-identity change, or stream-continuity loss also makes an older completion stale.

The one-shot image is cropped only through the already confirmed canvas. Full-frame coarse comparison re-rasterizes the accepted stream canvas image and the one-shot image through the same deterministic CGImage path. Production canvas selection requires identical surface geometry; synthetic whole-frame tests require identical source dimensions. A rejected one-shot sample does not invalidate an otherwise valid user canvas.

One-shot samples never enter the normal stream-frame receiver. They do not increment capture, new-frame, repeat, stable-frame, semantic identity, or slide-change metrics; do not satisfy a post-identity stream-frame gate; do not replace stream geometry; and do not create overlay mapping or lease provenance. A confirmed coarse or dense revision may start Vision analysis, but that analysis alone cannot render or renew the production overlay. A later eligible continuous-stream frame is required before display can resume.

Schema 11 records a metadata-only interval for the latest confirmed revision: ordinal, a mach-absolute evidence start, a mach-absolute confirmation time, and one bounded source classification. An ordinary stream-confirmed revision begins with the first qualifying continuous-stream `displayTime` and ends with the confirming stream frame's `displayTime`; an idle repeat reuses the preceding new frame's `displayTime` rather than inventing a callback-time stamp. A bounded fresh confirmation retains the original stream candidate's `displayTime` and ends with a local `mach_absolute_time()` stamp taken only after the result and all provenance guards have been accepted. The interval contains no image, recognized text, geometry, display identifier, window title, or input timestamp. For the six-input dynamic run, the strict external helper requires exactly six post-baseline revision events and exactly one as-yet-unused event per input. Each event must begin strictly after its input completes and confirm strictly before the next input starts, or before the validation cutoff for the final input; extra or reused events fail closed, and Vision must complete after the final revision. A report timestamp is not accepted as a fallback.

The task awaiting the OS callback captures the provider separately and retains the app model only for synchronous preflight and post-result handling. Stop, deallocation, or another boundary can therefore release the model even if the OS callback does not return. The capture actor still rejects any eventual stale completion.

## Alternatives considered

### Lower a detector threshold or required observation count

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

The implementation can seek the two additional observations needed by either existing three-observation detector while preserving exact-window and fail-closed boundaries. It deliberately gives up after bounded provider contention, malformed evidence, a stale boundary, or a mismatched result. The normal stream remains the authoritative source for delivery metrics, the beginning of revision provenance, semantic timing, coordinate mapping, and overlay display.

Deterministic Core and native tests cover exact coarse and dense token confirmation, candidate replacement and reset, stale and foreign tokens, exact identity and surface checks, crop and fingerprint production, one-provider-at-a-time lifecycle, sample-buffer conversion, successful two-sample confirmation, stale result rejection, stop and restart, provider and geometry failures, coarse mismatch, bounded busy deferral, stream recovery, model lifetime, evidence-interval normalization, and exclusion from stream and overlay provenance.

The schema-11 interval build completed a static exact-window diagnostic, but the earlier four-second dynamic schedule failed its strict interval check and motivated the coarse-path extension above. A separately frozen pre-decoder-hardening coarse-fresh app first stopped at a locked-session Accessibility preflight; after unlock it completed separately retained static, dynamic, and single-stroke/erase runs. Those reports remain evidence for that older producer/decoder only.

The decoder-hardened gate runtime was then frozen separately as `LectureBoard AI Schema 11 Decoder Hardened Verification.app`, executable SHA-256 `a6407496c7bd0044c3f30982e749a5556bd2b8e9a751ebd7ed476f59e9151cc9`, ad hoc CDHash `7a60426b1fb628f6fd3dce9b1c3516092d5a799a`. Its saved-path preflight report has SHA-256 `36dce0ffe83c11edbfc3990b16eee645e608fb174777330131c453d766d376d8`. A first static attempt and strict one-Escape cleanup both failed closed before runtime because the slide-show window lifecycle and editing-window restoration were not verified; a later passive exact-window check succeeded without input, and one bounded retry then completed. This sequence may reflect delayed or reused slide-show-window lifecycle state, but does not prove its root cause.

The decoder-hardened static report and sidecar have SHA-256 values `d018faf503ada46eefe0af0ac97f64cca7394cf690b6b2153b1614955ebc2a80` and `bd22de08bae4a7fafa3e4b37024b7eeca8b34f5184e0ddab3267075de47c02da`. The six-input report, SHA-256 `c7a73f7cb1bdcaa46ec216218883872d480630f7cf4ff177170f8d1906c14a3c`, records six non-reused events within the report's revision intervals with final Vision completion: five events were `coarseSignificantVisualChange` and one was `continuousDenseIdleRepeat`. No event used `boundedFreshSample`. The paired operator-captured helper sidecar, SHA-256 `5c7b0c73a8f059187f9319c2e681995e2e6a91042c5163bb821bf30bd37e488f`, supports input-window attribution for the six events under the eight-second schedule, but it is not cryptographically bound to the runtime report and is not release-grade provenance. The live report therefore verifies current fixed-build continuous-path revisions, while input attribution remains non-cryptographic, and it does not yet exercise the implementation chosen by this ADR.

The single-stroke report and sidecar have SHA-256 values `70e5772d5d4e8ab8947c725b854749fe2743b38f9189434530de2f0ad9aa63a1` and `518c60746850c40a6e428704eda2af834eaa95240b9efcb2d117ebf8f69c1aed`. The before and after-erase images are byte-identical at SHA-256 `2dcc102c64a42bf50345e769c05528c16497a98ae60b9b421cc74324479e67f4`; the after-ink image, SHA-256 `e0dbffd2e02423e64efb119ac62d31ea25b9503981589c1940308c790b865c91`, contains one visible red line. The report has separate aggregate-phase continuous-dense revision intervals, but this is not semantic or per-input ink/erase classification. Existing-ink recognition, AI rendering, a user-confirmed canvas, visible overlay alignment, semantic slide identity, and live bounded-fresh behavior remain unverified.

## Follow-up actions

- [x] Run the full local verification gate after the final decoder and documentation audits and record the exact automated evidence in [`docs/build-verification.md`](../build-verification.md); result-pointer edits made afterward receive targeted documentation and publication checks.
- [x] Record the schema-11 interval static baseline and retain the failed four-second dynamic run as negative timing evidence.
- [x] Extend the bounded path to exact post-baseline coarse candidates, add deterministic tests, pass the complete local gate for that checkpoint, and freeze a separately named schema-11 app without moving older evidence apps.
- [x] Verify the new frozen app's authorized fixed-path preflight and fail-closed `windowNotFound` report path.
- [x] Freeze the decoder-hardened gate runtime under a new name, verify its authorized no-request fixed-path preflight, and retain the earlier locked-session and slide-show-lifecycle failures as negative history.
- [x] Validate one decoder-hardened static exact-window sample before content-mutation or mouse input.
- [x] Run six controlled slide inputs at eight-second intervals and retain paired report and operator-captured helper output supporting six post-baseline events, one unused event per input with no extra or reused event, interval containment, and Vision completion after the final revision; retain the non-cryptographic provenance limitation above.
- [x] Run controlled single-stroke and erase input after the dynamic boundary; record one visible red line, byte-identical visual restoration, and two aggregate phase-correlated continuous-dense revisions without treating them as semantic classifications.
- [ ] Exercise at least one live `boundedFreshSample` episode on the decoder-hardened or later release-candidate implementation without weakening detector thresholds.
- [ ] Keep this path separate from future exact-window post-identity recovery, user-confirmed canvas accuracy, visible overlay alignment, and semantic ink classification.
