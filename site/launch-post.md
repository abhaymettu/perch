# Launch post draft (for Abhay to send himself)

## X

perch 2.0: an owl in your menu bar with how much of your claude week is gone, for every account,
and when each one resets.

i cut everything else from 1.3. now it sits at 0.18% cpu. github.com/abhaymettu/perch

## Longer (HN or a blog)

I run two Claude accounts and kept opening the usage page to see which one still had room this
week. Perch 2.0 puts that number next to the clock. Click the owl and each account gets one
section with its plan, the share of the week used, and when it resets. Click an account to put
its percent in the menu bar.

Perch 1.3 also listed Claude Code sessions, dev servers, LaunchAgents, cron jobs and simulators.
2.0 drops all of that, and the old panel stays on the v1.3 tag. With the popover closed it uses
0.18% of one core and 23 MB with the owl still, and `Scripts/bench.py` reproduces the numbers.
The usage figures come from an undocumented Anthropic endpoint, so they can break.

Download the DMG from the releases page, or `brew install --cask abhaymettu/tap/perch`.
