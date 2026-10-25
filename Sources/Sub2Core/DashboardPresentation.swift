import Foundation

/// Overview helpers that are not number formats: the performance window caption and trend bucket dates. Every number and
/// amount goes through DisplayFormat (00 §6.2, R10).
public enum DashboardPresentation {
    public static func performanceWindow(_ stats: DashboardStats) -> String {
        stats.rpmAvailable == nil ? "RPM 窗口由站点决定 · TPM 近5分钟均值" : "RPM 近60秒 · TPM 近5分钟均值"
    }

    /// Backend buckets have no offset: interpret them in the server zone (the reply's `query.timezone`, else the one
    /// sent with the request), never in the phone's (00 §6.4).
    public static func trendDate(_ raw: String, timeZone: TimeZone) -> Date? {
        let hourly = raw.count == 16
        let pattern = hourly ? #"^\d{4}-\d{2}-\d{2} \d{2}:00$"# : #"^\d{4}-\d{2}-\d{2}$"#
        guard raw.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let formatter = dateFormatter(timeZone: timeZone, format: hourly ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd")
        guard let date = formatter.date(from: raw), formatter.string(from: date) == raw else { return nil }
        return date
    }

    /// The zone is the server's (00 §6.3); callers pass it, there is no phone-zone default.
    public static func trendAxisLabel(_ date: Date, hourly: Bool, timeZone: TimeZone) -> String {
        dateFormatter(timeZone: timeZone, format: hourly ? "M/d HH:mm" : "M/d").string(from: date)
    }

    private static func dateFormatter(timeZone: TimeZone, format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone; formatter.dateFormat = format; formatter.isLenient = false
        return formatter
    }
}

extension DashboardStats {
    /// `rpm_available == false` means the live counter failed, not a measured zero, so the value is missing (00 §6.5);
    /// a legacy server without the flag still shows its number.
    public var availableRPM: Double? { rpmAvailable == false ? nil : rpm }
}
