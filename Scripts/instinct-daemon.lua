--[[ instinct-daemon.lua — loopback control daemon for the cloud<->Mac bridge.

PURPOSE
  Implements docs/instinct-daemon-spec.md and docs/transport-decision.md. One
  Hammerspoon module: HTTP + WebSocket on 127.0.0.1:8399, bearer tokens, two lanes
  (synchronous device verbs, async orch verbs), a 1000-id dedupe ring, and a vault
  queue drained on wake. Runs inside Hammerspoon.app so the TCC identity is
  Hammerspoon, never sshd/tmux. Supersedes Scripts/cmd-server.py (8788) for device
  verbs; cmd-server is left alone until the runner cuts over.
  Orch verbs: run (shell token required), say (voice command via interp.py), classify
  (fast-lane intent classification, shells to Scripts/fastlane/classify.py so the Mac
  leg and the cloud leg run byte-identical classifier code).

LOAD / RELOAD / STOP  (never hs.reload — his eventtap and hotkeys must survive)
  install:  ln -sf ~/Desktop/Playground/perch/Scripts/instinct-daemon.lua ~/.hammerspoon/instinct-daemon.lua
  load:     hs -c 'package.loaded["instinct-daemon"]=nil; if instinct then pcall(instinct.stop) end; require("instinct-daemon"); print(hs.json.encode(instinct.status()))'
  reload:   same line (the module stops any previous instance of itself first)
  status:   hs -c 'print(hs.json.encode(instinct.status()))'
  tokens:   hs -c 'instinct.reloadTokens()'   (also automatic on *.token writes)
  drain:    hs -c 'print(instinct.drainQueue())'      -- drain the vault queue now
  wake:     hs -c 'instinct.wake()'                   -- run the wake sequence by hand
  stop:     hs -c 'instinct.stop()'

STAGED KILL (each step is independent and reversible)
  1. hs -c 'instinct.stop()'                             -- port closed, timers/watchers gone
  2. comment the require line in ~/.hammerspoon/init.lua -- survives a Hammerspoon restart
  3. launchctl bootout gui/$(id -u)/com.instinct.daemon  -- stops the preflight keeper
  4. tailscale funnel --https=<daemon-port> off          -- unexposes it from the internet

ENDPOINTS
  GET  /v1/health   Authorization: Bearer <device token>
  POST /v1/batch    same, plus optional X-Shell-Token; body = JSON array of ops
  WS   /v1/ctl      first frame {"hello":id,"since":id|null,"token":...,"shell_token":...}
  Anything else, any auth failure, and every request while rate-limited: 404, empty body.

DECISIONS MADE HERE (beyond the spec, or where the spec left a choice)
  D1  Scales. hs.brightness is 0..100 and hs.audiodevice volume is 0..100, so
      `value` is read as a fraction when <= 1 and as a percentage otherwise. 1 means
      100%: send 99 (or 0.99) for 99%. Tolerance is 1 point on the 0..100 scale.
  D2  Queue files may carry device ops only. A queue op with lane=orch (run/say) is
      refused with an explicit error and the file still moves to done/. The queue dir
      is inside the iCloud vault, so accepting `run` from it would make "can write the
      vault" equal "can run shell as him" — the shell token exists precisely to stop
      that. Orch stays websocket-only, which is also what the spec says for batch.
  D3  Websocket frames always get a JSON reply, never an empty frame. Orch ops get
      {"accepted":true,...} immediately (no `ok`, since nothing is confirmed yet) and
      the real result frame arrives later via server:send. Frames that arrive during a
      wake drain get {"buffered":true,...} and their result frames are pushed after the
      drain, in arrival order. Neither reply claims success.
  D4  A websocket session is "live" if it has said hello and sent any frame in the last
      40 s, two missed 20 s client pings (hs.httpserver gives no disconnect event).
      The 5 s queue poll only runs when no session is live, per the spec.
  D5  Unobservable verbs. key.press and url.open leave no state to read back, so their
      readback is the identity of the app that received them (frontmost after the act,
      plus the requested app when one was named), labelled `confirmed` so the caller is
      never told more than was checked. ok=false if there is no frontmost app, or if a
      named app did not come forward. type.text does better: when the focused element
      exposes an AXValue under 4 KB, the verb waits for the typed string to appear in
      that value and reports readback mismatch if it never does (measured 2026-09-12:
      hs.eventtap.keyStrokes lands ~0.3-1 s after it returns, so an immediate read finds
      an empty field and would have been a silent no-op). No verb returns ok=true off a
      bare return code.
  D6  Device ops are synchronous, so the app.raise / window.* / url.open settle polls
      block Hammerspoon's main loop (1.5 s, 2.5 s for the fullscreen animation, 0.8 s).
      Caps are small and the alternative — async device replies — would break "device
      frames are answered in arrival order".
  D7  window.move tolerance is 8 pt per edge. Apps quantise frames (terminals to a
      character cell, Safari to a minimum width), so an exact compare would report
      readback mismatch on a move that did the right thing. Both frames are always
      reported, so the caller can judge.
  D8  Ring entries whose encoded result exceeds 8 KB (screenshots) are stored with the
      payload replaced by {omitted=true,bytes=N}. A dedupe hit on a screenshot id
      therefore returns metadata, not the image; ask again with a fresh id for bytes.
  D9  `since` resolution: acks are the ids recorded after that id in the ring. If the
      id is unknown or null, acks are every queue-origin id still in the ring — exactly
      the ops the client wrote to the vault and never got a reply for.
  D10 Auth failures are counted per frame and per request, including a websocket frame
      that arrives before hello. hs.httpserver cannot close a websocket server-side, so
      an unauthorised client is simply answered {"error":"unauthorized"} forever until a
      valid hello arrives on that same socket.
  D11 The log lives in ~/.perch-bridge/, which is the directory the token pathwatcher
      watches. The watcher therefore ignores every path that does not end in .token
      (F4: a watcher must exclude its own outputs, or it loops).
  D13 Hammerspoon cannot watch its own UI while a device verb is running: the verb owns
      the main run loop, so the console's own text field does not repaint until the verb
      returns. type.text therefore skips the AXValue confirmation when the frontmost app
      is Hammerspoon and says so in `confirmed`. Measured 2026-09-12: the same
      keystrokes that read back empty inside the verb were present in the field 1 s
      after it returned.
  D12 window.fullscreen waits for AXFullScreen to equal the request and for the frame
      to stop moving, then reports both plus whether the frame spans the screen width.
      Measured on this Mac 2026-09-12: AXFullScreen flips the instant setFullScreen is
      called, long before the space animation ends, and an exit issued during that
      animation is silently dropped by macOS — the daemon then correctly returns
      ok=false with fullscreen=true, and a retry (new id) succeeds. Height is not
      asserted: the Hammerspoon console in fullscreen measures 1512x883 at y=99 on a
      1512x982 screen, so macOS letterboxes some windows and a full-coverage test
      would fail a fullscreen that did happen.
]]

local instinct = {}

-- stop a previous incarnation before rebuilding state, so a re-require is clean
if _G.instinct and _G.instinct ~= instinct and type(_G.instinct.stop) == "function" then
  pcall(_G.instinct.stop)
