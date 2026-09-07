# Optional Developer ID distribution process

> ADR 0013 supersedes this document as the `v1.0.0` completion path. The project owner will not
> purchase or use an institutional Apple Developer Program membership. This stricter Developer ID
> and notarization route is retained only as an optional future enhancement and must not block or
> be claimed by the no-fee public release. See [`no-fee-release-process.md`](no-fee-release-process.md).

This document defines the fail-closed path from an approved source commit to a public LectureBoard
AI release. It does not assert that the current pre-release development tree is release-ready. The authoritative
feature, evidence, signing, publication, and post-publication gates remain in
[`v1-release-checklist.md`](v1-release-checklist.md).

## Current implementation boundary

The repository currently contains deterministic fixture coverage for the following distribution
controls:

- `scripts/release-preflight.sh` validates an exact annotated `v1.0.0` source state, local
  `origin/main` tracking commit, separately supplied CI commit, release metadata, Xcode 26.6,
  generated-project equality, and one explicitly approved Developer ID Application identity. It
  performs no build, signing, notarization, Apple submission, GitHub mutation, or network fetch.
- `scripts/verify-release-code.sh` validates already-produced app or DMG signature evidence. For an
  app, it also checks the exact bundle identifier, version, build, arm64 architecture, hardened
  runtime, secure timestamp, Developer ID requirements, certificate fingerprint, team, and the
  one-key audio-input entitlement allowlist. It does not build, sign, notarize, staple, package,
  or publish.
- `scripts/build-release-app.sh`, together with `scripts/release-artifact-tools.sh`, reconstructs
  and verifies the exact approved Git tree, constrains the generated Xcode project and package
  manifest, builds from isolated source, and commits an app and dSYM only after all required checks
  and cleanup succeed. The signed application `Info.plist` binds the approved commit and tag.
- `scripts/package-release-dmg.sh`, together with
  `scripts/release-package-evidence-tools.sh` and `scripts/release-exclusive-rename.c`, verifies the
  approved app and source evidence, submits the app and DMG notarization payloads through the named
  Keychain profile, staples and validates them, checks the mounted image and embedded app, and
  commits the final package and evidence through an exclusive fail-closed completion boundary.
- `scripts/prepublish-check.sh` runs the current 26-stage source, test, documentation, permission,
  version, and release-control gate. Its release fixtures exercise rejection paths without using a
  real distribution identity, contacting Apple, creating a production DMG, or mutating GitHub.

The authoritative automated entry is the directly executed `./scripts/prepublish-check.sh`, which
is also the CI entry. `make verify` remains a local convenience alias, not a release attestation:
command-line Make controls such as dry-run can skip recipes before any script begins. The direct
entry invokes child Make targets only through `scripts/release-make-gate.sh`, which removes inherited
Make behavior flags before starting Make; the fixed privileged recipe-shell wrapper then protects
the recipe-launch boundary.

On the development Mac audited on 2026-09-02, no valid code-signing identity was available. No
Developer ID-signed, notarized, or installable distribution artifact has therefore been produced.
The builder and packager fixture contracts have passed locally, but the credentialed production
Developer ID, notarization, stapling, final-DMG, clean-Mac, and public-download paths remain
unverified.

## Required non-secret inputs

The release operator records the following values without copying a password, private key, Apple
ID, or notary credential into the repository, command line, log, or provenance file:

- exact annotated tag and peeled commit;
- exact local `origin/main` and successful CI commit;
- release date, version, and positive bundle build number;
- expected Apple team identifier and Developer ID Application certificate fingerprint;
- name of a separately configured `notarytool` Keychain profile;
- exact Xcode, SDK, XcodeGen, and macOS versions;
- empty release-candidate output directory;
- expected asset names and reviewed release notes.

The Keychain profile is created once through an explicit human-operated credential setup. Release
scripts accept its name only. They never accept an Apple ID password, app-specific password,
private-key path, or a command that disables verification.

## Fixed release order

1. Run the source and identity preflight. Stop before building if any source, tag, CI, toolchain,
   metadata, generated-project, or Developer ID check fails.
2. Create an isolated checkout of the approved commit and build an arm64 Release archive. Export
   with manual Developer ID Application signing, the approved team and fingerprint,
   `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO`, and no Debug, Apple Development, or ad hoc fallback.
3. Verify the exported application and all approved nested code before contacting Apple.
4. Create a temporary ZIP of the application with `ditto --keepParent`, submit that ZIP using only
   the named `notarytool` profile, require the exact `Accepted` status and an issue-free log, then
   staple and validate the original application bundle.
5. Construct a disk image containing only the stapled application and the intended Applications
   link. Verify its structure and mounted contents, then sign the DMG with the approved Developer
   ID Application identity and secure timestamp.
6. Submit the signed DMG separately, require an issue-free `Accepted` result, staple and validate
   the DMG, run structural, signature, and remount checks, and verify that the embedded application
   remains the previously approved stapled application.
7. Only after the final DMG staple, compute the release checksum, size, signature identifiers, and
   provenance. No later build, signing, packaging, or staple operation may change those bytes.
8. Test that exact candidate on clean supported Macs, including quarantine-preserving transfer,
   Gatekeeper assessment, installation, first launch, permissions, relaunch, supported lecture
   flow, and recovery cases.
9. Obtain explicit publication approval naming the exact commit and final DMG SHA-256. Assemble
   and inspect a draft GitHub Release, then publish the immutable annotated tag and non-prerelease
   `v1.0.0` release without rewriting history.
10. Download the public asset without repository-owner credentials and repeat checksum, signature,
    notarization, Gatekeeper, installation, launch, permission, and core lecture verification. The
    project is not complete until this public-byte verification passes.

## Provenance record

The final integrated provenance record must bind the tag object, peeled commit, clean-tree result,
local `origin/main` and CI commit, toolchain versions, bundle version and build, application
executable SHA-256 and CDHash, team and leaf certificate fingerprint, final DMG SHA-256 and size,
app and DMG notary submission identifiers and log digests, stapler and Gatekeeper results, exact
test-result digest, and clean-Mac verification environment. The production scripts are designed to
encode or emit only a subset of those fields. Their fixtures validate contracts and rejection
paths; they produce no credentialed production record and are not yet this end-to-end record. Raw
credentials and private paths are excluded.

Signing timestamps and Apple notarization tickets make byte-for-byte reproduction of a signed
artifact inappropriate as the release claim. The supported claim is traceable regeneration from
the exact source commit and declared toolchain, followed by exact-byte verification of the final
published artifact.

## Stop and withdrawal rules

No failed check is converted to a warning and no threshold, signature, entitlement, or provenance
rule is weakened to make a candidate pass. A mismatch after publication triggers the withdrawal
rules in the v1 checklist. The published tag is preserved; a corrected artifact is built from a new
reviewed commit and released under the next appropriate semantic version.
