# ADR 0012: Select a managed slide-show window candidate before role challenge

- Status: Accepted
- Date: 2026-09-02

## Context

LectureBoard AI captures one exact PowerPoint window through ScreenCaptureKit. The capture boundary
freezes the Core Graphics window ID, owning process ID, and exact PowerPoint bundle identifier.
Production board output also requires independent semantic identity containing an app-owned
presentation-session token, PowerPoint slide ID, and slide index.

A read-only probe of the installed PowerPoint scripting interface found one semantic slide-show
window and two PowerPoint Core Graphics windows, but the inherited scripting `window.id` value was
`nil`. The documented scripting dictionary exposes an `id` property, yet the tested PowerPoint
build did not return it. Even if that value becomes available in another build, no public contract
states that it equals `SCWindow.windowID`. A title, enumeration order, approximate bounds,
frontmost state, or Accessibility correspondence would be a correlation rather than an exact
identity bridge and could attach one presentation's semantics to another window.

ScreenCaptureKit exposes the Core Graphics identifier as `SCWindow.windowID`. PowerPoint's
installed public scripting dictionary also says that `run slide show` returns a `slide show
window` object and that its `slideshow view.slide state` can be changed among running, black, and
white states. macOS provides Apple-event permission preflight and sending APIs, but the user must
consent before one application controls another. Consent must not be requested implicitly during
passive refresh or on the main thread, and the app must declare `NSAppleEventsUsageDescription`.

Relevant public API documentation:

