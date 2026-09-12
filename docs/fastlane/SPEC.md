# Feature spec: Jarvis fast lane (resident WSS holder + intent classifier)

Status: green-lit 2026-09-12 15:39 (iMessage "Yes"). Spec written 2026-09-12 before any
code, per the spec-kit rule for a new feature in an existing repo.

## Problem

A device verb sent from the cloud agent takes ~33 s from receipt to readback (runner's
figure, 2026-09-12). The daemon itself answers in ~150 ms once a socket is held
(`Scripts/instinct-daemon.lua`, funnel 10000, measured 2026-09-11). The rest is overhead:
a per-command ssh token fetch plus a cold TLS + WSS dial (~10 s) and one or more full
agent turns to decide what to send.

Target: ~1 s receipt -> readback for a known device verb, $0 API spend.

## User stories

1. **Known intent, Mac awake.** "brightness zero" arrives on the cloud side. Within about
   a second the Mac's brightness reads back 0 and the caller has the daemon's result frame.
   No agent turn ran.
2. **Unknown or ambiguous intent.** "mute the guy in the meeting" arrives. The fast lane
   returns an explicit `FALLBACK` marker in well under a second and does nothing on the
   Mac. The slow lane (full agent) takes it from there.
3. **Mac asleep or roaming.** "volume 50" arrives while the socket is down. The caller is
   told `queued` immediately. When the socket comes back the op is delivered once, and a
   duplicate delivery is answered from the daemon's dedupe ring, never re-executed.
4. **Holder restart.** The runner restarts the holder with one documented command. It
   refetches the device token over ssh, reconnects, and drains anything spooled.

## Functional requirements

### FR-A: resident cloud-side WSS holder (`Scripts/wss-holder.py`)

- A1. Holds exactly one WSS to `wss://abhays-macbook-pro.tail4948a2.ts.net:10000/v1/ctl`.
- A2. Handshake per `docs/instinct-daemon-spec.md`: first frame
  `{"hello": <session-id>, "since": <last result id or null>, "token": <device token>}`.
- A3. Liveness: app-level `{"ping": n}` every 20 s. No frame received for 40 s -> socket
  declared dead, closed, reconnect.
- A4. Reconnect backoff 1, 2, 4, 8, 16, 30 s cap, full jitter, forever. Every failed dial
  marks the Mac `away`.
- A5. Every op carries a uuid4 `id` (assigned by the holder when the client omits one).
  The daemon's 1000-id ring dedupes re-delivery; the holder never invents a second id for
  the same op.
- A6. Queue-when-away: when the socket is down, device ops are written to a cloud-local
  spool directory as `<ISO-timestamp>-<id>.json`, the caller gets `{"queued": true, "id"}`,
  and the spool drains in name order on the next successful hello. Delivered files move
  to `spool/done/`.
