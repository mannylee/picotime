import Foundation
import PicotimeCore

func calendarGridTests(_ t: TestRunner) {
    let cal = fixedCalendar()  // Gregorian, UTC, Sunday-first

    // MARK: weekStarts

    t.test("weekStarts count and centering") {
        let reference = makeDate(2026, 6, 15, 12, 0, 0, calendar: cal)  // a Monday
        let weeks = CalendarGrid.weekStarts(around: reference, radius: 2, calendar: cal)
        t.expectEqual(weeks.count, 5)  // -2...2
        // The middle entry is the start of the week containing the reference.
        let expectedMid = cal.dateInterval(of: .weekOfYear,
                                           for: cal.startOfDay(for: reference))!.start
        t.expectEqual(weeks[2], expectedMid)
    }

    t.test("weekStarts are seven days apart") {
        let weeks = CalendarGrid.weekStarts(around: makeDate(2026, 6, 15, calendar: cal),
                                            radius: 3, calendar: cal)
        for i in 1..<weeks.count {
            let delta = cal.dateComponents([.day], from: weeks[i - 1], to: weeks[i]).day
            t.expectEqual(delta, 7)
        }
    }

    t.test("default radius spans about ten years") {
        let weeks = CalendarGrid.weekStarts(around: makeDate(2026, 6, 15, calendar: cal),
                                            calendar: cal)
        t.expectEqual(weeks.count, 521)  // 2*260 + 1
    }

    // MARK: days

    t.test("days of week are seven consecutive") {
        let weekStart = makeDate(2026, 6, 14, calendar: cal)  // Sunday
        let days = CalendarGrid.days(ofWeekStarting: weekStart, calendar: cal)
        t.expectEqual(days.count, 7)
        t.expectEqual(days.first, weekStart)
        t.expectEqual(days.last, makeDate(2026, 6, 20, calendar: cal))
    }

    // MARK: isWeekend

    t.test("weekend detection") {
        t.expect(!CalendarGrid.isWeekend(makeDate(2026, 1, 1, calendar: cal), calendar: cal)) // Thu
        t.expect(!CalendarGrid.isWeekend(makeDate(2026, 1, 2, calendar: cal), calendar: cal)) // Fri
        t.expect(CalendarGrid.isWeekend(makeDate(2026, 1, 3, calendar: cal), calendar: cal))  // Sat
        t.expect(CalendarGrid.isWeekend(makeDate(2026, 1, 4, calendar: cal), calendar: cal))  // Sun
    }

    // MARK: indexOfWeek

    t.test("indexOfWeek finds and misses") {
        let weeks = CalendarGrid.weekStarts(around: makeDate(2026, 6, 15, calendar: cal),
                                            radius: 2, calendar: cal)
        t.expectEqual(CalendarGrid.indexOfWeek(weeks[3], in: weeks, calendar: cal), 3)
        let faraway = makeDate(1999, 1, 3, calendar: cal)
        t.expect(CalendarGrid.indexOfWeek(faraway, in: weeks, calendar: cal) == nil)
    }

    // MARK: month boundaries

    t.test("begins month from the week above") {
        // 2026-07-03 minus 7 days = 2026-06-26 (June) → month begins here.
        t.expect(CalendarGrid.beginsMonthFromWeekAbove(makeDate(2026, 7, 3, calendar: cal),
                                                       calendar: cal))
        // 2026-07-15 minus 7 days = 2026-07-08 (July) → same month.
        t.expect(!CalendarGrid.beginsMonthFromWeekAbove(makeDate(2026, 7, 15, calendar: cal),
                                                        calendar: cal))
    }

    t.test("month changes between adjacent days") {
        t.expect(CalendarGrid.monthChanges(from: makeDate(2026, 6, 30, calendar: cal),
                                           to: makeDate(2026, 7, 1, calendar: cal),
                                           calendar: cal))
        t.expect(!CalendarGrid.monthChanges(from: makeDate(2026, 7, 1, calendar: cal),
                                            to: makeDate(2026, 7, 2, calendar: cal),
                                            calendar: cal))
    }

    // MARK: weekdaySymbols

    t.test("weekday symbols rotate with first weekday") {
        let posix = Locale(identifier: "en_US_POSIX")
        let sundayFirst = CalendarGrid.weekdaySymbols(calendar: fixedCalendar(firstWeekday: 1),
                                                      locale: posix)
        let mondayFirst = CalendarGrid.weekdaySymbols(calendar: fixedCalendar(firstWeekday: 2),
                                                      locale: posix)
        t.expectEqual(sundayFirst.count, 7)
        t.expectEqual(mondayFirst.count, 7)
        // Monday-first is the Sunday-first list rotated left by one.
        t.expectEqual(mondayFirst, Array(sundayFirst[1...] + sundayFirst[..<1]))
    }

    // MARK: focusedAnchorIndex

    t.test("focused anchor index") {
        t.expect(CalendarGrid.focusedAnchorIndex(visibleLocation: 0, visibleLength: 0,
                                                 weekCount: 100) == nil)
        t.expect(CalendarGrid.focusedAnchorIndex(visibleLocation: 0, visibleLength: 8,
                                                 weekCount: 0) == nil)
        // A quarter of the way down: 10 + 8/4 = 12.
        t.expectEqual(CalendarGrid.focusedAnchorIndex(visibleLocation: 10, visibleLength: 8,
                                                      weekCount: 100), 12)
        // Clamped to the last index.
        t.expectEqual(CalendarGrid.focusedAnchorIndex(visibleLocation: 98, visibleLength: 8,
                                                      weekCount: 100), 99)
    }
}
