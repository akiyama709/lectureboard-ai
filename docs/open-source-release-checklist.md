# Initial open-source repository checklist (historical)

This checklist records the initial publication of the source repository on 2026-08-29. It is not the release checklist for the completed application. The repository is public, but no alpha, beta, release-candidate, or `v1.0.0` GitHub Release has been published.

Do not rerun the initial repository-publication script. Use [`v1-release-checklist.md`](v1-release-checklist.md) for the authoritative completion gates and the future public `v1.0.0` release.

## Repository

- [x] Create `akiyama709/lectureboard-ai` as a public repository
- [x] Use `main` as the default branch
- [ ] Enable private vulnerability reporting
- [ ] Enable branch protection after the first stable CI run
- [ ] Require pull-request review for non-trivial changes
- [ ] Enable Dependabot alerts and secret scanning when available

## Intellectual property and privacy

- [x] Confirm the MIT License choice
- [x] Confirm ownership or permission for every image and test asset
- [x] Exclude real lecture audio, unpublished slides, student data, model weights, and licensed fonts
- [x] Add notices for optional third-party components before including them

## Technical

- [x] Generate the Xcode project from `project.yml`
- [x] Run core tests
- [x] Run the unsigned app build
- [x] Check Japanese and English UI resources
- [ ] Verify screen, microphone, and speech permission prompts
- [x] Verify that no credentials appear in the Git history

## Communication

- [x] Clearly label the repository implementation as an alpha scaffold
- [x] State what is implemented and what is not
- [x] Include a privacy warning for real lecture use
- [x] Publish reproducible build instructions

These checked items describe repository content at initial publication. They do not establish that a distributable app, prerelease, signed build, notarized build, or completed product exists.
