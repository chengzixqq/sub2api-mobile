import Foundation

/// C-30 (S3D1-28): absolute times. Kept beside DisplayFormat.swift, whose body is frozen (X31). Callers inside Sub2Core that
/// hold a TimeZone, and the fields that 00 §6.3 shows in the phone's zone (an announcement's start and end), use the zone
/// variants (S6D2a-03).
extension DisplayFormat {
    /// An absolute time on the server's calendar (00 §6.3): "MM/dd HH:mm" in `now`'s year, "yyyy/MM/dd HH:mm" otherwise; `now`
    /// is the caller's server-corrected clock.
    public static func monthDayClock(_ date: Date?, timeZone: ServerTimeZone, now: Date) -> String {
        monthDayClock(date, zone: timeZone.timeZone, now: now)
    }

    /// `monthDay` and HH:mm in `zone`.
    static func monthDayClock(_ date: Date?, zone: TimeZone, now: Date) -> String {
        guard let date else { return missing }
        return monthDay(date, zone: zone, now: now) + " " + clock(date, timeZone: zone)
    }

    /// "MM/dd" in `now`'s year, "yyyy/MM/dd" otherwise, both on `zone`'s Gregorian calendar.
    static func monthDay(_ date: Date?, zone: TimeZone, now: Date) -> String {
        guard let date else { return missing }
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX"); calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let text = twoDigits(parts.month) + "/" + twoDigits(parts.day)
        guard let year = parts.year, year != calendar.component(.year, from: now) else { return text }
        return "\(year)/" + text
    }

    private static func twoDigits(_ value: Int?) -> String {
        let value = value ?? 0
        return value < 10 ? "0\(value)" : String(value)
    }
}
