# Privacy and security architecture

## Data classes

LectureBoard AI may encounter microphone audio, live screen frames, presentation files, speaker notes, unpublished research, student speech, manual ink, names, images, and provider credentials.

## Default policy

- Process transient audio and frames in memory.
- Do not persist raw audio by default.
- Do not persist full screen recordings by default.
- Do not send data to a network provider unless the lecturer explicitly enables that provider.
- Keep analytics disabled by default.
- Clearly show active capture and provider state.

## Provider isolation

A provider declares:

- data it receives
- whether data leaves the Mac
- retention policy
- supported languages
- model identity and version
- expected latency
- whether output can be reproduced

The UI must show this information before a lecture begins.

## Credentials

Cloud-provider credentials are stored in the macOS Keychain. They must never appear in repository files, `UserDefaults`, plaintext logs, exported sessions, crash reports, or screenshots.

## Student participation

Capturing student speech requires institutional policy review, appropriate notice, and a clear reason. The first implementation focuses on the lecturer microphone and does not identify individual students.

## Open-source test data

Public fixtures must be synthetic or explicitly licensed. Real slides, recordings, and transcripts must not be included merely because they are technically accessible to a contributor.

## Logging

Structured diagnostic logs should redact transcript text by default. A temporary verbose mode may be enabled for controlled testing, with a visible warning and automatic expiration.