end

-- ===========================================================================
-- 1. constants
-- ===========================================================================

local VERSION   = "1.1.0"
local PORT      = 8399
local HOME      = os.getenv("HOME")
local BRIDGE    = HOME .. "/.perch-bridge"
local DEV_TOKEN_PATH   = BRIDGE .. "/device.token"
local SHELL_TOKEN_PATH = BRIDGE .. "/shell.token"
local LOG_PATH  = BRIDGE .. "/instinct-daemon.log"
local RING_PATH = BRIDGE .. "/instinct-ring.json"
local QUEUE_DIR = HOME .. "/Library/Mobile Documents/iCloud~md~obsidian/Documents/Brain/05-Bridge/exec/device-queue"
local DONE_DIR  = QUEUE_DIR .. "/done"

local INTERP    = HOME .. "/code/local-workers/interp.py"
local CLASSIFY  = HOME .. "/Desktop/Playground/perch/Scripts/fastlane/classify.py"
local TAILSCALE = "/usr/local/bin/tailscale"
local PYTHON    = "/usr/bin/python3"
local ZSH       = "/bin/zsh"
local OPEN      = "/usr/bin/open"

local RING_MAX     = 1000
local FAIL_MAX     = 10     -- failures inside FAIL_WINDOW trips the limiter
local FAIL_WINDOW  = 60
local SILENCE      = 60     -- seconds of 404-everything after tripping
local RESULT_CAP   = 8192   -- bytes of encoded result kept in the ring (D8)
local RUN_CAP      = 55     -- seconds, `run`
local SAY_CAP      = 40     -- seconds, `say` (two interp.py calls worst case)
local CLASSIFY_CAP = 20     -- seconds, `classify`
local WS_IDLE      = 40     -- seconds without a frame before a session is not live (D4: two missed 20 s pings)
local WAKE_POLL    = 30     -- tailscale BackendState polls, 1 s apart
local QUEUE_POLL   = 5

local APP_PATTERN = "^[A-Za-z0-9 ._%-()]+$"          -- cmd-server's APP_RE
local URL_PATTERN = "^https?://[^%s'\"\\]+$"          -- cmd-server's URL_RE

local BROWSERS = {
  ["com.google.Chrome"] = true, ["com.apple.Safari"] = true,
  ["company.thebrowser.Browser"] = true, ["org.mozilla.firefox"] = true,
  ["com.brave.Browser"] = true, ["com.microsoft.edgemac"] = true,
}

local KEYS = {
  ["return"]=1, ["enter"]=1, escape=1, tab=1, space=1, delete=1, forwarddelete=1,
  up=1, down=1, left=1, right=1, home=1, ["end"]=1, pageup=1, pagedown=1, help=1,
}
for i = 1, 12 do KEYS["f" .. i] = 1 end
local MODS = { cmd=1, command=1, ctrl=1, control=1, alt=1, option=1, shift=1, fn=1 }

local ORCH = { run = true, say = true, classify = true }

-- ===========================================================================
-- 2. small utils
-- ===========================================================================

local state = {                      -- everything mutable lives here, so stop() is total
  started_at = os.time(),
  server = nil,
  timers = {},
  watchers = {},
  running = false,
  devToken = nil, shellToken = nil,
  fails = {},                        -- rolling window of failure timestamps
  silencedUntil = 0,
  ring = { list = {}, byId = {}, seq = 0, dirty = false },
  orchQueue = {}, orchBusy = false, orchTask = nil, orchTimer = nil,
  inflight = {},                     -- orch ids accepted but not yet in the ring
  ws = nil,                          -- { id, since, shell, lastFrame }
  draining = false,
  buffer = {},                       -- frames arrived mid-drain (D3)
  wakePolls = 0,
  wakeTask = nil,
}

local function nowMs() return hs.timer.absoluteTime() / 1e6 end
local function nowS()  return hs.timer.secondsSinceEpoch() end

-- one line per request: ts, action, ok, ms, and the error (or a note when ok)
local function log(action, ok, ms, err)
  local f = io.open(LOG_PATH, "a")
  if not f then return end
  local tail = ""
  if err then
    tail = string.format(" %s=%s", ok and "note" or "error", tostring(err):gsub("%s+", " "))
  end
  f:write(string.format("%s %s ok=%s ms=%d%s\n",
    os.date("%Y-%m-%dT%H:%M:%S"), tostring(action or "?"), tostring(ok),
    math.floor((ms or 0) + 0.5), tail))
  f:close()
end

local function readFile(path)
  local f = io.open(path, "r"); if not f then return nil end
  local d = f:read("*a"); f:close(); return d
end

local function writeAtomic(path, data)
  local tmp = path .. ".tmp"
  local f, e = io.open(tmp, "w")
  if not f then return false, tostring(e) end
  f:write(data); f:close()
  local ok, e2 = os.rename(tmp, path)
  if not ok then os.remove(tmp); return false, tostring(e2) end
  return true
end

local function mkdirp(path)
  if hs.fs.attributes(path, "mode") == "directory" then return true end
  local parent = path:match("^(.*)/[^/]+$")
  if parent and #parent > 1 then mkdirp(parent) end
  hs.fs.mkdir(path)
  return hs.fs.attributes(path, "mode") == "directory"
end

local function decode(str)
  if type(str) ~= "string" or str == "" then return nil end
  local ok, v = pcall(hs.json.decode, str)
  if ok and type(v) == "table" then return v end
  return nil
end

local function encode(t)
  local ok, v = pcall(hs.json.encode, t)
  return ok and v or '{"ok":false,"error":"encode failed"}'
end

-- blocking settle poll; returns true as soon as fn() is truthy (D6)
local function settle(seconds, fn)
  local deadline = nowS() + seconds
  if fn() then return true end
  repeat
    hs.timer.usleep(50000)
    if fn() then return true end
  until nowS() >= deadline
  return false
end

-- 0..1 fraction or 0..100 percent -> 0..100, nil when out of range (D1)
local function pct(v)
  if type(v) ~= "number" or v ~= v then return nil end
  if v < 0 or v > 100 then return nil end
  if v <= 1 then v = v * 100 end
  return v
end

local function validApp(name)
  if type(name) ~= "string" then return nil end
  if #name < 1 or #name > 64 then return nil end
  if not name:match(APP_PATTERN) then return nil end
  return name
end

local function frontApp() return hs.application.frontmostApplication() end

local function frontName()
  local a = frontApp()
  return a and a:name() or nil
end

-- ===========================================================================
-- 3. tokens and constant-time compare
-- ===========================================================================

-- No early exit: fold every byte of the longer string, then fold the lengths.
local function ctEq(a, b)
  if type(a) ~= "string" or type(b) ~= "string" then return false end
  local la, lb = #a, #b
  local n = la > lb and la or lb
  local diff = la ~ lb
  for i = 1, n do
    local ca = la > 0 and a:byte(((i - 1) % la) + 1) or 0
    local cb = lb > 0 and b:byte(((i - 1) % lb) + 1) or 0
    diff = diff | (ca ~ cb)
  end
  return diff == 0 and la > 0
