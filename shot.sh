#!/bin/bash
# Build, render every preview scenario in one window, write it to a PNG, quit.
# Usage: ./shot.sh <output.png> [main|pages|welcome]
set -e

OUT="${1:-/tmp/perch-preview.png}"
SET="${2:-main}"
ROOT="$(cd "$(dirname "$0")" && pwd)"

xcodebuild -project "$ROOT/Perch.xcodeproj" -scheme Perch -configuration Debug build \
  2>&1 | grep -E "error:|BUILD" || true

APP=$(xcodebuild -project "$ROOT/Perch.xcodeproj" -scheme Perch -configuration Debug \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')

pkill -f "Perch.app/Contents/MacOS/Perch" 2>/dev/null || true

rm -f "$OUT"
PERCH_UI_PREVIEW="$SET" PERCH_UI_SHOT="$OUT" "$APP/Perch.app/Contents/MacOS/Perch" >/dev/null 2>&1

[ -s "$OUT" ] || { echo "no png at $OUT" >&2; exit 1; }
echo "$OUT"
