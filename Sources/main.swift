import Cocoa
import ServiceManagement

// Picotime — a menu bar clock that shows the time as `YYYY-MM-DD HH:mm:ss`.
//
// It runs as an "accessory" app: no Dock icon, no app-switcher entry, no window.
// It puts an NSStatusItem in the menu bar, refreshes it once a second, and
// chimes at the top of every hour. Left-clicking the clock opens a scrollable
// calendar popover; the settings (Hourly Chime, Start at Login, Quit) live in a
// flat panel across the bottom of that popover.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?

    // The calendar popover shown when the clock is clicked.
    private let popover = NSPopover()
    private var calendarVC: CalendarViewController!

    // Whether the hourly chime plays. Persisted in UserDefaults; defaults to on
    // (registered in applicationDidFinishLaunching).
    private let chimeDefaultsKey = "hourlyChimeEnabled"
    var isChimeEnabled: Bool {
        UserDefaults.standard.bool(forKey: chimeDefaultsKey)
    }

    // Human-facing version (the build-date CalVer stamped by build.sh).
    var versionString: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
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
            // Clicking the clock toggles the calendar popover (instead of a menu).
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp])
        }

        // The calendar popover. `.transient` closes it when the user clicks
        // outside (including the menu bar), matching typical status-item UIs.
        calendarVC = CalendarViewController(app: self)
        popover.behavior = .transient
        popover.contentViewController = calendarVC
        // Fix the popover size explicitly so it doesn't fall back to a too-narrow
        // Auto Layout fitting size (the controller's view constraints match this).
        popover.contentSize = calendarVC.contentSize

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
            // Keep the calendar's "today" highlight correct if the popover is
            // left open across midnight; cheap and only runs while it's shown.
            if self.popover.isShown { self.calendarVC.refreshTicked() }
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

    // MARK: - Popover

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.close()
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Bring the app forward so the transient popover reliably takes focus.
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    // MARK: - Settings (driven from the popover toolbar / gear menu)

    /// Flip the hourly-chime preference and persist it. The next HH:00:00 tick
    /// reads `isChimeEnabled`, so no timer changes are needed.
    func toggleHourlyChime() {
        UserDefaults.standard.set(!isChimeEnabled, forKey: chimeDefaultsKey)
    }

    /// Current login-item status, driving the Start-at-Login checkbox. `.enabled`
    /// and `.requiresApproval` both read as "on" (the latter is registered but
    /// pending the user's confirmation in System Settings — common for the
    /// ad-hoc dev build).
    var isLoginEnabled: Bool {
        switch SMAppService.mainApp.status {
        case .enabled, .requiresApproval: return true
        default: return false
        }
    }

    var loginRequiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    /// Register/unregister the app as a login item via SMAppService (macOS 13+).
    /// Reads the current status live so state reflects reality even if the user
    /// changed it in System Settings > General > Login Items.
    @objc func toggleLaunchAtLogin(_ sender: Any?) {
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
    }

}

// MARK: - Calendar popover

