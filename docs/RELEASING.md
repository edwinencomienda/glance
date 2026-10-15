# Releasing

Every release is a git tag plus a GitHub release with notes and a
**Developer ID–signed, notarized** `Glance.dmg` (and `Glance.zip`). Pushing the
tag starts the [release workflow](../.github/workflows/release.yml), which
builds, signs, notarizes and publishes everything. People can still build from
source with `scripts/build-app.sh`.

## Quick checklist

1. `CHANGELOG.md`: `[Unreleased]` → `[X.Y.Z] - YYYY-MM-DD`, update the links.
2. `Resources/Info.plist`: version `X.Y.Z`, build number + 1.
3. `scripts/build-app.sh --install` and the [manual checklist](DEVELOPMENT.md#testing).
4. Commit `Release X.Y.Z` and push to `main`.
5. `scripts/release.sh` (dry run), then `scripts/release.sh --publish`.
6. Watch the workflow in the Actions tab, then install from the release's DMG.

Details for each step follow.

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
     [1.1.0]: https://github.com/edwinencomienda/glance/compare/v1.0.3...v1.1.0
     ```
     The new version's link compares against the previous release's tag.
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
   it opens without a Gatekeeper warning. Replacing a local
   `scripts/build-app.sh` build with the release changes the code signature,
   so macOS asks for Accessibility and Screen Recording again.

Publishing makes the update visible to everyone straight away: installed copies
(1.1.0 and later) check GitHub's latest release and show **Glance X.Y.Z
Available…**. The checker only sees published, non-draft, non-prerelease
releases whose tag is exactly `vX.Y.Z`, which is what `scripts/release.sh`
and the workflow produce. Don't edit a release into a draft or prerelease, or
rename its tag, once it's out.

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
right-click → **Export…**, choose `.p12` and set a password. Before uploading,
check the file and password match. This should print the "Developer ID
Application" subject (`-legacy` is needed because Keychain Access exports with
RC2 encryption, which OpenSSL 3 rejects otherwise):

```sh
openssl pkcs12 -in cert.p12 -nokeys -legacy | grep subject
base64 -i cert.p12 | gh secret set CERTIFICATE_BASE64
gh secret set CERTIFICATE_PASSWORD   # prompts for the password
```

Always update `CERTIFICATE_BASE64` and `CERTIFICATE_PASSWORD` together. If the
workflow fails at "Import signing certificate" with *The user name or
passphrase you entered is not correct*, they're from different exports.
Delete the exported `.p12` and the `.p8` from disk once they're stored as
secrets, and never commit them.

### Building a notarized DMG locally

Copy `.env.example` to `.env.prod` (gitignored) and fill in the API key's
path, ID and issuer, quoting values with spaces. `SIGN_IDENTITY` is optional:
it defaults to the first "Developer ID Application" identity in your keychain.
Then:

```sh
scripts/package-release.sh --check   # confirms the identity and credentials
scripts/package-release.sh           # → build/Glance.dmg and build/Glance.zip
```

This notarizes but publishes nothing.

### Renewing credentials

- **Developer ID certificate** (valid for 5 years): when it's renewed, export
  the new one as `.p12` and update both certificate secrets as above. Apps
  already released stay valid, because they were notarized with a timestamp.
- **App Store Connect API key:** if it's revoked or replaced, update
  `APPLE_API_KEY_BASE64`, `APPLE_API_KEY_ID` and `APPLE_API_ISSUER`, and
  `.env.prod` if you build locally.

`scripts/release.sh` only checks that the secrets exist, not that they work.
To test new credentials without releasing, run the workflow by hand from the
Actions tab.

## Fixing a release

- **Workflow failed:** fix the cause and re-run the failed job from the
  Actions tab. If the fix needs a code change, release a patch version instead
  of moving the tag. A re-run replaces the DMG and ZIP on an existing release.
- **Notes wrong:** edit them on GitHub (`gh release edit vX.Y.Z --notes-file …`)
  and fix `CHANGELOG.md` to match.
- **Bug found after release:** don't move or reuse a published tag. Fix it on
  `main` and release a patch version.
