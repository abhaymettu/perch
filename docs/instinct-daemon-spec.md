# instinct-daemon spec (lightweight, 2026-09-12)

Implements `docs/transport-decision.md`. Supersedes `Scripts/cmd-server.py` for device
verbs; cmd-server keeps running on 8788 until the runner cuts over.

## Shape

- One Lua module, `Scripts/instinct-daemon.lua`, symlinked to
  `~/.hammerspoon/instinct-daemon.lua`. Loaded from his `init.lua` by one appended line.
  Runs inside Hammerspoon.app, so the TCC identity is Hammerspoon (never sshd/tmux).
- `hs.httpserver`, interface `localhost`, port 8399, no Bonjour, no TLS (the funnel
  terminates TLS). Exposes a global `instinct` table with `stop()`, `reloadTokens()`,
  `status()` for `hs -c` control.
- Tokens: `~/.perch-bridge/device.token` (device verbs, batch, websocket) and
  `~/.perch-bridge/shell.token` (the `run` verb only). Hammerspoon cannot trap SIGHUP, so
  "re-read on SIGHUP" becomes: `hs.pathwatcher` on `~/.perch-bridge/` that reacts only to
  `*.token` writes (never logs, F4), plus `hs -c 'instinct.reloadTokens()'`.
- Auth: constant-time compare (fixed-length XOR fold). Any failure returns 404 with an
  empty body. Global limiter: 10 failures in a rolling 60 s window, then every request gets
  404 for 60 s. Per-source is meaningless behind the funnel (source is always loopback).

## Endpoints

- `GET /v1/health` (bearer) -> `{ok, version, uptime_s, ax_trusted, ws_client, queue_dir,
  ring_size, orch_queue_len}`.
- `POST /v1/batch` (bearer, `X-Shell-Token` header optional) body = JSON array of ops,
  reply = JSON array of results in the same order. Device ops run synchronously in order;
  orch ops in a batch return `{"ok":false,"error":"orch ops need the websocket"}`.
- WS `/v1/ctl`. First frame must be
  `{"hello":"<session-id>","since":"<last-ack-id or null>","token":"<device token>",
  "shell_token":"<optional>"}`. Reply `{"hello":true,"acks":[...ids executed from queue or ring since]}`.
  Anything else before hello, or a bad token -> the reply is `{"error":"unauthorized"}`
  and the frame counts as an auth failure (hs.httpserver cannot close a websocket from the
  server side; the daemon ignores that client until a valid hello arrives).
  `{"ping":n}` -> `{"pong":n}`. All other frames are ops.

## Op DSL

```
{"id":"uuid","action":"brightness.set","value":0.5}
```

`verb`+`args` (transport doc) is accepted and normalised to `action` + flat fields.
`lane` is optional; `run` and `say` are orch, everything else device. `id` is the
idempotency key: a duplicate id within the 1000-entry ring returns the cached result with
`"dedupe":true`. Missing id -> explicit error.

Result: `{"id","action","ok","ms","result","readback","error","tier"}`. `error` is a
string whenever `ok` is false. Silent no-ops are forbidden: if execute succeeded but
readback does not show the requested state, `ok=false`, `error="readback mismatch"`,
with both values reported.

## Verbs (device lane)

| action | params | execute | readback |
|---|---|---|---|
| brightness.set | value 0..1 (or 0..100) | hs.brightness.set | hs.brightness.get, tolerance 1% |
| brightness.get | | | hs.brightness.get |
| volume.set | value 0..1 (or 0..100) | default output setVolume | volume(), tolerance 1 |
| volume.get | | | volume, muted, device name |
| mute.set | value bool | setMuted | muted() |
| app.raise | app | launchOrFocus, poll <=1.5 s | frontmost app name |
| app.hide | app | hs.application:hide | isHidden |
| app.frontmost | | | frontmost app name, bundle |
| window.move | app, x, y, w, h | frontmost window setFrame | frame after |
| window.fullscreen | app, value bool | setFullScreen | isFullScreen |
| window.minimize | app | minimize | isMinimized |
| click | x, y (screen pts) | 3-tier | element description after, mouse pos |
| key.press | key, mods[] | hs.eventtap.keyStroke | frontmost app |
| type.text | text | hs.eventtap.keyStrokes | length typed, frontmost |
| url.open | url, app? | hs.urlevent.openURL or open -a | frontmost app |
| display | text, secs | hs.alert.show | true |
| screenshot | x,y,w,h? | hs.screen:snapshot -> PNG base64 | byte length |

