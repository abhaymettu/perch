# Perch owl bounds and motion, combined numbers-only build (lane perch-owl-10091147), 2026-10-09

**Status: built, tested and staged. NOT installed.** The install is held for the owner. The prior
install was denied as [Auto-Mode Bypass]; this lane did not retry it or route it anywhere else.

## What changed (usage-only ff2c5b0, on top of numbers-only 4f3fc38)

- **Cause of the clipping (owner 11:43:11).** `MenuBarIcon` drew on a 22x22 pt canvas around a
  21.08 pt face, which left 0.46 pt per side. The bob leans the head 2.8 base units (2.57 pt), so
  the face's left edge reached about -2 pt and was cut off.
- **Fix.** The canvas is now **30x22 pt**. The owl art is unchanged: same 22 pt scale, face size,
  features and tint. Its centre moved from 11 to 15 pt, still a whole point, so the resting owl
  draws as before. Height stays 22: lift and squash fit with 2.5 pt or more spare.
  - `faceRect(for:)` is now one shared static, used by both the render and the bounds check.
- **Motion smoothing (same moves, no new ones).**
  - `MenuBarIconAnimator.play` poses each frame at `ContinuousClock` elapsed time. It used to
    count sleeps, and each sleep plus render runs past 1/60 s, so moves drifted slow and stuttered.
  - Bob phase is eased with smoothstep. The bare sine left rest, and landed back on it, at full
    speed. The dip is `sway²` instead of `|sway|`, which kinked at the centre crossing.
  - Blink, peek, swivel and startle curves are unchanged.
- **Numbers-only (owner 11:40:24) kept.** The menu bar shows the owl plus "S x% · W y% used" only.
  Signed out, "· stale" and "Account not found" still show as honest states; see the
  `menu-bar-items.png` crop. Owl, Fable and account picker are untouched.

## Checks run (all this session)

| Check | Result |
|---|---|
| Debug `MenuBarIcon.selfCheck()` at the **old 22 pt** canvas | **fails** (`selfcheck-fail-22pt.log`): `owl blink at 0ms: face (0.458…) leaves (0,0,22,22) inset 0.875` |
| Same selfCheck at 30 pt (also `LimitsMonitor.selfCheck` and `Shell.selfCheck`) | passes, exit 0 (`selfcheck-pass-30pt.log`) |
| selfCheck content | every move both ways (blink, blink x2, peek L/R, bob, swivel L/R, startle) sampled every **1 ms**: face plus half the shadow stroke stays ≥0.5 pt inside the canvas. Every **60 fps frame** is also rendered, and its outer pixel ring must have zero alpha and its size must be 30x22 |
| Rendered filmstrip, every frame of every move (`filmstrip-every-frame.png`) | 411 frames, inspected by eye plus measured ink clearance at 2x: bob min L/R **3 px (1.5 pt)**; every other move min 8 px L/R; top ≥8 px, bottom ≥5 px. No frame touches its swatch edge |
| Zoomed bob/peek frames (`bob-zoom.png`) | glass squircle, sliced eyes and beak intact in every frame; style unchanged |
| Test targets | the project has one target (`Perch`) and no XCTest; the Debug selfChecks are the test suite |
| Release build of ff2c5b0 | `BUILD SUCCEEDED`; ad-hoc signed, `codesign --verify --deep --strict` OK; the Release binary has no debug-check strings (`strings | grep` 0) |

Evidence: `/Users/abhay/scratch/perch-usage-only-20261006/owl-evidence/` (preview-full.png,
filmstrip-every-frame.png, bob-zoom.png, menu-bar-items.png, both selfcheck logs).

## Staged build

- App: `/Users/abhay/scratch/perch-usage-only-20261006/stage/Perch.app` (ditto copy of
  `owl-build/Build/Products/Release/Perch.app`)
- Binary sha256: **4a0e0e22e0cf9fe81d262b08d7905fa12df5e1b95023890a178cfd69158169ee**
- Source: usage-only **ff2c5b0** (tree 17ec90cd94). Main **6fe0539** merges it with the identical
  tree. Local only: nothing pushed or deployed.
- Live now (checked 11:56): `/Applications/Perch.app` sha256
  343150568aacff72943116f60b496f0a2746b7e3a60c4dc41999650668b82da5, pid 91739.

## OWNER-RUN install (held; not executed by this lane)

```
bash ~/scratch/perch-usage-only-20261006/owl-install.sh
```

The script uses `set -euo pipefail`. Every check runs before anything moves:
1. Staged hash must equal 4a0e0e22…69ee, and the staged app must pass codesign.
2. The installed hash must equal 34315056…2da5.
3. The backup path `Perch.app.backup-0825cb9-34315056-<timestamp>` must not already exist.
4. Quit: `pgrep -fx` on the exact command line `/Applications/Perch.app/Contents/MacOS/Perch`.
   More than one match aborts. The script sends SIGTERM to that one PID and waits 5 s; if it is
   still alive, it aborts with nothing moved.
5. Swap: it moves the old app to the backup, then `ditto` the staged app in and re-checks the
   hash and codesign. On any failure an ERR trap puts the old app back and relaunches it.
   Finally `open -g`.

Rollback: `bash ~/scratch/perch-usage-only-20261006/owl-rollback.sh`. It checks that the backup
hash is 34315056…, quits the exact PID the same way, moves the owl build aside (kept, never
deleted), restores the backup, re-checks the hash and runs `open -g`.

Fixture tests ran on a copy of the live app, with `PERCH_APP`, `PERCH_BASE` and `PERCH_STAGED`
overridden and `PERCH_OPEN=echo`. /Applications was never touched; it was re-checked as
34315056 / pid 91739 after every test.
- A, tampered staged: ABORT, nothing moved.
- B, install: fixture becomes 4a0e0e22, backup is 34315056.
- C, re-run: ABORT, because the installed hash is no longer 34315056.
- D, rollback: fixture becomes 34315056 again, owl build kept aside as 4a0e0e22.
- E, rollback again: ABORT, no record.
- F, quit block on a compiled dummy at the fixture path: killed exactly that PID (SIGTERM 143).
  With two matching processes it aborted and both stayed alive.
- G, `ditto` failing (PATH shim) after the move: the trap restored the old app (34315056), exit 1.

## Held / open

- **Install**: owner-run only. The coordinator reviews the diff and pixels, then returns the
  command above to the owner.
- **Live pixels across motion frames**: needed from the owner's real menu bar after install,
  before anyone calls this DONE. The canvas adds 8 pt to the status item, so the title sits
  about 4 pt further right of the owl; that is his visual call.
- Ponytail review: on round 1 the string-matched alert flag was fixed. Kept, with the reasons in
  `#review-ack`:
  - The 1 ms sweep: clock-timed frames land at any t.
  - The every-frame filmstrip: the brief requires it, and the old 7 samples skipped the bob.
  - smoothstep over easeInOut: 1.5x rather than 2x speed at the centre crossing.
- The repo's `shot.sh` runs `pkill -f "Perch.app/Contents/MacOS/Perch"`, which also kills the
  live app. This lane used a scratch copy without the pkill. Follow-up: fix shot.sh (not in this
  scope).
