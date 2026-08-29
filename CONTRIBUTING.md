# Contributing

Thank you for considering a contribution to LectureBoard AI.

## Before opening a large pull request

Open an issue describing the educational problem, the proposed behavior, privacy implications, and how the change will be tested. Changes to capture, transcription, AI providers, data retention, or grounding rules require explicit design discussion.

## Development setup

```bash
make bootstrap
make test
make build
```

## Contribution expectations

- Keep the macOS-only scope for the initial milestones.
- Do not add a required cloud service to the core package.
- Never commit API keys, lecture recordings, student data, proprietary slides, model weights, or licensed fonts.
- Board output must remain traceable to transcript, slide, or speaker-note evidence.
- Add or update tests for logic changes.
- Clearly label prototypes and incomplete behavior.
- Keep Japanese documentation punctuation as `，` and `．`.

## Commit messages

Use a short imperative subject, for example:

```text
Add grounded comparison intent classifier
```

## Pull requests

A pull request should explain:

1. What problem it addresses.
2. Why the chosen design is appropriate for lectures.
3. What privacy or safety consequences it has.
4. How it was tested.
5. What remains incomplete.
