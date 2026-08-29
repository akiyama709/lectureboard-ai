# LectureBoard AI macOS product requirements v1.3

## Purpose

LectureBoard AI observes a live PowerPoint lecture, transcribes the lecturer, infers educational importance from context, and adds grounded text and simple diagrams to unused slide space. The lecturer should not need to memorize or speak commands.

## Initial scope

- macOS 26 or later
- Apple silicon first
- Microsoft PowerPoint for Mac
- Japanese，English，and Japanese–English mixed lectures
- Clean digital ink and a more handwritten preset

## Required behavior

- Infer importance from novelty, definitions, causality, contrast, enumeration, repetition, emphasis, slide dwell time, notes, and the existing board.
- Defer uncertain material without interrupting the lecturer.
- Show only stable annotations to students.
- Ground every annotation in slide, note, or transcript evidence.
- Treat PowerPoint ink and lecturer handwriting as occupied, human-priority space.
- Keep confirmed annotations spatially stable.
- Continue the lecture normally if the AI subsystem fails.

## Initial board forms

Keywords, definitions, bullet lists, questions, warnings, boxes, underlines, arrows, causal chains, comparisons, hierarchies, and simple concept maps.

## Privacy

Audio and slide content are ephemeral by default. Persistence, cloud transfer, and analytics require explicit opt-in. Provider credentials belong in the macOS Keychain and never in session logs or repository files.
