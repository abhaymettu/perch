#!/bin/bash
#
# test-targets.sh: the message-target command line end to end, against stand-in
# commands in a scratch folder. Builds a Debug Perch under a test bundle id, so
# the installed app's defaults and targets.json are never touched.
#
# Usage: Scripts/test-targets.sh [path/to/Perch.app]
#

set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ID="com.abhaymettu.perch.targets-test"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"; defaults delete "$TEST_ID" >/dev/null 2>&1' EXIT

APP="${1:-}"
if [ -z "$APP" ]; then
    xcodebuild -project "$ROOT/Perch.xcodeproj" -scheme Perch -configuration Debug \
        -derivedDataPath "$WORK/dd" PRODUCT_BUNDLE_IDENTIFIER="$TEST_ID" build > "$WORK/build.log" 2>&1 \
        || { tail -20 "$WORK/build.log"; exit 1; }
    APP="$WORK/dd/Build/Products/Debug/Perch.app"
fi
PERCH="$APP/Contents/MacOS/Perch"
export PERCH_TARGETS_FILE="$WORK/targets.json"

fails=0
check() { # name, expected, actual
    if [ "$2" == "$3" ]; then echo "ok   $1"; else echo "FAIL $1: expected [$2], got [$3]"; fails=$((fails + 1)); fi
}

# No file: a setup problem, exit 2, and the app would start normally.
"$PERCH" targets >/dev/null 2>"$WORK/err"; check "missing file exits 2" 2 $?
grep -q "No targets.json" "$WORK/err"; check "missing file says so" 0 $?

cat > "$PERCH_TARGETS_FILE" <<EOF
{"targets": [
  {"name": "Sink", "command": ["/bin/sh", "-c", "cat > \"\$1\"; echo \$PERCH_TARGET > \"\$1.name\"", "sh", "$WORK/sink.txt"]},
  {"name": "Down", "command": ["/bin/sh", "-c", "cat >/dev/null; echo thread gone >&2; exit 4"]}
]}
EOF

check "first target chosen by default" "Sink" "$("$PERCH" target)"
check "list marks the chosen one" "* Sink|  Down" "$("$PERCH" targets | paste -sd'|' -)"

printf 'line from stdin' | "$PERCH" send >"$WORK/out"; check "send exits 0" 0 $?
check "send says where" "Sent to Sink" "$(cat "$WORK/out")"
check "command got the text" "line from stdin" "$(cat "$WORK/sink.txt")"
check "command knows its target" "Sink" "$(cat "$WORK/sink.txt.name")"

"$PERCH" send words as arguments >/dev/null; check "send from arguments" "words as arguments" "$(cat "$WORK/sink.txt")"

check "target can be set, any case" "Down" "$("$PERCH" target down)"
check "and reads back" "Down" "$("$PERCH" target)"
printf 'keep this' | "$PERCH" send >/dev/null 2>"$WORK/err"; check "failed send exits 1" 1 $?
grep -q "Not sent to Down: thread gone. Kept in" "$WORK/err"; check "failure gives the reason" 0 $?
check "unsent text kept" "keep this" "$(cat "$WORK"/unsent/*.txt 2>/dev/null)"

printf 'one off' | "$PERCH" send --to sink >/dev/null; check "--to overrides the choice" "one off" "$(cat "$WORK/sink.txt")"
check "--to leaves the choice alone" "Down" "$("$PERCH" target)"

printf '   ' | "$PERCH" send >/dev/null 2>&1; check "empty message exits 2" 2 $?
"$PERCH" target Nowhere >/dev/null 2>&1; check "unknown target exits 2" 2 $?

echo '{"targets": [{"name": "A", "command": []}]}' > "$PERCH_TARGETS_FILE"
"$PERCH" targets >/dev/null 2>"$WORK/err"; check "bad file exits 2" 2 $?
grep -q "A has no command" "$WORK/err"; check "bad file says why" 0 $?

[ "$fails" -eq 0 ] && echo "all passed" || { echo "$fails failed"; exit 1; }
