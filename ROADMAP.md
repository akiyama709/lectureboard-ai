# Roadmap

The roadmap describes validation gates rather than promises of release dates.

## Milestone 0 — Public foundation

- [x] macOS-only scope
- [x] Native app shell
- [x] Provider-neutral core architecture
- [x] Context-first design with no required voice commands
- [x] Grounded board-intent data model
- [x] Transparent-overlay prototype
- [x] CI and open-source governance files

## Milestone 1 — Observable lecture prototype

- [ ] Capture the selected PowerPoint window continuously with ScreenCaptureKit — the current post-lifecycle-fix executable delivered 50 frames in a five-second static synthetic run; independent LaunchServices launch, dynamic rerun, representative decks, window reselection, and long-duration reliability remain pending
- [ ] Detect slide changes and stable frames — an earlier pre-lifecycle-fix run confirmed 5 stable frames and classified 4 slide changes, while the current executable confirmed one static stable frame; dynamic rerun and animations remain unverified, and broader threshold calibration across representative transitions remains pending
- [ ] Recognize slide text and geometry — Vision completed on the current executable with maxima of 35 text and 9 rectangle observations; OCR correctness and coordinate accuracy remain pending
- [ ] Build normalized occupied regions from detected text and rectangles — the current static run produced up to 4 occupied regions; coordinate and overlap-avoidance accuracy remain pending
- [ ] Detect existing PowerPoint ink as occupied space
- [ ] Route live transcript segments into the contextual board engine
- [ ] Render stable text, boxes, arrows, and causal chains
- [ ] Save the session as JSON and SVG — the runtime-verification metadata JSON is diagnostic evidence, not a lecture-session export

**Exit criterion:** a ten-minute Japanese or English lecture can run without overlap on a controlled slide deck.

## Milestone 2 — Contextual board quality

- [ ] Import `.pptx` text, geometry, and speaker notes
- [ ] Add evidence-linked AI summarization adapters
- [ ] Defer uncertain content instead of interrupting the lecturer
- [ ] Validate names, numbers, dates, quotations, and equations
- [ ] Add board-density and diagram-frequency controls
- [ ] Evaluate false-positive and false-negative board decisions

**Exit criterion:** independent reviewers judge most annotations useful and grounded on a representative lecture set.

## Milestone 3 — Japanese–English mixed lectures

- [ ] Detect short-span language changes
- [ ] Preserve original terminology
- [ ] Support important-term bilingual display
- [ ] Maintain a session glossary
- [ ] Add Japanese and English evaluation corpora with consent

**Exit criterion:** Japanese–English code-switching works without repeated manual language changes.

## Milestone 4 — Lecture-ready alpha

- [ ] Presenter control window
- [ ] Online-sharing composite window
- [ ] Recovery after PowerPoint restart or display reconnection
- [ ] Privacy-preserving lecture export
- [ ] Accessibility review
- [ ] Developer ID distribution signing, hardened runtime, and notarization
- [ ] Reproducible release workflow

**Exit criterion:** repeated use in real lectures with documented fallback procedures.

## Later exploration

- Keynote and PDF presentation support
- Personal writing-style adaptation with explicit opt-in
- More languages
- Student-side optional translated board views
- Windows and Linux only after the macOS implementation is dependable
