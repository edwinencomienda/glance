#!/usr/bin/env bash
# Checks and tags a release. The version comes from Resources/Info.plist; the
# release notes come from that version's section in CHANGELOG.md. Pushing the
# tag starts .github/workflows/release.yml, which builds the signed, notarized
# DMG and publishes the GitHub release.
#
# Usage: scripts/release.sh            (dry run: checks only, changes nothing)
#        scripts/release.sh --publish  (tag and push the tag)
# See docs/RELEASING.md.
set -euo pipefail
cd "$(dirname "$0")/.."

PUBLISH=false
[[ "${1:-}" == "--publish" ]] && PUBLISH=true

fail() { echo "✗ $*" >&2; exit 1; }
ok() { echo "✓ $*"; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Resources/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Resources/Info.plist)
TAG="v$VERSION"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "Version '$VERSION' isn't X.Y.Z"
ok "Version $VERSION (build $BUILD), tag $TAG"

# Repository state
[[ "$(git rev-parse --abbrev-ref HEAD)" == "main" ]] || fail "Not on main"
[[ -z "$(git status --porcelain)" ]] || fail "Working tree has uncommitted changes"
git fetch -q origin main --tags
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || fail "main isn't in sync with origin/main (push or pull first)"
! git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "Tag $TAG already exists"
ok "On main, clean, in sync, $TAG is new"

# Release notes: the CHANGELOG section for this version, up to the next heading
NOTES=$(scripts/release-notes.sh "$VERSION")
[[ -n "$NOTES" ]] || fail "CHANGELOG.md has no '## [$VERSION]' section"
grep -q "^\[$VERSION\]: " CHANGELOG.md || fail "CHANGELOG.md is missing the [$VERSION] link reference"
ok "Release notes found in CHANGELOG.md"

# The release workflow needs these repository secrets to sign and notarize
SECRETS=$(gh secret list --json name --jq '.[].name') || fail "Couldn't list repository secrets (gh auth?)"
for s in CERTIFICATE_BASE64 CERTIFICATE_PASSWORD APPLE_API_KEY_BASE64 APPLE_API_KEY_ID APPLE_API_ISSUER; do
  grep -qx "$s" <<<"$SECRETS" || fail "Repository secret $s is missing (see docs/RELEASING.md)"
done
ok "Signing secrets present"

# Quality gates
swift test >/dev/null 2>&1 || fail "swift test failed (run it to see why)"
ok "Tests pass"
scripts/build-app.sh >/dev/null 2>&1 || fail "scripts/build-app.sh failed (run it to see why)"
ok "App builds"

if ! $PUBLISH; then
  echo
  echo "Dry run complete. Release notes for $TAG:"
  echo "----------------------------------------"
  echo "$NOTES"
  echo "----------------------------------------"
  echo "Run 'scripts/release.sh --publish' to tag and publish."
  exit 0
fi

git tag -a "$TAG" -m "Glance $VERSION"
git push -q origin "$TAG"
ok "Pushed tag $TAG"
echo "The release workflow is now building, notarizing and publishing $TAG:"
echo "  $(gh repo view --json url --jq .url)/actions/workflows/release.yml"
