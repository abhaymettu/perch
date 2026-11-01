# Launch post draft (for Abhay to send himself)

## X

perch: one menu bar panel for everything running on your mac. claude code sessions, dev servers,
launch agents, cron, simulators, usage limits.

the first build used 75% of a core watching my machine. now under 4%. how: github.com/abhaymettu/perch

## Longer (HN or a blog)

I run a lot of Claude Code sessions at once, and kept losing track of which ones were still alive,
which dev server held which port, and how close I was to the usage limit. Perch puts all of it in
one menu bar panel, with an owl that turns amber when a session goes stale or a server fails to
restart.

The interesting part was the cost. The first full build, measured on a busy machine, used 75% of a
core and held 234 MB, because it spawned an `lsof` per session every three seconds and kept
re-rendering a closed panel. It now uses under 4% and 25 MB, and `Scripts/bench.py` reproduces the
numbers.

`brew install --cask abhaymettu/tap/perch`
