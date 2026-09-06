# LectureBoard AI v1.0.0 release checklist

## Definition of completion

LectureBoard AI is complete when the public, immutable, non-prerelease `v1.0.0` GitHub Release is available from `akiyama709/lectureboard-ai`, includes exactly `LectureBoard-AI-v1.0.0-arm64.zip`, `LectureBoard-AI-v1.0.0-test-results.json`, `SBOM.spdx.json`, `SHA256SUMS`, and `provenance.json` bound to the exact source commit, and all five attached assets downloaded from that public release pass the final verification below.

The public source repository is the development venue, not the completed product. No alpha, beta, or release-candidate GitHub Release will be published. Internal validation phases do not satisfy the completion definition.

## Current status

No application GitHub Release has been published. The current repository is a pre-release development scaffold. Existing local builds and the dated runtime checkpoints in `build-verification.md` are development artifacts, not the final release archive; they are ad hoc signed and are not Apple notarized.

Every item below must be evaluated against the exact release commit and exact candidate artifact. Earlier tests and historical runtime reports may inform readiness, but they do not automatically check a release item.

## 1. Controlled end-to-end gate

- [ ] From one explicitly selected editing window, the current build starts one new windowed PowerPoint slide show, causally binds its returned scripting object to one exact ScreenCaptureKit window, and continuously captures only that window.
- [ ] Stable visual updates and PowerPoint's exact slide ID and index are verified together without treating image difference as slide identity.
- [ ] OCR, geometry, user-confirmed slide-canvas cropping, visual stroke occupancy, and coordinate mapping are verified on controlled fixtures and live synthetic slides.
- [ ] Final transcript segments and real `SlideContext` data reach the contextual board engine with source evidence identifiers.
- [ ] Stable text, boxes, arrows, and simple diagrams render without covering occupied regions or interfering with human input.
- [ ] The original PowerPoint file remains unchanged during a lecture.
- [ ] A minimal lecture session is exported as JSON and SVG.
- [ ] Controlled ten-minute Japanese and English sessions complete separately in the supported environment with documented evidence and fallback procedures.

Passing this gate establishes the controlled core workflow only; it does not authorize publication.

## 2. Representative and repeated-use gate

- [ ] At least one representative Japanese deck and one representative English deck have documented results in separate sessions.
- [ ] Repeated managed start, normal stop, cancellation, window closure, permission denial, and capture interruption have documented results on the supported single-display configuration.
- [ ] OCR correctness, title selection, coordinates, occupancy, overlap avoidance, and board usefulness have stated acceptance observations for the two representative decks.
- [ ] Microphone transcription, transparent-overlay alignment, click-through behavior, mouse-ink non-interference, and human-input priority are verified.
- [ ] Recovery and data-integrity behavior are verified after the in-scope application, PowerPoint-window, capture, and permission failures.
- [ ] Privacy, accessibility, research-data boundaries, third-party licenses, and notices are reviewed for the supported use cases.
- [ ] The exact support contract in `supported-environment.md`, known limitations, user instructions, and fallback procedures are complete; full-screen, Presenter View, multi-display, online-sharing composition, code switching, and physical pen tablets remain explicit post-v1 work rather than inferred successes.

Passing this gate establishes representative-use evidence only; it does not authorize publication.

## 3. Final-candidate gate — exact distribution artifact

### Scope and quality

- [ ] The `v1.0.0` feature set, supported macOS version, Apple-silicon hardware class, PowerPoint version, windowed single-display mode, and explicit exclusions are frozen in `supported-environment.md`.
- [ ] All release-blocking defects are resolved, and every remaining known issue is triaged and documented.
- [ ] Required Core, native-app, integration, regression, and release tests pass on the exact release commit.
- [ ] The exact candidate completes the supported lecture path and recovery scenarios from a clean verification location on the supported Mac.
- [ ] Before publication approval, the project owner personally completes `user-acceptance-ja.md` against this exact candidate using a local copy of one self-selected PPTX; the original and working-copy byte sizes and SHA-256 values remain unchanged, and no private source or derived lecture content enters Git, GitHub, a connector, or a cloud/model context.
- [ ] No current-build behavior is described as verified solely from a historical build, fixture, or compile-only result.

### Privacy, security, licensing, and provenance

