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
- Independent review (Opus subagent): bench counted its own xcodebuild in RUSAGE_CHILDREN (numbers above inflated,
  baseline most); Shell.run had no timeout; reopen during close fade lost; open mid-scan skipped rescan. All fixed
  (wait4, 10 s watchdog, isOpen flag, rescanWanted). Wakeups now interrupt_wkups only. Benches rerunning (b2-*.json
  in scratch). check-cwd.sh: kernel and lsof never disagree; lsof blank for 1 to 15 of 40 on a busy machine.
- HANDOFF if context runs out: fill README table + site/writeup.md + site/meta.json + launch-post from b2-*.json,
  rebuild Scripts/release.sh 1.3, update homebrew-tap sha, push main, tag v1.3, gh release create with
  scratch notes-1.3.md + zip + dmg, brew install --cask --appdir=<scratch> test, settle.
- Corrected 300 s benches: owl idling 3.55% / 2.3% / 122 MB / 30.44; owl still 1.6% / 0.3% / 20 MB / 3.14;
  before (70ef2e6) owl idling 64.15% / 18.03% / 352 MB / 46.43. Footprint is a single end-of-run sample and varies
  (owl idling read 25 MB in the first run, 122 MB here); README says so.
