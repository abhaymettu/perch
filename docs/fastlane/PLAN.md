# Implementation plan: Jarvis fast lane

Spec: `docs/fastlane/SPEC.md`. Written 2026-09-12 before code.

## Technical context

- Daemon: `Scripts/instinct-daemon.lua`, Hammerspoon, 127.0.0.1:8399, fronted by
  `tailscale funnel` on 10000 (`https://abhays-macbook-pro.tail4948a2.ts.net:10000`
  -> `http://127.0.0.1:8399`). WS at `/v1/ctl`. Protocol in `docs/instinct-daemon-spec.md`.
- Orch verbs run through `startTask(job, bin, args, cap, onExit)` with `hs.task`
  (see `doSay`). `PYTHON` is `/usr/bin/python3`. Adding a verb = add to `ORCH`, add a
  `doX` that calls `startTask`, route it in `pumpOrch`.
- Local model on the Mac: magnitude gateway, OpenAI-compatible,
  `http://127.0.0.1:10100/inference/v1/chat/completions`, model
  `gemma-4-e2b-it-qat:gguf:q4`. interp.py's request shape works (temperature 0,
  `chat_template_kwargs.enable_thinking=false`). Reuse it.
- Cloud side: python3, no guaranteed pip, no inbound, HTTPS egress to the funnel.
  ssh to the Mac exists as `/tmp/macssh` (tailnet-direct, funnel fallback, ~1.2 s).
- Language: python 3 stdlib on both sides; lua for the daemon verb. No new deps.

## Structure

```
Scripts/wss-holder.py            resident holder + client CLI + importable submit()
Scripts/fastlane/classify.py     rules tier + LLM tier + validation, CLI --json
Scripts/fastlane/intents.json    ~60 labelled utterances
Scripts/fastlane/bench_classify.py   accuracy + latency per leg, portable
Scripts/fastlane/bench_e2e.py    receipt -> readback through the holder, N trials
Scripts/fastlane/bench_before.py cold per-command path (token fetch + cold dial + verb)
Scripts/instinct-daemon.lua      + orch verb `classify` (additive)
docs/fastlane/{SPEC,PLAN,TASKS,BENCH,CLOUD-STEPS}.md
```

## Design decisions

1. **Hand-rolled RFC 6455 client, not `websockets`.** The sandbox may not pip install,
   and the daemon only uses text frames and app-level ping. About 120 lines of stdlib
   `ssl` + `socket`. Client-to-server frames are masked; server frames are unmasked;
   handle opcodes text (1), close (8), ping (9, answer pong 10), pong (10); fragmentation
   is reassembled but not expected.
2. **One reader thread, one writer lock.** Pending ops map id -> Event + slot. The reader
   thread routes every incoming frame by `id`; frames with `accepted: true` are stored as
   interim and do not release the waiter unless `wait: false`. `pong` frames refresh the
   liveness clock. Any frame refreshes it too.
3. **Spool replay = re-send.** On hello the daemon returns `acks` for ring ids after
   `since`; the holder logs them but still re-sends every spooled op. The ring answers
   duplicates with `dedupe: true`, so replay is idempotent without holder-side ack logic.
4. **`since` = last id that received a final result**, persisted in the holder's state
   file next to the spool.
5. **Rules before model.** Whole-utterance regexes handle the obvious phrasings at zero
   cost and cannot false-fire on near-misses because they only match the full string.
   The model sees only what rules did not match. Both tiers produce the same op shape.
6. **Model output is data.** Parse first `{...}`, validate intent against the table,
   validate slots, else FALLBACK. Never build a shell string from it.
7. **Daemon verb `classify` shells to classify.py** rather than reimplementing the
   prompt in lua, so the Mac leg and the cloud leg run byte-identical classifier code.
   Cap 20 s. Reload the module live with the install script's exact `hs -c` line; the
   held WS session drops once (the holder's reconnect test).
8. **Measurement verbs are invisible.** brightness.get, and brightness.set to the value
   just read. No alerts, no window moves, no lock.

## Risks

- Cloud CPU-only small model may be slow on prompt processing. Keep the system prompt
  under ~200 tokens; the harness reports the number either way.
- The daemon holds a single `state.ws`. A Mac-side holder test replaces whatever session
  the runner holds; results for that session's in-flight orch ops still arrive via
  `server:send`. Acceptable during the build window; noted in BENCH.md.
- Reloading the daemon module drops the live socket. Announced in BENCH.md with the
  staged kill.

## Verification

- Holder: unit-level frame codec test (mask/unmask round trip, close handshake) plus a
  live run on the Mac against the funnel URL: 20 brightness.get ops, forced module
  reload mid-run, spool a queued op while down, observe replay + dedupe.
- Classifier: `bench_classify.py` on the full set, rules-only and gemma-on-Mac, 0 false
  fires on the must-fallback subset.
- Daemon verb: `curl`-free WS test via the holder: `{"action":"classify","text":"mute"}`
  returns the classify JSON; `readback` echoes the op.
- E2E: `bench_e2e.py` N=20 through the holder, p50/p95 in BENCH.md.
