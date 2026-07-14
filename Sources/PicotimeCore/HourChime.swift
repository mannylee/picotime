import Foundation

/// Logic for the hourly chime that plays at the top of every hour.
public enum HourChime {
    /// True when `date` falls exactly on the top of an hour — minute and second
    /// both zero — the moment the chime should play.
    ///
    /// This is the pure decision; the app pairs it with a per-second timer tick
    /// (so a real `HH:00:00` rollover is caught) and the actual sound playback.
    public static func isTopOfHour(_ date: Date, calendar: Calendar = .current) -> Bool {
        let parts = calendar.dateComponents([.minute, .second], from: date)
        return parts.minute == 0 && parts.second == 0
    }
}
