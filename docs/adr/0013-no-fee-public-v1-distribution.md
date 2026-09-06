# ADR 0013: Publish the final v1 release without paid Apple distribution services

- Status: Accepted
- Date: 2026-09-05

## Context

LectureBoard AI is free and open-source software. The project owner will not purchase an Apple
Developer Program membership and cannot publish under an eligible institution. Developer ID
certificates and Apple notarization are therefore unavailable. This distribution constraint is
independent of product maturity: an application is not an alpha or beta merely because Apple has
not identified or notarized its publisher.

## Decision

The project will publish no alpha, beta, or release-candidate GitHub Release. Completion means a
public, immutable, non-prerelease `v1.0.0` GitHub Release whose supported feature set has passed
the release tests and documented live verification. The release will identify the exact public
source commit, provide reproducible local build instructions, and attach exactly these five files:

- `LectureBoard-AI-v1.0.0-arm64.zip`;
- `LectureBoard-AI-v1.0.0-test-results.json`;
- `SBOM.spdx.json`;
- `SHA256SUMS`; and
- `provenance.json`.

The application archive carries an ad hoc code signature, with no claim that it is Developer ID
signed or Apple notarized. The provenance record binds the archive and content-free test evidence
to the release commit. Release notes, supported-environment information, and installation
instructions remain in the GitHub Release body rather than becoming a sixth attachment.
Installation may use only Apple's per-application **Open Anyway** exception when Gatekeeper blocks
the downloaded archive. The project will not tell users to disable Gatekeeper globally or remove
quarantine metadata.

Publication still requires explicit approval naming the exact release commit and application
archive SHA-256. Completion is established only after downloading all five public assets without
repository-owner credentials, confirming their exact names and byte equality with the approved
local set, and rechecking the archive checksum, bundle identity, ad hoc signature, architecture,
version, launch, permissions, and supported core workflow on a supported Mac.

## Consequences

The application can be functionally complete and released as `v1.0.0` without a paid Apple
membership, but macOS cannot identify its publisher through Developer ID or recognize an Apple
notarization ticket. Users of the prebuilt archive should expect an initial Gatekeeper warning and
must make a deliberate per-application exception. The release documentation and user interface
must not imply Apple review, notarization, malware scanning, or an identified developer.

ADR 0007 remains authoritative for public-release finality, exact-artifact verification, and the
rule that prereleases are not completion. This ADR supersedes only its mandatory Developer ID,
notarization, and automatic Gatekeeper-acceptance requirements.
