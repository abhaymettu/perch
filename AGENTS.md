# AGENTS.md

Notes for coding agents working on Perch, a SwiftUI menu bar app for macOS 14+.

## Layout

- `Perch/App`: app entry, `MenuBarController` (status item, panel window, open and close).
- `Perch/State/AppState.swift`: the scan loop and every user action (stop, restart, shut down).
- `Perch/Services`: one scanner per source (`ClaudeScanner`, `PortScanner`, `LaunchAgentScanner`,
  `CronScanner`, `SimulatorMonitor`, `LimitsMonitor`) plus `ProcessResolver` (kernel reads) and
  `Shell` (subprocesses).
- `Perch/Views`: the panel. `Perch/Views/Owl`: the menu bar owl and its motion.
- `Perch/Design/Palette.swift`: every color token. Use `Color.wash(_:)` and `Color.sink(_:)` for
  overlays so light and dark both work; never hard-code `.white.opacity` in a view.
- `Perch/Design/PreviewHarness.swift`: frozen demo scenarios for screenshots.

## Build and check

```sh
xcodebuild -scheme Perch -configuration Debug build
./shot.sh /tmp/main.png main      # every panel state, one PNG
PERCH_APPEARANCE=light ./shot.sh /tmp/light.png main
Scripts/bench.py 120              # CPU, memory, wakeups of a Release build
```

Debug builds run `selfCheck()` assertions at launch (`ClaudeScanner`, `LimitsMonitor`,
`LaunchAgent`, `FailureBox`, `MenuBarIcon`, `Shell`). A failed assertion crashes the harness, which
is the test failure. Run a Debug build after touching any of those files.

## Rules

- **Cost is a feature.** Do not add a subprocess per process or per row; read the kernel
  (`ProcessResolver`) instead. Rerun `Scripts/bench.py` after changing the scan loop and update the
  README table if the numbers move.
- **Nothing renders while the panel is closed.** `PanelRoot` mounts `MenuBarView` only while open.
  Keep it that way.
- **Never run a test build under the shipping bundle id** (`com.abhaymettu.perch`). Override it, as
  `Scripts/bench.py` does, so an installed Perch is never touched.
- **LaunchAgents stay read-only.**
- **Privacy.** The only network call is the usage fetch in `LimitsMonitor`. Do not add another
  without updating the README's privacy table.
- **README pictures are staged.** Regenerate with `PERCH_UI_PREVIEW=hero` (and `PERCH_HERO=hot`),
  never from a real machine.
- No em dashes in prose, comments or commit messages.
