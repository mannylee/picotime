import Foundation

/// Pure calendar/week math backing the scrollable calendar popover.
///
/// The popover renders a virtualized table of week rows; these helpers compute
/// the week list, the days of a week, weekend/month-boundary flags, weekday
/// symbols, and the "focused month" anchor — all without any AppKit dependency,
/// so they can be unit-tested directly.
public enum CalendarGrid {
    /// Week-start dates spanning ±`radius` weeks around the week containing
    /// `reference`. Mirrors the popover's virtualized week list (±260 ≈ ±5 years).
    public static func weekStarts(around reference: Date, radius: Int = 260,
                                  calendar: Calendar = .current) -> [Date] {
        let start = calendar.startOfDay(for: reference)
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: start)?.start else {
            return []
        }
        var weeks: [Date] = []
        for offset in -radius...radius {
            if let w = calendar.date(byAdding: .weekOfYear, value: offset, to: thisWeek) {
                weeks.append(w)
            }
        }
        return weeks
    }

    /// The seven day-dates of the week beginning at `weekStart`.
    public static func days(ofWeekStarting weekStart: Date,
                            calendar: Calendar = .current) -> [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    /// Whether `date` is a weekend day (Gregorian Saturday or Sunday), which the
    /// grid dims.
    public static func isWeekend(_ date: Date, calendar: Calendar = .current) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        return weekday == 1 || weekday == 7
    }

    /// Index of the week in `weeks` whose start is the same day as `weekStart`.
    public static func indexOfWeek(_ weekStart: Date, in weeks: [Date],
                                   calendar: Calendar = .current) -> Int? {
        weeks.firstIndex { calendar.isDate($0, inSameDayAs: weekStart) }
    }

    /// True when `day`'s month differs from the same column one week earlier — a
    /// month "begins" in this cell relative to the row above. Drives the
    /// horizontal segment of the snaking month-divider hairline.
    public static func beginsMonthFromWeekAbove(_ day: Date,
                                                calendar: Calendar = .current) -> Bool {
        guard let prevWeekDay = calendar.date(byAdding: .day, value: -7, to: day) else {
            return false
        }
        return !calendar.isDate(day, equalTo: prevWeekDay, toGranularity: .month)
    }

    /// True when `day` and `previousDay` (the cell to its left) fall in different
    /// months. Drives the vertical step joining the divider's two levels.
    public static func monthChanges(from previousDay: Date, to day: Date,
                                    calendar: Calendar = .current) -> Bool {
        !calendar.isDate(day, equalTo: previousDay, toGranularity: .month)
    }

    /// Locale-aware very-short weekday symbols rotated so the calendar's
    /// `firstWeekday` comes first (e.g. `["S","M","T","W","T","F","S"]` for a
    /// Sunday-first calendar).
    public static func weekdaySymbols(calendar: Calendar = .current,
                                      locale: Locale = .current) -> [String] {
        let df = DateFormatter()
        df.locale = locale
        var syms = df.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        let first = calendar.firstWeekday - 1  // firstWeekday is 1-based
        if first > 0 && first < syms.count {
            syms = Array(syms[first...] + syms[..<first])
        }
        return syms
    }

    /// The row index to treat as the focused-month anchor given the visible row
    /// range: a quarter of the way down the viewport (past a partially-scrolled
    /// top row), clamped to the list. Returns nil when nothing is visible.
    public static func focusedAnchorIndex(visibleLocation: Int, visibleLength: Int,
                                          weekCount: Int) -> Int? {
        guard visibleLength > 0, weekCount > 0 else { return nil }
        return min(weekCount - 1, visibleLocation + visibleLength / 4)
    }
}
