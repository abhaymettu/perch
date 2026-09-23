# Perch diet

Perch was sold as a lightweight menu bar app but used far too much CPU. This is what was measured, what caused it, and what changed.

## How it was measured

Both builds are Release, built from this repo, with `CODE_SIGNING_ALLOWED=NO`. "Before" is `5183857`; "after" is this branch. Each build was launched from its own binary alongside the installed `/Applications/Perch.app`, which was left alone. The menu stayed closed for the whole measurement. For each run:

- **Launch**: the time from `exec` until the app's status item exists, polled through Accessibility (`AXExtrasMenuBar` gets a child). 5 launches per run.
- **15 s settle**, then **60 s idle**. During that minute:
  - `top -l 61 -s 1 -stats pid,cpu,mem,power,threads`: CPU %, memory (phys footprint), and threads.
  - `powermetrics --samplers tasks --show-process-energy -i 1000 -n 60`: CPU ms/s, interrupt wakeups/s, and energy impact.
  - `eslogger exec`: every process Perch spawned.
- `sample` for 3 s, to see what is running.

Three runs per build, alternating before and after (b1 a1 b2 a2 b3 a3), because the Mac had other load. The table shows the mean of the three runs. The one exception is launch, which is the median of 15.

## Before / after

| Metric (idle, menu closed) | Before | After | Change |
|---|---|---|---|
| Idle CPU, Perch process (`top`) | 8.75 % | 1.56 % | -82 % |
| CPU time, Perch process (`powermetrics`) | 90.0 ms/s | 26.6 ms/s | -70 % |
| Child processes spawned | 1,729 / min | 10.7 / min | -99.4 % |
| CPU burned in those children (est.) | ~15 s / min (~25 % of a core) | ~0.1 s / min | ~-99 % |
| Wakeups (interrupt, `powermetrics`) | 57.4 /s | 33.3 /s | -42 % |
| Energy impact (`powermetrics`) | 296.8 | 68.1 | -77 % |
| Memory, phys footprint | 58 to 203 MB, sawtooth | 18 to 24 MB, flat | about -85 % at the peak |
| Threads | 18.3 | 6.5 | -64 % |
| Launch to menu bar icon | 173 ms | 125 ms | -28 % |

Per-run numbers (top CPU % / ms/s / wakeups/s / energy / spawns):

- Before: 9.44 / 98.4 / 60.4 / 323 / 1775 · 8.50 / 85.3 / 57.0 / 283 / 1707 · 8.31 / 86.1 / 54.7 / 283 / 1705
- After: 1.20 / 22.5 / 32.1 / 49 / 12 · 2.06 / 36.0 / 34.0 / 106 / 12 · 1.43 / 21.2 / 33.9 / 49 / 8

Notes on the table:

- **Child CPU is estimated.** `lsof -d cwd -a -p <pid>` costs 0.010 s of CPU (measured three times with `/usr/bin/time`). About 1,500 of them ran each minute, one per Claude session on every 3 s poll: ~61 sessions × 20 polls, plus servers. That CPU belongs to `lsof`, not to Perch, so Activity Monitor never showed it on Perch's row. It is most of why the Mac felt loaded.
- **The owl pauses while nobody is at the Mac** (details under the fourth cause below). During all three "after" runs, no one had touched the keyboard or mouse for 2 minutes or more (input-idle was 529 s, 167 s and 153 s at the starts), so the owl was mostly still. An earlier after-build run, with the owl animating freely while someone was using the Mac, measured **1.96 % CPU, 27 ms/s, 37 wakeups/s, 69 energy, 52 to 56 MB flat**. A second run under the same conditions read 2.81 % and 42 ms/s. So with someone at the Mac, expect about 2 to 3 % CPU, against 8 to 10 % before.
- **Memory**: the "after" floor is low partly because the panel is no longer built until the first click. Once it has been opened, the process sits around 55 MB. That is still flat, where before it was a 60 to 200 MB sawtooth.
- **Wakeups** that remain mostly belong to AppKit and the status item, plus the owl while it is animating. The 30 s scan and 60 s title tick are timers with tolerance, so the system can batch them with other wakeups.

## What was causing the load

Found with `sample`, `eslogger` and the per-second `top` series, in order of cost:

