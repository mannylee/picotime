import Foundation
import PicotimeCore

func hourChimeTests(_ t: TestRunner) {
    let cal = fixedCalendar()

    t.test("top of hour at minute and second zero") {
        t.expect(HourChime.isTopOfHour(makeDate(2026, 6, 15, 14, 0, 0, calendar: cal), calendar: cal))
    }

    t.test("midnight is top of hour") {
        t.expect(HourChime.isTopOfHour(makeDate(2026, 6, 15, 0, 0, 0, calendar: cal), calendar: cal))
    }

    t.test("non-zero second is not top of hour") {
        t.expect(!HourChime.isTopOfHour(makeDate(2026, 6, 15, 14, 0, 1, calendar: cal), calendar: cal))
    }

    t.test("non-zero minute is not top of hour") {
        t.expect(!HourChime.isTopOfHour(makeDate(2026, 6, 15, 14, 30, 0, calendar: cal), calendar: cal))
    }
}