/// The scrollable calendar shown when the clock is clicked.
///
/// Layout top-to-bottom: a header (month label + navigation), a weekday header
/// row, a continuously scrolling table of week rows, and a flat settings panel
/// (Hourly Chime / Start at Login toggles, version, Quit) pinned to the bottom.
final class CalendarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    private unowned let app: AppDelegate
    private let cal = Calendar.current

    // One entry per week (the week-start date), spanning ±5 years around launch.
    // NSTableView virtualizes rows, so a few hundred entries is cheap.
    private let weeks: [Date]

    private let monthLabel = NSTextField(labelWithString: "")
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()

    // Flat settings controls, shown at the bottom of the popover.
    private let chimeCheckbox = NSButton(checkboxWithTitle: "Hourly Chime", target: nil, action: nil)
    private let loginCheckbox = NSButton(checkboxWithTitle: "Start at Login", target: nil, action: nil)
    private let versionLabel = NSTextField(labelWithString: "")

    // Alpha mask that fades the week grid out at its top and bottom edges, as a
    // "there's more to scroll" cue. Updated to the scroll view's size on layout.
    private let scrollMask = CAGradientLayer()

    private let rowHeight: CGFloat = 32

    private let headerFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale.current
        // Year first, then the standalone month name (still locale-localized).
        // A fixed dateFormat (not a localized template) keeps the year-month order.
        f.dateFormat = "yyyy LLLL"
        return f
    }()

    init(app: AppDelegate) {
        self.app = app

        // Build the week list centered on the week containing today.
        var weeks: [Date] = []
        let today = Calendar.current.startOfDay(for: Date())
        if let thisWeek = Calendar.current.dateInterval(of: .weekOfYear, for: today)?.start {
            for offset in -260...260 {
                if let w = Calendar.current.date(byAdding: .weekOfYear, value: offset, to: thisWeek) {
                    weeks.append(w)
                }
            }
        }
        self.weeks = weeks

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    // Fixed popover width, so the layout doesn't jump when the month label's
    // text length changes (e.g. "May 2026" vs "September 2026").
    private let contentWidth: CGFloat = 224
    private let contentHeight: CGFloat = 340
    private let headerHeight: CGFloat = 34

    /// The popover's fixed content size (also used by the AppDelegate to size the
    /// popover so it doesn't compute a narrower Auto Layout fitting size).
    var contentSize: NSSize { NSSize(width: contentWidth, height: contentHeight) }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: contentHeight))
        preferredContentSize = root.frame.size

        // --- Toolbar: month/year label (left) + navigation cluster (right) ---
        monthLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        monthLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)  // stretch → pushes nav right
        // Let the label truncate rather than widen the popover on long months.
        monthLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        monthLabel.lineBreakMode = .byTruncatingTail

        // Chevrons: sized just under the month text and dimmed, so navigation is
        // present but low-emphasis. The today button is a calendar glyph. The
        // three sit together, flush to the right edge of the header.
        let prev = iconButton("chevron.left", "Previous month", #selector(goPreviousMonth),
                              pointSize: 11, dimmed: true)
        let todayBtn = iconButton("calendar", "Jump to today", #selector(goToday),
                                  pointSize: 13)
        let next = iconButton("chevron.right", "Next month", #selector(goNextMonth),
                              pointSize: 11, dimmed: true)
        let nav = NSStackView(views: [prev, todayBtn, next])
        nav.orientation = .horizontal
        nav.alignment = .centerY
        nav.spacing = 8
        nav.translatesAutoresizingMaskIntoConstraints = false

        // Plain container (not a stack view) so we can pin the month label to the
        // left and the nav cluster hard to the right edge — a horizontal stack's
        // distribution wouldn't reliably push the buttons all the way right.
        let toolbar = NSView()
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        monthLabel.translatesAutoresizingMaskIntoConstraints = false
        toolbar.addSubview(monthLabel)
        toolbar.addSubview(nav)
        NSLayoutConstraint.activate([
            monthLabel.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 10),
            monthLabel.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            nav.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -10),
            nav.centerYAnchor.constraint(equalTo: toolbar.centerYAnchor),
            monthLabel.trailingAnchor.constraint(lessThanOrEqualTo: nav.leadingAnchor, constant: -6),
        ])

        // --- Weekday header row (S M T W T F S), locale-aware ---
        let header = WeekdayHeaderView()
        header.translatesAutoresizingMaskIntoConstraints = false

        // --- Scrolling week grid ---
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("week"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = rowHeight
        tableView.intercellSpacing = .zero
        tableView.gridStyleMask = []
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .none
        tableView.style = .plain
        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = false  // scroll via wheel/trackpad; no visible bar
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        // Update the month label as the user scrolls.
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(boundsChanged),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView)

        // Fade the grid out at its top/bottom edges via an alpha mask on the
        // scroll view's layer. Because it masks the actual pixels, it composites
        // correctly over the popover's material regardless of appearance. The
        // stop positions are set in viewDidLayout (they depend on the height).
        scrollView.wantsLayer = true
        scrollMask.colors = [
            NSColor.clear.cgColor, NSColor.black.cgColor,
            NSColor.black.cgColor, NSColor.clear.cgColor,
        ]
        scrollMask.startPoint = NSPoint(x: 0.5, y: 0)
        scrollMask.endPoint = NSPoint(x: 0.5, y: 1)
        scrollView.layer?.mask = scrollMask

        // --- Flat settings, at the bottom of the popover (no gear/menu) ---
        let settings = makeSettingsPanel()

        root.addSubview(toolbar)
        root.addSubview(header)
        root.addSubview(scrollView)
        root.addSubview(settings)

        NSLayoutConstraint.activate([
            root.widthAnchor.constraint(equalToConstant: contentWidth),
            root.heightAnchor.constraint(equalToConstant: contentHeight),

            toolbar.topAnchor.constraint(equalTo: root.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            toolbar.heightAnchor.constraint(equalToConstant: headerHeight),

            header.topAnchor.constraint(equalTo: toolbar.bottomAnchor),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            header.heightAnchor.constraint(equalToConstant: 16),

            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 2),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: settings.topAnchor),

            settings.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            settings.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            settings.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])

        view = root
    }

    /// The flat settings block pinned to the bottom of the popover: a hairline
    /// divider, the two toggles, and a version line with a Quit button.
    ///
    /// Laid out with an explicit top→bottom constraint chain (divider pinned to
    /// the top, Quit's bottom pinned to the panel's bottom) so the panel's height
    /// is fully determined by its content and it *hugs* rather than stretching —
    /// otherwise it would expand to fill and starve the scroll view above it.
    private func makeSettingsPanel() -> NSView {
        let panel = NSView()
        panel.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        chimeCheckbox.target = self
        chimeCheckbox.action = #selector(toggleChime(_:))
        chimeCheckbox.font = NSFont.systemFont(ofSize: 12)
        chimeCheckbox.translatesAutoresizingMaskIntoConstraints = false

        loginCheckbox.target = self
        loginCheckbox.action = #selector(toggleLogin(_:))
        loginCheckbox.font = NSFont.systemFont(ofSize: 12)
        loginCheckbox.toolTip =
            "If macOS shows it as needing approval, confirm Picotime in System Settings ▸ General ▸ Login Items."
        loginCheckbox.translatesAutoresizingMaskIntoConstraints = false

        versionLabel.font = NSFont.systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.stringValue = "Picotime \(app.versionString)"
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        versionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let quit = NSButton(title: "Quit", target: nil, action: #selector(NSApplication.terminate(_:)))
        quit.bezelStyle = .rounded
        quit.controlSize = .small
        quit.font = NSFont.systemFont(ofSize: 11)
        quit.translatesAutoresizingMaskIntoConstraints = false
        quit.setContentHuggingPriority(.required, for: .horizontal)
        quit.setContentCompressionResistancePriority(.required, for: .horizontal)

        panel.addSubview(divider)
        panel.addSubview(chimeCheckbox)
        panel.addSubview(loginCheckbox)
        panel.addSubview(versionLabel)
        panel.addSubview(quit)

        let leading: CGFloat = 12
        NSLayoutConstraint.activate([
            // Decorative hairline at the top; fixed height so it stays *out* of
            // the vertical sizing chain (an unconstrained separator stretches).
            divider.topAnchor.constraint(equalTo: panel.topAnchor),
            divider.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),

            // Rigid top→bottom chain, both ends pinned to the panel, so the panel
            // hugs its content height instead of stretching.
            chimeCheckbox.topAnchor.constraint(equalTo: panel.topAnchor, constant: 9),
            chimeCheckbox.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: leading),

            loginCheckbox.topAnchor.constraint(equalTo: chimeCheckbox.bottomAnchor, constant: 6),
            loginCheckbox.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: leading),

            quit.topAnchor.constraint(equalTo: loginCheckbox.bottomAnchor, constant: 8),
            quit.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -12),
            quit.bottomAnchor.constraint(equalTo: panel.bottomAnchor, constant: -10),

            // Version sits left, vertically centered on Quit, and never overlaps it.
            versionLabel.centerYAnchor.constraint(equalTo: quit.centerYAnchor),
            versionLabel.leadingAnchor.constraint(equalTo: panel.leadingAnchor, constant: leading),
            versionLabel.trailingAnchor.constraint(lessThanOrEqualTo: quit.leadingAnchor, constant: -8),
        ])
        return panel
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // Keep the single column as wide as the table so day cells fill 7 columns.
        if let column = tableView.tableColumns.first {
            column.width = tableView.bounds.width
        }
        // Size the fade mask to the scroll view and set the fade depth (~14pt at
        // each edge) as a fraction of its height. Wrapped in a no-implicit-
        // animation block so the mask doesn't lag behind a live resize.
        let h = scrollView.bounds.height
        if h > 0 {
            let fade = min(0.5, 14 / h)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            scrollMask.frame = scrollView.bounds
            scrollMask.locations = [0, NSNumber(value: fade), NSNumber(value: 1 - fade), 1]
            CATransaction.commit()
        }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        // Re-scroll to today every time the popover opens, so "today" is correct
        // even if days have passed since the last open.
        refreshSettingsState()
        scrollToToday()
    }

    // MARK: Toolbar actions

    @objc private func goToday() { scrollToToday() }

    @objc private func goPreviousMonth() { stepMonth(by: -1) }
    @objc private func goNextMonth() { stepMonth(by: 1) }

    // MARK: Settings

    @objc private func toggleChime(_ sender: NSButton) {
        app.toggleHourlyChime()
        refreshSettingsState()
    }

    @objc private func toggleLogin(_ sender: NSButton) {
        app.toggleLaunchAtLogin(sender)
        refreshSettingsState()
    }

    /// Sync the checkbox states with the live app state (chime pref + login-item
    /// status), so they're correct on open and after any external change.
    private func refreshSettingsState() {
        chimeCheckbox.state = app.isChimeEnabled ? .on : .off
        loginCheckbox.state = app.isLoginEnabled ? .on : .off
        loginCheckbox.title = app.loginRequiresApproval
            ? "Start at Login — approve in Settings"
            : "Start at Login"
    }

    // MARK: Scrolling

    /// Scroll so today's week sits near the top with one week of context above.
    private func scrollToToday() {
        let start = cal.startOfDay(for: Date())
        guard let weekStart = cal.dateInterval(of: .weekOfYear, for: start)?.start else { return }
        scrollWeekToTop(indexOfWeek(weekStart), context: 1)
    }

    /// Jump to the week containing the 1st of the month `delta` months away from
    /// the currently focused month.
    private func stepMonth(by delta: Int) {
        let base = focusedMonthDate() ?? Date()
        guard let target = cal.date(byAdding: .month, value: delta, to: base),
              let firstOfMonth = cal.date(from: cal.dateComponents([.year, .month], from: target)),
              let weekStart = cal.dateInterval(of: .weekOfYear, for: firstOfMonth)?.start
        else { return }
        scrollWeekToTop(indexOfWeek(weekStart), context: 0)
    }

    private func indexOfWeek(_ weekStart: Date) -> Int? {
        weeks.firstIndex { cal.isDate($0, inSameDayAs: weekStart) }
    }

    private func scrollWeekToTop(_ index: Int?, context: Int) {
        guard let index else { return }
        let target = max(0, index - context)
        let rect = tableView.rect(ofRow: target)
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: rect.minY))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        updateMonthLabel()
    }

    // MARK: Month label

    @objc private func boundsChanged() { updateMonthLabel() }

    /// The month of the week sitting in the vertical middle of the visible area.
    private func focusedMonthDate() -> Date? {
        let visible = tableView.rows(in: tableView.visibleRect)
        guard visible.length > 0 else { return nil }
        // Anchor to a week near the top of the viewport (a quarter of the way
        // down, past any partially-scrolled top row) rather than the middle, so
        // opening on today shows today's month instead of one a month ahead.
        let anchor = min(weeks.count - 1, visible.location + visible.length / 4)
        // Use midweek (Wed-ish) so the label tracks the month most of the row
        // belongs to, not a stray spill-over day.
        return cal.date(byAdding: .day, value: 3, to: weeks[anchor])
    }

    private func updateMonthLabel() {
        guard let date = focusedMonthDate() else { return }
        monthLabel.stringValue = headerFormatter.string(from: date)
    }

    /// Redraw visible rows so the "today" highlight stays correct across midnight.
    func refreshTicked() {
        guard isViewLoaded else { return }
        tableView.enumerateAvailableRowViews { rowView, _ in
            rowView.subviews.forEach { $0.needsDisplay = true }
        }
    }

    // MARK: NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int { weeks.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("weekRow")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? WeekRowView) ?? {
            let v = WeekRowView()
            v.identifier = id
            return v
        }()
        cell.weekStart = weeks[row]
        return cell
    }
}

