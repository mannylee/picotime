# Picotime

A tiny macOS menu bar clock that shows the time as `YYYY-MM-DD HH:mm:ss` (e.g. `2026-07-13 14:32:07`) — the format the built-in Control Center clock won't give you.

Picotime is a menu bar–only "accessory" app: no Dock icon, no window, no app-switcher entry. It just puts one item in the menu bar and refreshes it every second.

## Build

```sh
./build.sh
```

This compiles `Sources/main.swift` with `swiftc` (Command Line Tools — no Xcode project needed) and assembles a universal `Picotime.app` bundle, ad-hoc code-signed.

## Run

```sh
open Picotime.app
```

The timestamp appears in the menu bar, to the left of the system clock. Click it and choose **Quit Picotime** to stop it.

## Hide the built-in clock

macOS reserves the far-right menu bar slot for the Control Center clock and offers no direct "hide" toggle, so pick one:

1. **Make it analog** (recommended, no extra tools): System Settings → Control Center → Clock → *Clock Options* → **Analog**. It collapses to a small clock face with no text, leaving Picotime as the timestamp you actually read.
2. **Hide it with a menu bar manager** such as [Hidden Bar](https://github.com/dwarvesf/hidden) (free) or Bartender/Ice.

Picotime is independent of whatever you choose — quit it any time.

## Launch at login

- **Simple:** System Settings → General → Login Items → **+** → select `Picotime.app`.
- **Scripted:** register a `~/Library/LaunchAgents` plist, or call `SMAppService.mainApp.register()` from the app.

## Customizing the format

Edit the `dateFormat` string in [Sources/main.swift](Sources/main.swift) and rebuild. It uses [Unicode date field patterns](https://www.unicode.org/reports/tr35/tr35-dates.html#Date_Field_Symbol_Table):

- `HH` 24-hour, `hh` 12-hour, `a` AM/PM
- `ss` seconds — drop it (and slow the timer) if you don't want a per-second tick

## How it works

- `NSStatusItem` — the standard AppKit menu bar item.
- A 1s `Timer` added in `.common` run-loop mode (keeps ticking while a menu is open) updates the title via a `DateFormatter`.
- `setActivationPolicy(.accessory)` + `LSUIElement` in `Info.plist` → no Dock icon.
- Monospaced-digit font so the width stays steady as digits change.
