# ADR 0002: Observe PowerPoint and render a separate overlay

- Status: Accepted
- Date: 2026-08-29

## Context

Writing directly into the PowerPoint file or slideshow creates coupling, risks modifying source material, and complicates undo and recovery.

## Decision

The first implementation observes the PowerPoint window and renders AI annotations in a transparent, click-through overlay. PowerPoint remains authoritative. A composite sharing window is part of the planned online-teaching path，because meeting applications should receive one combined window.

## Consequences

The overlay can be hidden immediately and does not corrupt the presentation. Exact coordinate tracking and online window-sharing behavior require careful validation.
