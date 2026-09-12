#!/bin/zsh
# install-daemon.sh - idempotent installer for the instinct device daemon.
# Run by hand. See docs/instinct-daemon-spec.md ("Install") for the contract.
#
#   ./install-daemon.sh            install / update in place
#   ./install-daemon.sh --dry-run  print what it would do, change nothing
#   ./install-daemon.sh --uninstall  staged kill + remove symlink and plist (backup stays)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${0:A}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

HS_DIR=~/.hammerspoon
INIT_LUA="$HS_DIR/init.lua"
MODULE_SRC="$REPO/Scripts/instinct-daemon.lua"
MODULE_LINK="$HS_DIR/instinct-daemon.lua"
BRIDGE_DIR=~/.perch-bridge
DEVICE_TOKEN="$BRIDGE_DIR/device.token"
SHELL_TOKEN="$BRIDGE_DIR/shell.token"
PLIST_SRC="$REPO/Scripts/com.instinct.daemon.plist"
PLIST_DST=~/Library/LaunchAgents/com.instinct.daemon.plist
LABEL="com.instinct.daemon"
REQUIRE_LINE='local ok, err = pcall(require, "instinct-daemon"); if not ok then print("instinct-daemon failed: " .. tostring(err)) end'

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

DRY_RUN=0
UNINSTALL=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    --uninstall) UNINSTALL=1 ;;
    *) echo "unknown flag: $arg" >&2; exit 1 ;;
  esac
done

run() {
  if [ "$DRY_RUN" -eq 1 ]; then
    print -r -- "[dry-run] $*"
  else
    "$@"
  fi
}

# manual timeout (no `timeout` binary on this Mac): see instinct-daemon-preflight.sh.
with_timeout() {
  local secs=$1; shift
  "$@" &
  local pid=$!
  ( sleep "$secs"; kill "$pid" 2>/dev/null ) &
  local watcher=$!
  wait "$pid"
  local rc=$?
  kill "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  return "$rc"
}

print_kill_block() {
  cat <<'EOF'

Staged kill (run these by hand, in order, to back this out):
  hs -c 'instinct.stop()'
  sed -i '' 's/^local ok, err = pcall(require, "instinct-daemon")/-- &/' ~/.hammerspoon/init.lua
  launchctl bootout gui/$(id -u)/com.instinct.daemon
EOF
}

do_uninstall() {
  echo "-- uninstall: staged kill --"
  HS_BIN="$(command -v hs || true)"
  if [ -n "$HS_BIN" ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      print -r -- "[dry-run] $HS_BIN -c 'instinct.stop()'"
    else
      with_timeout 8 "$HS_BIN" -c 'instinct.stop()' || true
    fi
  else
    echo "hs binary not found on PATH, skipping instinct.stop()"
  fi

  if [ -f "$INIT_LUA" ]; then
    run sed -i '' 's/^local ok, err = pcall(require, "instinct-daemon")/-- &/' "$INIT_LUA"
  fi

  run launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true

  if [ -L "$MODULE_LINK" ] || [ -e "$MODULE_LINK" ]; then
    run rm -f "$MODULE_LINK"
  fi
  if [ -f "$PLIST_DST" ]; then
    run rm -f "$PLIST_DST"
  fi

  echo "-- uninstall done (init.lua.bak-* backups and tokens left in place) --"
}

if [ "$UNINSTALL" -eq 1 ]; then
  do_uninstall
  exit 0
fi

echo "-- install-daemon.sh ($([ "$DRY_RUN" -eq 1 ] && echo dry-run || echo live)) --"

# a. tokens
run mkdir -p "$BRIDGE_DIR"
if [ ! -f "$DEVICE_TOKEN" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    print -r -- "[dry-run] openssl rand -hex 32 > $DEVICE_TOKEN; chmod 600 $DEVICE_TOKEN"
  else
    openssl rand -hex 32 >"$DEVICE_TOKEN"
    chmod 600 "$DEVICE_TOKEN"
  fi
else
  echo "device.token already exists, leaving it"
fi
if [ ! -f "$SHELL_TOKEN" ]; then
  if [ "$DRY_RUN" -eq 1 ]; then
    print -r -- "[dry-run] openssl rand -hex 32 > $SHELL_TOKEN; chmod 600 $SHELL_TOKEN"
  else
    openssl rand -hex 32 >"$SHELL_TOKEN"
    chmod 600 "$SHELL_TOKEN"
  fi
else
  echo "shell.token already exists, leaving it"
fi

# b. symlink the module
run mkdir -p "$HS_DIR"
run ln -sfn "$MODULE_SRC" "$MODULE_LINK"

# c. backup init.lua, append require line if absent
if [ -f "$INIT_LUA" ]; then
  BACKUP="$INIT_LUA.bak-$(date +%Y%m%d-%H%M%S)"
  run cp "$INIT_LUA" "$BACKUP"
else
  echo "no init.lua found at $INIT_LUA, will create one"
  BACKUP=""
fi

if [ -f "$INIT_LUA" ] && grep -q 'require("instinct-daemon")' "$INIT_LUA"; then
  echo "init.lua already requires instinct-daemon, leaving it"
else
  if [ "$DRY_RUN" -eq 1 ]; then
    print -r -- "[dry-run] append require line to $INIT_LUA"
  else
    {
      echo ""
      echo '-- instinct device daemon (added 2026-09-12, staged kill: comment this line, then hs -c '\''instinct.stop()'\'')'
      echo "$REQUIRE_LINE"
    } >>"$INIT_LUA"
  fi
fi

# d. load live without hs.reload
HS_BIN="$(command -v hs || true)"
if [ -z "$HS_BIN" ]; then
  echo "hs binary not found on PATH, skipping live load and health check"
else
  if [ "$DRY_RUN" -eq 1 ]; then
    print -r -- "[dry-run] $HS_BIN -c 'package.loaded[\"instinct-daemon\"]=nil; if instinct then pcall(instinct.stop) end; require(\"instinct-daemon\")'"
    print -r -- "[dry-run] curl -s -m 3 -H \"Authorization: Bearer \$(cat $DEVICE_TOKEN)\" http://127.0.0.1:8399/v1/health"
  else
    with_timeout 8 "$HS_BIN" -c 'package.loaded["instinct-daemon"]=nil; if instinct then pcall(instinct.stop) end; require("instinct-daemon")' || true
    if [ -f "$DEVICE_TOKEN" ]; then
      health="$(curl -s -m 3 -H "Authorization: Bearer $(cat "$DEVICE_TOKEN")" http://127.0.0.1:8399/v1/health || true)"
      echo "health: $health"
    fi
  fi
fi

# e. install + bootstrap the LaunchAgent
run mkdir -p ~/Library/LaunchAgents
run cp "$PLIST_SRC" "$PLIST_DST"
run launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
run launchctl bootstrap "gui/$(id -u)" "$PLIST_DST"
if [ "$DRY_RUN" -eq 1 ]; then
  print -r -- "[dry-run] launchctl print gui/\$(id -u)/$LABEL | head -5"
else
  launchctl print "gui/$(id -u)/$LABEL" | head -5 || true
fi

echo "-- install done --"
print_kill_block