- A7. IPC: loopback-only unix socket. One JSON line in (the op, or `{"ctl": "status"}`),
  one JSON line out (the daemon's result frame, `queued`, or an error object). For orch
  ops (`run`, `say`, `classify`) the holder returns the final result frame, not the
  `accepted` frame, unless the client passes `"wait": false`.
- A8. Device token: fetched at holder start by a configurable ssh command (default reads
  `~/.perch-bridge/device.token` on the Mac), written cloud-side with mode 600, never
  written to any log or stdout. The holder reuses an existing 600 file when the ssh
  fetch fails and the file exists.
- A9. Runs under `nohup` in the foreground-serving mode; restart recipe in CLOUD-STEPS.md.
- A10. Python 3 stdlib only. The cloud sandbox has no guaranteed pip. The WebSocket
  client (RFC 6455 text frames, masking, close) is implemented in the file.

### FR-B: fast-lane intent classifier (`Scripts/fastlane/classify.py`)

- B1. Input: one utterance. Output: one JSON object with `intent`, the daemon op
  (`{"action": ..., ...}`) or `null`, `fallback` (bool), `tier` (`rules` or `llm`), `ms`.
- B2. Tier 1 is a deterministic rule table (whole-utterance regexes) covering the
  known intents. It fires only on unambiguous phrasing. Anything else goes to tier 2.
- B3. Tier 2 is a small local model behind any OpenAI-compatible chat endpoint
  (`FASTLANE_LLM_URL`, `FASTLANE_LLM_MODEL`). The prompt lists the intents and slots,
  demands one JSON object, and names `FALLBACK` as the answer for anything else.
- B4. Post-validation: the model's intent must be in the table and slots must validate
  (numbers in range, app names resolvable, urls http(s)). Anything else -> `FALLBACK`.
  Model output is never executed or shell-interpolated.
- B5. Intent table (device lane only): brightness.set, brightness.get, volume.set,
  volume.get, mute.set (on/off), app.raise, app.hide, window.fullscreen (on/off),
  window.minimize, url.open, lock_screen (maps to key.press q with cmd+ctrl),
  app.frontmost. Relative changes ("brightness up"), conditionals, and anything
  outside the table are `FALLBACK`.
- B6. Test set `Scripts/fastlane/intents.json`: about 60 utterances. Roughly two thirds
  are positives across the table with phrasing variety; one third are adversarial
  near-misses that MUST fall through (shared words, wrong domain, out-of-range values,
  conditionals, bare app names).
- B7. Benchmark harness `Scripts/fastlane/bench_classify.py`: runs the test set against
  (a) rules only, (b) the LLM at a given endpoint, (c) rules then LLM. Reports accuracy,
  false-fire rate on the must-fallback subset, and latency p50/p95. Portable stdlib
  python so the runner can execute it unchanged on the cloud sandbox.
- B8. Gemma-on-Mac leg with the real network hop: an additive orch verb `classify`
  `{text}` on the daemon runs `classify.py --json --llm` on the Mac and returns its
  JSON. The cloud-side harness calls it through the holder so the measured latency
  includes the relayed round trip.

### FR-C: measurement (`docs/fastlane/BENCH.md`)

- C1. Before: the per-command cold path as the cloud runs it today (token fetch over the
  relayed ssh path, cold TLS + WSS dial, hello, one verb with readback), measured from
  the Mac through the public funnel hostname. The runner's ~33 s and ~10 s figures are
  reported as reported, not remeasured.
- C2. After: receipt -> readback through classifier + holder + held WSS, for a device
  verb, N >= 20 trials, p50/p95. Verbs used in measurement are invisible on the machine
  (brightness.get, brightness.set to the current value).
- C3. Classification leg: gemma-on-Mac (via the daemon verb, hop included) vs the cloud
  small model (local to the sandbox), same test set. Winner takes the leg; the doc says
  which and why with the numbers.

## Non-goals

- No change to `~/.hammerspoon/init.lua`. The daemon change is one additive verb,
  loaded live and readback-verified, with a staged kill in BENCH.md.
- No vault-queue changes. The spool is cloud-local.
- No paid model API. Local models only on both sides.
- No push. perch is public; commit locally only.

## Success criteria

- SC1. Known-intent device verb: p50 receipt -> readback <= 1.0 s on a warm socket
  (measured on the Mac through the funnel; cloud-side figure added by the runner).
- SC2. Must-fallback subset: 0 false fires for the chosen classification leg.
- SC3. Positive subset: >= 90% correct op for the chosen leg.
- SC4. Holder survives a forced disconnect (daemon module reload) and a killed socket:
  reconnects with backoff, replays the spool, and the daemon answers the replay from
  its ring with `dedupe: true`.
- SC5. Token never appears in holder logs, stdout, or the repo (grep proves it).

## Assumptions (named because they change the work if wrong)

- The Mac's Gemma 4 E2B is served by the local `magnitude` gateway on 127.0.0.1:10100
  (model id `gemma-4-e2b-it-qat:gguf:q4`), which is what `interp.py` already uses. ollama
  on this Mac has no gemma pulled. "ollama" in the brief is read as "the local model
  server that already serves gemma-4-e2b"; the harness takes any OpenAI-compatible URL.
- The cloud sandbox's small model is whatever the runner can run CPU-only (ollama or
  llama.cpp server). CLOUD-STEPS.md names candidates; the harness does not care which.
