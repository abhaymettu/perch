# Tasks: Jarvis fast lane

Plan: `docs/fastlane/PLAN.md`. [P] = can run in parallel with its neighbours.

## Phase 1: spec (done before this file)
- [x] T01 SPEC.md, PLAN.md, TASKS.md

## Phase 2: build legs (parallel, Sonnet subagents)
- [x] T02 [P] `Scripts/wss-holder.py`: RFC 6455 client, hello/since, 20/40 s liveness,
      jittered backoff, spool + replay, unix-socket IPC, token fetch, `serve|send|status`
      CLI, importable `submit()`. Self-test against the funnel from the Mac.
- [x] T03 [P] `Scripts/fastlane/classify.py` + `intents.json` (~60) + `bench_classify.py`.
      Run rules-only and gemma-on-Mac (magnitude, local) legs; record numbers.
- [x] T04 [P] daemon orch verb `classify` in `Scripts/instinct-daemon.lua`; live reload
      via the install script's `hs -c` line; readback-verify with a WS client.

## Phase 3: integrate and measure (orchestrator)
- [x] T05 `bench_before.py`: relayed ssh token fetch + cold dial + verb, N=5.
- [x] T06 `bench_e2e.py`: utterance -> classify -> holder -> readback, N=20, p50/p95.
- [x] T07 classification leg via daemon `classify` through the holder (hop included).
- [x] T08 `docs/fastlane/BENCH.md` with all numbers, staged kill, canary note.
- [x] T09 `docs/fastlane/CLOUD-STEPS.md`: model install options, harness run, holder
      install + nohup + restart, token fetch, socket path, smoke test.

## Phase 4: close
- [x] T10 ponytail review, act on findings.
- [x] T11 grep the repo for the token value; commit locally; no push.
- [ ] T12 `lane-exit.sh fastlane`.
