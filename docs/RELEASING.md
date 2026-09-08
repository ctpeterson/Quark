# Releasing Quark

Quark uses Semantic Versioning and Keep a Changelog. The `version` field in `quark.nimble` is authoritative; Git tags and changelog headings reflect it.

## Choose the version

Before `1.0.0`:

- increment `MINOR` for a changed portable contract or a substantial capability;
- increment `PATCH` for compatible fixes, documentation, or build improvements; and
- use a prerelease suffix such as `-rc.1` only when publishing a candidate for wider testing.

After `1.0.0`, increment `MAJOR` for incompatible public-interface changes, `MINOR` for compatible capabilities, and `PATCH` for compatible fixes.

## Prepare and publish a release

1. Confirm every notable user-facing change is under `CHANGELOG.md` → `Unreleased`.
2. Choose `X.Y.Z`, set `version = "X.Y.Z"` in `quark.nimble`, and replace the `Unreleased` changelog contents with `## [X.Y.Z] - YYYY-MM-DD` beneath a fresh empty `Unreleased` section.
3. Add comparison links at the bottom of `CHANGELOG.md` once a previous release tag exists.
4. Run `nimble verify`, then inspect `git diff --check`, the complete diff, and repository status.
5. Commit the release as `release: vX.Y.Z`.
6. Create an annotated tag with `git tag -a vX.Y.Z -m "Quark X.Y.Z"`.
7. Push the commit and tag. Nimble discovers package versions from version-like repository tags.

The version and tag must agree. A release tag is immutable; correct a released defect with a new version.