// MARK: - Drawing views

/// The locale-aware weekday header (e.g. "S M T W T F S"), laid out on the same
/// 7-column grid as the day cells below it.
private final class WeekdayHeaderView: NSView {
    override var isFlipped: Bool { true }

    private let symbols: [String] = {
        let cal = Calendar.current
        let df = DateFormatter()
        df.locale = Locale.current
        var syms = df.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let first = cal.firstWeekday - 1  // firstWeekday is 1-based
        if first > 0 && first < syms.count {
            syms = Array(syms[first...] + syms[..<first])
        }
        return syms
    }()

    override func draw(_ dirtyRect: NSRect) {
        let colWidth = bounds.width / 7
        let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para,
        ]
        for (i, sym) in symbols.enumerated() {
            let size = (sym as NSString).size(withAttributes: attrs)
            let rect = NSRect(x: CGFloat(i) * colWidth,
                              y: (bounds.height - size.height) / 2,
                              width: colWidth, height: size.height)
            (sym as NSString).draw(in: rect, withAttributes: attrs)
        }
    }
}

/// One week's row of seven day cells. Draws the day numbers, dims weekends,
/// outlines today, and separates adjacent months with a snaking hairline.
private final class WeekRowView: NSView {
    var weekStart: Date? { didSet { needsDisplay = true } }

