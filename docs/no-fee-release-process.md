# No-fee v1 distribution process

This is the authoritative distribution path for the public `v1.0.0` release. ADR 0013 records the
decision not to purchase or use an institutional Apple Developer Program membership. The older
Developer ID and notarization tooling remains available as an optional future enhancement, but it
is not a completion requirement.

## Release artifact

The release asset is an arm64 ZIP containing `LectureBoard AI.app`. The application uses the
hardened runtime, an ad hoc signature, the reviewed entitlement allowlist, bundle identifier
`io.github.akiyama709.LectureBoardAI`, marketing version `1.0.0`, and a positive build number. It
must not contain a Developer ID identity, Apple team identifier, notarization ticket, development
entitlement, credential, private lecture material, or local absolute path.

The release also contains SHA-256 checksums, an SBOM, release notes, and machine-readable
provenance binding the source tag and commit, application executable, archive, toolchain, bundle
metadata, entitlements, and exact test result.

## Fixed order

1. Freeze and document the supported feature set and environment.
2. Complete the controlled, representative, privacy, accessibility, license, and recovery gates.
3. Set all version metadata to `1.0.0` and create an exact annotated local tag candidate.
4. Verify a clean tree, exact tag and commit, successful CI commit, generated Xcode project, and
   declared toolchain before building.
5. Build the Release application from an isolated checkout with the hardened runtime and ad hoc
   signing. Do not fall back to a Debug or Apple Development build.
6. Verify the application and every nested executable, then package only the application bundle
   with macOS metadata preserved. Reject unexpected ZIP entries and path traversal.
7. Generate the checksum, SBOM, provenance, release notes, and installation instructions. Do not
   change the application or archive afterward.
8. On a clean supported Mac, preserve quarantine and verify the expected Gatekeeper warning,
   Apple's per-application **Open Anyway** path, installation, first launch, permissions, relaunch,
   core lecture workflow, and recovery. Never disable Gatekeeper globally or remove quarantine.
9. Obtain explicit publication approval naming the exact commit and archive SHA-256.
10. Publish the annotated `v1.0.0` tag and non-prerelease GitHub Release without rewriting history.
11. Download the public archive without repository-owner credentials and repeat the checksum,
    structure, signature, metadata, installation, permission, launch, and supported-workflow checks.
12. Record the public URL and final evidence in `docs/build-verification.md`.

## Claim boundary

The completed application may be called the final `v1.0.0`; lack of Apple distribution services
does not make it an alpha or beta. Documentation must nevertheless state plainly that Apple has
not identified the publisher, scanned or notarized the archive, or authorized automatic
Gatekeeper acceptance. Checksums and repository provenance allow users to verify that downloaded
bytes match this project, but they do not replace Apple's trust service.
