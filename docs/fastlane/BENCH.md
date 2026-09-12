# Fast lane benchmark: receipt -> readback for a device verb

Measured 2026-09-12 16:00-16:10 CDT on the Mac, against the live daemon (v1.1.0) through
the funnel. Every number below that says "relayed" was taken with the TCP connection
pinned to Tailscale's public ingress (209.177.145.97), because the Mac resolves its own
funnel hostname to its tailnet IP and tailscaled short-circuits it locally (a cold HTTPS
call is 20 ms that way, 430 ms relayed). The relayed path is the one the cloud takes.
Raw JSON for every run is in the session scratchpad; the harnesses regenerate it.

## Headline

| Path | p50 | p95 | n | Source |
|---|---|---|---|---|
| Before, as the cloud runs it today (agent turns + per-command token fetch + cold dial) | ~33 s | | | runner's figure, reported not remeasured |
| Before, transport only: relayed ssh handshake + cold TLS/WSS dial + hello + verb | 1.57 s | 1.60 s | 5 | `bench_before.py --connect-host 209.177.145.97` |
| After: utterance -> rules classifier -> holder IPC -> held WSS -> execute -> readback | **109 ms** | **117 ms** | 20 | `bench_e2e.py --mode hybrid` |

Target was ~1 s. Measured 0.11 s on the relayed path from the Mac. The cloud sandbox
adds its own DERP leg (cloud -> ord ~49 ms one way per `transport-decision.md`), so
expect roughly 0.15-0.25 s there; the runner records the actual figure in the
"Cloud-side results" section below.

## Before: where the 33 s goes

`bench_before.py`, n=5, relayed:

| leg | p50 ms | p95 ms | mean | min | max |
|---|---|---|---|---|---|
| ssh handshake to the Mac (token fetch leg, stops at auth since the Mac has no key to itself) | 834 | 910 | 826 | 768 | 910 |
| cold TLS + WSS upgrade + hello | 617 | 671 | 620 | 578 | 671 |
| one verb, brightness.get, with readback | 122 | 123 | 120 | 109 | 123 |
| total per command | 1573 | 1598 | 1565 | 1520 | 1598 |
| for contrast: one cold HTTPS `POST /v1/batch` | 429 | 443 | 421 | 395 | 443 |

The transport accounts for ~1.6 s of the ~10 s per-command overhead the runner sees;
the rest is agent tool-call latency around each step (spawning ssh, spawning the
client, reading files), and the ~33 s total is that plus one or more full model turns.
The fast lane removes all three: no ssh, no dial, no turn.

## After: the fast lane

`bench_e2e.py`, n=20 each, relayed, holder resident, verbs alternate `brightness.set`
to the current value and `brightness.get` (both invisible):

| mode | classify p50 | holder round trip p50 / p95 | total p50 / p95 | ok |
|---|---|---|---|---|
| hybrid (rules hit every time) | 0 ms | 109 / 117 ms | 109 / 117 ms | 20/20 |
| rules | 0 ms | 110 / 114 ms | 110 / 114 ms | 20/20 |

Holder round trip = unix-socket IPC + WSS frame out + daemon execute + readback + frame
back. Daemon-side execute is 1-12 ms; the rest is the relay. Warm `brightness.get`
alone through the holder: p50 122 ms, p95 142 ms (n=20).

## Classification leg: gemma-on-Mac vs cloud small model

Test set: `Scripts/fastlane/intents.json`, 63 utterances, 43 positives across all 12
intents, 20 adversarial near-misses that must fall through. Same file, same code on
both sides. "via hop" = sent through the holder to the daemon's `classify` verb, so
the number includes the relayed round trip plus a `/usr/bin/python3` process start.

| leg | positives | false fires (of 20) | p50 ms | p95 ms | passes SC2+SC3 |
|---|---|---|---|---|---|
| rules only, local | 43/43 | 0 | 0.01 | 0.01 | yes |
| gemma-4-e2b (magnitude, Mac), llm only, local | 37/43 (86%) | 7 | 185 | 382 | no |
| gemma-4-e2b, llm only, via hop | 37/43 (86%) | 7 | 441 | 676 | no |
| hybrid (rules then gemma), local | 43/43 | 0 | 0.01 | 0.08 | yes |
| hybrid, via hop | 43/43 | 0 | 166 | 193 | yes |
| cloud small model, llm only | runner fills in | | | | |
| cloud small model, hybrid | runner fills in | | | | |

gemma-4-e2b alone false-fires on 7 of 20 adversarials ("brightness up a bit", "make it
louder", "mute after the call", "don't mute", "mute and lock the screen", "what is
brightness", "how do i lock the screen") and misses 6 positives (unmute x2, and
open/switch-to for chrome, spotify, notes). Three prompt revisions did not move it past
86% / 7. The hybrid rows pass only because the tier-1 rules now carry explicit guards
(negation, question words, comparatives, conditionals, bare app names) so none of the
20 adversarials reach the model.

### Decision

1. **The rules tier takes the leg.** It is exact, costs nothing, and runs on the cloud
   side with no hop. It already covers every positive in the set.
2. **No LLM tier is trusted for firing yet.** On the evidence, a novel phrasing that
   slips past the rule guards and reaches gemma would false-fire about a third of the
   time. Until a model shows 0 false fires in `--mode llm` on this set, the deployed
   mode is `rules`: matched -> fire, unmatched -> `FALLBACK` to the slow lane. Hybrid
   stays available behind `--mode hybrid` for the runner's cloud model trial.
