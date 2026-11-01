#!/bin/bash
#
# release.sh: build Perch for a GitHub release.
#
#   Release build -> ad-hoc signature -> Perch-<version>.zip and Perch-<version>.dmg
#   in build/release, with their SHA-256 sums for the Homebrew cask.
#
# Perch has no Developer ID certificate yet, so the app is ad-hoc signed and
# not notarized. Gatekeeper blocks it on first open until the quarantine flag
# is cleared; the Homebrew cask does that on install.
#
# Usage: Scripts/release.sh 1.3
#

set -euo pipefail

VERSION="${1:?usage: Scripts/release.sh <version>}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/release"
ARCHIVE="$OUT/Perch.xcarchive"
APP="$OUT/Perch.app"

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ROOT"

echo "==> Archiving $VERSION"
xcodebuild -project Perch.xcodeproj -scheme Perch -configuration Release \
    -archivePath "$ARCHIVE" -destination "generic/platform=macOS" \
    MARKETING_VERSION="$VERSION" ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
    archive > "$OUT/xcodebuild.log" 2>&1 || { tail -30 "$OUT/xcodebuild.log"; exit 1; }
cp -R "$ARCHIVE/Products/Applications/Perch.app" "$APP"

echo "==> Ad-hoc signing"
codesign --force --deep --options runtime --sign - "$APP"
codesign --verify --deep --strict "$APP"
lipo -archs "$APP/Contents/MacOS/Perch"

echo "==> Zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUT/Perch-$VERSION.zip"

echo "==> DMG"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname "Perch $VERSION" -srcfolder "$STAGE" -ov -format UDZO "$OUT/Perch-$VERSION.dmg"
rm -rf "$STAGE"

cd "$OUT"
shasum -a 256 "Perch-$VERSION.zip" "Perch-$VERSION.dmg" | tee SHA256SUMS
