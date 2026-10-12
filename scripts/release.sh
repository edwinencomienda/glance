#!/usr/bin/env bash
# Tags and publishes a source release on GitHub. The version comes from
# Resources/Info.plist; the release notes come from that version's section in
# CHANGELOG.md. No binaries are attached: Glance is built from source.
#
# Usage: scripts/release.sh            (dry run: checks only, changes nothing)
#        scripts/release.sh --publish  (tag, push the tag, create the release)
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
NOTES=$(awk -v v="$VERSION" '
  $0 ~ "^## \\[" v "\\]" { found = 1; next }
  found && /^## \[/ { exit }
  found && /^\[.*\]: / { exit }
  found { print }
' CHANGELOG.md | sed -e '/./,$!d')
[[ -n "$NOTES" ]] || fail "CHANGELOG.md has no '## [$VERSION]' section"
grep -q "^\[$VERSION\]: " CHANGELOG.md || fail "CHANGELOG.md is missing the [$VERSION] link reference"
ok "Release notes found in CHANGELOG.md"

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
gh release create "$TAG" --title "Glance $VERSION" --notes "$NOTES" --verify-tag
echo "Released: $(gh release view "$TAG" --json url --jq .url)"