1. **One `lsof` per Claude session per poll.** `ClaudeScanner` resolved each session's working directory with `lsof -d cwd`, and `ServerScanner` spawned a `ps` and an `lsof` for every dev server. All of this ran every 3 s whether the menu was open or not. With about 60 sessions on this Mac, that came to 1,700 processes a minute.
2. **`Shell.run` blocked the Swift concurrency pool.** It called `readDataToEndOfFile()` and `waitUntilExit()` inside a continuation on the cooperative pool. `waitUntilExit` spins a run loop while it waits. This is the "12 threads busy on `com.apple.root.user-initiated-qos.cooperative`" from the original profile: each thread was parked on a child process.
3. **Everything polled every 3 s while the panel was closed.** The poll ran `ps`, `lsof -iTCP`, `xcrun simctl` (two processes plus a CoreSimulator spin-up, even with no simulator booted), `launchctl list` and `crontab -l`. A separate 1 s timer re-checked the icon state and the panel height.
4. **The owl redrew through a fresh GPU renderer at 60 fps.** Each frame called `ImageRenderer.cgImage`, which brings up a RenderBox/Metal renderer. That was the Metal work seen while nothing was on screen. Each call also allocated a ~100 MB transient, which caused the 60 to 200 MB memory sawtooth in the "before" `top` series. Idle moves play every 1.6 to 4.4 s, so this ran constantly.
5. **The panel was built at launch** and re-laid itself out offscreen on every state change. The empty state's `repeatForever` loops also kept running after the panel closed.

No third-party dependencies were present (no SwiftPM packages), so there was nothing to drop.

## What changed

- **`ProcessResolver`**: a session's or server's working directory now comes from `proc_pidinfo(PROC_PIDVNODEPATHINFO)`, and a server's argv from `KERN_PROCARGS2` (the same source `ps` reads). Neither spawns a process. Checked against `lsof` and `ps` for all 61 live Claude PIDs and 12 listening PIDs: the output was identical. The dead `parseCWD` is gone.
- **`Shell.run`**: the blocking read happens on a GCD utility thread, not the concurrency pool, and `waitUntilExit` is gone. EOF means the child is done, and Foundation reaps it. The run showed no zombies.
- **`AppState`**: polls every 3 s only while the panel is open. While it is closed, it polls every 30 s with 6 s timer tolerance. It also refreshes right away when the panel opens and (coalesced over 2 s) on app launch, app quit and wake. While the menu is closed, the only things the menu bar shows are whether the owl is awake and whether it is red. Nothing there needs a 3 s poll.
- **`SimulatorMonitor`**: skips `xcrun simctl` unless a `launchd_sim` process exists. Every booted simulator runs one, with or without Simulator.app. This was tested by booting a throwaway simulator: the check went true, both builds listed it, and the simulator was then deleted.
- **`MenuBarController`**:
  - The 1 s timer is replaced by `withObservationTracking` on `isActive`, `hasProblem` and the quota title, plus a 60 s tick (10 s tolerance) for the minute-granular reset countdown and a session going stale.
  - The panel is built on first click. One forced layout pass lets the first open land at full height; this was measured at 710 px from the first 20 ms, with no grow.
  - It tells `AppState` when the panel opens and closes.
- **Owl (`MenuBarIcon`, `MenuBarIconAnimator`, `OwlMotion`)**:
  - Frames render into a 44×44 CPU bitmap (`ImageRenderer.render` into our own `CGContext`) rather than `renderer.cgImage`. On-screen output was compared against the old build and matches.
  - Each move variant (blink, double blink, peek ±, bob, swivel ±, startle) and each resting pose is rendered once, then replayed from a cache of a few hundred small bitmaps (about 3 MB).
  - Idle moves stop while no input has arrived for 2 min: the loop sleeps in 30 s steps and plays nothing. Reactions (the startle when something goes red) and awake/asleep changes still draw immediately.
- **`EmptyStateView`**: its `repeatForever` drift stops when the panel closes and restarts on open, as before.
- **`LimitsMonitor`**: the 180 s usage fetch gets 30 s of timer tolerance.

Every feature still behaves as before: all scanners, the red owl, the quota title and countdown, restart and kill actions, the simulator rows, the bridge tasks, and the usage widget feed. The panel still refreshes every 3 s while it is open. The trade-off is that a change made while the menu is closed takes up to 30 s to reach the owl, unless an app launch or quit triggers a refresh first. Opening the menu always refreshes first.
