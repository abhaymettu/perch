#!/bin/bash
# Build, render every preview scenario in one window, screenshot it, quit.
# Usage: ./shot.sh <output.png> [main|pages]
set -e

OUT="${1:-/tmp/blink-preview.png}"
SET="${2:-1}"
ROOT="$(cd "$(dirname "$0")" && pwd)"

xcodebuild -project "$ROOT/Blink.xcodeproj" -scheme Blink -configuration Debug build \
  2>&1 | grep -E "error:|BUILD" || true

APP=$(xcodebuild -project "$ROOT/Blink.xcodeproj" -scheme Blink -configuration Debug \
  -showBuildSettings 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')
BIN="$APP/Blink.app/Contents/MacOS/Blink"

pkill -f "Blink.app/Contents/MacOS/Blink" 2>/dev/null || true
sleep 0.4

RECTFILE=$(mktemp)
BLINK_UI_PREVIEW="$SET" "$BIN" > "$RECTFILE" 2>/dev/null &
PID=$!

for _ in $(seq 1 40); do
  RECT=$(grep -m1 '^PREVIEW_RECT ' "$RECTFILE" 2>/dev/null | cut -d' ' -f2) || true
  [ -n "$RECT" ] && break
  sleep 0.25
done

if [ -z "$RECT" ]; then
  kill "$PID" 2>/dev/null || true
  echo "harness never printed a frame" >&2
  exit 1
fi

sleep 1.2   # let the material and the robot's first frame settle
screencapture -x -R"$RECT" "$OUT"
kill "$PID" 2>/dev/null || true
rm -f "$RECTFILE"
echo "$OUT"
