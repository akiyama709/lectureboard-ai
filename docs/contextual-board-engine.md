# Contextual board engine

## Objective

The engine decides what deserves visible board space without requiring command phrases. It should be conservative: missing a marginal point is less harmful than confidently showing an incorrect statement during a lecture.

## Inputs

- Current slide text, objects, notes, and occupied regions
- Stable transcript segments with language and confidence
- Recent transcript context
- Existing board intents and their evidence
- Slide dwell time
- Optional prosodic features
- Pointer and PowerPoint-ink attention signals

## Baseline score

The deterministic baseline combines:

```text
importance =
    0.28 × novelty_from_slide
  + 0.29 × discourse_structure
  + 0.18 × repetition
  + 0.17 × spoken_emphasis
  + 0.08 × slide_dwell
```

This is an initial, inspectable baseline rather than a scientifically validated final weighting. Evaluation data should be used to recalibrate it.

## Discourse structures

The baseline recognizes cues for definitions, causality, comparison, enumeration, and questions in Japanese and English. Later semantic providers may improve paraphrase handling, but they must return evidence references and structured output.

## Deferred decisions

A proposal below the visibility threshold stays internal. It may become visible when later speech clarifies the concept, repeats it, or connects it to a higher-level structure. The app does not ask the lecturer to confirm ordinary uncertainty during the lecture.

## Grounding contract

Every `BoardIntent` contains source transcript identifiers. Future slide and note evidence identifiers will use the same pattern. Generated wording may compress or reorganize evidence, but it must not add an unsupported factual proposition.

## High-risk tokens

The validator applies stricter handling to:

- names and affiliations
- numbers and units
- dates and historical claims
- direct quotations
- formulas and symbols
- legal, medical, and safety claims

When exact validation is unavailable, the content is deferred or shown only in a private presenter preview.

## Evaluation

Evaluation must separately measure:

- useful annotations displayed
- useful annotations missed
- unsupported content displayed
- overlap with slide content or human ink
- reading stability
- latency from completed idea to visible board
- lecturer interventions
- student comprehension and cognitive load

Japanese and English results must be reported separately before mixed-language claims are made.
