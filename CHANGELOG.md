# Changelog

## 2.1 (2026-11-09)

- The owl moves on springs now. Every behaviour can interrupt any other and carry on from where the
  head was. Idle behaviours draw at 60 frames a second and reactions at the display's own rate.
- New things it does: tilts its head, shakes its feathers, wakes up and dozes off, looks at the
  number when it changes, does a double take at a warning, breathes out when a problem clears,
  cheers a new week, dips when clicked, looks down at the open panel, follows the pointer, and
  turns all the way round when you pick another account.
- A blink closes like an eyelid instead of squeezing the eye flat.
- The amber owl is solid again, with dark eyes and beak. As a thin tint it turned grey over a
  coloured wallpaper and hid its own eyes on a light menu bar.
- A click dips the owl on the same frame, before the panel opens.
- Drawn with Core Graphics instead of a SwiftUI image renderer.
- Reduce Motion stops all movement, the startle included.

## 2.0 (2026-11-03)

- Perch is now a Claude usage app. The full panel (sessions, dev servers, LaunchAgents, cron,
  simulators) is gone; it stays available at the `v1.3` tag.
- Several accounts: one section per account, each with its plan, the week's percent used, the
  reset countdown and the Fable week. Click an account to put it in the menu bar.
- The menu bar shows the picked account's week as a bare percent, like the battery item.
- The 5-hour session window is gone, so there is no session row.
- Stale, spent and signed-out states say so in words, not colour alone.
- The popover follows the system light or dark appearance.

## 1.3 (2026-11-01)

- About 18 times less CPU, light mode, a solid amber alarm owl. Notes on the
  [v1.3 release](https://github.com/abhaymettu/perch/releases/tag/v1.3).
