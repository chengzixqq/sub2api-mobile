import Foundation

/// C-30 (S3D1-28): absolute times. Kept beside DisplayFormat.swift, whose body is frozen (X31).
extension DisplayFormat {
    /// An absolute time on the server's calendar (00 §6.3): "MM/dd HH:mm" in `now`'s year, "yyyy/MM/dd HH:mm" otherwise; `now`
    /// is the caller's server-corrected clock.
    public static func monthDayClock(_ date: Date?, timeZone: ServerTimeZone, now: Date) -> String {
        guard let date else { return missing }
        let calendar = timeZone.calendar
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let text = twoDigits(parts.month) + "/" + twoDigits(parts.day) + " " + twoDigits(parts.hour) + ":" + twoDigits(parts.minute)
        guard let year = parts.year, year != calendar.component(.year, from: now) else { return text }
        return "\(year)/" + text
    }

    private static func twoDigits(_ value: Int?) -> String {
        let value = value ?? 0
        return value < 10 ? "0\(value)" : String(value)
    }
}
