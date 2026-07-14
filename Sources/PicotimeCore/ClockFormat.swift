import Foundation

/// The menu bar clock's display format.
///
/// Locked to `en_US_POSIX` so the pattern is never localized, matching the app's
/// deliberate design (a fixed `yyyy-MM-dd HH:mm:ss`, 24-hour, no localization).
public enum ClockFormat {
    /// The fixed, locale-independent clock pattern. Capital `HH` = 24-hour.
    public static let pattern = "yyyy-MM-dd HH:mm:ss"

    /// A `DateFormatter` locked to `en_US_POSIX` with the fixed `pattern`.
    ///
    /// `timeZone` defaults to the current zone (what the running app uses); tests
    /// pass a fixed zone so the formatted string is deterministic.
    public static func makeFormatter(timeZone: TimeZone = .current) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = pattern
        return f
    }

    /// Format `date` with a fresh formatter. Convenience for one-off formatting
    /// and testing; the app reuses a single `makeFormatter()` per tick instead.
    public static func string(from date: Date, timeZone: TimeZone = .current) -> String {
        makeFormatter(timeZone: timeZone).string(from: date)
    }
}
