<h1 align="center">
  <img src=".github/icon.png" width="128" alt="" /><br />
  Perch
</h1>

<p align="center">
An owl in your menu bar that shows how much of your Claude week is gone, for every account you
use, and when each one resets.
</p>

<p align="center">
  <a href="https://github.com/abhaymettu/perch/releases/latest"><img src="https://img.shields.io/github/v/release/abhaymettu/perch?label=release" alt="Latest release" /></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14 or later" />
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT license" />
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset=".github/hero-dark.png" />
    <img src=".github/hero-light.png" width="520" alt="The Perch popover under its menu bar owl: two Claude accounts, each with its plan beside the name, the week's percent used, when it resets, and the Fable week underneath" />
  </picture>
</p>

I run two Claude accounts and kept opening the usage page to see which one still had room this
week. Perch puts that number next to the clock. Click the owl and you get every account, its
plan, how much of the week is used and when it resets.

## Install

Download `Perch-2.0.dmg` from [Releases](https://github.com/abhaymettu/perch/releases/latest) and
drag it to Applications. Perch is not notarized yet (see [Limits](#limits)), so a downloaded copy
needs one command before macOS will open it:

```sh
xattr -dr com.apple.quarantine /Applications/Perch.app
```

Requires macOS 14 (Sonoma) or later. The build is universal, Apple silicon and Intel.

## What it shows

- **One section per account.** The name, its plan beside it in small grey type ("Ultra"), the
  share of the week already used, and the time until the week resets. The Fable week sits on one
  quiet line underneath with its own small meter.
- **The menu bar number.** Beside the owl, the week's percent used for the account you pick,
  the way the battery item shows its charge. Click an account in the popover to put it in the
  menu bar. A filled ring and the words "In menu bar" mark the one that is there.
- **Only what exists.** There is no 5-hour session window any more, so there is no session row.
  A window that is not reported is not drawn, never shown as a blank or a 0.
- **Trouble, in words.** A spent week reads "limit reached" in amber. A reading older than 15
  minutes says "Stale" with its age. A signed-out account collapses to one line that says so.
  Colour never carries the meaning on its own.

The popover follows the system's light or dark appearance on the standard popover material. The
footer says when the newest reading landed, and the ⋯ menu holds Start at Login, the usage page
and Quit.

## One account or several

With one account, Perch reads your usage itself (see [Privacy](#privacy)). The first time, macOS
may ask whether `security` may read `Claude Code-credentials`. Choose **Always Allow**.

With several accounts, the cards come from a feed: a JSON file at
`~/.local/state/perch-usage/state.json` that a separate poller writes, checking each account with
that account's own Keychain item. Perch never sees those tokens. It reloads the file whenever it
changes, and switches to the account list once the file holds more than one account. The shape:

```json
{
  "account": "acct2",
  "accounts": {
    "acct1": {
      "label": "Main account",
      "plan": "Ultra",
      "status": "live",
      "observed_at": "2026-11-03T09:40:00Z",
      "weekly": { "usage_percent": 100, "severity": "normal", "resets_at": "2026-11-06T22:00:00Z" },
      "models": { "fable": { "usage_percent": 4, "resets_at": "2026-11-06T22:00:00Z" } }
    },
    "acct2": { "label": "Second account", "plan": "Ultra", "status": "live", "...": "..." }
  }
}
```

`account` is the default for the menu bar. `status` is `live`, or `removed-needs-reauth` for an
account signed out of this Mac. Missing pieces drop out rather than failing the file. Perch
does not ship the poller; anything that writes this file works.

## The owl

<p align="center">
  <img src=".github/menubar.png" width="264" alt="The Perch status item in the macOS menu bar: the owl beside 65%" />
</p>

The glyph is not an image asset. A status item is a 22 pt bitmap, which rules out Lottie, GIF and
SVG, so the owl is a vector drawing, redrawn for every frame it moves and not at all while it sits
still.

Each part of the pose (the turn of the head, its tilt, the eyelids, the amber tint) rides its own
spring, and a behaviour is a short score that tells the springs where to go. Nothing is a fixed
keyframe, so one behaviour can cut into another and the head carries on from wherever it was. Its
features ride a cylinder inside the head, so a turn foreshortens the eyes and carries the far one
out of sight. Halfway round you are looking at the back of its head.

Mostly it sits still. Every few seconds it does one small thing and goes back to rest: usually a
blink, sometimes a glance to one side, a tilt of the head, a slow sideways sway with the face held
level, a shake of its feathers, and now and then a full turn.

<p align="center">
  <img src=".github/owl.png" width="640" alt="Filmstrips of the owl tilting its head, startling, and cheering a new week" />
</p>

The rest of what it does means something:

| The owl | What happened |
|---|---|
| Sits with its eyes half shut | No reading yet, or the account you picked is signed out |
| Wakes: lids lift, two blinks, a stretch | The first reading arrived |
| Looks at the number | The percent beside it just changed |
| Looks, looks away, looks again with wide eyes | The week crossed into warning |
| Startles and turns amber | A window turned critical, or the reading went stale |
| Shuts its eyes and breathes out | The problem cleared |
| Hops twice, eyes arched | The week rolled over |
| Dips, then looks down | You clicked it, and the panel is open underneath |
| Turns all the way round | You picked another account. Its number lands while the owl's back is turned |
| Follows your pointer | The pointer is over it |

Under Reduce Motion nothing moves: the owl goes straight to each state and only the amber tint
fades in. Idle motion also stops whenever nobody can see the menu bar. `Scripts/owl-clips.sh out`
films every behaviour from the same code the menu bar runs.

## The iOS widget

`Widget/Perch Usage.js` is a [Scriptable](https://scriptable.app) widget that shows the same
numbers with the same owl. If Scriptable's iCloud folder exists on the Mac, Perch writes
`perch-usage.json` into it after each fetch: percentages and reset times only, never the token.
Copy the script into Scriptable's iCloud Documents folder and add a medium Scriptable widget
pointing at it.

## Privacy

| What | How Perch reads it | Where it goes |
|---|---|---|
| Usage, the account Claude Code is signed in to | The OAuth token Claude Code keeps in your login Keychain, read with `/usr/bin/security` for each request | `https://api.anthropic.com/api/oauth/usage`, once every 180 seconds |
| Usage, several accounts | `~/.local/state/perch-usage/state.json` | Nowhere |
| Your default model name | `~/.claude/settings.json` | Nowhere |
| Widget copy | Written to Scriptable's iCloud folder, if it exists | Your iCloud Drive |

The usage request is the only network call Perch makes. It runs whether you watch one account
or several.
The token is held only for the length of the request and is never written to disk or logged.

## What it costs

A menu bar app runs all day, so its cost is a feature. `Scripts/bench.py` builds a Release copy
under its own bundle id, runs it with the popover closed, and reports CPU, memory and wakeups.
Measured on an M4 Pro running macOS 26 with about 1,170 processes, two minutes each
(`Scripts/bench.py 120` and `Scripts/bench.py 120 --owl`):

| | CPU, Perch plus what it spawns | CPU, Perch alone | Memory | Wakeups |
|---|---|---|---|---|
| Owl still | 0.18% | 0.05% | 23 MB | 1.8 /s |
| Owl idling | 2.1% | 1.9% | 125 MB | 32 /s |

CPU is percent of one core over Perch's whole life, launch included, counting the `security`
and `claude --version` children it spawns. Memory is the physical footprint (what Activity Monitor shows) read once at
the end of the run and moves between runs. Wakeups are per second, steady state. The bench makes real usage requests,
so run it with Claude Code signed in.

## Limits

- **Not notarized.** There is no Developer ID certificate yet, so the app is ad-hoc signed and
  Gatekeeper blocks a downloaded copy until the quarantine flag is cleared.
- **The usage endpoint is undocumented.** Anthropic can change or remove it. If it breaks, Perch
  says "Usage unavailable" instead of guessing.
- **Several accounts need a poller.** Perch reads the feed above but does not write it.

## Build from source

```sh
git clone https://github.com/abhaymettu/perch.git
cd perch
xcodebuild -scheme Perch -configuration Release -derivedDataPath build build
open build/Build/Products/Release/Perch.app
```

Or open `Perch.xcodeproj` in Xcode 16 or later and run. `Scripts/release.sh 2.0` builds the zip
and DMG for a release. Design work happens in a preview harness rather than the live popover:
`./shot.sh out.png main` renders every state side by side to a PNG (add `PERCH_APPEARANCE=light`
for light), and `PERCH_UI_PREVIEW=hero` renders the staged pictures in this README. See
`Perch/Design/PreviewHarness.swift`.

Perch 1.3, the single-account build with the full panel (Claude sessions, dev servers,
LaunchAgents, cron, simulators), is still on the [v1.3 tag](https://github.com/abhaymettu/perch/tree/v1.3).

## Credits

Perch started as a fork of [Blink](https://github.com/megootronic/Blink) by
[Mo](https://mo.software). This build keeps the usage limits and the owl.

## License

MIT. See [LICENSE](LICENSE); the original copyright is kept alongside this one.
