# Versioning

LectureBoard AI uses Semantic Versioning for repository releases. During development, the
repository version in `CITATION.cff` and the first released entry after `Unreleased` in
`CHANGELOG.md` may include a prerelease suffix, such as `0.1.0-alpha`. Those two versions and
their `YYYY-MM-DD` release dates must agree.

Apple bundle metadata has a narrower representation. `MARKETING_VERSION` in `project.yml` is
exactly the `MAJOR.MINOR.PATCH` core of the repository version, without a prerelease suffix or
build metadata. `CURRENT_PROJECT_VERSION` is a positive integer and must be advanced when a new
bundle build is distributed.

For the stable public v1 release, `CITATION.cff`, the released `CHANGELOG.md` heading, and
`MARKETING_VERSION` will all use `1.0.0`. The CFF and changelog dates will use the actual release
date. Run `make check-version-consistency` before creating a tag or release artifact.

This consistency check validates version and date metadata only. It does not establish that an
artifact was built, tested, signed, notarized, published, or independently verified.
