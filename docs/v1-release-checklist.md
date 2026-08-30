# LectureBoard AI v1.0.0 release checklist

## Definition of completion

LectureBoard AI is complete when the public `v1.0.0` GitHub Release is available from `akiyama709/lectureboard-ai`, includes an installable macOS artifact signed with Developer ID and accepted by Apple notarization, and the artifact downloaded from that public release passes the final verification below.

The public source repository is the development venue, not the completed product. Alpha, beta, and release-candidate builds are intermediate validation gates. Publishing any prerelease does not satisfy the completion definition.

## Current status

No alpha, beta, release-candidate, or `v1.0.0` GitHub Release has been published. The current repository is an alpha scaffold. Existing local builds are development artifacts; the currently verified runtime bundle is ad hoc signed, not Developer ID distribution signed or notarized.

Every item below must be evaluated against the exact release commit and exact candidate artifact. Earlier tests and historical runtime reports may inform readiness, but they do not automatically check a release item.

## 1. Alpha gate — end-to-end controlled path

- [ ] The current build safely identifies and continuously captures only the selected PowerPoint window.
- [ ] Stable visual updates and an independent actual-slide identity signal are implemented and verified without treating image difference as slide identity.
- [ ] OCR, geometry, slide-canvas cropping, existing-ink occupancy, and coordinate mapping are verified on controlled fixtures and live synthetic slides.
- [ ] Final transcript segments and real `SlideContext` data reach the contextual board engine with source evidence identifiers.
- [ ] Stable text, boxes, arrows, and simple diagrams render without covering occupied regions or interfering with human input.
- [ ] The original PowerPoint file remains unchanged during a lecture.
- [ ] A minimal lecture session is exported as JSON and SVG.
- [ ] A controlled ten-minute Japanese or English lecture completes with documented evidence and fallback procedures.

Passing this gate establishes a functional alpha only.

## 2. Beta gate — representative and repeated use

- [ ] Representative Japanese, English, and staged mixed-language decks have documented results.
- [ ] Animations, window reselection, PowerPoint restart, display reconnection, multiple-display arrangements, and long-duration operation have documented results.
- [ ] OCR correctness, title selection, coordinates, occupancy, overlap avoidance, and board usefulness have stated metrics and acceptance thresholds.
- [ ] Microphone transcription, transparent-overlay alignment, click-through behavior, pen-tablet non-interference, and human-ink priority are verified.
- [ ] Online-sharing composition is verified in the supported presentation and meeting configurations.
- [ ] Recovery and data-integrity behavior are verified after application, PowerPoint, capture, display, and permission failures.
- [ ] Privacy, accessibility, research-data boundaries, third-party licenses, and notices are reviewed for the supported use cases.
- [ ] Known limitations, tester instructions, and fallback procedures are complete.

Passing this gate establishes beta readiness only.

## 3. Release-candidate gate — exact distribution artifact

### Scope and quality

- [ ] The `v1.0.0` feature set, supported macOS versions, supported Mac hardware, and supported PowerPoint versions are frozen and documented.
- [ ] All release-blocking defects are resolved, and every remaining known issue is triaged and documented.
- [ ] Required Core, native-app, integration, regression, and release tests pass on the exact release commit.
- [ ] The exact candidate completes the supported lecture path and recovery scenarios on clean supported Macs.
- [ ] No current-build behavior is described as verified solely from a historical build, fixture, or compile-only result.

### Privacy, security, licensing, and provenance

- [ ] The release tree contains no credentials, private lecture material, student data, unpublished slides, model weights, signing material, or unintended local paths.
- [ ] The privacy statement accurately describes local processing, every optional external provider, data retention, permissions, and exported session data.
- [ ] Dependency licenses, bundled assets, fonts, third-party notices, and source obligations are complete.
- [ ] Security reporting instructions and supported-version policy are published.
- [ ] The release commit, build environment, dependency versions, and artifact provenance are recorded.
- [ ] `MARKETING_VERSION`, `CITATION.cff`, `CHANGELOG.md`, the annotated tag, the GitHub Release name, and the app bundle metadata identify the same release according to the documented SemVer-to-bundle-version rule.

### macOS distribution

- [ ] The installable artifact is produced reproducibly from the approved release commit.
- [ ] The application uses the hardened runtime and an appropriate Developer ID Application signature.
- [ ] The designated requirement is bound to the approved Apple Developer team.
- [ ] `codesign --verify --deep --strict` succeeds on the candidate.
- [ ] The installable artifact is submitted to Apple notarization and accepted.
- [ ] The notarization ticket is stapled where the distribution format supports stapling.
- [ ] Gatekeeper assessment succeeds on the candidate after transfer to a clean supported Mac.
- [ ] Download, installation, first launch, Screen Recording, microphone, Speech, and normal relaunch are verified without development-only entitlements or paths.
- [ ] The candidate's SHA-256 checksum and version metadata are recorded.

### Documentation and operations

- [ ] Installation, permissions, first lecture, update, uninstall, troubleshooting, privacy, accessibility, fallback, and support instructions are complete.
- [ ] Release notes distinguish verified capabilities, prototypes, known limitations, and unsupported configurations.
- [ ] The README and documentation consistently identify alpha, beta, and RC as prerelease stages and `v1.0.0` as the completion release.
- [ ] `docs/build-verification.md` contains dated evidence for the exact release commit and artifact.
- [ ] A rollback or withdrawal procedure is documented in case the public artifact is defective.

Passing this gate establishes an RC that is ready for the final publication decision. It is not project completion.

## 4. Public v1.0.0 publication

- [ ] All required GitHub Actions checks pass for the approved release commit.
- [ ] The release commit on `main` is reviewed and has no unintended changes.
- [ ] Explicit user approval is obtained immediately before the external publication action.
- [ ] An annotated `v1.0.0` tag is created from the approved release commit and pushed without rewriting history.
- [ ] A public GitHub Release is created for `v1.0.0`; it is not marked as a prerelease.
- [ ] The Developer ID-signed and notarized installable macOS artifact is attached.
- [ ] Release notes, supported environment, installation instructions, known limitations, privacy information, and SHA-256 checksum are included.
- [ ] Source archives and attached artifacts correspond to the approved tag and recorded provenance.

## 5. Post-publication verification — completion gate

- [ ] The public release page and artifact are accessible without repository-owner credentials.
- [ ] The artifact is downloaded from the public GitHub Release into a clean verification environment.
- [ ] The downloaded artifact's SHA-256 matches the published checksum.
- [ ] Developer ID signature, designated requirement, hardened runtime, notarization, stapling where applicable, and Gatekeeper acceptance are independently rechecked.
- [ ] Installation, first launch, required permission flow, relaunch, and the supported core lecture path succeed from the downloaded artifact.
- [ ] The public release URL, tag commit, artifact filename, checksum, signing identity, notarization result, test environment, and final results are recorded in `docs/build-verification.md`.
- [ ] Any discrepancy is resolved before the release is described as complete.

Only when every item in Sections 1–5 has passed, with Sections 3–5 evaluated against the same `v1.0.0` commit and public artifact, may the project be described as complete.

## Historical initial-publication material

The following documents and script concern creation of the source repository, not the completed application release:

- [`github-publication-ja.md`](github-publication-ja.md)
- [`open-source-release-checklist.md`](open-source-release-checklist.md)
- `scripts/publish-to-github.sh`

The repository already exists. Do not rerun the initial publication script for branch updates, pull requests, prereleases, release candidates, or `v1.0.0` publication.