    private let cal = Calendar.current

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let weekStart else { return }
        let colWidth = bounds.width / 7
        let today = Date()

        let days: [Date] = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
        guard days.count == 7 else { return }

        // Month-boundary divider, drawn as a snaking step. A cell gets a hairline
        // along its top edge when the day one week earlier in the same column is
        // in an earlier month — i.e. this cell's month "begins" relative to the
        // row above. Where the month changes mid-row, a vertical segment joins
        // the two horizontal levels so the boundary reads as one continuous line.
        // A touch brighter than separatorColor and slightly thicker, for a clearer
        // month boundary.
        let dividerColor = NSColor.separatorColor.blended(withFraction: 0.45, of: .labelColor)
            ?? NSColor.tertiaryLabelColor
        let dividerWidth: CGFloat = 1.5
        dividerColor.setStroke()
        for i in 0..<7 {
            if let prevWeekDay = cal.date(byAdding: .day, value: -7, to: days[i]),
               !cal.isDate(days[i], equalTo: prevWeekDay, toGranularity: .month) {
                let x0 = CGFloat(i) * colWidth
                let top = NSBezierPath()
                top.move(to: NSPoint(x: x0, y: dividerWidth / 2))
                top.line(to: NSPoint(x: x0 + colWidth, y: dividerWidth / 2))
                top.lineWidth = dividerWidth
                top.stroke()
            }
            if i > 0, !cal.isDate(days[i], equalTo: days[i - 1], toGranularity: .month) {
                let x = CGFloat(i) * colWidth
                let step = NSBezierPath()
                step.move(to: NSPoint(x: x, y: 0))
                step.line(to: NSPoint(x: x, y: bounds.height))
                step.lineWidth = dividerWidth
                step.stroke()
            }
        }

