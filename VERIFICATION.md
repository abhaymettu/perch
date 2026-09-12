# instinct-daemon verification

Date: 2026-09-12. Machine: macOS 26.5.2, M4 Pro, Hammerspoon 1.1.1.

## How this was measured

Loopback only, `http://127.0.0.1:8399`, no funnel in the path. The transport
decision doc estimates the funnel adds roughly 170 ms RTT on top of these
numbers; the funnel cutover is a separate gated step and was not exercised
here. HTTP verbs were driven through `POST /v1/batch` with curl, one op per
call, a fresh UUID id per call. Websocket verbs were driven through the
stdlib client at `wsclient.py` (scratchpad), which dials `/v1/ctl`, sends a
hello frame with the device (and where needed shell) token, and prints every
frame with a monotonic timestamp so ordering and latency read straight off
the transcript. `ms` is the daemon's own reported field on the result; wall
ms is measured by this run around the curl request/response or read off the
websocket transcript timestamps. Three samples per verb where state allows a
clean round trip; fewer where the action is not idempotent or would leave
extra visible side effects (single UI actions such as clicks, the console
window choreography, and the two irreversible-looking calls like `display`
and `screenshot`).

Baseline recorded before any change: brightness 100, volume 0, muted false,
frontmost app Google Chrome (`com.google.Chrome`). Everything below was
restored to this baseline by the end of the run, proven with a final read
(see Restore proof).

## Latency table

All ms values are daemon-reported `ms` (median, min-max over the samples
taken) unless marked single-sample. Wall ms is the same convention around
the curl call.

| verb | params | daemon ms (median, min-max) | wall ms (median, min-max) | readback | ok/tier |
|---|---|---|---|---|---|
| brightness.get | - | 1 (0-1) | 11 (10-13) | 100 | ok |
| brightness.set | value=90 | 2 (2-7) | 14 (14-19) | 89 | ok |
| brightness.set | value=100 | 2 (2-6) | 15 (15-18) | 100 | ok |
| volume.get | - | 2 | 15 | volume 0, muted false | ok |
| volume.set | value=20 | 3 (3-12) | 24 (17-29) | 19.999998 | ok |
| volume.set | value=0 | 2 (1-10) | 14 (10-20) | 0 | ok |
| mute.set | value=true | 2 (1-4) | 14 (13-17) | true | ok |
| mute.set | value=false | 1 (1-2) | 13 (12-14) | false | ok |
| app.frontmost | - | 1 | 16 (16-17) | Google Chrome / com.google.Chrome | ok |
| app.raise | app=Hammerspoon | 12 (12-32) | 25 (23-44) | Hammerspoon | ok |
| app.raise | app=Google Chrome | 16 (5-28) | 41 (30-51) | Google Chrome | ok |
| app.hide | app=Hammerspoon | 10 (8-16) | 23 (18-28) | true (isHidden) | ok |
| app.raise (post-hide) | app=Hammerspoon | 18 (1 sample) | 28 | Hammerspoon | ok |
| app.raise (post-hide) | app=Google Chrome | 20 (1 sample) | 31 | Google Chrome | ok |
| window.move | baseline frame 765,33,510,487 | 9 (9-17) | 21 (19-29) | frame matches request exactly | ok |
| window.move | 100,100,600,400 | 17 (9-17) | 29 (22-45) | frame matches request exactly | ok |
| window.move | back to 765,33,510,487 | 6 (6-9) | 20 (17-22) | frame matches request exactly | ok |
| window.fullscreen | value=true | 100 (1 sample) | 112 | fullscreen=true, frame 0,99,1512,883, spans_width=true | ok |
| window.fullscreen | value=false | 106 (1 sample) | 135 | fullscreen=false, frame back to 765,33,510,487 | ok |
| click | tier 1, Preferences button (1057,66) | 419 (1 sample) | 442 | element AXButton/Preferences, mouse 1102,19 | ok, tier 1 |
| key.press | cmd+w (close Preferences) | 4 (1 sample) | 19 | frontmost Hammerspoon | ok |
| click | tier 3, console text area (900,300) | 519 (1 sample) | 542 | element AXTextArea/..., mouse 900,300 | ok, tier 3 |
| key.press | escape | 3 (1 sample) | 19 | frontmost Hammerspoon (confirmed identity only) | ok |
| type.text | "instinctverify123" (17 chars) | 308 (1 sample) | 334 | confirmed "frontmost app identity only (target is Hammerspoon...)" (D13 path) | ok |
| key.press | cmd+a (clear) | 4 (1 sample) | 24 | frontmost Hammerspoon | ok |
| key.press | delete (clear) | 3 (1 sample) | 15 | frontmost Hammerspoon | ok |
| display | text="instinct verify", secs=1 | 10 (1 sample) | 22 | shown=true | ok |
| screenshot | 0,0,200,200 | 36 (1 sample) | 52 | 226164 bytes (base64 PNG) | ok |
| screenshot | full screen | 1874 (1 sample) | 2104 | 9334732 bytes (base64 PNG) | ok |
| url.open | "file:///etc/hosts" | 0 (1 sample) | 17 | error: "bad url (http/https, 11..300 chars, no whitespace or quotes)" | rejected as expected |
| url.open | "https://example.com/ has space" | 0 (1 sample) | 14 | same error string | rejected as expected |

Brightness and volume readbacks landed within the D1 tolerances (1 point on
the 0-100 scale); the volume readback of 19.999998... for a requested 20 is
float noise well inside that tolerance. Window frames came back exact, not
just within the D7 8 pt tolerance. `window.fullscreen false` restored the
exact pre-fullscreen frame on its own, matching D12.

## Websocket

