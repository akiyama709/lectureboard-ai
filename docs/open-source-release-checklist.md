# Open-source release checklist

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

- [x] Clearly label the release as alpha
- [x] State what is implemented and what is not
- [x] Include a privacy warning for real lecture use
- [x] Publish reproducible build instructions
