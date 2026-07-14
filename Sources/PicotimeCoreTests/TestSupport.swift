import Foundation

/// A fully deterministic calendar (Gregorian, UTC, fixed first weekday) so tests
/// don't depend on the machine's locale/timezone.
func fixedCalendar(firstWeekday: Int = 1) -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.locale = Locale(identifier: "en_US_POSIX")
    c.firstWeekday = firstWeekday
    return c
}

/// Build a `Date` from components using `calendar` (UTC by default via
/// `fixedCalendar`). Force-unwraps because the inputs are always valid in tests.
func makeDate(_ year: Int, _ month: Int, _ day: Int,
              _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0,
              calendar: Calendar) -> Date {
    var c = DateComponents()
    c.year = year; c.month = month; c.day = day
    c.hour = hour; c.minute = minute; c.second = second
    return calendar.date(from: c)!
}
