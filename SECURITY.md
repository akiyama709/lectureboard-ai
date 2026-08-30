# Security and privacy policy

## Reporting a vulnerability

Please do not disclose security or privacy vulnerabilities in a public issue. Use GitHub's private vulnerability-reporting feature when it is enabled for the repository. Until then, contact the repository owner privately through the contact method listed on the owner's GitHub profile.

## Sensitive data

LectureBoard AI may process unpublished research, student speech, personal information, screen content, microphone audio, and API credentials. Contributors must not include real lecture data in tests or examples unless it is explicitly licensed and consented for public release.

## Secrets

API credentials must be stored in the macOS Keychain by provider adapters. They must never be stored in source files, sample projects, logs, session exports, or issue attachments.

## Supported versions

No GitHub prerelease or final release has been published. During development, security fixes target the latest supported commit on `main`; no production-security warranty is made for the alpha scaffold or local development artifacts. If a prerelease is published, its release notes must state whether it receives security fixes. The supported-version policy for `v1.0.0` must be fixed before the release-candidate gate closes.
