# No-fee v1 distribution process

This is the authoritative distribution path for the public `v1.0.0` release. ADR 0013 records the
decision not to purchase or use an institutional Apple Developer Program membership. The older
Developer ID and notarization tooling remains available as an optional future enhancement, but it
is not a completion requirement.

## Release assets

The attached asset set contains exactly five regular files:

- `LectureBoard-AI-v1.0.0-arm64.zip`;
- `LectureBoard-AI-v1.0.0-test-results.json`;
- `SBOM.spdx.json`;
- `SHA256SUMS`; and
- `provenance.json`.

Release notes and supported-environment information belong in the GitHub Release body and are not
a sixth attachment. The ZIP contains `LectureBoard AI.app`. The application uses the
hardened runtime, an ad hoc signature, the reviewed entitlement allowlist, bundle identifier
`io.github.akiyama709.LectureBoardAI`, marketing version `1.0.0`, and a positive build number. It
must not contain a Developer ID identity, Apple team identifier, notarization ticket, development
entitlement, credential, private lecture material, or local absolute path.

The test-evidence JSON contains no test logs, local paths, or lecture content. The checksum manifest
covers the ZIP, test evidence, SBOM, and provenance. The provenance binds the source tag and
commit, application executable, archive, toolchain, bundle metadata, entitlements, and the public
test-evidence asset. The test evidence binds its exact source commit and the local authoritative
result bundle by a content-tree digest without publishing test logs or local paths. Produce that
digest by hashing the byte-exact manifest emitted by the committed
`scripts/release-artifact-tools.sh tree-manifest` command. Retain the frozen `.xcresult` and
`prepublication-gate.log` as private evidence; neither is a GitHub Release asset. The manifest is a
deterministic intermediate representation and need not be retained separately.

## Operator commands

Use full absolute paths and the same full `COMMIT_OID` throughout. Each output directory below must
have an existing parent and must not already exist.

First, generate fresh evidence from the clean exact commit. This command creates one content-free
public JSON, one private gate log, and exactly one newly generated private authoritative
`.xcresult` in the evidence directory:

```bash
./scripts/no-fee-release-v1.sh evidence \
  --source-dir /absolute/path/to/lectureboard-ai \
  --commit COMMIT_OID \
  --output-dir /absolute/path/to/private-evidence
```

Create the annotated `v1.0.0` tag candidate at that same commit, then prepare the release directory
using the exact three evidence outputs. Replace `Test-LectureBoardAI-....xcresult` with the one
result-bundle name produced by `evidence`:

```bash
./scripts/no-fee-release-v1.sh prepare \
  --source-dir /absolute/path/to/lectureboard-ai \
  --tag v1.0.0 \
  --commit COMMIT_OID \
  --test-result /absolute/path/to/private-evidence/LectureBoard-AI-v1.0.0-test-results.json \
  --test-result-bundle /absolute/path/to/private-evidence/Test-LectureBoardAI-....xcresult \
  --gate-log /absolute/path/to/private-evidence/prepublication-gate.log \
  --output-dir /absolute/path/to/approved-release
```

The prepared directory must contain exactly the five files listed above. Verify those exact local
bytes before approval or upload:

```bash
./scripts/no-fee-release-v1.sh verify \
  --archive /absolute/path/to/approved-release/LectureBoard-AI-v1.0.0-arm64.zip \
  --checksum /absolute/path/to/approved-release/SHA256SUMS \
  --sbom /absolute/path/to/approved-release/SBOM.spdx.json \
  --provenance /absolute/path/to/approved-release/provenance.json \
  --test-result /absolute/path/to/approved-release/LectureBoard-AI-v1.0.0-test-results.json \
  --commit COMMIT_OID
```

After explicit publication approval, publish only those five attachments in an immutable,
non-draft, non-prerelease `v1.0.0` GitHub Release. Then run the unauthenticated public verifier. It
downloads all five assets, the public REST release metadata, and the public annotated-tag refs into
a new local evidence directory; requires `immutable: true`, exact asset metadata, the annotated tag
object, its peeled exact commit, and byte equality with the approved directory; and independently
verifies the downloaded archive:

```bash
./scripts/no-fee-release-v1.sh verify-public \
  --source-dir /absolute/path/to/lectureboard-ai \
  --approved-dir /absolute/path/to/approved-release \
  --commit COMMIT_OID \
  --output-dir /absolute/path/to/public-verification
```

`public-release.json`, `public-tag-refs.txt`, and `verification-receipt.json` are local
post-publication evidence, not additional GitHub Release assets. The lower-level
`compare-public` command is available only when the five public assets and both public metadata
files have already been acquired independently. It begins
`compare-public --approved-dir DIR --downloaded-dir DIR` and also requires
`--release-metadata FILE`, `--tag-refs FILE`, and `--commit OID`; its complete concrete form is:

```bash
./scripts/no-fee-release-v1.sh compare-public \
  --approved-dir /absolute/path/to/approved-release \
  --downloaded-dir /absolute/path/to/downloaded-assets \
  --release-metadata /absolute/path/to/public-release.json \
  --tag-refs /absolute/path/to/public-tag-refs.txt \
  --commit COMMIT_OID
```

## Fixed order

1. Freeze and document the supported feature set and environment.
2. Complete the controlled, representative, privacy, accessibility, license, and recovery gates.
3. Set all version metadata to `1.0.0`, finalize one clean exact source commit, and ensure its CI
   checks pass.
4. Run `evidence` against that clean exact commit. Preserve its private gate log and `.xcresult`,
   and use only its content-free JSON as a public asset.
5. Create an exact annotated local tag candidate, then run `prepare` with the same commit and the
   exact three evidence outputs. Do not fall back to a Debug or Apple Development build.
6. Run `verify` against the exact prepared five-asset directory. The preparation path must have
   packaged only the application bundle, and the verifier must check the application and every
   nested executable.
   The reviewed bundle has no required resource forks, ACLs, or extended attributes, so omit those
   archive metadata classes to prevent AppleDouble files from appearing inside the signed bundle.
   Reject unexpected ZIP entries and path traversal, and require strict signature verification
   after both macOS `ditto` and `/usr/bin/unzip` extraction.
7. Confirm the generated checksum, SBOM, provenance, public test evidence, release notes, and
   installation instructions. Do not change any approved asset afterward.
8. On a clean supported Mac, preserve quarantine and verify the expected Gatekeeper warning,
   Apple's per-application **Open Anyway** path, installation, first launch, permissions, relaunch,
   core lecture workflow, and recovery. Never disable Gatekeeper globally or remove quarantine.
9. Obtain explicit publication approval naming the exact commit and archive SHA-256.
10. Publish the annotated `v1.0.0` tag and an immutable, non-draft, non-prerelease GitHub Release
    containing exactly the five approved attachments, without rewriting history.
11. Run `verify-public` without repository-owner credentials. Retain its downloaded assets,
    public REST metadata, public tag refs, and receipt, then repeat installation, permission,
    launch, and supported-workflow checks against its downloaded archive.
12. Record the public URL and final evidence in `docs/build-verification.md`.

## Claim boundary

The completed application may be called the final `v1.0.0`; lack of Apple distribution services
does not make it an alpha or beta. Documentation must nevertheless state plainly that Apple has
not identified the publisher, scanned or notarized the archive, or authorized automatic
Gatekeeper acceptance. Checksums and repository provenance allow users to verify that downloaded
bytes match this project, but they do not replace Apple's trust service.
