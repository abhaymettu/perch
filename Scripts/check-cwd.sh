#!/bin/bash
# Compares the working directory Perch reads from the kernel (proc_pidinfo)
# with what lsof reports, for up to 40 live `claude` processes.
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
swiftc -O "$DIR/cwd.swift" -o "$TMP/cwd"
PIDS=$(pgrep -x claude | head -40)
[ -n "$PIDS" ] || { echo "no claude processes running"; exit 1; }
"$TMP/cwd" $PIDS > "$TMP/kernel.txt"
for p in $PIDS; do echo "$p $(lsof -d cwd -a -p "$p" -Fn 2>/dev/null | sed -n 's/^n//p')"; done > "$TMP/lsof.txt"
total=$(wc -l < "$TMP/kernel.txt" | tr -d ' ')
same=$(paste -d'|' "$TMP/kernel.txt" "$TMP/lsof.txt" | awk -F'|' '$1 == $2' | wc -l | tr -d ' ')
lsof_blank=$(awk 'NF == 1' "$TMP/lsof.txt" | wc -l | tr -d ' ')
echo "$same of $total match; lsof returned nothing for $lsof_blank"
paste -d'|' "$TMP/kernel.txt" "$TMP/lsof.txt" | awk -F'|' '$1 != $2 && split($2, a, " ") > 1 { print "DISAGREE: " $0; bad = 1 } END { exit bad }'
