# Perch: how much of my Claude week is left, on every account

Perch is an owl in the Mac menu bar that shows how much of your Claude week is gone, for every
account you use, and when each one resets. It is free and MIT licensed, and it installs from a DMG
or with `brew install --cask abhaymettu/tap/perch`.

## Why it exists

I run two Claude accounts and kept opening the usage page to see which one still had room this
week. Perch puts that number next to the clock. Click the owl and you get every account, its plan,
how much of the week is used and when it resets.

Perch 1.3 did a lot more. It listed Claude Code sessions, dev servers, LaunchAgents, cron jobs and
simulators in one big panel. In 2.0 I cut all of that and kept the one thing I opened it for. The
old panel is still on the [v1.3 tag](https://github.com/abhaymettu/perch/tree/v1.3).

## What it shows

Each account gets one section: the name with its plan beside it in small grey type, the share of
the week already used, and the time until the week resets. The Fable week sits on one quiet line
underneath with its own small meter. Beside the owl in the menu bar is the week's percent used for
the account you pick, the way the battery item shows its charge. Click an account in the popover
to put it there.

Perch draws only what exists. There is no 5-hour session window any more, so there is no session
row, and a window that is not reported is left out instead of shown as a blank or a 0. Trouble is
said in words, never by colour alone. A spent week reads "limit reached" in amber, a reading older
than 15 minutes says "Stale" with its age, and a signed-out account collapses to one line that says
so.

## One account or several

With one account, Perch reads your usage itself. It takes the OAuth token Claude Code keeps in your
login Keychain, holds it only for the request, and asks Anthropic's usage endpoint once every 180
seconds. That request is the only network call Perch makes.

With several accounts, the sections come from a JSON file at `~/.local/state/perch-usage/state.json`
that a separate poller writes, each account checked with its own Keychain item. Perch never sees
those tokens. It reloads the file whenever it changes. Perch does not ship the poller, and anything
that writes the file works; the [README](README.md) has the shape.

## Install

Download `Perch-2.0.dmg` from the [latest release](https://github.com/abhaymettu/perch/releases/latest)
and drag it to Applications. Perch is not notarized yet, so a downloaded copy needs one command
before macOS will open it:

```
xattr -dr com.apple.quarantine /Applications/Perch.app
```

Or install it with Homebrew, which clears that flag for you:

```
brew install --cask abhaymettu/tap/perch
```

It needs macOS 14 or later and runs on Apple silicon and Intel.

## What it costs

A menu bar app runs all day, so its own cost matters more than any feature. `Scripts/bench.py`
builds a Release copy under its own bundle id, runs it with the popover closed and reports CPU,
memory and wakeups, so anyone can rerun it without touching an installed Perch.

On an M4 Pro running macOS 26 with about 1,170 processes, two minutes per run, Perch used 0.18% of
one core and 23 MB with the owl still, counting the `security` and `claude --version` processes it
spawns. With the owl idling it used 2.1% and 125 MB, and woke 32 times a second instead of 1.8.

## What a skeptic should poke at

The cost numbers come from one machine, one run each, with the popover closed, and memory moves
between runs. The usage figures come from an undocumented Anthropic endpoint that can change. If it
breaks, Perch says "Usage unavailable" instead of guessing. Several accounts need a poller that
Perch does not include. And the app is ad-hoc signed, not notarized, which is why the install needs
the quarantine step.

Repo: https://github.com/abhaymettu/perch
