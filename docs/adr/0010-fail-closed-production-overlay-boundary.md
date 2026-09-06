# ADR 0010: Require a fail-closed production-overlay boundary

- Status: Accepted
- Date: 2026-08-31

## Context

ADR 0009 established a user-confirmed slide canvas in captured output-pixel coordinates. That rectangle is suitable for cropping visual input, but it is not by itself proof of where a production overlay may be drawn in AppKit screen coordinates. ScreenCaptureKit surface padding, content scale, the window's current global position, Quartz and AppKit coordinate orientation, display arrangement, window ownership, foreground state, and occluding windows can all change independently.

The original transparent-panel prototype could cover a selected display for demonstration. Using that full-display behavior as a production fallback would allow content to appear outside the confirmed slide, over another application, or over a PowerPoint dialog. Likewise, checking foreground and window eligibility only when ScreenCaptureKit happens to deliver a frame would leave an already visible overlay stale when capture delivery becomes idle.

The production path therefore needs two independent proofs: an exact coordinate mapping for the current captured frame, and a short-lived authorization to remain visible in the current desktop/window state. Missing, stale, contradictory, or ambiguous evidence must hide the overlay rather than select an approximate target.

## Decision

### Exact coordinate proof

The production mapper accepts a placement only when all of the following facts agree:

- The user-confirmed canvas belongs to the active capture operation and exact ScreenCaptureKit window.
- The confirmation and current frame have identical validated capture-surface geometry and output-pixel dimensions. Test-only whole-frame provenance is rejected by the production mapper.
- A new delivery supplies its own valid `screenRect`. A verified idle repeat uses its own valid current value, rejects a present malformed value, or only when the key is absent carries forward the prior validated rectangle as a candidate. A retained candidate cannot authorize display or lease renewal without a fresh exact-window eligibility check whose current Core Graphics bounds agree within two points.
- The current frame sequence is retained in the resulting placement, and the app renders only when that sequence still equals the latest eligible visual frame.
- The confirmed output-pixel rectangle lies inside the surface `contentRect` after applying `scaleFactor` and `contentScale`. At most one output pixel of SDK rounding drift is accepted.
- The resulting Quartz global target rectangle is finite, nonempty, and fully contained by exactly one validated display snapshot.
- That one display provides the bridge from Quartz's global top-left coordinates to AppKit's global bottom-left coordinates. The overlay controller rechecks unique AppKit display containment before showing the panel.

Failure of any check produces no placement. There is no title-, order-, aspect-ratio-, approximate-bounds-, nearest-display-, last-known-position-, or full-display production fallback.

### Production-display eligibility

An exact coordinate placement is necessary but not sufficient. Production rendering also requires all of these current conditions:

- Capture is active, the canvas is confirmed, semantic slide identity is outside quarantine and synchronized to its required post-boundary frame, the board scene is nonempty, and the visual analysis grounding that authorized the scene is fresh and complete.
- The frozen PowerPoint process identifier and exact PowerPoint bundle identifier identify the frontmost application.
- The on-screen Core Graphics window list contains exactly one entry for the frozen ScreenCaptureKit window identifier.
- That entry has the frozen owner process, is on screen, and is at layer zero.
- Each edge of its freshly read Core Graphics bounds agrees with the frame-carried validated ScreenCaptureKit screen-position candidate within two points. This tolerance covers coordinate rounding only and is not an approximate window-matching fallback; it is mandatory when the candidate was carried through verified idle-key omission.
- No earlier entry in the front-to-back on-screen window list, at any layer, has a positive-area intersection with the selected PowerPoint window. A dialog, another application window, or another overlapping window therefore closes the production path.

Missing or malformed application, window-list, identity, geometry, analysis, or ordering evidence denies display. The app's own overlay process is excluded from the eligibility snapshot so that the panel does not disqualify itself; no other occluding process or layer is ignored.

The user's explicit hide action sets a persistent production-suppression latch. A later capture delivery does not undo it; only an explicit new capture or demo action begins a separately authorized path. Capture stop or error, a semantic identity boundary, content-unavailable delivery, visual-change uncertainty, stale analysis, geometry invalidation, or loss of any eligibility condition hides the production overlay and clears its rendered-state cache.

