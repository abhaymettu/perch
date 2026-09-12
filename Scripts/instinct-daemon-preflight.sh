#!/bin/zsh
# instinct-daemon-preflight.sh - runs every 60s from the gui launchd domain (via
# com.instinct.daemon.plist), so its TCC identity is the Aqua session, never sshd/tmux.
#
# Steps: make sure Hammerspoon.app is running, check AX trust (read-only, never opens
# System Settings), check the daemon's /v1/health, try one live (re)load if health is
# down, then trim the log. Always exits 0 so launchd never backs off the interval.
set -uo pipefail

export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

LOG=~/.perch-bridge/instinct-preflight.log
TOKEN_FILE=~/.perch-bridge/device.token
HS_BIN="$(command -v hs || true)"

mkdir -p ~/.perch-bridge

ts() { date '+%Y-%m-%dT%H:%M:%S%z'; }
log() { print -r -- "$(ts) $1 $2" >>"$LOG"; }

# manual timeout: this Mac has no `timeout` binary, so run the command in the
# background, kill it if it outlives the budget, and wait for it either way.
# usage: with_timeout <seconds> <cmd...>  -> prints cmd's stdout+stderr, exits its status
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

# --- a. Hammerspoon running? ---
if ! pgrep -x Hammerspoon >/dev/null 2>&1; then
  open -a Hammerspoon
  log "hammerspoon-launch" "started"
  waited=0
  while [ "$waited" -lt 10 ]; do
    pgrep -x Hammerspoon >/dev/null 2>&1 && break
    sleep 1
    waited=$((waited + 1))
  done
  if pgrep -x Hammerspoon >/dev/null 2>&1; then
    log "hammerspoon-wait" "running after ${waited}s"
  else
    log "hammerspoon-wait" "still not running after ${waited}s"
  fi
else
  log "hammerspoon-check" "already running"
fi

# --- b. AX preflight (read-only, no dialogs) ---
if [ -n "$HS_BIN" ]; then
  ax_out="$(with_timeout 8 "$HS_BIN" -c 'print(hs.accessibilityState())' 2>&1)"
  ax_status=$?
  if [ -z "$ax_out" ] && [ "$ax_status" -ne 0 ]; then
    log "ax-preflight" "timeout-or-no-response"
  elif print -r -- "$ax_out" | grep -qi 'true'; then
    log "ax-preflight" "trusted"
  else
    log "ax-preflight" "LOUD: untrusted (accessibility not granted to Hammerspoon) out=${ax_out}"
  fi
else
  log "ax-preflight" "hs binary not found on PATH"
fi

# --- c. daemon health ---
health_check() {
  if [ -r "$TOKEN_FILE" ]; then
    curl -s -m 3 -H "Authorization: Bearer $(cat "$TOKEN_FILE")" http://127.0.0.1:8399/v1/health 2>&1
  else
    echo ""
  fi
}

health_out="$(health_check)"
if [ -n "$health_out" ] && print -r -- "$health_out" | grep -q '"ok"[[:space:]]*:[[:space:]]*true'; then
  log "daemon-health" "ok"
else
  log "daemon-health" "down (out=${health_out:0:200})"
  if [ -n "$HS_BIN" ] && pgrep -x Hammerspoon >/dev/null 2>&1; then
    load_out="$(with_timeout 8 "$HS_BIN" -c 'if not instinct then require("instinct-daemon") end' 2>&1)"
    log "daemon-live-load" "attempted out=${load_out:0:200}"
    health_out2="$(health_check)"
    if [ -n "$health_out2" ] && print -r -- "$health_out2" | grep -q '"ok"[[:space:]]*:[[:space:]]*true'; then
      log "daemon-health-recheck" "ok"
    else
      log "daemon-health-recheck" "still down (out=${health_out2:0:200})"
    fi
  fi
fi

# --- d. trim log to under 2000 lines ---
if [ -f "$LOG" ]; then
  lines=$(wc -l <"$LOG" 2>/dev/null | tr -d ' ')
  if [ -n "$lines" ] && [ "$lines" -gt 2000 ]; then
    tmp="${LOG}.tmp.$$"
    tail -n 2000 "$LOG" >"$tmp" && mv "$tmp" "$LOG"
  fi
fi

exit 0