- [ ] The release tree contains no credentials, private lecture material, student data, unpublished slides, model weights, signing material, or unintended local paths.
- [ ] The privacy statement accurately describes local processing, every optional external provider, data retention, permissions, and exported session data.
- [ ] Dependency licenses, bundled assets, fonts, third-party notices, and source obligations are complete.
- [ ] Security reporting instructions and supported-version policy are published.
- [ ] The release commit, build environment, dependency versions, and artifact provenance are recorded.
- [ ] `MARKETING_VERSION`, `CITATION.cff`, `CHANGELOG.md`, the annotated tag, the GitHub Release name, and the app bundle metadata identify the same release according to the documented SemVer-to-bundle-version rule.

### macOS distribution

- [ ] The installable application archive is produced traceably from the approved release commit and declared toolchain; reproducibility means traceable regeneration and does not assert byte-identical compiler output.
- [ ] Release preflight rejects a dirty tree, untracked files, a lightweight or incorrectly targeted tag, origin or CI-commit mismatch, inconsistent version metadata, generated-project drift, and an unexpected Xcode version before any build begins.
- [ ] `no-fee-release-v1.sh evidence --source-dir DIR --commit OID --output-dir DIR` runs the complete prepublication gate in an isolated checkout of the clean exact commit and produces one new authoritative native `.xcresult`, its private `prepublication-gate.log`, and the content-free public test-evidence JSON.
- [ ] The private gate log and frozen `.xcresult` are retained as local evidence and are not attached to the GitHub Release; only `LectureBoard-AI-v1.0.0-test-results.json` from that evidence transaction enters the exact five-asset public set.
- [ ] The distribution build runs from an isolated checkout or worktree and has no Debug or Apple Development signing fallback.
- [ ] `prepare` consumes the exact public test JSON, frozen `.xcresult`, and private gate log from the same evidence transaction through `--test-result`, `--test-result-bundle`, and `--gate-log`, and binds them to the same full commit identifier.
- [ ] The application uses the hardened runtime and an ad hoc signature with no team identity or secure timestamp.
- [ ] Strict verification succeeds for the application and every nested executable component; the runtime flag, absence of an Apple team identity, architecture, bundle metadata, and exact entitlement allowlist are checked.
- [ ] The ZIP contains only the intended application bundle, preserves required Unix modes, omits unneeded AppleDouble/resource-fork/extended-attribute entries, rejects path traversal and unexpected entries, and retains a valid strict application signature after both macOS `ditto` and `/usr/bin/unzip` extraction.
- [ ] The release includes SHA-256 checksums, an SBOM, the content-free test-evidence JSON, and provenance binding the archive, executable, bundle version, toolchain, public test evidence, tag, and exact commit.
- [ ] The complete `verify` command passes for the exact five prepared files and full approved commit identifier before publication approval.
- [ ] A quarantine-preserving transfer produces the expected Gatekeeper warning, and installation is verified using only Apple's per-application Open Anyway exception. Instructions never disable Gatekeeper globally or remove quarantine metadata.
- [ ] Download, installation, first launch, Screen Recording, microphone, Speech, and normal relaunch are verified without development-only entitlements or paths.
- [ ] The final archive checksum, size, code-directory hashes, exact public test-evidence digest and local result-bundle tree digest, and version metadata are recorded after packaging; no later rebuild, signing, or packaging changes those bytes.

### Documentation and operations

- [ ] Installation, permissions, first lecture, update, uninstall, troubleshooting, privacy, accessibility, fallback, and support instructions are complete.
- [ ] Release notes distinguish verified capabilities, prototypes, known limitations, and unsupported configurations.
- [ ] The README and documentation consistently state that no prerelease application will be published and that `v1.0.0` is the completion release.
- [ ] `docs/build-verification.md` contains dated evidence for the exact release commit and artifact.
- [ ] A rollback or withdrawal procedure is documented in case the public artifact is defective, including who may act, which evidence is preserved, and how users are warned without rewriting the published tag.

Passing this gate establishes an exact candidate ready for the final publication decision. It is not project completion.

## 4. Public v1.0.0 publication

