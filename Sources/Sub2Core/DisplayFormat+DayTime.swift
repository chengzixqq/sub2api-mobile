import Foundation

/// 10 §3.3 the alert detail's 触发 and 结束 (S1-12): always the day and the time, never “N 分钟前”. Beside DisplayFormat.swift,
/// whose body stays as it is (X31).
extension DisplayFormat {
    /// “今天 09:29” on the server's day of `now`, “昨天 22:10” the day before, “10月21日 09:29” otherwise; nil is “—”. `now` is the
    /// caller's server-corrected clock and `timeZone` the server's.
    public static func dayTime(_ date: Date?, now: Date, timeZone: TimeZone) -> String {
        guard let date else { return missing }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let time = clock(date, timeZone: timeZone)
        if calendar.isDate(date, inSameDayAs: now) { return "今天 " + time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "昨天 " + time }
        let day = calendar.dateComponents([.month, .day], from: date)
        return "\(day.month ?? 0)月\(day.day ?? 0)日 " + time
    }
}
