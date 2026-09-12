# Cloud-side steps: fast lane

For the runner on the cloud sandbox. Everything here is python 3 stdlib; nothing to pip
install. Paths assume the perch checkout is at `~/perch` on the sandbox (adjust).
Mac-side pieces (daemon verb `classify`, funnel 10000) are already live.

## 0. What is where

| Piece | Path | Runs on |
|---|---|---|
| Resident WSS holder | `Scripts/wss-holder.py` | cloud sandbox, nohup |
| Classifier (rules + local model) | `Scripts/fastlane/classify.py` | both sides |
| Intent test set | `Scripts/fastlane/intents.json` | both sides |
| Classification harness | `Scripts/fastlane/bench_classify.py` | both sides |
| End-to-end harness | `Scripts/fastlane/bench_e2e.py` | cloud sandbox |
| Daemon orch verb `classify` | `Scripts/instinct-daemon.lua` | Mac (live, v1.1.0) |

## 1. Holder install (once per sandbox)

```sh
mkdir -p ~/.perch-bridge/holder && chmod 700 ~/.perch-bridge
export HOLDER_TOKEN_CMD='/tmp/macssh cat ~/.perch-bridge/device.token'
nohup python3 ~/perch/Scripts/wss-holder.py serve >> ~/.perch-bridge/holder/nohup.out 2>&1 &
sleep 3
python3 ~/perch/Scripts/wss-holder.py status
```

`status` must show `"mac": "up"` and a `last_rtt_ms` in the low hundreds. The token is
written to `~/.perch-bridge/device.token` (mode 600) and never logged. If the ssh fetch
fails on a later restart and that file exists, the holder reuses it.

Two rules learned on the Mac side:

- **One websocket client per daemon.** The daemon pushes orch results (`classify`,
  `say`, `run`) only to the most recently connected websocket. Never run two holders,
  and after any other WS client connects (a test script, `bench_before.py`), restart
  the holder. Device verbs are unaffected.
- **Keep `HOLDER_DIR` short.** The unix socket path must stay under ~100 bytes.

Optional env: `HOLDER_URL` (default is the funnel `wss://...:10000/v1/ctl`),
`HOLDER_DIR` (default `~/.perch-bridge/holder`), `HOLDER_SHELL_TOKEN_FILE` (only if
you also want `run` over the holder; fetch `shell.token` the same way).

### Restart recipe

```sh
python3 ~/perch/Scripts/wss-holder.py stop        # or: kill $(pgrep -f 'wss-holder.py serve')
nohup python3 ~/perch/Scripts/wss-holder.py serve >> ~/.perch-bridge/holder/nohup.out 2>&1 &
python3 ~/perch/Scripts/wss-holder.py status
```

Log: `~/.perch-bridge/holder/holder.log`. Spool of ops sent while the Mac was away:
`~/.perch-bridge/holder/spool/` (delivered ones move to `spool/done/`).

### Smoke test

```sh
python3 ~/perch/Scripts/wss-holder.py send '{"action":"brightness.get"}'
python3 ~/perch/Scripts/wss-holder.py send '{"action":"classify","text":"mute","mode":"rules"}'
```

## 2. Small model on the sandbox (CPU only, $0)

Any OpenAI-compatible chat endpoint works. Two options; pick what the sandbox allows.

**ollama, user-mode tarball (no root):**

```sh
mkdir -p ~/ollama && cd ~/ollama
curl -fsSL https://ollama.com/download/ollama-linux-amd64.tgz | tar xz
nohup ./bin/ollama serve >> ~/ollama/serve.log 2>&1 &
./bin/ollama pull gemma3:1b            # ~800 MB, no thinking mode
./bin/ollama pull qwen2.5:1.5b-instruct # alternative
export FASTLANE_LLM_URL=http://127.0.0.1:11434/v1/chat/completions
export FASTLANE_LLM_MODEL=gemma3:1b
```

Avoid thinking-mode models (qwen3) here: ollama ignores `chat_template_kwargs`, so
they would spend seconds reasoning before the one-line answer.

**llama.cpp server (if ollama cannot run):** download a `llama-server` release binary
and a small instruct GGUF (gemma-3-1b-it Q4, or Qwen2.5-1.5B-Instruct Q4), run
`llama-server -m model.gguf --port 8080 -c 2048`, then
`FASTLANE_LLM_URL=http://127.0.0.1:8080/v1/chat/completions FASTLANE_LLM_MODEL=any`.

Warm the model once before measuring:

```sh
python3 ~/perch/Scripts/fastlane/classify.py --json --mode llm "mute"
```

## 3. Classification benchmark (the leg decision)

Run all three from the sandbox. Same test set, same code as the Mac numbers in BENCH.md.

```sh
cd ~/perch
# cloud small model, local to the sandbox
python3 Scripts/fastlane/bench_classify.py --set Scripts/fastlane/intents.json --mode llm    --out /tmp/bench-llm-cloud.json
python3 Scripts/fastlane/bench_classify.py --set Scripts/fastlane/intents.json --mode hybrid --out /tmp/bench-hybrid-cloud.json
# gemma on the Mac, through the holder (includes the relayed hop)
python3 Scripts/fastlane/bench_classify.py --set Scripts/fastlane/intents.json --mode llm    --via-holder ~/.perch-bridge/holder/holder.sock --out /tmp/bench-llm-mac-hop.json
python3 Scripts/fastlane/bench_classify.py --set Scripts/fastlane/intents.json --mode hybrid --via-holder ~/.perch-bridge/holder/holder.sock --out /tmp/bench-hybrid-mac-hop.json
```

Decision rule (from SPEC SC2/SC3): a leg needs 0 false fires on the must-fallback subset
and >= 90% on positives; among legs that pass, lowest p50 wins. Paste the four summary
blocks into BENCH.md under "Cloud-side results".

## 4. End-to-end receipt -> readback

First the cold per-command path for the "before" row (run this BEFORE starting the
holder, or restart the holder afterwards, see the one-client rule):

```sh
python3 ~/perch/Scripts/fastlane/bench_before.py --n 5 --ssh-cmd '/tmp/macssh cat ~/.perch-bridge/device.token' --out /tmp/bench-before-cloud.json
```

Then the fast lane:

```sh
python3 ~/perch/Scripts/fastlane/bench_e2e.py --sock ~/.perch-bridge/holder/holder.sock --n 20 --out /tmp/bench-e2e-cloud.json
```

Uses invisible verbs only (brightness.get, then brightness.set to the value just read).
Prints p50/p95 for classify, holder round trip, and total. Paste into BENCH.md.

## 5. Kill switch and cleanup

```sh
python3 ~/perch/Scripts/wss-holder.py stop
rm -f ~/.perch-bridge/device.token         # if the sandbox is being torn down
```

Mac side, if the daemon verb must go: `git checkout -- Scripts/instinct-daemon.lua` then
the reload line in BENCH.md. Funnel kill switch is unchanged:
`tailscale funnel --https=10000 off`.