- [ ] All required GitHub Actions checks pass for the approved release commit.
- [ ] The release commit on `main` is reviewed and has no unintended changes.
- [ ] Explicit user approval is obtained immediately before the external publication action and identifies the exact release commit and final application-archive SHA-256.
- [ ] An annotated `v1.0.0` tag is created from the approved release commit and pushed without rewriting history.
- [ ] Exactly five attached assets—`LectureBoard-AI-v1.0.0-arm64.zip`, `LectureBoard-AI-v1.0.0-test-results.json`, `SBOM.spdx.json`, `SHA256SUMS`, and `provenance.json`—and the separate release-note body are assembled and verified in a draft GitHub Release before it becomes public.
- [ ] A public GitHub Release is created for `v1.0.0`; it is non-draft, is not marked as a prerelease, and has immutable-release controls enabled. A mutable Release does not satisfy this gate.
- [ ] The hardened-runtime, ad hoc-signed arm64 application archive is attached without any Developer ID or Apple-notarization claim.
- [ ] Release notes, supported environment, installation instructions, known limitations, privacy information, SHA-256 checksum, SBOM, and provenance are included.
- [ ] `LectureBoard-AI-v1.0.0-test-results.json` is attached and matches both `SHA256SUMS` and the provenance record without exposing test logs or local paths.
- [ ] GitHub's source archives and all five attached assets correspond to the approved tag and recorded provenance.

## 5. Post-publication verification — completion gate

- [ ] The public release page and all five attached assets are accessible without repository-owner credentials.
- [ ] All five attached assets are downloaded from the public GitHub Release into a clean verification environment, have the exact approved names, and match the approved local files byte for byte.
- [ ] The unauthenticated public REST metadata is retained locally and reports the exact repository, `v1.0.0` tag, non-draft and non-prerelease state, `immutable: true`, and exactly the five approved asset names and sizes; any digest field supplied by GitHub matches the downloaded bytes.
- [ ] The unauthenticated public tag-ref snapshot is retained locally and contains exactly the annotated `v1.0.0` tag object and its peeled approved commit.
- [ ] The complete `verify-public --source-dir DIR --approved-dir DIR --commit OID --output-dir DIR` transaction passes. Its downloaded assets, `public-release.json`, `public-tag-refs.txt`, and `verification-receipt.json` are retained as local post-publication evidence, not Release attachments.
- [ ] The four downloaded payload SHA-256 values match the downloaded and byte-identical `SHA256SUMS` manifest.
- [ ] Bundle identity, ad hoc signature, hardened runtime, architecture, version, entitlement allowlist, SBOM, and provenance are independently rechecked.
- [ ] The expected Gatekeeper warning and Apple's per-application Open Anyway exception are independently verified without disabling Gatekeeper globally or removing quarantine metadata.
- [ ] Installation, first launch, required permission flow, relaunch, and the supported core lecture path succeed from the downloaded artifact.
- [ ] The public release URL, release-metadata digest, annotated tag object and peeled commit, five asset filenames and digests, ad hoc signature evidence, test environment, and final results are recorded in `docs/build-verification.md`.
- [ ] Any discrepancy is resolved before the release is described as complete.

## 6. Withdrawal and rollback triggers

Publication must pause before the release becomes public, or the public artifact must be withdrawn
from ordinary download while preserving the tag and evidence for investigation, if any of the
following occurs:

- the public asset digest, tag commit, bundle metadata, signature, SBOM, or recorded
  provenance differs from the approved candidate;
- the documented per-application Gatekeeper exception, installation, first launch, required permission setup, relaunch, or the supported
  core lecture path fails on a clean supported Mac;
- the application modifies an original PowerPoint file, exposes lecture content unexpectedly,
  accepts ungrounded output, or renders while an identity, canvas, capture, or human-input safety
  boundary is unavailable;
- a release-blocking crash, data-integrity failure, permission loop, security issue, or materially
  misleading capability statement is found after publication.

Withdrawal is not completion. After correction, a new reviewed commit and artifact must repeat the
release-candidate and publication checks. A published tag is never moved or force-updated; a
replacement release uses the next appropriate semantic version.

Only when every item in Sections 1–5 has passed, with Sections 3–5 evaluated against the same `v1.0.0` commit and exact five-asset public Release, may the project be described as complete.

## Historical initial-publication material

The following documents and script concern creation of the source repository, not the completed application release:

- [`github-publication-ja.md`](github-publication-ja.md)
- [`open-source-release-checklist.md`](open-source-release-checklist.md)
- `scripts/publish-to-github.sh`

The repository already exists. Do not rerun the initial publication script for branch updates, pull requests, prereleases, release candidates, or `v1.0.0` publication.