Eligibility is leased rather than retained indefinitely. A production render or renewal requires a current eligible window check tied to a fresh, completed visual analysis and the current frame. An independently scheduled expiry hides the overlay even when ScreenCaptureKit delivers no further frame. Workspace or active-application changes also hide it immediately. Lease scheduling is injectable so expiry behavior can be tested deterministically; the accepted boundary does not rely on capture cadence as its clock.

Repeated deliveries may recheck eligibility without physically rerendering an unchanged scene and target. Render deduplication is an optimization only; it does not extend eligibility or bypass expiry.

### Demo separation

Full-display rendering remains available only through the explicit demo path. Demo content is cleared and its panel is hidden when production capture starts. The demo path does not satisfy or renew a production eligibility lease, and it is never selected when production coordinate or window evidence fails.

## Alternatives considered

### Keep the production overlay full-display until live calibration is complete

Rejected. A broad panel would knowingly exceed the confirmed slide boundary and could place AI content over controls, dialogs, or another application.

### Reuse the last valid position without revalidation or choose the nearest display

Rejected. Window movement, resize, display reconfiguration, or disappearance would turn unqualified old coordinates into an ungrounded target. The accepted idle-omission policy carries a prior validated rectangle only as a candidate and still requires the current exact Core Graphics window, ownership, foreground state, bounds agreement, and occlusion checks before display or lease renewal.

### Match PowerPoint by title, approximate bounds, frontmost state alone, or window-list order

Rejected. None of these facts binds the target to the exact frozen ScreenCaptureKit window and owner. The two-point bounds tolerance is applied only after exact window-ID and owner matching.

### Recheck eligibility only when capture frames arrive

Rejected. An idle or stalled capture could leave an overlay visible after the user changes applications or an occluding window appears. The independent expiring lease and workspace/application invalidation close that gap.

### Ignore higher-layer or same-process windows

Rejected. A PowerPoint dialog or another overlapping panel can conceal the target just as another application's window can. Any earlier validated on-screen intersection denies production display.

## Consequences

The production overlay now has a deterministic path to one exact confirmed-canvas AppKit rectangle, while the broad display panel is explicitly demo-only. The boundary favors disappearing over displaying content in an uncertain place. It may therefore hide during transient foreground, window-list, analysis, or geometry changes and wait for fresh qualifying evidence before returning.

Pure geometry tests cover surface and scale consistency, one-pixel rounding tolerance, current-frame sequence binding, negative display origins, one-display containment, cross-display rejection, and Quartz-to-AppKit conversion. Window-policy and native integration tests cover exact identity, foreground ownership, unique layer-zero on-screen matching, two-point bounds tolerance, front-to-back occlusion, malformed evidence, manual suppression, content-unavailable and visual-change hiding, render deduplication, lease expiry, and recovery only from current qualifying evidence.

These are implementation and deterministic-test results only. They do not establish live PowerPoint alignment, real ScreenCaptureKit `screenRect` orientation or attachment behavior, Core Graphics window-list z-order in every PowerPoint mode, multiple-display and scale-factor correctness, movement or resize behavior, full-screen or presenter-mode behavior, exact visible alignment, click-through behavior, or non-interference with mouse and pen-tablet input. Each tested live mode must be recorded separately before it is described as verified.

## Follow-up actions

1. Validate the mapper and eligibility boundary on a controlled live PowerPoint window without weakening any exact-identity or no-fallback rule.
2. Exercise window movement, resize, full-screen, presenter mode, multiple display origins and scales, display reconnection, dialogs, application switching, and overlapping windows, recording success and failure separately.
3. Measure visible overlay alignment against the confirmed canvas and record the tested tolerance rather than inferring it from synthetic geometry.
4. Validate click-through behavior and verify that mouse and pen-tablet input still reaches PowerPoint without interference.
5. Calibrate the eligibility lease only from recorded live transition and idle-capture evidence; do not present an implementation default as a verified operational interval.