Click tiers: (1) `hs.axuielement.systemElementAtPosition` then `performAction("AXPress")`;
(2) walk ancestors for the nearest element listing `AXPress` or `AXClick` in
`actionNames()` and perform it; (3) `hs.eventtap.leftClick`. Browser bypass: if the
frontmost bundle is in `{com.google.Chrome, com.apple.Safari, company.thebrowser.Browser,
org.mozilla.firefox, com.brave.Browser, com.microsoft.edgemac}` go straight to tier 3.
Result reports `tier`. If AX is not trusted, click/key/type return
`error="accessibility not trusted"` up front.

## Orch lane

- `run` {cmd}: requires shell token. `hs.task` `/bin/zsh -lc`, 55 s cap, FIFO one at a
  time, output tails (4000/1500). Result frame sent when done via `server:send`.
- `say` {text}: `hs.task python3 ~/code/local-workers/interp.py <text> --dry`, parse the
  plan, map to daemon actions where a mapping exists (open-app -> app.raise, volume ->
  volume.set/mute.set, fullscreen-app -> window.fullscreen, url/web-search -> url.open,
  display -> display, frontmost -> app.frontmost, press-key -> key.press, type-text ->
  type.text, tile-pair -> two window.move), execute with readback; otherwise run
  `interp.py <text>` (non-dry) and return its result with `via:"interp"`.
- `classify` {text, mode?}: mode is `hybrid` (default), `llm`, or `rules`. `hs.task
  python3 Scripts/fastlane/classify.py --json --mode <mode> <text>`, 20 s cap. stdout
  decoded as JSON; exit non-zero or undecodable -> `ok=false`. Otherwise `ok` mirrors
  the classifier's own `ok`, `result` is the full parsed object, and `readback` is
  `{intent, fallback, tier}`.

## Queue and wake

- Queue dir: `<vault>/05-Bridge/exec/device-queue/`, files `<ISO>-<id>.json` each one op or
  array of ops; `done/` sibling. The existing `exec/queue/` (markdown argv jobs for execd)
  is a different contract and is not touched.
- Poll every 5 s while no websocket hello is live, and on every hello (before answering
  it) and on `hs.caffeinate.watcher` systemDidWake after `tailscale status --json`
  reports Running (poll 1 s, 30 s cap). During a drain incoming frames are buffered in
  memory and answered after the drain, in order. No filesystem watcher.
- Ring: last 1000 ids with results, persisted to `~/.perch-bridge/instinct-ring.json`
  after each drain and every 60 s if dirty.

## Install

- `Scripts/install-daemon.sh`: backup init.lua to `init.lua.bak-<date>`, symlink module,
  create tokens (600) if missing, append the require line if absent, load the module live
  via `hs -c` (no hs.reload, so his eventtap is untouched), bootstrap the LaunchAgent.
- `Scripts/com.instinct.daemon.plist`: gui domain, RunAtLoad + StartInterval 60, runs
  `Scripts/instinct-daemon-preflight.sh`: ensure Hammerspoon.app is running (open -a),
  check `hs.accessibilityState()`, curl health, log to `~/.perch-bridge/instinct-preflight.log`.
- Staged kill (in the module header and install script):
  `hs -c 'instinct.stop()'`, comment the require line, `launchctl bootout gui/$(id -u)/com.instinct.daemon`.
