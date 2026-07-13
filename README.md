# Picotime

A tiny macOS menu bar clock that shows the time as `YYYY-MM-DD HH:mm:ss` (e.g. `2026-07-13 14:32:07`) — the format the built-in Control Center clock won't give you.

Picotime is a menu bar–only "accessory" app: no Dock icon, no window, no app-switcher entry. It just puts one item in the menu bar and refreshes it every second. It also chimes at the top of every hour. Click the clock to open a scrollable calendar.

## Build

```sh
./build.sh
```

This compiles `Sources/main.swift` with `swiftc` (Command Line Tools — no Xcode project needed) and assembles a universal `Picotime.app` bundle, ad-hoc code-signed.

## Run

```sh
open Picotime.app
```

The timestamp appears in the menu bar, to the left of the system clock. Click it to open a scrollable calendar popover: a continuously scrolling week grid with today outlined, weekends dimmed, and a hairline dividing adjacent months. The header shows **`Year Month`** with prev / today / next buttons; the settings live in a flat panel at the bottom — **Hourly Chime** (toggle), **Start at Login** (toggle), the version (**Picotime `yyyymmdd`**), and **Quit**.

## Hide the built-in clock

macOS reserves the far-right menu bar slot for the Control Center clock and offers no direct "hide" toggle, so pick one:

1. **Make it analog** (recommended, no extra tools): System Settings → Control Center → Clock → *Clock Options* → **Analog**. It collapses to a small clock face with no text, leaving Picotime as the timestamp you actually read.
2. **Hide it with a menu bar manager** such as [Hidden Bar](https://github.com/dwarvesf/hidden) (free) or Bartender/Ice.

Picotime is independent of whatever you choose — quit it any time.

## Launch at login

Click the menu bar clock and toggle **Start at Login** in the settings panel at the bottom of the calendar. This registers the app with macOS via `SMAppService`. The checkbox is read from the live registration status at launch and each time the popover opens, so it stays in sync with System Settings → General → Login Items.

If the label reads **"Start at Login — approve in Settings"** with the box checked, macOS has the registration but is waiting for you to confirm it under Login Items — flip it on there once. This is common for the ad-hoc-signed dev build.

The registration is tied to the app's on-disk location, and `build.sh` recreates the bundle on every build — so for a login item that reliably survives, move `Picotime.app` to `/Applications` and toggle it on from there.

## Hourly chime

At the top of every hour (`HH:00:00`) Picotime plays a short chime, bundled at `Resources/beep-beep.mp3`. Toggle it on/off from the settings panel at the bottom of the calendar (**Hourly Chime**) — the choice is remembered across launches (it's on by default).

To change the sound, replace that file (any `NSSound`-supported format — `.wav`/`.aiff`/`.caf`/`.m4a`/`.mp3`) and rebuild; if you rename it, update the `forResource`/`withExtension` lookup in [Sources/main.swift](Sources/main.swift). See [CREDITS.md](CREDITS.md) for the bundled sound's attribution.

## Customizing the format

Edit the `dateFormat` string in [Sources/main.swift](Sources/main.swift) and rebuild. It uses [Unicode date field patterns](https://www.unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table):

- `HH` 24-hour, `hh` 12-hour, `a` AM/PM
- `ss` seconds — drop it (and slow the timer) if you don't want a per-second tick

## How it works

- `NSStatusItem` — the standard AppKit menu bar item.
- A 1s `Timer` added in `.common` run-loop mode (keeps ticking during UI tracking, e.g. while the calendar popover is open) updates the title via a `DateFormatter`.
- `setActivationPolicy(.accessory)` + `LSUIElement` in `Info.plist` → no Dock icon.
- Monospaced-digit font so the width stays steady as digits change.
- `SMAppService.mainApp` (macOS 13+) backs the **Start at Login** toggle; the calendar re-reads its status each time the popover opens so the checkbox never goes stale.
- An `NSSound` loaded from the bundle plays when the second-boundary tick lands on `HH:00:00`. `build.sh` copies `Resources/` into `Contents/Resources/` so the bundle can find it.
- Clicking the clock toggles a `.transient` `NSPopover` whose content is a `CalendarViewController`. The week grid is a virtualized view-based `NSTableView` (one row per week, ±5 years), each row a custom-drawn `WeekRowView`; a gradient alpha mask fades the grid at its top/bottom edges as a scroll cue.
