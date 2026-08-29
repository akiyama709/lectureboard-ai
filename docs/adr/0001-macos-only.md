# ADR 0001: macOS-only initial implementation

- Status: Accepted
- Date: 2026-08-29

## Context

Screen capture, transparent overlays, audio permissions, full-screen spaces, and pen behavior are operating-system-specific. Simultaneous macOS, Windows, and Linux development would divert work from lecture quality and reliability.

## Decision

The initial implementation targets macOS 26 or later，with primary validation on Apple silicon. Other platforms are outside the active roadmap until the macOS lecture path is dependable.

## Consequences

The project can use native Apple frameworks directly and reduce compatibility layers. Early adoption is narrower, but validation is clearer and failure handling can be designed around one platform.
