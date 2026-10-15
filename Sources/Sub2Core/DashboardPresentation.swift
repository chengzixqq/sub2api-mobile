import Foundation

/// Display rules shared with the administrator Web dashboard. Missing actual
/// billing and account-cost values stay unavailable; standard cost is distinct.
public enum DashboardPresentation {
    public static func compactNumber(_ value: Int, locale: Locale = .current) -> String {
        if value >= 1_000_000_000 { return fixed(Decimal(value) / 1_000_000_000, digits: 2) + "B" }
        if value >= 1_000_000 { return fixed(Decimal(value) / 1_000_000, digits: 2) + "M" }
        if value >= 1_000 { return fixed(Decimal(value) / 1_000, digits: 2) + "K" }
        let formatter = NumberFormatter()
        formatter.locale = locale; formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0; formatter.maximumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    public static func compactNumber(_ value: Double, locale: Locale = .current) -> String {
        guard value.isFinite else { return "不可用" }
        if value >= 1_000_000_000 { return fixed(value / 1_000_000_000, digits: 2) + "B" }
        if value >= 1_000_000 { return fixed(value / 1_000_000, digits: 2) + "M" }
        if value >= 1_000 { return fixed(value / 1_000, digits: 2) + "K" }
        let formatter = NumberFormatter()
        formatter.locale = locale; formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0; formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    public static func cost(_ value: Decimal?) -> String {
        guard let value, !value.isNaN else { return "不可用" }
        if value >= 1_000 { return "$" + fixed(value / 1_000, digits: 2) + "K" }
        let digits = value >= 1 ? 2 : value >= Decimal(string: "0.01")! ? 3 : 4
        return "$" + fixed(value, digits: digits)
    }

    public static func duration(_ milliseconds: Double?) -> String {
        guard let milliseconds, milliseconds.isFinite, milliseconds >= 0 else { return "不可用" }
        if milliseconds >= 1_000 {
            return fixed(Decimal(milliseconds) / 1_000, digits: 2) + "s"
        }
        return fixed(Decimal(milliseconds), digits: 0) + "ms"
    }

    /// Backend buckets have no offset: interpret them in the same timezone sent
    /// with the trend request, rather than parsing them as UTC.
    public static func trendDate(_ raw: String, timeZone: TimeZone = .current) -> Date? {
        let hourly = raw.count == 16
        let pattern = hourly ? #"^\d{4}-\d{2}-\d{2} \d{2}:00$"# : #"^\d{4}-\d{2}-\d{2}$"#
        guard raw.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let formatter = dateFormatter(timeZone: timeZone, format: hourly ? "yyyy-MM-dd HH:mm" : "yyyy-MM-dd")
        guard let date = formatter.date(from: raw), formatter.string(from: date) == raw else { return nil }
        return date
    }

    public static func trendAxisLabel(_ date: Date, hourly: Bool, timeZone: TimeZone = .current) -> String {
        dateFormatter(timeZone: timeZone, format: hourly ? "M/d HH:mm" : "M/d").string(from: date)
    }

    private static func dateFormatter(timeZone: TimeZone, format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone; formatter.dateFormat = format; formatter.isLenient = false
        return formatter
    }

    private static func fixed(_ value: Decimal, digits: Int) -> String {
        fixed(NSDecimalNumber(decimal: value), digits: digits)
    }

    private static func fixed(_ value: Double, digits: Int) -> String {
        fixed(NSNumber(value: value), digits: digits)
    }

    private static func fixed(_ value: NSNumber, digits: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false; formatter.minimumFractionDigits = digits
        formatter.maximumFractionDigits = digits; formatter.roundingMode = .halfUp
        return formatter.string(from: value) ?? value.stringValue
    }
}
