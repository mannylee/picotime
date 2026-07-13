import Cocoa

// Picotime — a menu bar clock that shows the time as `YYYY-MM-DD HH:mm:ss`.
//
// It runs as an "accessory" app: no Dock icon, no app-switcher entry, no window.
// All it does is put an NSStatusItem in the menu bar and refresh it once a second.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    // Fixed format, locale-independent. Capital HH = 24-hour clock.
    // en_US_POSIX guarantees the digits/format never get localized.
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            // Monospaced digits keep the item width steady so it doesn't jitter
            // as the numbers change each second.
            button.font = NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize, weight: .regular)
        }

        // Right-click / click menu with a Quit item.
        let menu = NSMenu()
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
            self.scheduleNextTick()
        }
        timer.tolerance = 0  // fire as close to the boundary as possible
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    @objc private func update() {
        statusItem.button?.title = formatter.string(from: Date())
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // no Dock icon; programmatic twin of LSUIElement
app.run()