        for i in 0..<7 {
            let day = days[i]
            let comps = cal.dateComponents([.day, .weekday], from: day)
            let dayNum = comps.day ?? 0
            let weekday = comps.weekday ?? 0
            let cellRect = NSRect(x: CGFloat(i) * colWidth, y: 0, width: colWidth, height: bounds.height)
            let isToday = cal.isDate(day, inSameDayAs: today)
            let isWeekend = (weekday == 1 || weekday == 7)  // Gregorian Sun/Sat

            // Today: rounded accent outline, like the screenshot's boxed day.
            if isToday {
                let box = NSBezierPath(roundedRect: cellRect.insetBy(dx: 3.5, dy: 3.5),
                                       xRadius: 5, yRadius: 5)
                NSColor.controlAccentColor.setStroke()
                box.lineWidth = 1.5
                box.stroke()
            }

            let numFont = NSFont.monospacedDigitSystemFont(
                ofSize: 12, weight: isToday ? .semibold : .regular)
            let color: NSColor = isToday
                ? .controlAccentColor
                : (isWeekend ? .secondaryLabelColor : .labelColor)
            drawCentered("\(dayNum)", in: cellRect, font: numFont, color: color,
                         verticallyCenter: true)
        }
    }

    private func drawCentered(_ string: String, in rect: NSRect, font: NSFont,
                              color: NSColor, verticallyCenter: Bool) {
        let para = NSMutableParagraphStyle()
        para.alignment = .center
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: para,
        ]
        let size = (string as NSString).size(withAttributes: attrs)
        let y = verticallyCenter ? rect.minY + (rect.height - size.height) / 2 : rect.minY
        let drawRect = NSRect(x: rect.minX, y: y, width: rect.width, height: size.height)
        (string as NSString).draw(in: drawRect, withAttributes: attrs)
    }
}

// MARK: - Toolbar icon-button factory

extension CalendarViewController {
    /// A borderless icon button whose glyph is sized to `pointSize` (roughly the
    /// month label's text size) and optionally dimmed for low-emphasis controls.
    /// The button hugs its image so it doesn't add bulk around the symbol.
    fileprivate func iconButton(_ symbol: String, _ tooltip: String, _ action: Selector,
                                pointSize: CGFloat = 13, dimmed: Bool = false) -> NSButton {
        let button = NSButton()
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imagePosition = .imageOnly
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)?
            .withSymbolConfiguration(config)
        if dimmed { button.contentTintColor = .secondaryLabelColor }
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .vertical)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)  // no Dock icon; programmatic twin of LSUIElement
app.run()
