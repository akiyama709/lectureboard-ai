# ADR 0004: Provider-neutral speech and semantic reasoning

- Status: Accepted
- Date: 2026-08-29

## Context

Lecture data may be sensitive, and available speech and language models change rapidly. Hard-coding one cloud provider would limit privacy choices and long-term maintainability.

## Decision

Capture, transcription, semantic planning, validation, and rendering communicate through explicit protocols and serializable models. Local and cloud providers are optional adapters.

## Consequences

The initial architecture is slightly more modular, but it supports local-first use, provider comparison, and open-source contribution without requiring a commercial account.
