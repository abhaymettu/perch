<h1 align="center">
  <img src=".github/icon.png" width="144" alt="" /><br />
  Blink
</h1>

<p align="center">
A little robot that lives in your menu bar and keeps an eye on everything running on your Mac —
Claude Code sessions, dev servers, background agents, cron jobs, simulators, and how much of your
Claude usage limit is left.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" />
  <img src="https://img.shields.io/badge/Swift-5-orange" />
  <img src="https://img.shields.io/badge/license-MIT-green" />
</p>

<p align="center">
  <img src=".github/screenshot.png" width="360" alt="The Blink panel: usage strip, Claude sessions, dev servers, daemons and simulators" />
</p>

> **This is a fork.** [megootronic/Blink](https://github.com/megootronic/Blink) is the original and
> covers dev servers and simulators. This fork adds Claude Code session tracking, LaunchAgents,
> cron, and a usage strip. Everything upstream does still works the same way.

## Features

**Added in this fork**

- **Claude Code sessions** — one row per session, not per process, grouped by kind and working
  directory. Remote-control lanes, interactive terminals, and headless `--print` runs are told
  apart and aged separately, because a lane idle for two days is normal and a headless run alive
  for seventeen hours is not.
- **Usage limits** — session and weekly windows as percent-of-limit, with the time until each
  resets. The leading number rides in the menu bar next to the robot.
- **Background agents** — every LaunchAgent in `~/Library/LaunchAgents`, with its schedule and
  whether it is running, idle, or has failed. Read-only on purpose (see below).
- **Cron** — active crontab lines with their schedule. Auto-hides when the crontab is empty.
- **Collapsible sections** — each section folds away and remembers that it did.

**From upstream**

- **Live server monitoring** — every dev server running, with port, framework and project name
- **Restart without leaving the menu bar** — stop and relaunch in one click
- **Failures explained in place** — when a restart doesn't come back, the row shows why
- **Framework detection** — Next.js, Vite, Nuxt, Remix, Astro, Django, Flask, Rails and more
- **Simulator tracking** — booted simulators with device, runtime, and the app running inside
- **Start at login**

## Install

No release build. Clone it and build with Xcode 15 or later:

```
git clone https://github.com/abhaymettu/blink-fork.git
cd blink-fork
xcodebuild -scheme Blink -configuration Release build
```

Or open `Blink.xcodeproj` and hit run. Requires macOS 14 (Sonoma) or later.

For prebuilt binaries of the original, without the Claude features, use
[upstream's releases](https://github.com/megootronic/Blink/releases/latest).

## Network and privacy

Upstream Blink makes no network requests at all. **This fork makes one**, and only if you use
Claude Code:

- Every 180 seconds it `GET`s `https://api.anthropic.com/api/oauth/usage` to read your rate-limit
  percentages. Nothing is sent but the request itself.
- It authenticates with the OAuth token Claude Code already stores in your login Keychain, read
  per-request via `/usr/bin/security` and held only for the length of the request. The token is
  never written to disk, never logged, and never sent anywhere except Anthropic.
- If the token is missing or expired, the usage strip hides itself and nothing else changes.

Everything else — processes, ports, agents, simulators — is read locally. No telemetry, no
analytics, no update check, no elevated permissions, no background daemon.

## Why the agents are read-only

Blink will show you a LaunchAgent's state but will not start, stop, or unload it. A menubar panel
is the wrong place for a control whose misfire takes down something you rely on and gives you no
way to bring it back. Reveal the plist and use `launchctl` if you mean it.

Claude sessions and dev servers *are* killable — those are cheap to restart.

## How It Works

Blink polls every few seconds using standard macOS tools:

- **Port scanning** — `lsof` to find listening TCP ports
- **Process classification** — `ps`, matching on `argv[0]` and the resolved binary, never a
  substring search over the full argument string
- **Project names** — reads `package.json`, `Cargo.toml`, or falls back to the directory name
- **Agents and cron** — `launchctl list` cross-referenced against the plists on disk, and `crontab -l`
- **Simulators** — `xcrun simctl` for booted simulator data

Restarting is less obvious than it sounds. The process holding a port often can't be relaunched
from its own arguments — Next.js and npm both overwrite their `argv` with a display title, and
`argv[0]` is usually a bare name like `node` rather than a path. So Blink reads the real arguments
and the resolved binary from the kernel, and walks up the parent chain to find a process that can
actually be launched again, never straying outside the server's own project directory.

## Tech

- SwiftUI, in an `NSPanel` hung off an `NSStatusItem`
- Swift concurrency (async/await, `TaskGroup`)
- `@Observable` for reactive state
- `SMAppService` for start at login
- macOS 14+ (Sonoma)

Design work happens in a preview harness rather than the live panel — the panel is invisible to
Accessibility and awkward to screenshot. Set `BLINK_UI_PREVIEW` and the app opens a window
rendering every UI state side by side. See `Blink/Design/PreviewHarness.swift`.

## Contributing

PRs welcome. Keep it clean.

1. Fork it
2. Create your branch (`git checkout -b feature/thing`)
3. Commit (`git commit -m 'Add thing'`)
4. Push (`git push origin feature/thing`)
5. Open a PR

## Credits

Original by [Mo](https://mo.software) — [megootronic/Blink](https://github.com/megootronic/Blink).
Claude session, usage, agent and cron support added in this fork.

## License

MIT, same as upstream.
