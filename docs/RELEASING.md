# Releasing

Every release is a git tag plus a GitHub release with notes and a
**Developer ID–signed, notarized** `Glance.dmg` (and `Glance.zip`). Pushing the
tag starts the [release workflow](../.github/workflows/release.yml), which
builds, signs, notarizes and publishes everything. People can still build from
source with `scripts/build-app.sh`.

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
   version's section and link, that the signing secrets exist, and that the
   tests pass and the app builds. Then it prints the release notes. It changes
   nothing.
5. **Publish:** `scripts/release.sh --publish`. It creates the annotated tag
   `vX.Y.Z` and pushes it.
6. **Watch the workflow** in the Actions tab (about 10 minutes, mostly waiting
   on notarization). It checks that the tag matches `Info.plist`, runs the
   tests, runs `scripts/package-release.sh` and creates the GitHub release
   "Glance X.Y.Z" with the changelog notes and the DMG and ZIP attached.
7. **Check the download:** install from the release's DMG on a Mac and confirm
   it opens without a Gatekeeper warning.

To build the DMG without releasing, run the workflow by hand from the Actions
tab (**Run workflow**). It uploads the DMG and ZIP as a workflow artifact and
publishes nothing.

## Signing and notarization

`scripts/package-release.sh` builds the universal app, signs it with a
**Developer ID Application** identity and the hardened runtime, notarizes and
staples it, then wraps it in a DMG that's signed, notarized and stapled too.

### Repository secrets

The workflow needs these under **Settings → Secrets and variables → Actions**:

| Secret | What to put in it |
| --- | --- |
| `CERTIFICATE_BASE64` | Base64 of the Developer ID Application certificate exported as `.p12` (`base64 -i cert.p12 \| pbcopy`) |
| `CERTIFICATE_PASSWORD` | The password set when exporting the `.p12` |
| `APPLE_API_KEY_BASE64` | Base64 of an App Store Connect API key `.p8` (`base64 -i AuthKey_XXXX.p8 \| pbcopy`) |
| `APPLE_API_KEY_ID` | The API key's 10-character ID |
| `APPLE_API_ISSUER` | The issuer UUID (App Store Connect → Users and Access → Integrations) |

The signing identity's name is read from the certificate, so it isn't a
secret. The workflow imports the certificate into a throwaway keychain with a
random password and deletes it, and the API key, when the job ends.

To export the `.p12`: in Keychain Access, find "Developer ID Application: …",
right-click → **Export…**, choose `.p12` and set a password. Delete the
exported `.p12` and the `.p8` from disk once they're stored as secrets, and
never commit them.

### Building a notarized DMG locally

```sh
export SIGN_IDENTITY="Developer ID Application: Name (TEAMID)"
export APPLE_API_KEY=/path/to/AuthKey_XXXXXXXXXX.p8
export APPLE_API_KEY_ID=XXXXXXXXXX
export APPLE_API_ISSUER=00000000-0000-0000-0000-000000000000
scripts/package-release.sh   # → build/Glance.dmg and build/Glance.zip
```

## Fixing a release

- **Workflow failed:** fix the cause and re-run the failed job from the
  Actions tab. If the fix needs a code change, release a patch version instead
  of moving the tag. A re-run replaces the DMG and ZIP on an existing release.
- **Notes wrong:** edit them on GitHub (`gh release edit vX.Y.Z --notes-file …`)
  and fix `CHANGELOG.md` to match.
- **Bug found after release:** don't move or reuse a published tag. Fix it on
  `main` and release a patch version.
