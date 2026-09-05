# ADR 0007: Define completion as the public v1.0.0 GitHub Release

- Status: Accepted; distribution-signing requirements superseded by ADR 0013
- Date: 2026-08-30

## Context

The source repository is already public, while the application remains in pre-release development. Repository creation, source availability, internal validation labels, and local development builds do not establish that general users can install and use a completed macOS application.

## Decision

Project completion means publication of the public `v1.0.0` GitHub Release for `akiyama709/lectureboard-ai`. ADR 0013 supersedes this record's mandatory Developer ID and Apple-notarization requirements because the project owner will use no paid or institutional Apple membership. The final archive instead follows the no-fee verification requirements in [`../v1-release-checklist.md`](../v1-release-checklist.md).

Controlled-workflow, representative-use, and exact-artifact checks are internal validation gates. No alpha, beta, or release-candidate application Release will be published; only the verified final `v1.0.0` is intended for public application distribution.

## Consequences

Release readiness is evaluated against the exact release commit and artifact rather than inferred from repository visibility or historical builds. The final external publication requires explicit approval. Version metadata, licensing, privacy, security, accessibility, installation, recovery, supported environments, known limitations, checksums, and artifact provenance must be resolved before the release-candidate gate closes.

The institutional review mentioned in ADR 0006 is not inferred from the existence of the public repository. Any institutional, contractual, intellectual-property, privacy, or research-ethics review required for the supported `v1.0.0` use cases remains an explicit release gate.
