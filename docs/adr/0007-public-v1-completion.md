# ADR 0007: Define completion as the public v1.0.0 GitHub Release

- Status: Accepted
- Date: 2026-08-30

## Context

The source repository is already public, while the application remains an alpha scaffold. Repository creation, source availability, prerelease labels, and local development builds do not establish that general users can install and use a completed macOS application.

## Decision

Project completion means publication of the public `v1.0.0` GitHub Release for `akiyama709/lectureboard-ai`. The release must include an installable macOS artifact that is Developer ID signed, uses the hardened runtime, is accepted by Apple notarization, and passes the post-publication verification in [`../v1-release-checklist.md`](../v1-release-checklist.md).

Alpha, beta, and release-candidate builds are intermediate validation gates. They may be distributed for testing, but they are not project completion.

## Consequences

Release readiness is evaluated against the exact release commit and artifact rather than inferred from repository visibility or historical builds. The final external publication requires explicit approval. Version metadata, licensing, privacy, security, accessibility, installation, recovery, supported environments, known limitations, checksums, and artifact provenance must be resolved before the release-candidate gate closes.

The institutional review mentioned in ADR 0006 is not inferred from the existence of the public repository. Any institutional, contractual, intellectual-property, privacy, or research-ethics review required for the supported `v1.0.0` use cases remains an explicit release gate.
