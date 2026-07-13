# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Picotime is a menu bar–only macOS "accessory" app (no Dock icon, no window, no app-switcher entry) that displays the time as `yyyy-MM-dd HH:mm:ss`, refreshed every second, and chimes at the top of every hour. It has a click menu with a **Start at Login** toggle and **Quit**. The entire app is a single Swift file, [Sources/main.swift](Sources/main.swift) using AppKit/Cocoa directly — there is no Xcode project, no Swift Package Manager manifest, and no third-party dependencies. The one bundled asset is the hourly chime, `Resources/beep-beep.mp3` (attribution in [CREDITS.md](CREDITS.md)).

## Build & run

```sh
./build.sh          # compile + assemble Picotime.app
open Picotime.app    # run it (timestamp appears in menu bar)
```

[build.sh](build.sh) compiles `main.swift` with the Command Line Tools `swiftc` (no Xcode needed), builds separate `arm64` and `x86_64` slices, `lipo`s them into a universal binary, and ad-hoc code-signs the bundle. `Picotime.app/` is a build artifact (git-ignored) — it's regenerated on every build.

There are no tests, linter, or CI.

## Architecture notes

- **`setActivationPolicy(.accessory)` in code + `LSUIElement` in [Info.plist](Info.plist) together** produce the no-Dock-icon behavior. Changing one without the other is inconsistent — keep them in sync.
- **The timer reschedules itself each tick** (`scheduleNextTick`) rather than using a repeating `Timer`. It computes the delay to the next whole-second boundary so the displayed second flips in lockstep with the system clock instead of drifting from the launch offset. It's added in `.common` run-loop mode so it keeps ticking while the menu is open.
- **`en_US_POSIX` locale + monospaced-digit font** are deliberate: the POSIX locale prevents the format from being localized, and the monospaced digits keep the item width steady so it doesn't jitter as numbers change. Preserve both when editing display logic.
- **Deployment target is macOS 13.0**, set in both `build.sh` (`-target …-macosx13.0`) and `Info.plist` (`LSMinimumSystemVersion`).
- **The hourly chime rides on the existing per-second tick.** `chimeIfTopOfHour()` is called from the timer's fire block (not the initial launch `update()`, so opening the app mid-hour never beeps) and plays the `NSSound` only when the current minute and second are both `00`. The sound is loaded once via `Bundle.main.url(forResource:withExtension:)`, so **`build.sh` must copy `Resources/` into `Contents/Resources/`** for the lookup to resolve — that copy step is part of the build. If you drop `ss` from the format, the top-of-hour check still needs a per-second (or at least per-minute) cadence to catch the `:00` second — see the note in "Changing the time format".
- **The chime is toggleable and persisted.** The **Hourly Chime** menu item flips `hourlyChimeEnabled` in `UserDefaults`; `chimeIfTopOfHour()` early-returns when it's off. It defaults to on via `UserDefaults.standard.register(defaults:)` in `applicationDidFinishLaunching` (the registration domain is volatile, so a fresh install has no stored key and reads `true`). Both menu checkmarks (chime + login) are refreshed in `menuWillOpen` so they never go stale.
- **The "Start at Login" toggle uses `SMAppService.mainApp`** (from `ServiceManagement`, macOS 13+ — matches the deployment target, so no legacy `SMLoginItemSetEnabled` helper bundle). The menu item's checkmark is driven off `SMAppService.mainApp.status`, refreshed in `menuWillOpen` (`AppDelegate` is the menu's delegate) so it stays in sync with System Settings. `SMAppService` registers *this bundle's on-disk path*, and `build.sh` recreates the bundle each build — so a durable login item means running from a stable location like `/Applications`.

## Changing the time format

Edit the `dateFormat` string in [Sources/main.swift](Sources/main.swift) and rebuild. It uses Unicode date field patterns (`HH` 24-hour, `hh` 12-hour, `a` AM/PM). If you drop `ss` (seconds), also relax the per-second timer cadence in `scheduleNextTick`.
