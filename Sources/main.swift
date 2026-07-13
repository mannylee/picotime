import Cocoa
import ServiceManagement

// Picotime — a menu bar clock that shows the time as `YYYY-MM-DD HH:mm:ss`.
//
// It runs as an "accessory" app: no Dock icon, no app-switcher entry, no window.
// It puts an NSStatusItem in the menu bar, refreshes it once a second, and
// chimes at the top of every hour. The menu offers "Hourly Chime" and
// "Start at Login" toggles.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var loginItem: NSMenuItem!
    private var chimeItem: NSMenuItem!

    // Whether the hourly chime plays. Persisted in UserDefaults; defaults to on
    // (registered in applicationDidFinishLaunching).
    private let chimeDefaultsKey = "hourlyChimeEnabled"
    private var isChimeEnabled: Bool {
        UserDefaults.standard.bool(forKey: chimeDefaultsKey)
    }

    // Fixed format, locale-independent. Capital HH = 24-hour clock.
    // en_US_POSIX guarantees the digits/format never get localized.
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    // Short chime played at the top of every hour (HH:00:00). Loaded once from
    // the app bundle's Resources; stays nil (silent) if the file is missing.
    private let hourlyChime: NSSound? = {
        guard let url = Bundle.main.url(forResource: "beep-beep", withExtension: "mp3") else {
            return nil
        }
        return NSSound(contentsOf: url, byReference: true)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Missing key ⇒ chime on, matching the app's original always-on behavior.
        UserDefaults.standard.register(defaults: [chimeDefaultsKey: true])

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Monospaced digits keep the item width steady so it doesn't jitter
            // as the numbers change each second.
            button.font = NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize, weight: .regular)
        }

        // Click menu with the setting toggles and a Quit item.
        let menu = NSMenu()
        menu.delegate = self  // refresh the checkmarks each time the menu opens

        // Non-clickable version line (the build-date CalVer stamped by build.sh).
        // A nil action leaves it disabled, so it reads as a greyed-out label.
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let versionItem = NSMenuItem(title: "Picotime \(version)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)
        menu.addItem(.separator())

        chimeItem = NSMenuItem(
            title: "Hourly Chime",
            action: #selector(toggleHourlyChime(_:)),
            keyEquivalent: "")
        chimeItem.target = self
        menu.addItem(chimeItem)

        loginItem = NSMenuItem(
            title: "Start at Login",
            action: #selector(toggleLaunchAtLogin(_:)),
            keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)

        // Reflect the persisted/registered state immediately, so the checkmarks
        // are right the first time the menu opens after a launch — not only
        // after menuWillOpen has fired once.
        refreshChimeItemState()
        refreshLoginItemState()

        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit Picotime",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"))
        statusItem.menu = menu

        update()
        scheduleNextTick()
    }

    /// Schedule the next update to fire right as the wall clock rolls over to a
    /// new second, then reschedule from inside the fire block. This keeps the
    /// displayed second changing in lockstep with the system clock, instead of
    /// drifting from whatever sub-second offset the app launched at.
    ///
    /// Added in `.common` run-loop mode so it keeps ticking while a menu is open
    /// (the default mode pauses timers during menu tracking).
    private func scheduleNextTick() {
        let now = Date().timeIntervalSince1970
        let delayToBoundary = 1.0 - now.truncatingRemainder(dividingBy: 1.0)
        let timer = Timer(timeInterval: delayToBoundary, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.update()
            self.chimeIfTopOfHour()
            self.scheduleNextTick()
        }
        timer.tolerance = 0  // fire as close to the boundary as possible
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func update() {
        statusItem.button?.title = formatter.string(from: Date())
    }

    /// Play the chime when the wall clock rolls over to the top of the hour.
    /// Driven from the timer tick (not the initial launch `update()`), so
    /// opening the app mid-hour never beeps — only a real HH:00:00 rollover does.
    private func chimeIfTopOfHour() {
        guard isChimeEnabled else { return }
        let parts = Calendar.current.dateComponents([.minute, .second], from: Date())
        if parts.minute == 0 && parts.second == 0 {
            hourlyChime?.stop()  // rewind in case it's somehow still playing
            hourlyChime?.play()
        }
    }

    /// Flip the hourly-chime preference and persist it. The next HH:00:00 tick
    /// reads `isChimeEnabled`, so no timer changes are needed.
    @objc private func toggleHourlyChime(_ sender: NSMenuItem) {
        UserDefaults.standard.set(!isChimeEnabled, forKey: chimeDefaultsKey)
        refreshChimeItemState()
    }

    private func refreshChimeItemState() {
        chimeItem.state = isChimeEnabled ? .on : .off
    }

    /// Register/unregister the app as a login item via SMAppService (macOS 13+).
    /// Reads the current status live so the checkmark reflects reality even if the
    /// user changed it in System Settings > General > Login Items.
    @objc private func toggleLaunchAtLogin(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn't update Start at Login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        refreshLoginItemState()
    }

    private func refreshLoginItemState() {
        // `.enabled` is the normal "on" state. `.requiresApproval` means the app
        // IS registered but macOS wants the user to confirm it in System Settings
        // (common for ad-hoc-signed apps run from a dev folder) — from the user's
        // point of view they turned it on, so show a tick and say so in the title.
        switch SMAppService.mainApp.status {
        case .enabled:
            loginItem.state = .on
            loginItem.title = "Start at Login"
        case .requiresApproval:
            loginItem.state = .on
            loginItem.title = "Start at Login (approve in System Settings)"
        default:  // .notRegistered, .notFound
            loginItem.state = .off
            loginItem.title = "Start at Login"
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        refreshChimeItemState()
        refreshLoginItemState()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // no Dock icon; programmatic twin of LSUIElement
app.run()
