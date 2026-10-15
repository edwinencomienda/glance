#!/usr/bin/env bash
# Builds a Developer ID–signed, notarized Glance.app and packages it as
# build/Glance.dmg and build/Glance.zip, ready to attach to a GitHub release.
# The release workflow (.github/workflows/release.yml) runs this on every tag;
# run it locally to build a notarized DMG without releasing.
#
# Credentials come from the environment or from .env.prod (gitignored; see
# .env.example):
#   SIGN_IDENTITY     "Developer ID Application: Name (TEAMID)". Optional: the
#                     first Developer ID Application identity in the keychain.
#   APPLE_API_KEY     path to the App Store Connect API key (.p8)
#   APPLE_API_KEY_ID  the key's 10-character ID
#   APPLE_API_ISSUER  the issuer UUID
#
# Usage: scripts/package-release.sh          (build, sign, notarize, package)
#        scripts/package-release.sh --check  (only check the credentials)
# See docs/RELEASING.md.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "✗ $*" >&2; exit 1; }

if [[ -f .env.prod ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env.prod
  set +a
fi

SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Developer ID Application:.*\)"/\1/p' | head -1)}"
[[ "$SIGN_IDENTITY" == "Developer ID Application:"* ]] \
  || fail "No Developer ID Application identity (set SIGN_IDENTITY or install the certificate)"
for var in APPLE_API_KEY APPLE_API_KEY_ID APPLE_API_ISSUER; do
  [[ -n "${!var:-}" ]] || fail "$var isn't set (see .env.example)"
done
[[ -f "$APPLE_API_KEY" ]] || fail "APPLE_API_KEY doesn't point to a file"

if [[ "${1:-}" == "--check" ]]; then
  echo "✓ Signing as $SIGN_IDENTITY; notarization credentials set"
  exit 0
fi

APP=build/Glance.app
DMG=build/Glance.dmg
ZIP=build/Glance.zip
notarize() {
  xcrun notarytool submit "$1" --wait \
    --key "$APPLE_API_KEY" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER"
}

echo "==> Building"
GLANCE_SIGN_IDENTITY="$SIGN_IDENTITY" scripts/build-app.sh

echo "==> Signing with $SIGN_IDENTITY"
# Re-sign with a secure timestamp, which notarization requires.
codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Notarizing the app"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
notarize "$ZIP"
xcrun stapler staple "$APP"
# Re-zip so the download carries the stapled ticket.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Creating the DMG"
STAGING=build/dmg-staging
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
ditto --noextattr --noqtn "$APP" "$STAGING/Glance.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname Glance -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

echo "==> Notarizing the DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"
spctl --assess --type open --context context:primary-signature --verbose "$DMG"

echo "✓ Built $DMG and $ZIP"
