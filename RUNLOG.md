# RUNLOG

Working log for the 1.3 release lane. Newest entries at the bottom.

## 2026-11-01 release lane

- Restored the full panel (sessions, servers, agents, cron, simulators) on branch `release` from 5183857, kept the
  newer 30pt owl, dropped the private bridge section and the unrelated daemon/fastlane scripts and docs.
- Light mode: panel follows the system appearance (`Color.wash`/`Color.sink` tokens, `.popover` material), owl glass
  in ink on light. Port shown as `:3,000` fixed (verbatim text).
- Cost, measured with `Scripts/bench.py` (Release build, bundle id com.abhaymettu.perch.bench, status item hidden):
  baseline 70ef2e6 2-min run: 64% CPU incl. children, 14% self, 339 MB footprint. Causes found: per-session `lsof`
  fan-out (100 claude procs at the time), closed panel still rendering animated text (glyph cache +1 MB/s, seen in
  `heap`/`malloc_history`), owl idling while unseen. After fixes, 300 s, owl still: 2.26% / 0.3% / 21 MB / 2.17
  wakeups/s. Owl-idling and 300 s baseline runs pending in scratch runbench.sh.
- `top` IDLEW is unusable here (does not update even for WindowServer), so wakeups come from proc_pid_rusage.
- In-process cwd checked against lsof on 40 live claude pids: 39 equal, 1 where lsof gave nothing and kernel gave a path.
- Alert owl is now a solid amber chip; hot usage meters amber. Staged hero pictures from `PERCH_UI_PREVIEW=hero`.
- NEXT: fill README cost table, release.sh 1.3, gh release, homebrew-tap repo + cask, fresh-clone check, site/ files.
- 300 s benches (scratch runbench.sh): after, owl still 2.26% / 0.3% / 21 MB / 2.17 wakeups/s; after, owl idling
  3.66% / 2.43% / 25 MB / 29.56; before (70ef2e6), owl idling 74.52% / 17.43% / 234 MB / 52.02.
- Release 1.3 built by Scripts/release.sh: universal, ad-hoc + hardened runtime. zip sha256 da327ef4...77a3.
- Em dashes removed from all tracked files (54 inherited ones in comments and strings).