- [Apple: `SCWindow.windowID`](https://developer.apple.com/documentation/screencapturekit/scwindow/windowid)
- [Apple: `AEDeterminePermissionToAutomateTarget`](https://developer.apple.com/documentation/coreservices/3025784-aedeterminepermissiontoautomatet)
- [Apple: `NSAppleEventsUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nsappleeventsusagedescription)
- [Apple: `NSAppleEventDescriptor.sendEvent`](https://developer.apple.com/documentation/foundation/nsappleeventdescriptor/sendevent%28options%3Atimeout%3A%29)

## Decision

The first semantic-identity route will use a managed setup with two distinct stages. A causal
window-birth correlation is only a **candidate**. It is never an exact semantic binding until a
separate challenge-response validates the window role.

### Stage A: select a managed-start candidate

For one attempt, the app will:

1. Freeze one running PowerPoint process ID, exact `com.microsoft.Powerpoint` bundle identifier,
   and one existing selected window identity.
2. Generate an opaque, runtime-only binding-session token.
3. Require one active presentation, zero slide-show windows, a complete on-screen ScreenCaptureKit
   inventory for the frozen process and bundle, and the frozen selected window in that inventory.
4. Only after an explicit user action, check or request Automation consent off the main thread.
   The start client must atomically revalidate the same process, bundle, session, one active
   presentation, and zero slide-show windows before sending exactly one `run slide show` command.
5. Retain the returned slide-show object specifier behind an opaque, runtime-only client token.
6. Accept a window-birth candidate only when scripting changes from zero to exactly one slide-show
   window, every observed baseline tuple remains present, and exactly one previously absent window
   ID appears for the frozen process and bundle.
7. Require the complete post-start inventory and scripting evidence to repeat unchanged before
   returning the candidate correlation.

The deterministic candidate policy latches its first rejection until reset. It rejects malformed
or duplicate IDs, process or bundle replacement, an ambiguous active-presentation count, a
pre-existing slide show, no new ID, multiple new IDs, observable baseline disappearance, session
mismatch, and candidate drift. This stage cannot prove that the new ID has the slide-show role and
cannot detect a same-ID, same-PID, same-bundle lifecycle replacement. Those limitations are why its
result is not a binding.

### Stage B: validate the candidate's slide-show role

The app will challenge the exact PowerPoint object returned by `run slide show`, not a slide-show
object found later by title or enumeration:

1. Prefer a reversible visibility challenge if the frozen PowerPoint build demonstrably supports
   it without recreating the window. Hide and show only the returned object and require only the
   candidate ID to disappear and return while every other identity remains unchanged.
2. Otherwise, use a reversible pixel challenge. Set the returned object's slide-show view through
   a per-attempt nonce-derived order of black and white states, then restore its original running
   state.
3. After each successful Apple-event reply, accept only ScreenCaptureKit frames from the candidate
   whose `displayTime` is strictly newer than the command boundary. Require repeated stable
   evidence for each challenge state and require every other PowerPoint window to remain unchanged.
4. Reject if the returned scripting object, process, bundle, complete inventory, slide ID, slide
   index, presentation saved state, candidate window, challenge sequence, or restoration evidence
   is missing or changes unexpectedly.
5. Continue production capture from the same validated `SCWindow` object and stream generation.
   Do not reselect a window later by numeric ID. Stream end or identity drift immediately makes
   semantic identity unavailable.
6. Only after successful restoration create the runtime binding containing the exact window,
   app-owned session token, capture generation, and a strictly newer semantic-reading boundary.

A visibility or black/white response is a managed challenge validation, not a mathematical OS
guarantee about Core Graphics ID lifetimes. Even after live verification, documentation must call
the result challenge-validated under a complete, unchanged PowerPoint-window inventory. It must
not claim a public static API bridge that does not exist.

The current unavailable provider remains the application default. Candidate-policy or coordinator
success cannot start the exact semantic provider and cannot authorize production overlay output.

## Alternatives considered

### Bind an arbitrary existing slide show by title, order, bounds, focus, or Accessibility

Rejected. None of those public values is the exact Core Graphics window identifier returned by
ScreenCaptureKit, and more than one PowerPoint window may satisfy the same correlation.

### Treat a causally new window as the slide-show window without a role challenge

Rejected. The same observation can arise when the slide show reuses an existing ID while an
unrelated PowerPoint window appears. Repeating the same inventory does not resolve that ambiguity.

### Copy the requested capture identity onto an unbound scripting result

Rejected. That would make the provider's target identity self-asserted and bypass independent
window-role evidence.

### Use an undocumented Accessibility-to-Core-Graphics bridge or another private API

Rejected. A public `v1.0.0` cannot depend on an unsupported private bridge, and the result would
remain unsuitable for release signing and compatibility claims.

### Match the confirmed captured canvas against rendered slides from a user-selected `.pptx`

Deferred as a complementary route. Unique visual matching can bind visible semantics directly to
captured pixels and may later support user-bound existing windows. It cannot by itself prove that
the running document is the selected file when two files render identically, cannot uniquely
identify duplicate visual slides, and cannot authorize hidden speaker notes without a separate
user-confirmed deck-to-window association.

### Treat visual content changes as slide identity

Rejected. Animations, ink, erasure, pointer changes, and other within-slide updates can change
pixels without changing the PowerPoint slide.

## Consequences

This route deliberately narrows the initially supported presentation mode. An arbitrary
already-running slide show, ambiguous active presentations, an unvalidated candidate, a failed
restoration, or a configuration that changes more than one PowerPoint window remains unsupported
and fail-closed. Presenter View requires a later independently validated design.

The transaction avoids persisting a presentation title or path in runtime reports. Object tokens,
binding tokens, slide IDs, and window IDs remain runtime-only correlation material. Runtime
verification continues to export only bounded states and counters.

Automation consent is an explicit setup step. Passive window refresh, ordinary app launch,
deterministic tests, and the unavailable provider must never trigger a consent sheet or send an
Apple event. Rebuilding an ad hoc development app may still change macOS permission identity; live
tests will use separately frozen artifacts and will not repeatedly request consent.

Current deterministic tests verify candidate evaluation and native coordination only. No current
test verifies live Automation consent, PowerPoint command execution, the returned object specifier,
window-role challenge, restoration, same-stream continuation, real semantic transitions,
post-identity frame synchronization, or visible production output.

## Follow-up actions

- [x] Add the platform-neutral managed-start candidate policy and rejection tests.
- [x] Add a native candidate coordinator with injected observation, command, and waiter clients.
- [x] Keep the exact semantic polling shell structurally separate from the default unavailable
      provider.
- [x] Add the returned-object visibility or black/white role-challenge policy and coordinator.
- [x] Add a no-prompt Automation preflight plus an explicit off-main consent path and
      `NSAppleEventsUsageDescription`.
- [x] Add a strict Apple-event descriptor builder/parser for the bounded supported PowerPoint
      object graph without sending events from passive application paths.
- [ ] Implement the PowerPoint scripting client with an opaque returned-object handle, bounded
      external calls, and exact active-presentation revalidation.
- [ ] Share only a challenge-validated binding with the exact semantic provider and AppModel.
- [ ] Add setup UI that explains the managed start and brief reversible role challenge.
- [ ] Freeze a test build and validate static baseline, role challenge and restoration, actual
      transitions, session replacement, target closure, ambiguity rejection, and post-identity
      fresh-frame synchronization.
- [ ] Retain arbitrary existing-window capture as observation-only until a separately exact
      semantic route is verified.
