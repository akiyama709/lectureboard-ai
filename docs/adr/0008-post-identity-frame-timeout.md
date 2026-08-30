# ADR 0008: Keep post-identity frame timeout fail-closed

- Status: Accepted
- Date: 2026-08-30

## Context

After an independent slide-identity baseline or transition is confirmed, LectureBoard AI rejects visual analysis until ScreenCaptureKit delivers a `.new` frame whose `SCFrameInfo.displayTime` is strictly later than the app's local mach-absolute acceptance time for that identity observation. This prevents a frame from the previous slide from entering the new slide context.

A static PowerPoint slide may yield only `.idle` deliveries. Those deliveries repeat the previous image and display time, so they cannot safely open the gate. The previous implementation remained paused without exposing whether it was waiting or had waited unusually long.

The local macOS 26.5 SDK exposes stream start, stop, content-filter updates, configuration updates, and one-shot screenshot capture. It does not expose a request that guarantees a new stream frame with a post-request `SCFrameInfo.displayTime`. A one-shot screenshot also lacks that display-time provenance.

## Decision

Add a deterministic post-identity frame gate with four states: `notRequired`, `waiting`, `synchronized`, and `timedOut`.

- A confirmed identity boundary starts a two-second wait using a boundary token.
- Timeout changes only the observable state. It does not open the gate.
- Visual analysis and final-transcript board proposals remain paused while the state is `waiting` or `timedOut`. A transcript callback timestamp must also be strictly later than the app's local frame-synchronization acceptance time, so delayed MainActor delivery cannot admit speech produced during the wait.
- A strictly newer `.new` ScreenCaptureKit frame may synchronize the gate even after timeout.
- Candidate identity, capture stop, capture error, and capture restart cancel the pending wait and invalidate its token.
- A delayed timeout from an earlier boundary or capture session cannot change the current state.
- Runtime metadata records only the frame-sync state. It does not record slide IDs, presentation tokens, paths, images, recognized text, or coordinates.

The runtime-report format moves to schema 5. Schema 1 through schema 4 remain decodable, with a missing frame-sync field interpreted as `notRequired`.

## Alternatives considered

### Accept an idle repeat after a delay

Rejected. Callback time or wall-clock age does not prove that the repeated image was displayed after the identity boundary.

### Restart or reconfigure `SCStream`

Deferred. The public API does not promise that this produces a qualifying display time, and stream restart adds lifecycle and stale-callback races. It is not used as evidence of freshness.

### Use `SCScreenshotManager`

Deferred for a separate design. A one-shot exact-window capture may provide a future recovery path, but it has different provenance and no `SCFrameInfo.displayTime`. It must not be disguised as a stream frame. Any future implementation must revalidate the exact window ID, owning process ID, and bundle identifier; track a separate capture epoch; and reject completions from stale boundaries or sessions.

## Consequences

The app now makes an indefinite safety pause diagnosable and testable without weakening the stale-frame boundary. Timeout alone does not restore liveness on a static slide. Automatic fresh-frame acquisition and its runtime validation remain future work.

The default unavailable identity provider never starts this wait. Therefore deterministic Core and native app tests verify the new state machine and integration, while live timeout behavior with a production PowerPoint identity provider remains unverified.

## Follow-up actions

1. Preserve the exact-window fail-closed constraints when designing a one-shot capture provenance.
2. Implement a production PowerPoint identity provider only after a public API can bind semantic slide information to the selected exact window ID.
3. Run a controlled static-slide and transition validation before claiming that automatic fresh-frame recovery works at runtime.
