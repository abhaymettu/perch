# AGENTS.md

Notes for coding agents working on Perch, a SwiftUI menu bar app for macOS 14+ that shows Claude
usage for one or several accounts. `main` is the shipping app (2.0 onward). The single-account
build with the full panel (sessions, servers, agents, cron, simulators) lives at tag `v1.3`.

## Layout

- `Perch/App/MenuBarController.swift`: status item, popover panel, open and close, the 1 s title
  timer.
- `Perch/Services/LimitsMonitor.swift`: the usage fetch (one account, every 180 s), the
  multi-account feed at `~/.local/state/perch-usage/state.json`, the menu bar title and the owl's
  awake and alert states.
- `Perch/Services/Shell.swift`: subprocesses, with a 10 s watchdog. `LoginItem.swift`: start at login.
- `Perch/Views`: `UsagePopup` (the panel), `AccountCards` (several accounts), `UsageStrip` (one
  account).
- `Perch/Views/Owl`: the menu bar owl. `OwlPose` (the pose and the stance each app state rests in),
  `OwlSpring` (one closed-form spring per pose channel), `OwlAction` (an action is a score of cues;
  `OwlPerformer` plays them), `OwlRepertoire` (every action, and the catalogue of scenes),
  `MenuBarIcon` (the Core Graphics drawing), `OwlDirector` (the display link, idling, events).
- `Perch/Design/Palette.swift`: every color token, adaptive for light and dark. Never hard-code a
  fixed white or black overlay in a view.
- `Perch/Design/PreviewHarness.swift`: frozen demo scenarios for screenshots.
- `Widget/Perch Usage.js`: the Scriptable iOS widget.

## Build and check

```sh
xcodebuild -scheme Perch -configuration Debug build
./shot.sh /tmp/dark.png main                          # every popover state, one PNG
PERCH_APPEARANCE=light ./shot.sh /tmp/light.png main
Scripts/owl-clips.sh /tmp/owl                         # every owl action as an mp4 and a contact sheet
Scripts/bench.py 120                                  # CPU, memory, wakeups of a Release build
```

`PERCH_OWL_DEMO=1` plays the whole owl catalogue in the real menu bar, and `PERCH_OWL_TRACE=<file>`
logs, per stretch of motion, which display link drove it, the frame rate, missing frames, how late
the main thread got to a frame, and draw times.

Debug builds run `selfCheck()` assertions at launch (`LimitsMonitor`, `MenuBarIcon`, `Shell`). A
failed assertion crashes the harness before it writes a PNG, which is the test failure. Run a
Debug build after touching any of those files.

## Rules

- **Cost is a feature.** Rerun `Scripts/bench.py` after changing the poll loop, the title timer or
  the owl, and update the README table if the numbers move.
- **Never run a test build under the shipping bundle id** (`com.abhaymettu.perch`). Override it, as
  `Scripts/bench.py` does, so an installed Perch is never touched. `shot.sh` only kills the copy
  it built.
- **Privacy.** The only network call is the usage fetch in `LimitsMonitor`. Do not add another
  without updating the README's privacy table. The feed is read, never written.
- **Every owl action has a job.** A new one goes in `OwlRepertoire` with a scene in `catalogue`, so
  the launch check walks its bounds and the clip script films it, and a line in the README table
  saying what it tells the user. Reactions end by handing every channel back with `rest`.
- **Meaning is never colour alone.** Every amber state also says it in words or shape.
- **README pictures are staged.** Regenerate with `PERCH_UI_PREVIEW=hero` and
  `PERCH_APPEARANCE=light|dark` (`PERCH_HERO=hot` for a spent week), never from a real machine:
  `PERCH_APPEARANCE=dark ./shot.sh .github/hero-dark.png hero`.
- **Releases** come from `Scripts/release.sh <version>` (ad-hoc signed, zip and DMG plus
  SHA256SUMS) and are attached to a `v<version>` GitHub release.
- No em dashes in prose, comments or commit messages.
