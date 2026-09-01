#!/bin/bash
#
# release.sh — Perch's ship pipeline:
#   Release build (Developer ID, hardened runtime) -> styled DMG ->
#   notarize + staple.
#
# Notary credentials are Apple-ID/team-level, not per-app, so this reuses
# the "Era" keychain profile by default. To use a separate one:
#   xcrun notarytool store-credentials "Perch" \
#     --apple-id <apple-id> --team-id SARBM2PYZ7
#   NOTARY_PROFILE=Perch ./Scripts/release.sh
#
# Usage: ./Scripts/release.sh
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$SCRIPT_DIR")"
BUILD="$ROOT/build"
ARCHIVE="$BUILD/Perch.xcarchive"
APP="$BUILD/Perch.app"
DMG="$BUILD/Perch.dmg"
PROFILE="${NOTARY_PROFILE:-Era}"

cd "$ROOT"
mkdir -p "$BUILD"
rm -rf "$ARCHIVE" "$APP" "$DMG"

echo "==> Archiving (Release)"
xcodebuild -project Perch.xcodeproj -scheme Perch -configuration Release \
    -archivePath "$ARCHIVE" archive | grep -E "error|warning: code sign|ARCHIVE" || true
[ -d "$ARCHIVE/Products/Applications/Perch.app" ] || { echo "archive failed"; exit 1; }
cp -R "$ARCHIVE/Products/Applications/Perch.app" "$APP"

echo "==> Verifying signature"
# The project signs with Developer ID and hardened runtime; Perch has no
# nested frameworks, so there is nothing to re-sign — only to check.
codesign --verify --deep --strict "$APP"
SIGINFO=$(codesign -dvv "$APP" 2>&1)
case "$SIGINFO" in
    *"Authority=Developer ID Application"*) ;;
    *) echo "NOT Developer ID signed"; exit 1 ;;
esac
case "$SIGINFO" in
    *"flags=0x10000(runtime)"*) ;;
    *) echo "hardened runtime missing — notarization will fail"; exit 1 ;;
esac

echo "==> Building DMG"
"$SCRIPT_DIR/build-dmg.sh" "$APP" > /dev/null
[ -f "$DMG" ] || { echo "dmg failed"; exit 1; }

echo "==> Notarizing (profile: $PROFILE)"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo "==> Gatekeeper check (the app inside; the DMG itself is not codesigned)"
spctl -a -t exec -vv "$APP" || true

VERSION=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString)
BUILDNUM=$(defaults read "$APP/Contents/Info" CFBundleVersion)

echo ""
echo "Shipped artifacts in build/:"
echo "  Perch.dmg — notarized + stapled, version $VERSION ($BUILDNUM)"
echo "  Attach it to the GitHub release for tag v$VERSION."
