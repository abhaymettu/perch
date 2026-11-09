#!/bin/bash
# Film the owl. Builds Scripts/OwlClips against the app's own owl sources,
# renders every scene in the catalogue frame by frame, and writes into <out>:
#
#   <scene>.mp4   60 fps: the owl enlarged on a dark and a light bar, and
#                 underneath at the menu bar's own pixels
#   <scene>.png   contact sheet, every second frame, dark bar
#   frames/       the raw PNG sequences, 2 and 16 pixels a point
#
# Nothing here runs the app or touches the menu bar: the frames come from the
# same performer and renderer the status item uses. Needs ffmpeg.
#
# Usage: Scripts/owl-clips.sh <out-dir> [scene name ...]
set -euo pipefail

OUT="${1:?usage: Scripts/owl-clips.sh <out-dir> [scene ...]}"; shift || true
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OWL="$ROOT/Perch/Views/Owl"
DARK=0x1B1B1F; LIGHT=0xE9E9EC

mkdir -p "$OUT"
swiftc -O -D DEBUG -o "$OUT/owlclips" \
  "$OWL"/{OwlPose,OwlSpring,OwlAction,OwlRepertoire,OwlGeometry,MenuBarIcon}.swift "$ROOT/Scripts/OwlClips/main.swift"
"$OUT/owlclips" "$OUT/frames" 60 "$@"

for dir in "$OUT"/frames/*/; do
  slug="$(basename "$dir")"
  # Top: 16 px a point on each bar. Bottom: the real 2 px a point, centred under it.
  ffmpeg -loglevel error -y \
    -f lavfi -i "color=c=$DARK:s=480x412:r=60" -f lavfi -i "color=c=$LIGHT:s=480x412:r=60" \
    -framerate 60 -i "$dir/dark-big/%04d.png" -framerate 60 -i "$dir/light-big/%04d.png" \
    -framerate 60 -i "$dir/dark-real/%04d.png" -framerate 60 -i "$dir/light-real/%04d.png" \
    -filter_complex "[0][2]overlay=0:0:shortest=1[d];[d][4]overlay=210:360[dark];\
[1][3]overlay=0:0:shortest=1[l];[l][5]overlay=210:360[light];[dark][light]hstack" \
    -c:v libx264 -crf 12 -pix_fmt yuv420p -movflags +faststart "$OUT/$slug.mp4"

  frames=$(find "$dir/dark-big" -name '*.png' | wc -l | tr -d ' ')
  rows=$(( (frames / 2 + 12) / 12 ))
  ffmpeg -loglevel error -y -f lavfi -i "color=c=$DARK:s=120x88:r=60" -framerate 60 -i "$dir/dark-big/%04d.png" \
    -filter_complex "[1]scale=120:88:flags=area[f];[0][f]overlay=shortest=1,select='not(mod(n\,2))',tile=12x$rows:color=$DARK:padding=2" \
    -frames:v 1 "$OUT/$slug.png"
done
echo "$OUT"
