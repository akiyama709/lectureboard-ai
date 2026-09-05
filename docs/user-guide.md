# LectureBoard AI v1.0.0 user guide

> Status: procedural draft. Do not treat a step as verified for `v1.0.0` until the exact public
> candidate and the public re-download have corresponding evidence in
> [`build-verification.md`](build-verification.md).

## Before installing

Use LectureBoard AI only in the narrow configuration in
[`supported-environment.md`](supported-environment.md): an Apple-silicon Mac, one local display,
one PowerPoint presentation, no existing slide show, PowerPoint's windowed slide-show mode, and
one lecture language per session.

The no-fee release is hardened and ad hoc signed, but it is not Developer ID signed or Apple
notarized. Apple therefore cannot identify its publisher or perform the notarization trust check.
Download the ZIP and checksum only from the project's public GitHub Release and verify the ZIP
before opening it:

```bash
shasum -a 256 "LectureBoard-AI-1.0.0-macos-arm64.zip"
```

The value must exactly match the release checksum. A mismatch means stop; do not open the App.

## Install and first open

1. Expand the verified ZIP and move `LectureBoard AI.app` to `/Applications` without renaming it.
2. Open the App once from Finder. macOS is expected to block the first launch because the App is
   not registered or notarized by Apple.
3. Follow Apple's per-application procedure in [Open a Mac app from an unknown
   developer](https://support.apple.com/en-gb/guide/mac-help/mh40616/mac): open **System Settings →
   Privacy & Security**, use the App-specific **Open Anyway** choice, authenticate, and confirm the
   open.
4. Never disable Gatekeeper globally and never remove quarantine metadata with a Terminal command.

Keep this exact App at this exact path throughout testing. A different build may have the same
name and bundle identifier but a different ad hoc code identity, so macOS may treat it as a
different App.

## Permissions

- **Screen & System Audio Recording:** LectureBoard AI needs screen access to capture the selected
  PowerPoint window. It does not request system-audio capture. Apple documents the controls under
  [Privacy & Security → Screen & System Audio
  Recording](https://support.apple.com/en-ie/guide/mac-help/mchld6aa7d23/mac).
- **Automation → Microsoft PowerPoint:** managed start needs explicit permission to create and
  read one exact PowerPoint slide-show object. It does not adopt an existing slide show.
- **Microphone** and **Speech Recognition:** requested only when transcription starts. Apple Speech
  is configured to require on-device recognition. If the selected locale cannot recognize on the
  device, transcription fails closed instead of using a network fallback.
- **Accessibility** and **Full Disk Access:** not required by the supported workflow. Stop and
  report the issue if the release unexpectedly requests either one.

If Screen Recording is already shown as granted inside LectureBoard AI, do not request it again.
If it is denied, request it once, enable the exact installed App in System Settings, quit that App,
and reopen the same path. If it is still denied, stop instead of repeating the request.

## Prepare PowerPoint

1. Close other presentations and any running PowerPoint slide show.
2. Open exactly one presentation in its normal editing window.
3. In PowerPoint, select **Slide Show → Set Up Slide Show → Browsed by an individual (window)**.
   Microsoft describes this show type in [Create a self-running
   presentation](https://support.microsoft.com/en-US/PowerPoint/training/create-a-self-running-presentation).
4. For a first or pre-release test, work from a local copy and keep the source file closed. Follow
   [`user-acceptance-ja.md`](user-acceptance-ja.md) for the required before-and-after integrity
   checks.

LectureBoard AI is designed not to edit or save the presentation. That property remains a release
gate and must be checked against the exact candidate; keeping a separate source file is still the
safe test procedure.

## Start a lecture

1. Open LectureBoard AI and select Japanese or English for the session.
2. Confirm that Screen Recording is granted, then choose **Refresh PowerPoint windows**.
3. Select the exact PowerPoint editing window.
4. Choose **Start managed slide show** once. PowerPoint may present its Automation consent on the
   first use.
5. Wait for the newly created windowed slide show and capture status. The App must stop rather than
   continue if it cannot bind the returned PowerPoint object to one exact captured window.
6. On the frozen preview, drag around only the visible slide, excluding PowerPoint controls and
   surrounding UI, then confirm the slide area.
7. Start transcription only after the current slide identity, fresh frame, and visual analysis are
   ready.

During a lecture, use PowerPoint normally. Human mouse or pen input has priority. **Hide board**
immediately hides LectureBoard AI output. If slide identity, canvas, current analysis, focus, or
window geometry becomes uncertain, the overlay is expected to hide rather than guess.

## Stop and export

1. Stop transcription, then stop capture.
2. Confirm that the managed slide show is closed and the PowerPoint editing window remains.
3. Use **Export session** only after capture has stopped. Selecting a JSON filename also writes an
   SVG with the same basename beside it.
4. Treat both files as lecture data. They contain the confirmed or pinned public board scene and
   may include derived board text, but are designed to exclude source slide images, raw audio,
   full transcripts, OCR source text, window titles, capture identifiers, and non-public intents.
5. Close the PowerPoint copy without saving any ink, and perform the required file-integrity check
   when testing a candidate.

## Troubleshooting and safe fallback

- **Repeated Screen Recording prompt:** verify that only the exact installed candidate is being
  used. Quit and reopen that same App once. Do not authorize multiple DerivedData copies and do not
  keep pressing the request button.
- **No PowerPoint window:** confirm Screen Recording permission, keep one normal editing window
  visible, stop any existing slide show, then refresh once.
- **Managed start fails:** confirm the supported PowerPoint version and the windowed show type. Do
  not switch to full screen, Presenter View, or kiosk mode as a workaround.
- **On-device speech unavailable:** continue without transcription or stop the session. The App
  deliberately has no network fallback.
- **Overlay disappears:** restore PowerPoint to the front, avoid moving or resizing either window,
  and reselect the slide area if requested. Hidden output is the safe state.
- **Export is disabled:** first stop capture and confirm that at least one public board scene was
  produced.
- **Crash, wrong window, ungrounded content, intercepted input, or file change:** stop using the
  App. Preserve only content-free diagnostics until the material has been reviewed for privacy.

PowerPoint alone remains the fallback. Stop LectureBoard AI and continue the slide show without
automatic board output whenever the safety boundary cannot be restored promptly.

## Update, uninstall, and support

For an update, download and verify the new release independently. Keep the old App until the new
one passes first launch; do not overwrite a running App. The new ad hoc code identity may require
new per-App permissions.

To uninstall, stop capture and transcription, quit LectureBoard AI, move only `LectureBoard AI.app`
to the Trash, and remove its entries from macOS Privacy & Security if desired. Session exports are
separate files and are not deleted automatically.

Report ordinary defects through GitHub Issues without attaching private slides, screenshots,
audio, transcripts, exports, credentials, or absolute local paths. Follow [`SECURITY.md`](../SECURITY.md)
for security or privacy vulnerabilities. Keyboard-only use, VoiceOver, physical pen tablets,
multi-display arrangements, full-screen modes, mixed-language recognition, and online-meeting
composition are not verified for v1.0.0 unless a later release document explicitly says otherwise.
