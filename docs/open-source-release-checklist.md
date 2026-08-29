# Open-source release checklist

## Repository

- [ ] Create `akiyama709/lectureboard-ai` as a public repository
- [ ] Use `main` as the default branch
- [ ] Enable private vulnerability reporting
- [ ] Enable branch protection after the first stable CI run
- [ ] Require pull-request review for non-trivial changes
- [ ] Enable Dependabot alerts and secret scanning when available

## Intellectual property and privacy

- [ ] Confirm the MIT License choice
- [ ] Confirm ownership or permission for every image and test asset
- [ ] Exclude real lecture audio, unpublished slides, student data, model weights, and licensed fonts
- [ ] Add notices for optional third-party components before including them

## Technical

- [ ] Generate the Xcode project from `project.yml`
- [ ] Run core tests
- [ ] Run the unsigned app build
- [ ] Check Japanese and English UI resources
- [ ] Verify screen, microphone, and speech permission prompts
- [ ] Verify that no credentials appear in the Git history

## Communication

- [ ] Clearly label the release as alpha
- [ ] State what is implemented and what is not
- [ ] Include a privacy warning for real lecture use
- [ ] Publish reproducible build instructions