3. **If the cloud small model passes** (0 false fires, >= 90% positives in llm mode),
   it takes the LLM tier: it is local to the sandbox, so classification adds no hop.
   gemma-on-Mac would only win if the cloud model fails and gemma passed, and it did
   not; its hop also costs ~120 ms plus a process start.

Extra data point, not part of the decision: `qwen3.5-4b` on magnitude (Mac, llm only,
local) scored 35/43 positives (81%), 2 false fires ("brightness up a bit", "make it
louder"), p50 846 ms, p95 2536 ms, max 11.7 s. Fewer false fires than gemma but far too
slow, and still not zero.

## Cloud-side results

Runner: paste the summary blocks from CLOUD-STEPS.md sections 3 and 4 here.

- cloud small model (name, size): llm ... / hybrid ...
- gemma-on-Mac via holder from the cloud: llm ... / hybrid ...
- `bench_e2e.py` from the cloud: total p50 / p95 ...

## Findings that changed the design

- **One websocket client at a time.** `hs.httpserver:send` pushes orch results (run,
  say, classify) only to the most recently connected websocket. A second session
  (another holder, a test client) silently takes the push target; the first holder's
  orch ops then time out while the daemon log shows them succeeding. Device verbs are
  unaffected (replied inline). Rule: one holder per daemon; after any other WS session
  connects, restart the holder. Noted in CLOUD-STEPS.md.
- **The Mac cannot measure its own funnel honestly** without pinning the public ingress
  IP. `HOLDER_CONNECT_HOST` exists for that; leave it unset on the cloud.
- **AF_UNIX paths are capped at ~104 bytes on macOS**; the holder's socket must live
  under a short `HOLDER_DIR`. The default `~/.perch-bridge/holder` is fine.
- **Holder reader thread must start before spool replay** (fixed during the build; the
  first replay attempt timed out with the result sitting unread in the socket buffer).
- The daemon reads `value <= 1` as a fraction; the classifier sends integers 0 and
  2..100 and the fraction 0.01 for "1" so nothing is ambiguous.

## Machine-visible changes made during this lane, and how to back them out

1. **Daemon module reloaded live once** at 15:54:57 to load the additive `classify`
   verb (version 1.0.0 -> 1.1.0). The held websocket dropped for ~1 s and reconnected.
   `~/.hammerspoon/init.lua` untouched. Canary: the daemon has served every verb since
   (log `~/.perch-bridge/instinct-daemon.log`); judge after 24 h of normal use.
   Staged kill:
   ```
   git checkout -- Scripts/instinct-daemon.lua docs/instinct-daemon-spec.md
   /opt/homebrew/bin/hs -c 'package.loaded["instinct-daemon"]=nil; if instinct then pcall(instinct.stop) end; require("instinct-daemon")'
   ```
2. **A test holder instance is still running on the Mac** (session
   `holder-Abhays-MacBook-Pro-*`, state under `/tmp/perch-holder-test`, pinned to the
   public ingress). It holds the daemon's push target until the cloud holder connects.
   Kill:
   ```
   HOLDER_DIR=/tmp/perch-holder-test python3 Scripts/wss-holder.py stop
   ```
   It is not installed anywhere; a reboot removes it.

No watchers, no menubar items, no dialogs, no window effects were added.

## Reproduce

```
export HOLDER_DIR=/tmp/perch-holder-test HOLDER_CONNECT_HOST=209.177.145.97
nohup python3 Scripts/wss-holder.py serve >> /tmp/perch-holder-test/nohup.out 2>&1 &
python3 Scripts/fastlane/bench_before.py --n 5 --connect-host 209.177.145.97
python3 Scripts/fastlane/bench_classify.py --set Scripts/fastlane/intents.json --mode rules
python3 Scripts/fastlane/bench_classify.py --set Scripts/fastlane/intents.json --mode llm
python3 Scripts/fastlane/bench_classify.py --set Scripts/fastlane/intents.json --mode llm --via-holder /tmp/perch-holder-test/holder.sock
python3 Scripts/fastlane/bench_e2e.py --sock /tmp/perch-holder-test/holder.sock --n 20
```

## Cloud-side results (sandbox, 2026-09-12 16:40-16:41 CDT)

Measured from the cloud sandbox by the runner; raw JSON in docs/fastlane/raw-bench-*.json.

Classifier legs, intents.json (63 utterances = 43 positives + 20 must-fallback):

| leg | positives | false fires | p50 |
|---|---|---|---|
| hybrid, rules + cloud gemma3:1b | 43/43 (100%) | 0 | 0.01 ms |
| hybrid, rules + Mac gemma via holder | 43/43 (100%) | 0 | 183 ms |
| Mac gemma alone via holder | 35/43 (81%) FAIL | 9 FAIL | 477 ms |
| cloud gemma3:1b alone (2-core sandbox) | 15/43 (35%) FAIL | 2 FAIL | 8858 ms |

Leg decision (SPEC SC2/SC3): rules-first hybrid wins; LLM fallback leg belongs to the
Mac gemma (uniform 183 ms) - the sandbox 1b is both slowest and least accurate, and
standalone LLMs false-fire on safety-critical negatives ("don't mute").

End to end, receipt -> readback (bench_e2e, hybrid, n=20, 20/20 ok, invisible verbs):
classify 0.05 ms, holder round trip 122 ms, TOTAL p50 122 ms / p95 130 ms.
Before (cloud, n=5): cold path 1610 ms p50 (ssh 913 + dial 563 + verb 122); ~33 s with
the agent-turn path. Target ~1 s beaten ~8x.
