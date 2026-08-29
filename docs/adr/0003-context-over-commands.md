# ADR 0003: Contextual inference instead of required voice commands

- Status: Accepted
- Date: 2026-08-29

## Context

Voice-command help changes how a lecturer speaks, adds cognitive load, and makes the assistant feel like a tool that must be continuously operated.

## Decision

No voice command is required for ordinary board generation. The engine infers educational importance from slide and lecture context. Optional emergency controls remain available through the application UI and keyboard shortcuts.

## Consequences

The system needs conservative uncertainty handling, traceable evidence, and evaluation of false positives. The lecturer can speak naturally.
