#!/usr/bin/env bash
# Builds Glance.app into ./build. Pass --install to copy it to /Applications.
#
# Signing: macOS ties Accessibility / Screen Recording grants to the code signature.
# With a stable identity (e.g. "Apple Development: …") grants survive rebuilds;
# ad-hoc signing (the fallback) means re-granting after each rebuild.
# Override with: GLANCE_SIGN_IDENTITY="Apple Development: Name (TEAMID)" scripts/build-app.sh
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Glance"

APP=build/Glance.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Glance"
cp Resources/Info.plist "$APP/Contents/Info.plist"

IDENTITY="${GLANCE_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' | head -1)}"
codesign --force --options runtime --sign "${IDENTITY:--}" "$APP"
echo "Signed with: ${IDENTITY:-ad-hoc}"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Glance 2>/dev/null || true
  rm -rf /Applications/Glance.app
  cp -R "$APP" /Applications/
  open /Applications/Glance.app
  echo "Installed to /Applications/Glance.app"
else
  echo "Built $APP"
fi
