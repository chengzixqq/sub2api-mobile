import Foundation

/// 20 §2.3 / §0.6: the account detail's times beyond `clock` (X31: DisplayFormat.swift itself stays as it is).
extension DisplayFormat {
    /// HH:MM:SS on the server's calendar (“更新于 14:05:09”).
    public static func clockWithSeconds(_ date: Date?, timeZone: TimeZone) -> String {
        guard let date else { return missing }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
        return [parts.hour, parts.minute, parts.second].map(clockPart).joined(separator: ":")
    }

    /// “刚刚” under a minute (or ahead of `now`), then whole minutes, hours and days, rounded down: “12 分钟前”, “3 小时前”,
    /// “2 天前”. `now` is the caller's server-corrected clock; unlike `relativeTime` it never repeats a time of day.
    public static func elapsed(since date: Date?, now: Date) -> String {
        guard let date else { return missing }
        let seconds = now.timeIntervalSince(date)
        guard seconds.isFinite, seconds >= 60 else { return "刚刚" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) 分钟前" }
        let hours = minutes / 60
        return hours < 24 ? "\(hours) 小时前" : "\(hours / 24) 天前"
    }

    private static func clockPart(_ value: Int?) -> String {
        let value = value ?? 0
        return value < 10 ? "0\(value)" : String(value)
    }
}