end

function instinct.reloadTokens()
  local d = readFile(DEV_TOKEN_PATH)
  local s = readFile(SHELL_TOKEN_PATH)
  state.devToken   = d and d:gsub("%s+$", "") or nil
  state.shellToken = s and s:gsub("%s+$", "") or nil
  log("tokens.reload", state.devToken ~= nil, 0,
      (not state.devToken) and "device.token missing" or nil)
  return { device = state.devToken ~= nil, shell = state.shellToken ~= nil }
end

-- ===========================================================================
-- 4. rate limiter (global; source is always loopback behind the funnel)
-- ===========================================================================

local function silenced()
  return nowS() < state.silencedUntil
end

local function noteFailure()
  local t = nowS()
  state.fails[#state.fails + 1] = t
  local keep = {}
  for _, ts in ipairs(state.fails) do
    if t - ts <= FAIL_WINDOW then keep[#keep + 1] = ts end
  end
  state.fails = keep
  if #keep >= FAIL_MAX then
    state.silencedUntil = keep[#keep] + SILENCE
    state.fails = {}
    log("auth.silenced", false, 0, string.format("%d failures in %ds", FAIL_MAX, FAIL_WINDOW))
  end
end

-- ===========================================================================
-- 5. dedupe ring
-- ===========================================================================

local function ringLoad()
  local raw = decode(readFile(RING_PATH) or "")
  if not raw or type(raw.entries) ~= "table" then return end
  for _, e in ipairs(raw.entries) do
    if type(e) == "table" and type(e.id) == "string" then
      state.ring.list[#state.ring.list + 1] = e
      state.ring.byId[e.id] = e
      if (e.seq or 0) > state.ring.seq then state.ring.seq = e.seq end
    end
  end
end

local function ringSave()
  if not state.ring.dirty then return end
  local ok, err = writeAtomic(RING_PATH, encode({ seq = state.ring.seq, entries = state.ring.list }))
  state.ring.dirty = not ok
  if not ok then log("ring.save", false, 0, err) end
end

local function ringGet(id)
  local e = id and state.ring.byId[id]
  return e and e.result or nil
end

local function ringPut(id, result, origin)
  if type(id) ~= "string" or id == "" then return end
  if state.ring.byId[id] then return end               -- first result wins
  local stored = result
  local enc = encode(result)
  if #enc > RESULT_CAP then                            -- D8
    stored = { id = result.id, action = result.action, ok = result.ok, ms = result.ms,
               readback = result.readback, error = result.error, tier = result.tier,
               result = { omitted = true, bytes = #enc } }
  end
  state.ring.seq = state.ring.seq + 1
  local e = { id = id, seq = state.ring.seq, origin = origin or "live", result = stored }
  state.ring.list[#state.ring.list + 1] = e
  state.ring.byId[id] = e
  while #state.ring.list > RING_MAX do                 -- FIFO eviction
    local old = table.remove(state.ring.list, 1)
    if old and state.ring.byId[old.id] == old then state.ring.byId[old.id] = nil end
  end
  state.ring.dirty = true
end

local function ringAcks(since)                          -- D9
  local out = {}
  local e = since and state.ring.byId[since]
  if e then
    for _, x in ipairs(state.ring.list) do
      if (x.seq or 0) > (e.seq or 0) then out[#out + 1] = x.id end
    end
  else
    for _, x in ipairs(state.ring.list) do
      if x.origin == "queue" then out[#out + 1] = x.id end
    end
  end
  return out
end

-- ===========================================================================
-- 6. device verbs
--    Contract: fn(op) -> ok(bool), result(table|nil), readback(any),
--    error(string|nil), tier(number|nil). ok=false always carries an error string.
-- ===========================================================================

local V = {}

V["brightness.get"] = function()
  local b = hs.brightness.get()
  if type(b) ~= "number" then return false, nil, nil, "hs.brightness.get returned nothing" end
  return true, { brightness = b }, b, nil
end

V["brightness.set"] = function(op)
  local want = pct(op.value)
  if not want then return false, nil, nil, "value must be 0..1 or 0..100" end
  local target = math.floor(want + 0.5)
  if not hs.brightness.set(target) then
    return false, nil, hs.brightness.get(), "hs.brightness.set refused " .. target
  end
  settle(0.6, function() return math.abs((hs.brightness.get() or -1) - target) <= 1 end)
  local got = hs.brightness.get()
  if type(got) ~= "number" then return false, nil, nil, "brightness readback unavailable" end
  if math.abs(got - target) > 1 then
    return false, { requested = target }, got,
      string.format("readback mismatch: requested %d, display reports %s", target, tostring(got))
  end
  return true, { requested = target }, got, nil
end

local function outDev()
  return hs.audiodevice.defaultOutputDevice()
end

V["volume.get"] = function()
  local d = outDev()
  if not d then return false, nil, nil, "no default output device" end
  local v, m = d:volume(), d:muted()
  if type(v) ~= "number" then return false, nil, nil, "device reports no volume" end
  return true, { volume = v, muted = m and true or false, device = d:name() },
         { volume = v, muted = m and true or false }, nil
end

V["volume.set"] = function(op)
  local want = pct(op.value)
  if not want then return false, nil, nil, "value must be 0..1 or 0..100" end
  local d = outDev()
  if not d then return false, nil, nil, "no default output device" end
  d:setVolume(want)
  settle(0.4, function() return math.abs((d:volume() or -1) - want) <= 1 end)
  local got = d:volume()
  if type(got) ~= "number" then return false, nil, nil, "volume readback unavailable" end
  if math.abs(got - want) > 1 then
    return false, { requested = want, device = d:name() }, got,
      string.format("readback mismatch: requested %.1f, device reports %.1f", want, got)
  end
  return true, { requested = want, device = d:name() }, got, nil
end

V["mute.set"] = function(op)
  if type(op.value) ~= "boolean" then return false, nil, nil, "value must be true or false" end
  local d = outDev()
  if not d then return false, nil, nil, "no default output device" end
  d:setMuted(op.value)
  settle(0.4, function() return (d:muted() and true or false) == op.value end)
  local got = d:muted() and true or false
  if got ~= op.value then
    return false, { requested = op.value, device = d:name() }, got,
      string.format("readback mismatch: requested muted=%s, device reports %s",
                    tostring(op.value), tostring(got))
  end
  return true, { requested = op.value, device = d:name() }, got, nil
end

V["app.frontmost"] = function()
  local a = frontApp()
  if not a then return false, nil, nil, "no frontmost application" end
  return true, { app = a:name(), bundle = a:bundleID(), pid = a:pid() },
         { app = a:name(), bundle = a:bundleID() }, nil
end

V["app.raise"] = function(op)
  local name = validApp(op.app)
  if not name then return false, nil, nil, "bad app name" end
  if not hs.application.launchOrFocus(name) then
    return false, nil, frontName(), "launchOrFocus failed: no app named " .. name
  end
  local matched
  settle(1.5, function()                                       -- D6
    local f = frontApp()
    if not f then return false end
    local fn = f:name() or ""
    if fn:lower() == name:lower() then matched = fn; return true end
    local b = f:bundleID() or ""
    if b:lower():find(name:lower(), 1, true) then matched = fn; return true end
    return false
  end)
  local got = frontName()
  if not matched then
    return false, { requested = name }, got,
      string.format("readback mismatch: asked for %s, frontmost is %s", name, tostring(got))
  end
  return true, { requested = name }, got, nil
end

local function runningApp(name)
  local a = hs.application.get(name)
  if a then return a end
  local list = { hs.application.find(name) }
  return list[1]
end

V["app.hide"] = function(op)
  local name = validApp(op.app)
  if not name then return false, nil, nil, "bad app name" end
  local a = runningApp(name)
  if not a then return false, nil, nil, name .. " is not running" end
  a:hide()
  settle(1.0, function() return a:isHidden() == true end)
  local got = a:isHidden() and true or false
  if not got then
    return false, { requested = name }, got, "readback mismatch: requested hidden=true, app reports false"
  end
  return true, { requested = name }, got, nil
end

-- window picker shared by the window.* verbs
local function pickWindow(op)
  if op.app ~= nil then
    local name = validApp(op.app)
    if not name then return nil, "bad app name" end
    local a = runningApp(name)
    if not a then return nil, name .. " is not running" end
    local w = a:focusedWindow() or a:mainWindow()
    local all = a:allWindows()
    if not w and all then w = all[1] end
    if not w then return nil, name .. " has no window" end
    return w
  end
  local w = hs.window.frontmostWindow()
  if not w then return nil, "no frontmost window" end
  return w
end

V["window.move"] = function(op)
  for _, k in ipairs({ "x", "y", "w", "h" }) do
    if type(op[k]) ~= "number" then return false, nil, nil, "x, y, w and h must be numbers" end
  end
  if op.w < 40 or op.h < 40 then return false, nil, nil, "w and h must be at least 40 pt" end
  local w, err = pickWindow(op)
  if not w then return false, nil, nil, err end
  local before = w:frame()
  w:setFrame({ x = op.x, y = op.y, w = op.w, h = op.h })
  local want = { x = op.x, y = op.y, w = op.w, h = op.h }
  local close = function()
    local f = w:frame()
    return math.abs(f.x - want.x) <= 8 and math.abs(f.y - want.y) <= 8
       and math.abs(f.w - want.w) <= 8 and math.abs(f.h - want.h) <= 8
  end
  settle(1.0, close)
  local f = w:frame()
  local got = { x = f.x, y = f.y, w = f.w, h = f.h }
  if not close() then                                          -- D7
    return false, { requested = want, before = { x = before.x, y = before.y, w = before.w, h = before.h } },
           got, "readback mismatch: frame is not within 8 pt of the requested rect"
  end
  return true, { requested = want, window = w:title() }, got, nil
end

-- true once two consecutive 50 ms samples report the same frame (animation over)
local function frameSettled(w, cap)
  local last = nil
  return settle(cap, function()
    local f = w:frame()
    local key = string.format("%d,%d,%d,%d", f.x, f.y, f.w, f.h)
    if last == key then return true end
    last = key
    return false
  end)
end

V["window.fullscreen"] = function(op)
  if type(op.value) ~= "boolean" then return false, nil, nil, "value must be true or false" end
  local w, err = pickWindow(op)
  if not w then return false, nil, nil, err end
  w:setFullScreen(op.value)
  -- AXFullScreen flips optimistically, so the frame has to stop moving too (D12)
  settle(2.5, function() return (w:isFullScreen() and true or false) == op.value end)  -- D6
  frameSettled(w, 3.0)
  local got = w:isFullScreen() and true or false
  local f, full = w:frame(), w:screen():fullFrame()
  local spans = math.abs(f.w - full.w) <= 4
  local readback = { fullscreen = got, frame = { x = f.x, y = f.y, w = f.w, h = f.h },
                     spans_width = spans }
  if got ~= op.value then
    return false, { requested = op.value }, readback,
      string.format("readback mismatch: requested fullscreen=%s, window reports %s",
                    tostring(op.value), tostring(got))
  end
  if op.value and not spans then
    return false, { requested = op.value }, readback,
      string.format("readback mismatch: AXFullScreen=true but the frame is %d pt wide on a %d pt screen",
                    f.w, full.w)
  end
  return true, { requested = op.value, window = w:title() }, readback, nil
end

V["window.minimize"] = function(op)
  local w, err = pickWindow(op)
  if not w then return false, nil, nil, err end
  w:minimize()
  settle(1.2, function() return w:isMinimized() == true end)
  local got = w:isMinimized() and true or false
  if not got then
    return false, nil, got, "readback mismatch: requested minimized=true, window reports false"
  end
  return true, { window = w:title() }, got, nil
end

local function axTrusted() return hs.accessibilityState() end

local function describeAt(x, y)
  local el = hs.axuielement.systemElementAtPosition(x, y)
  if not el then return nil end
  local role = el:attributeValue("AXRole") or "?"
  local label = el:attributeValue("AXTitle") or el:attributeValue("AXDescription")
             or el:attributeValue("AXValue")
  if type(label) ~= "string" then label = nil end
  if label then label = label:gsub("%s+", " "):sub(1, 60) end
  return role .. (label and ("/" .. label) or "")
end

local function hasPress(el)
  local ok, names = pcall(function() return el:actionNames() end)
  if not ok or type(names) ~= "table" then return nil end
  for _, n in ipairs(names) do
    if n == "AXPress" then return "AXPress" end
    if n == "AXClick" then return "AXClick" end
  end
  return nil
end

V["click"] = function(op)
  if not axTrusted() then return false, nil, nil, "accessibility not trusted" end
  if type(op.x) ~= "number" or type(op.y) ~= "number" then
    return false, nil, nil, "x and y must be numbers (screen points)"
  end
  local f = frontApp()
  local bundle = f and f:bundleID() or ""
  local tier, acted = nil, false
  if not BROWSERS[bundle] then
    local el = hs.axuielement.systemElementAtPosition(op.x, op.y)
    if el then
      local a = hasPress(el)                                   -- tier 1
      if a then
        local ok = pcall(function() el:performAction(a) end)
        if ok then tier, acted = 1, true end
      end
      if not acted then                                        -- tier 2: nearest ancestor
        local cur, hops = el, 0
        while cur and hops < 6 do
          local p = cur:attributeValue("AXParent")
          if not p then break end
          local pa = hasPress(p)
          if pa then
            local ok = pcall(function() p:performAction(pa) end)
            if ok then tier, acted = 2, true end
            break
          end
          cur, hops = p, hops + 1
        end
      end
    end
  end
  if not acted then                                            -- tier 3 (and browser bypass)
    hs.eventtap.leftClick(hs.geometry.point(op.x, op.y))
    tier = 3
  end
  settle(0.3, function() return false end)
  local m = hs.mouse.absolutePosition()
  local readback = { element = describeAt(op.x, op.y), mouse = { x = m.x, y = m.y },
                     frontmost = frontName(), bypass = BROWSERS[bundle] and bundle or nil }
  if tier == 3 and (math.abs(m.x - op.x) > 2 or math.abs(m.y - op.y) > 2) then
    return false, { tier = tier }, readback,
      string.format("readback mismatch: clicked (%.0f,%.0f) but the cursor is at (%.0f,%.0f)",
                    op.x, op.y, m.x, m.y)
  end
  return true, { tier = tier }, readback, nil, tier
end

V["key.press"] = function(op)
  if not axTrusted() then return false, nil, nil, "accessibility not trusted" end
  local key = type(op.key) == "string" and op.key:lower() or nil
  if not key or not (KEYS[key] or key:match("^[a-z0-9]$") or key:match("^[%p]$")) then
    return false, nil, nil, "bad key"
  end
  local mods = {}
  if op.mods ~= nil then
    if type(op.mods) ~= "table" then return false, nil, nil, "mods must be an array" end
    for _, m in ipairs(op.mods) do
      if type(m) ~= "string" or not MODS[m:lower()] then
        return false, nil, nil, "bad modifier: " .. tostring(m)
      end
      mods[#mods + 1] = m:lower()
    end
  end
  local target = frontApp()
  if not target then return false, nil, nil, "no frontmost application to receive the key" end
  hs.eventtap.keyStroke(mods, key, 0)
  local got = frontName()                                      -- D5
  if not got then return false, { key = key, mods = mods }, nil, "frontmost app vanished after the keystroke" end
  return true, { key = key, mods = mods },
         { delivered_to = got, confirmed = "frontmost app identity only" }, nil
end

V["type.text"] = function(op)
  if not axTrusted() then return false, nil, nil, "accessibility not trusted" end
  local t = op.text
  if type(t) ~= "string" or #t < 1 or #t > 2000 then
    return false, nil, nil, "text must be a string of 1..2000 bytes"
  end
  if t:find("%z") then return false, nil, nil, "text contains a NUL byte" end
  local app = frontApp()
  if not app then return false, nil, nil, "no frontmost application to receive the text" end
  local target = app:name()
  -- when the focused element exposes a small AXValue, that value is the readback (D5).
  -- Hammerspoon itself is excluded: its own UI cannot repaint while a synchronous verb
  -- blocks its run loop, so the field would always read stale (D13).
  local focused, before = nil, nil
  local selfTarget = app:bundleID() == "org.hammerspoon.Hammerspoon"
  if not selfTarget then
    local axApp = hs.axuielement.applicationElement(app)
    focused = axApp and axApp:attributeValue("AXFocusedUIElement") or nil
    before = focused and focused:attributeValue("AXValue") or nil
    if type(before) ~= "string" or #before > 4096 then before = nil; focused = nil end
  end
  hs.eventtap.keyStrokes(t)
  if focused then
    settle(1.5, function()
      local v = focused:attributeValue("AXValue")
      return type(v) == "string" and v:find(t, 1, true) ~= nil
    end)
    local after = focused:attributeValue("AXValue")
    if type(after) ~= "string" or not after:find(t, 1, true) then
      return false, { chars = #t }, { delivered_to = frontName(), field_before = before,
                                      field_after = type(after) == "string" and after:sub(-200) or nil },
        "readback mismatch: the focused field does not contain the typed text"
    end
    return true, { chars = #t },
           { delivered_to = frontName(), confirmed = "focused field contains the text",
             field_after = after:sub(-200) }, nil
  end
  settle(0.3, function() return false end)
  local got = frontName()                                      -- D5
  if got ~= target then
    return false, { chars = #t }, { delivered_to = got, expected = target },
      string.format("readback mismatch: typed into %s but %s was frontmost at the start",
                    tostring(got), target)
  end
  return true, { chars = #t },
         { delivered_to = got, confirmed = selfTarget
             and "frontmost app identity only (target is Hammerspoon: it cannot repaint mid-verb)"
             or  "frontmost app identity only (focused element exposes no readable value)" }, nil
end

V["url.open"] = function(op)
  local url = op.url
  if type(url) ~= "string" or #url < 11 or #url > 300 or not url:match(URL_PATTERN) then
    return false, nil, nil, "bad url (http/https, 11..300 chars, no whitespace or quotes)"
  end
  local app = nil
  if op.app ~= nil then
    app = validApp(op.app)
    if not app then return false, nil, nil, "bad app name" end
  end
  if app then
    local t = hs.task.new(OPEN, nil, { "-a", app, url })
    if not t or not t:start() then return false, nil, nil, "could not spawn open -a" end
  else
    if not hs.urlevent.openURL(url) then return false, nil, frontName(), "openURL refused" end
  end
  settle(0.8, function()                                       -- D6
    local n = frontName()
    return n ~= nil and (not app or n:lower() == app:lower())
  end)
  local got = frontName()
  if not got then return false, { url = url, app = app }, nil, "no frontmost app after opening the url" end
  if app and got:lower() ~= app:lower() then                   -- D5
    return false, { url = url, app = app }, got,
      string.format("readback mismatch: asked for %s, frontmost is %s", app, got)
  end
  return true, { url = url, app = app }, got, nil
end

V["display"] = function(op)
  local t = op.text
  if type(t) ~= "string" or #t < 1 or #t > 200 or t:find("[\r\n]") then
    return false, nil, nil, "text must be 1..200 chars on one line"
  end
  local secs = type(op.secs) == "number" and op.secs or 20
  if secs < 1 or secs > 300 then return false, nil, nil, "secs must be 1..300" end
  local uuid = hs.alert.show(t, {}, hs.screen.mainScreen(), secs)
  if type(uuid) ~= "string" or uuid == "" then
    return false, nil, nil, "hs.alert.show returned no handle"
  end
  return true, { text = t, secs = secs, uuid = uuid }, { shown = true, uuid = uuid }, nil
end

V["screenshot"] = function(op)
  local scr = hs.screen.mainScreen()
  if not scr then return false, nil, nil, "no screen" end
  local img
  if type(op.x) == "number" and type(op.y) == "number"
     and type(op.w) == "number" and type(op.h) == "number" then
    if op.w < 1 or op.h < 1 then return false, nil, nil, "w and h must be positive" end
    img = scr:snapshot(hs.geometry.rect(op.x, op.y, op.w, op.h))
  else
    img = scr:snapshot()
  end
  if not img then return false, nil, nil, "snapshot failed (screen recording permission?)" end
  local url = img:encodeAsURLString(false, "png")
  if type(url) ~= "string" then return false, nil, nil, "png encode failed" end
  local b64 = url:gsub("^data:image/png;base64,", "")
  if #b64 < 64 then return false, nil, #b64, "png encode produced " .. #b64 .. " bytes" end
  return true, { png_base64 = b64, bytes = #b64 }, { bytes = #b64 }, nil
end

-- ===========================================================================
-- 7. op normalisation and the device lane
-- ===========================================================================

-- accepts both {"action":..., flat fields} and the transport doc's {"verb","args"}
local function normalise(raw)
  if type(raw) ~= "table" then return nil, "op must be an object" end
  local op = {}
  for k, v in pairs(raw) do op[k] = v end
  if op.action == nil and type(op.verb) == "string" then op.action = op.verb end
  if type(op.args) == "table" then
    for k, v in pairs(op.args) do if op[k] == nil then op[k] = v end end
  end
  op.args, op.verb = nil, nil
  if type(op.action) ~= "string" then return nil, "missing action" end
  if type(op.id) ~= "string" or op.id == "" then return nil, "missing id" end
  if #op.id > 128 then return nil, "id too long" end
  if op.lane ~= nil and op.lane ~= "device" and op.lane ~= "orch" then
    return nil, "lane must be device or orch"
  end
  return op
end

local function laneOf(op)
  return ORCH[op.action] and "orch" or "device"
end

-- run one device verb, always returning the full result frame
local function runDevice(op)
  local t0 = nowMs()
  local fn = V[op.action]
  if not fn then
    return { id = op.id, action = op.action, ok = false, ms = 0,
             error = "unknown action: " .. tostring(op.action) }
  end
  local ok, a, b, c, d, e = pcall(fn, op)
  local res = { id = op.id, action = op.action, ms = math.floor((nowMs() - t0) + 0.5) }
  if not ok then
    res.ok, res.error = false, "exception: " .. tostring(a):sub(1, 300)
  else
    res.ok = a and true or false
    res.result, res.readback, res.error, res.tier = b, c, d, e
    if res.ok and res.error then res.error = nil end
    if not res.ok and (res.error == nil or res.error == "") then
      res.error = "failed without an error string (bug in " .. op.action .. ")"
    end
  end
  log(op.action, res.ok, res.ms, res.error)
  return res
end

-- ===========================================================================
-- 8. orch lane (async FIFO, one task at a time)
-- ===========================================================================

local pumpOrch   -- forward declaration
local wsLive     -- forward declaration

local function orchDone(job, res)
  res.id, res.action = job.op.id, job.op.action
  res.ms = math.floor((nowMs() - job.t0) + 0.5)
  if res.ok == nil then res.ok = false end
  if not res.ok and (res.error == nil or res.error == "") then
    res.error = "orch op failed without an error string"
  end
  log(job.op.action, res.ok, res.ms, res.error)
  state.inflight[job.op.id] = nil
  ringPut(job.op.id, res, job.origin)
  if job.origin == "ws" and wsLive() and state.server then
    pcall(function() state.server:send(encode(res)) end)
  end
  state.orchBusy, state.orchTask = false, nil
  if state.orchTimer then state.orchTimer:stop(); state.orchTimer = nil end
  hs.timer.doAfter(0, pumpOrch)
end

local function startTask(job, bin, args, cap, onExit)
  local t                                                   -- declared first: the callback
  t = hs.task.new(bin, function(code, out, err)             -- closes over this very local
    if state.orchTask ~= t then return end                  -- already timed out / killed
    onExit(code, out or "", err or "")
  end, args)
  if not t then return orchDone(job, { ok = false, error = "could not create task for " .. bin }) end
  state.orchTask = t
  state.orchTimer = hs.timer.doAfter(cap, function()
    if state.orchTask ~= t then return end
    pcall(function() t:terminate() end)
    state.orchTask = nil
    orchDone(job, { ok = false, error = string.format("timeout (%ds cap)", cap) })
  end)
  if not t:start() then
    state.orchTask = nil
    if state.orchTimer then state.orchTimer:stop(); state.orchTimer = nil end
    orchDone(job, { ok = false, error = "task failed to start: " .. bin })
  end
end

local function doRun(job)
  local cmd = job.op.cmd
  if type(cmd) ~= "string" or #cmd < 1 or #cmd > 4000 or cmd:find("%z") then
    return orchDone(job, { ok = false, error = "bad cmd (1..4000 bytes, no NUL)" })
  end
  startTask(job, ZSH, { "-lc", cmd }, RUN_CAP, function(code, out, err)
    state.orchTask = nil
    orchDone(job, {
      ok = code == 0,
      result = { rc = code, out = out:sub(-4000), err = err:sub(-1500) },
      readback = { rc = code, out_bytes = #out, err_bytes = #err },
      error = code ~= 0 and string.format("exit %d: %s", code,
              (err ~= "" and err or out):sub(-300):gsub("%s+", " ")) or nil,
    })
  end)
end

-- interp.py --dry plan -> device op, where the spec defines a mapping
local function planToOps(plan, id)
  local a = plan.action
  local function mk(action, extra)
    local op = { id = id, action = action }
    for k, v in pairs(extra or {}) do op[k] = v end
    return op
  end
  local app = plan.app
  if app == "(frontmost)" then app = nil end
  if a == "open-app" and app then return { mk("app.raise", { app = app }) } end
  if a == "fullscreen-app" then return { mk("window.fullscreen", { app = app, value = true }) } end
  if a == "frontmost" then return { mk("app.frontmost") } end
  if a == "display" then return { mk("display", { text = plan.text, secs = 20 }) } end
  if a == "press-key" then return { mk("key.press", { key = plan.key }) } end
  if a == "type-text" then return { mk("type.text", { text = plan.text }) } end
  if (a == "url" or a == "web-search") and type(plan.url) == "string" then
    return { mk("url.open", { url = plan.url }) }
  end
  if a == "volume" then
    if type(plan.mute) == "boolean" then return { mk("mute.set", { value = plan.mute }) } end
    if type(plan.level) == "number" then return { mk("volume.set", { value = plan.level }) } end
    return nil
  end
  if a == "tile-pair" and plan.left and plan.right then
    local f = hs.screen.mainScreen():frame()
    local half = math.floor(f.w / 2)
    return {
      mk("window.move", { app = plan.left,  x = f.x,        y = f.y, w = half,      h = f.h }),
      mk("window.move", { app = plan.right, x = f.x + half, y = f.y, w = f.w - half, h = f.h }),
    }
  end
  return nil
end

local function doSay(job)
  local text = job.op.text
  if type(text) ~= "string" or #text < 1 or #text > 300 or text:find("%z") then
    return orchDone(job, { ok = false, error = "bad text (1..300 bytes, no NUL)" })
  end
  startTask(job, PYTHON, { INTERP, text, "--dry" }, SAY_CAP, function(code, out, err)
    state.orchTask = nil
    local parsed = decode(out)
    if code ~= 0 or not parsed then
      return orchDone(job, { ok = false,
        error = string.format("interp --dry exit %d: %s", code,
                ((err ~= "" and err or out) or ""):sub(-250):gsub("%s+", " ")) })
    end
    if parsed.ok == false then
      return orchDone(job, { ok = false, result = parsed,
        error = "interp refused: " .. tostring(parsed.err or "unknown"):sub(1, 200) })
    end
    local plan = parsed.dry
    local ops = type(plan) == "table" and planToOps(plan, job.op.id) or nil
    if ops then
      local subs, allOk, firstErr = {}, true, nil
      for i, sub in ipairs(ops) do
        sub.id = job.op.id .. "#" .. i                        -- sub-ops never enter the ring
        local r = runDevice(sub)
        subs[#subs + 1] = r
        if not r.ok then allOk = false; firstErr = firstErr or r.error end
      end
      return orchDone(job, {
        ok = allOk, result = { via = "daemon", plan = plan, steps = subs },
        readback = subs[#subs] and subs[#subs].readback or nil,
        error = (not allOk) and ("mapped plan failed: " .. tostring(firstErr)) or nil,
      })
    end
    -- no mapping: let interp.py do it for real
    startTask(job, PYTHON, { INTERP, text }, SAY_CAP, function(c2, o2, e2)
      state.orchTask = nil
      local r2 = decode(o2)
      if c2 ~= 0 or not r2 then
        return orchDone(job, { ok = false,
          error = string.format("interp exit %d: %s", c2,
                  ((e2 ~= "" and e2 or o2) or ""):sub(-250):gsub("%s+", " ")) })
      end
      orchDone(job, {
        ok = r2.ok and true or false, result = r2, readback = { via = "interp", did = r2.did },
        error = (not r2.ok) and tostring(r2.err or "interp reported failure"):sub(1, 250) or nil,
      })
    end)
  end)
end

local function doClassify(job)
  local text = job.op.text
  if type(text) ~= "string" or #text < 1 or #text > 300 or text:find("%z") then
    return orchDone(job, { ok = false, error = "bad text (1..300 bytes, no NUL)" })
  end
  local mode = job.op.mode
  if mode == nil then mode = "hybrid" end
  if mode ~= "hybrid" and mode ~= "llm" and mode ~= "rules" then
    return orchDone(job, { ok = false, error = "mode must be hybrid, llm or rules" })
  end
  startTask(job, PYTHON, { CLASSIFY, "--json", "--mode", mode, text }, CLASSIFY_CAP,
    function(code, out, err)
      state.orchTask = nil
      local parsed = decode(out)
      if code ~= 0 or not parsed then
        return orchDone(job, { ok = false,
          error = string.format("classify exit %d: %s", code,
                  ((err ~= "" and err or out) or ""):sub(-250):gsub("%s+", " ")) })
      end
      orchDone(job, {
        ok = parsed.ok == true, result = parsed,
        readback = { intent = parsed.intent, fallback = parsed.fallback, tier = parsed.tier },
        error = (parsed.ok ~= true) and tostring(parsed.error or "classify reported failure") or nil,
      })
    end)
end

pumpOrch = function()
  if state.orchBusy or not state.running then return end
  local job = table.remove(state.orchQueue, 1)
  if not job then return end
  state.orchBusy, job.t0 = true, nowMs()
  if job.op.action == "run" then doRun(job)
  elseif job.op.action == "classify" then doClassify(job)
  else doSay(job) end
end

-- returns the immediate acknowledgement frame (D3)
local function enqueueOrch(op, origin, shellOk)
  if op.action == "run" and not shellOk then
    local res = { id = op.id, action = op.action, ok = false, ms = 0,
                  error = "run requires the shell token" }
    log(op.action, false, 0, res.error)
    return res
  end
  state.inflight[op.id] = true
  state.orchQueue[#state.orchQueue + 1] = { op = op, origin = origin }
  hs.timer.doAfter(0, pumpOrch)
  return { id = op.id, action = op.action, accepted = true, lane = "orch",
           queue_pos = #state.orchQueue }
end

-- ===========================================================================
-- 9. dispatch (dedupe, lane routing)
-- ===========================================================================

-- origin: "ws" | "batch" | "queue"; returns the frame to reply with
local function dispatch(raw, origin, shellOk)
  local op, err = normalise(raw)
  if not op then
    local id = type(raw) == "table" and type(raw.id) == "string" and raw.id or nil
    local res = { id = id, action = type(raw) == "table" and raw.action or nil,
                  ok = false, ms = 0, error = err }
    log("malformed", false, 0, err)
    return res
  end
  if state.inflight[op.id] then
    return { id = op.id, action = op.action, accepted = true, lane = "orch",
             dedupe = true, note = "already in flight, result will arrive once" }
  end
  local cached = ringGet(op.id)
  if cached then
    local copy = {}
    for k, v in pairs(cached) do copy[k] = v end
    copy.dedupe = true
    return copy
  end
  local lane = op.lane or laneOf(op)
  if lane == "orch" or ORCH[op.action] then
    if origin == "batch" then
      local res = { id = op.id, action = op.action, ok = false, ms = 0,
                    error = "orch ops need the websocket" }
      log(op.action, false, 0, res.error)
      return res
    end
    if origin == "queue" then                                  -- D2
      local res = { id = op.id, action = op.action, ok = false, ms = 0,
                    error = "orch ops are not accepted from the vault queue" }
      log(op.action, false, 0, res.error)
      ringPut(op.id, res, "queue")
      return res
    end
    return enqueueOrch(op, origin, shellOk)
  end
  local res = runDevice(op)
  ringPut(op.id, res, origin)
  return res
end

-- ===========================================================================
-- 10. vault queue
-- ===========================================================================

local function queueFiles()
  local names = {}
  local ok, iter, dirObj = pcall(hs.fs.dir, QUEUE_DIR)
  if not ok or not iter then return names end
  for name in iter, dirObj do
    if name and name:match("%.json$") then names[#names + 1] = name end
  end
  table.sort(names)
  return names
end

local function retire(name, errText)
  local src, dst = QUEUE_DIR .. "/" .. name, DONE_DIR .. "/" .. name
  if errText then writeAtomic(dst .. ".error", errText .. "\n") end
  local ok, e = os.rename(src, dst)
  if not ok then log("queue.retire", false, 0, tostring(e)) end
end

local function drainQueue(reason)
  if not mkdirp(DONE_DIR) then
    log("queue.drain", false, 0, "cannot create " .. DONE_DIR)
    return 0
  end
  local n = 0
  for _, name in ipairs(queueFiles()) do
    local t0 = nowMs()
    local body = readFile(QUEUE_DIR .. "/" .. name)
    local parsed = decode(body or "")
    if not parsed then
      log("queue.malformed", false, nowMs() - t0, name)
      retire(name, "not valid JSON, or not an object/array: " .. name)
    else
      local ops = parsed[1] ~= nil and parsed or { parsed }
      local bad = nil
      for _, raw in ipairs(ops) do
        local res = dispatch(raw, "queue", false)
        if not res.ok and not res.dedupe then bad = bad or res.error end
        n = n + 1
      end
      retire(name, bad and ("one or more ops failed: " .. tostring(bad)) or nil)
    end
  end
  if n > 0 then log("queue.drain", true, 0, reason .. " executed=" .. n) end
  ringSave()
  return n
end

-- ===========================================================================
-- 11. websocket session
-- ===========================================================================

wsLive = function()
  return state.ws ~= nil and (nowS() - state.ws.lastFrame) < WS_IDLE
end

local function flushBuffer()
  local pending = state.buffer
  state.buffer = {}
  for _, item in ipairs(pending) do
    local res = dispatch(item.raw, "ws", item.shell)
    if state.server then pcall(function() state.server:send(encode(res)) end) end
  end
end

local function wsCallback(msg)
  if silenced() then return '{"error":"unauthorized"}' end
  local frame = decode(msg)
  if not frame then
    noteFailure()
    return '{"error":"unauthorized"}'
  end

  if frame.hello ~= nil then
    if not ctEq(frame.token, state.devToken) then
      noteFailure()
      log("ws.hello", false, 0, "bad token")
      return '{"error":"unauthorized"}'
    end
    local shellOk = frame.shell_token ~= nil and ctEq(frame.shell_token, state.shellToken)
    state.ws = { id = tostring(frame.hello), since = frame.since, shell = shellOk,
                 lastFrame = nowS() }
    drainQueue("hello")                                        -- drain before answering
    local acks = ringAcks(type(frame.since) == "string" and frame.since or nil)
    log("ws.hello", true, 0, nil)
    return encode({ hello = true, acks = acks, shell = shellOk, version = VERSION })
  end

  if not state.ws then                                          -- D10
    noteFailure()
    return '{"error":"unauthorized"}'
  end
  state.ws.lastFrame = nowS()

  if frame.ping ~= nil then return encode({ pong = frame.ping }) end

  if state.draining then                                        -- D3
    state.buffer[#state.buffer + 1] = { raw = frame, shell = state.ws.shell }
    return encode({ id = frame.id, action = frame.action or frame.verb, buffered = true,
                    reason = "wake drain in progress" })
  end

  return encode(dispatch(frame, "ws", state.ws.shell))
end

-- ===========================================================================
-- 12. HTTP
-- ===========================================================================

local function header(headers, name)
  if type(headers) ~= "table" then return nil end
  local want = name:lower()
  for k, v in pairs(headers) do
    if type(k) == "string" and k:lower() == want then return v end
  end
  return nil
end

local function httpCallback(method, path, headers, body)
  if silenced() then return "", 404, {} end
  local auth = header(headers, "Authorization") or ""
  local bearer = auth:match("^[Bb]earer%s+(.+)$")
  if not ctEq(bearer, state.devToken) then
    noteFailure()
    return "", 404, {}
  end
  local shellOk = ctEq(header(headers, "X-Shell-Token"), state.shellToken)

  if method == "GET" and path == "/v1/health" then
    return encode(instinct.status()), 200, { ["Content-Type"] = "application/json" }
  end

  if method == "POST" and path == "/v1/batch" then
    local ops = decode(body or "")
    if not ops or ops[1] == nil then
      return encode({ ok = false, error = "body must be a non-empty JSON array of ops" }),
             400, { ["Content-Type"] = "application/json" }
    end
    local out = {}
    for _, raw in ipairs(ops) do out[#out + 1] = dispatch(raw, "batch", shellOk) end
    ringSave()
    return encode(out), 200, { ["Content-Type"] = "application/json" }
  end

  noteFailure()                                                 -- unknown path on a good token
  return "", 404, {}
end

-- ===========================================================================
-- 13. wake, timers, watchers
-- ===========================================================================

local function afterWake()
  state.draining = true
  state.wakePolls = 0
  local function poll()
    if not state.running then state.draining = false; return end
    state.wakePolls = state.wakePolls + 1
    local t = hs.task.new(TAILSCALE, function(code, out)
      local running = false
      if code == 0 then
        local j = decode(out or "")
        running = j ~= nil and j.BackendState == "Running"
      end
      if running or state.wakePolls >= WAKE_POLL then
        log("wake.tailscale", running, 0,
            running and ("Running after " .. state.wakePolls .. "s")
                    or ("not Running after " .. state.wakePolls .. "s, draining anyway"))
        drainQueue("wake")
        state.draining = false
        flushBuffer()
      else
        state.timers.wake = hs.timer.doAfter(1, poll)
      end
    end, { "status", "--json" })
    if not t or not t:start() then
      log("wake.tailscale", false, 0, "could not run tailscale status")
      drainQueue("wake")
      state.draining = false
      flushBuffer()
    else
      state.wakeTask = t
    end
  end
  poll()
end

-- ===========================================================================
-- 14. lifecycle
-- ===========================================================================

function instinct.status()
  return {
    ok = state.running,
    version = VERSION,
    uptime_s = os.time() - state.started_at,
    ax_trusted = hs.accessibilityState(),
    ws_client = wsLive(),
    ws_session = state.ws and state.ws.id or nil,
    queue_dir = QUEUE_DIR,
    ring_size = #state.ring.list,
    orch_queue_len = #state.orchQueue + (state.orchBusy and 1 or 0),
    port = PORT,
    draining = state.draining,
    buffered = #state.buffer,
    silenced_for_s = silenced() and math.floor(state.silencedUntil - nowS()) or 0,
    tokens = { device = state.devToken ~= nil, shell = state.shellToken ~= nil },
  }
end

function instinct.stop()
  state.running = false
  for _, t in pairs(state.timers) do pcall(function() t:stop() end) end
  state.timers = {}
  if state.orchTimer then pcall(function() state.orchTimer:stop() end); state.orchTimer = nil end
  if state.orchTask then pcall(function() state.orchTask:terminate() end); state.orchTask = nil end
  if state.wakeTask then pcall(function() state.wakeTask:terminate() end); state.wakeTask = nil end
  for _, w in pairs(state.watchers) do pcall(function() w:stop() end) end
  state.watchers = {}
  if state.server then
    pcall(function() state.server:setCallback(nil) end)
    pcall(function() state.server:stop() end)
    state.server = nil
  end
  state.orchQueue, state.orchBusy, state.buffer, state.ws = {}, false, {}, nil
  state.inflight = {}
  state.ring.dirty = true
  ringSave()
  log("daemon.stop", true, 0, nil)
  return true
end

local function start()
  mkdirp(BRIDGE)
  mkdirp(DONE_DIR)
  instinct.reloadTokens()
  ringLoad()

  local server = hs.httpserver.new(false, false)
  server:setInterface("localhost"):setPort(PORT):maxBodySize(2 * 1024 * 1024)
  server:setCallback(httpCallback)
  server:websocket("/v1/ctl", wsCallback)
  server:start()
  state.server = server
  state.running = true

  -- token watcher: *.token only, so the daemon's own log cannot retrigger it (D11)
  state.watchers.tokens = hs.pathwatcher.new(BRIDGE .. "/", function(paths)
    for _, p in ipairs(paths) do
      if p:match("%.token$") then instinct.reloadTokens(); return end
    end
  end):start()

  state.watchers.wake = hs.caffeinate.watcher.new(function(event)
    if event == hs.caffeinate.watcher.systemDidWake then afterWake() end
  end):start()

  state.timers.queue = hs.timer.doEvery(QUEUE_POLL, function()
    if state.draining or wsLive() then return end               -- D4
    drainQueue("poll")
  end)

  state.timers.ring = hs.timer.doEvery(60, ringSave)

  log("daemon.start", true, 0, "port " .. PORT .. " version " .. VERSION)
  drainQueue("start")
  return instinct
end

instinct.start = start
instinct.drainQueue = function() return drainQueue("manual") end
-- the wake sequence, callable by hand: preflight after a boot, and for testing
instinct.wake = function() afterWake(); return true end
instinct.version = VERSION

start()

_G.instinct = instinct
return instinct
