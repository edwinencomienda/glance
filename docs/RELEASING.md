# Releasing

Glance ships as **source releases**: a git tag plus a GitHub release with notes.
No prebuilt app is attached. People build it themselves with
`scripts/build-app.sh`, signed with their own identity, so nothing needs
notarizing.

## Versioning

[Semantic Versioning](https://semver.org/), `MAJOR.MINOR.PATCH`:

- **PATCH** (1.0.1): bug fixes only.
- **MINOR** (1.1.0): new features or settings, backwards compatible. Existing
  settings keep working, and new settings default to the current behaviour.
- **MAJOR** (2.0.0): breaking changes, e.g. raising the minimum macOS version,
  or removing or reinterpreting a setting.

The version lives in `Resources/Info.plist`:

- `CFBundleShortVersionString`: the user-facing version (`1.0.0`). The tag is
  `v` + this.
- `CFBundleVersion`: a build number that goes up by one with every release
  (`1`, `2`, `3`…), whatever the version.

## Changelog

`CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

- **Every user-facing change** adds a line under `## [Unreleased]` in the same
  commit, in one of the groups **Added**, **Changed**, **Fixed** or **Removed**.
  Internal refactors and doc-only changes don't need an entry.
- Write entries for users: what changed for them, not which file changed.
- At release time, the `Unreleased` section becomes the version's section and
  its notes become the GitHub release notes, word for word.

## Making a release

1. **Prepare the version.** On `main`, in one commit (e.g. `Release 1.1.0`):
   - In `CHANGELOG.md`, rename `## [Unreleased]` to `## [1.1.0] - YYYY-MM-DD`,
     add a fresh empty `## [Unreleased]` above it, and update the links at the
     bottom:
     ```
     [Unreleased]: https://github.com/edwinencomienda/glance/compare/v1.1.0...HEAD
     [1.1.0]: https://github.com/edwinencomienda/glance/compare/v1.0.0...v1.1.0
     ```
   - In `Resources/Info.plist`, set `CFBundleShortVersionString` to `1.1.0` and
     increment `CFBundleVersion`.
2. **Test.** Run `scripts/build-app.sh --install` and go through the manual
   checklist in [DEVELOPMENT.md](DEVELOPMENT.md#testing).
3. **Push** the release commit to `main`.
4. **Dry run:** `scripts/release.sh`. It checks that you're on a clean `main`
   in sync with `origin`, that the tag is new, that the changelog has the
   version's section and link, and that the tests pass and the app builds. Then
   it prints the release notes. It changes nothing.
5. **Publish:** `scripts/release.sh --publish`. It creates the annotated tag
   `vX.Y.Z`, pushes it, and creates the GitHub release "Glance X.Y.Z" with the
   changelog notes.

## Fixing a release

- **Notes wrong:** edit them on GitHub (`gh release edit vX.Y.Z --notes-file …`)
  and fix `CHANGELOG.md` to match.
- **Bug found after release:** don't move or reuse a published tag. Fix it on
  `main` and release a patch version.
