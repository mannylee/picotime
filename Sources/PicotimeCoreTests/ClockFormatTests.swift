import Foundation
import PicotimeCore

func clockFormatTests(_ t: TestRunner) {
    let utc = TimeZone(identifier: "UTC")!
    let cal = fixedCalendar()

    t.test("pattern is fixed") {
        t.expectEqual(ClockFormat.pattern, "yyyy-MM-dd HH:mm:ss")
    }

    t.test("formats a known date with a fixed zone") {
        let date = makeDate(2026, 1, 2, 3, 4, 5, calendar: cal)
        t.expectEqual(ClockFormat.string(from: date, timeZone: utc), "2026-01-02 03:04:05")
    }

    t.test("uses a 24-hour clock") {
        // 11 PM must render as 23, not 11 — capital HH.
        let date = makeDate(2026, 12, 31, 23, 59, 59, calendar: cal)
        t.expectEqual(ClockFormat.string(from: date, timeZone: utc), "2026-12-31 23:59:59")
    }

    t.test("formatter has POSIX locale and the fixed pattern") {
        let f = ClockFormat.makeFormatter(timeZone: utc)
        t.expectEqual(f.locale.identifier, "en_US_POSIX")
        t.expectEqual(f.dateFormat, "yyyy-MM-dd HH:mm:ss")
    }
}
