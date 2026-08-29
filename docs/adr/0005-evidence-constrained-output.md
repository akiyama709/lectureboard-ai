# ADR 0005: Evidence-constrained student-visible output

- Status: Accepted
- Date: 2026-08-29

## Context

A language model can produce fluent wording that is not supported by the lecturer or slide. In a live lecture，an unsupported name，number，quotation，date，formula，or factual claim can mislead students before the lecturer notices it.

## Decision

Every student-visible board element must reference one or more stable transcript or slide-evidence identifiers. Model output is structured，validated，length-limited，and rejected when evidence is missing or high-risk tokens cannot be verified.

## Consequences

The system is deliberately conservative. Some useful but uncertain annotations will be deferred. Post-lecture review remains possible because every element keeps its source evidence.