Dialed `/v1/ctl`, sent hello with the device token, 5 ping/pong round trips
measured with the client forcing a read between each send (an earlier
pipelined attempt where all 5 pings were sent back-to-back before any read
showed all 5 pongs arriving in a single burst — that was the test client
buffering its own unread socket data, not the daemon; spacing the reads
apart gave clean per-frame timing):

| sample | send t (ms) | pong t (ms) | latency (ms) |
|---|---|---|---|
| 1 | 1006 | 1007 | 1 |
| 2 | 2008 | 2009 | 1 |
| 3 | 3010 | 3011 | 1 |
| 4 | 4012 | 4012 | 0 |
| 5 | 5014 | 5015 | 1 |

Median 1 ms, min 0, max 1.

One `brightness.get` frame over the same socket: reply arrived 3 ms after
send, `ms:1`, readback 100.

### Lane independence proof

Hello sent with both device and shell tokens. Two frames sent back to back:
`run {"cmd":"sleep 3; echo done"}` then `brightness.get`, both immediately
after hello.

```
t=     2 == HTTP/1.1 101 Web Socket Protocol Handshake
t=     2 -> hello (device+shell tokens)
t=     4 <- {"acks":[],"hello":true,"shell":true,"version":"1.0.0"}
t=   304 -> run {"cmd":"sleep 3; echo done"}
t=   304 -> brightness.get
t=   305 <- {"queue_pos":1,"accepted":true,"lane":"orch","action":"run"}
t=   309 <- {"result":{"brightness":100},"ms":1,"ok":true,"action":"brightness.get"}
t=  3367 <- {"result":{"out":"done\n","rc":0,"err":""},"ms":3060,"ok":true,"action":"run"}
```

The device-lane `brightness.get` reply landed at t=309 ms, about 3.06
seconds before the orch-lane `run` finished at t=3367 ms. The blocking shell
command on the orch lane did not delay the device lane, confirming the
two-lane design in the spec.

### say (orch verb)

Sent over the same kind of session (device token only, no shell token
needed for `say`): `{"action":"say","text":"which app is in front"}`.
Reply arrived via `via:"daemon"` (mapped to `app.frontmost` internally,
not the `interp.py` fallback), `ms:1610`, result confirmed Google Chrome
frontmost, matching the live state at the time.

## Auth

Three failures total, well under the 10-in-60s limiter (the builder already
exercised the limiter itself on 2026-09-12: 10 failures triggers 60 s of
blanket 404, then recovery).

| case | result |
|---|---|
| bad bearer, `GET /v1/health` | `HTTP/1.1 404 Not Found`, `Content-Length: 0` |
| no auth header, `GET /v1/health` | `HTTP/1.1 404 Not Found`, `Content-Length: 0` |
| good device token, wrong path `/v1/nope` | `HTTP/1.1 404 Not Found`, `Content-Length: 0` |

All three came back with an empty body, matching the spec's "any auth
failure: 404, empty body."

## Dedupe

Sent `{"id":"dedupe-verify-1","action":"brightness.get"}`, got
`readback:100, ok:true`, no dedupe flag. Resent the identical id: got
`dedupe:true, readback:100, ok:true` — identical readback, served from the
ring cache.

## Queue

Wrote one op file directly to the vault queue dir while no websocket
session was live:

```
.../05-Bridge/exec/device-queue/20260912T183716Z-qv1.json
{"id":"qv1-<uuid>","action":"brightness.get"}
```

It moved to `done/` on its own after about 11 seconds (consistent with the
spec's 5 s poll interval while no session is live — roughly two poll
cycles). A fresh websocket session then sent `hello` with `since:null` and
the reply's `acks` array contained exactly that queue-origin id
(`qv1-D1FBB07C-0E5C-441C-937A-A5438F33B508`), matching D9 (unknown/null
`since` acks every queue-origin id still in the ring). The test file in
`done/` was deleted afterward. One slip during cleanup: after deleting the
file, an `rmdir` on the now-empty `done/` directory succeeded and removed
the directory itself; it was recreated immediately (empty, same permissions
layout) so the queue dir is back to its pre-test shape.

## Health after everything

Final `GET /v1/health`: `ok:true, ax_trusted:true, ws_client:true,
ws_session:"verify-sess-5", uptime_s:314, ring_size:80, orch_queue_len:0,
buffered:0, draining:false, silenced_for_s:0`, tokens both present. No
errors, no lingering drain state, no active silencing from the auth tests.

## Restore proof

| state | start | end |
|---|---|---|
| brightness | 100 | 100 |
| volume | 0 | 0 |
| muted | false | false |
| frontmost app | Google Chrome | Google Chrome |

All four match. The Hammerspoon console window, opened for the window.move
and click tests, was closed with `hs.closeConsole()` before the final
Chrome re-raise, and the vault queue's `done/` directory was restored to
empty after the queue test's cleanup slip above.

## Not verified live

- Browser-bundle click bypass path (tier 3 forced when frontmost bundle is
  Chrome/Safari/Arc/Firefox/Brave/Edge): not exercised, since his Chrome has
  live tabs and clicking through the daemon would have touched them. The
  tier 1 and tier 3 clicks tested here both ran against the Hammerspoon
  console, not a browser.
- `url.open` browser happy path: skipped per instructions; only the two
  rejection cases (file: URL, URL with whitespace) were tested.
- `window.minimize`: not tested. The spec lists it but this run's
  instructions did not call for it, and the header notes the builder could
  not get it to take reliably on the console window.
- Real sleep/wake cycle and the `hs.caffeinate.watcher` wake-triggered queue
  drain path: not exercised, since it requires an actual sleep/wake, not a
  simulated one.
- The funnel path (public HTTPS ingress, the ~170 ms RTT estimate from the
  transport doc): loopback only in this run; funnel cutover is a separate
  gated step.
