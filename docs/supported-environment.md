# v1.0.0 supported environment

This document defines the deliberately narrow support contract targeted by the first public
application release. A configuration is not described as verified until the exact release
artifact has passed the corresponding live gate in `docs/build-verification.md`.

## Targeted support contract

- Apple silicon Mac running macOS 26.6.x; the development checkpoint is macOS 26.6.2 (25G83)
- Microsoft PowerPoint for Mac 16.112.x; the development checkpoint is 16.112.3
- one local display, one active presentation, and one explicitly selected PowerPoint presentation
  or slide-show view
- a user-started standard **full-screen or windowed** PowerPoint slide show; it may be running before
  LectureBoard AI starts or may be selected after one refresh
- read-only visual observation: the supported workflow neither requests PowerPoint Automation nor
  starts, edits, saves, or closes the presentation
- stable visual changes form local slide epochs; this does not claim access to PowerPoint's exact
  slide ID, index, or speaker notes
- one lecture language per session: Japanese or U.S. English
- local ScreenCaptureKit, Vision, Apple Speech requests that require on-device recognition, and
  deterministic contextual-board processing; if on-device recognition is unavailable,
  transcription fails closed and no lecture content is sent to a cloud provider
- mouse or trackpad input for the controlled human-ink test

## Not supported by v1.0.0

- Intel Macs, macOS releases other than the documented macOS 26.6.x range, or other presentation
  applications
- Presenter View, kiosk mode, more than one active presentation, or ambiguous PowerPoint surfaces
- multiple-display placement, display reconnection, or online-meeting share composition
- automatic Japanese-English code switching within one session
- exact semantic slide identity, speaker-note access, visually indistinguishable transitions,
  reliable tracking of rapid animations, semantic classification of PowerPoint ink, a physical
  pen tablet, or automatic recovery after
  PowerPoint or display restart
- cloud model adapters, automatic updates, or background launch

Unsupported configurations are excluded from release claims; they are not silently generalized
from single-display or fixture evidence. The app must stop or keep output hidden when its exact
window, visual slide epoch, user-confirmed canvas, current visual analysis, or overlay-safety
evidence is unavailable.

## Distribution boundary

The public archive is planned as a hardened-runtime, ad hoc-signed arm64 application. It will not
be Developer ID signed or Apple notarized. Installation may require Apple's per-application
**Open Anyway** action. Documentation must never direct users to disable Gatekeeper globally or
remove quarantine metadata.
