# Perch: what is running on my Mac, and what it costs to ask

Perch is a menu bar app for people who run Claude Code all day. One click shows every Claude Code
session, dev server, LaunchAgent, cron job and booted simulator on the machine, plus how much of
the Claude usage limit is left. It is free, MIT licensed, and installs with
`brew install --cask abhaymettu/tap/perch`.

## The problem

Agents multiply processes. On the machine this was built on there were between 30 and 100 `claude`
processes alive at any moment, spread across remote-control lanes, terminals and headless runs.
`ps aux | grep claude` printed 315 lines against 34 real processes, because the pattern matches a
path inside every unrelated shell. Which sessions are still working, which have been stuck for
seventeen hours, and which dev server is holding port 3000 are questions you end up answering by
hand.

Perch groups processes into sessions by walking the process tree, tells the three kinds of Claude
session apart, and judges each against its own clock: a lane idle for two days is normal, a
headless run alive for four hours is stale. When something goes stale or fails, the owl in the menu
bar turns amber.

## The part worth reading: a monitor that was heavier than what it watched

A menu bar app runs every minute of the day, so its own cost matters more than any feature. The
first full build of Perch, measured on a busy machine, used **64% of a CPU core** (counting
the `ps` and `lsof` processes it spawned) and held **352 MB** of memory after five minutes. Three causes,
each found with a measurement rather than a guess:

1. **Rendering nobody could see.** `heap` showed 17,000 CoreGraphics glyph bitmaps. The panel was
   closed, but every poll still animated its counters inside it, and SwiftUI rasterized that text on
   the CPU. The fix mounts the panel's views only while it is open.
2. **A process per session.** Each session's working directory came from its own `lsof`, every
   three seconds. With 100 sessions, that is 100 `lsof` runs per tick. Perch now asks the kernel
   (`proc_pidinfo`), and the answer matched `lsof` on 39 of 40 live sessions; on the 40th, `lsof`
   returned nothing.
3. **Polling for an audience of none.** Scans run every 15 seconds while the panel is closed and every
   3 while it is open, and the owl only animates when the menu bar is actually on screen.

After: **1.6% CPU and 20 MB** with the owl still, **3.6%** with it idling (memory with the owl
idling varied between runs, 25 to 122 MB). Those are heavy-load figures: CPU and wakeups rise with
the number of processes the scans walk, and a lighter-load rerun of the owl-still case measured 0.82%
CPU and 1.7 wakeups a second. Every number
comes from `Scripts/bench.py`, which builds its own copy under a separate bundle id, so anyone can
rerun it without touching an installed Perch.

## What a skeptic should poke at

The numbers come from one machine, and the closed-panel case is the one measured. The usage figures
come from an undocumented Anthropic endpoint that can change. The app is not notarized yet, so the
Homebrew cask clears the quarantine flag on install.

Repo: https://github.com/abhaymettu/perch
