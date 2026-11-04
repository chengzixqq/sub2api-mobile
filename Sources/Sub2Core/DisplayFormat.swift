import Foundation

/// The App's only number and time formats (00 §6.1–§6.2, §6.5, R10). Pages call these instead of formatting on their own.
/// Missing, NaN and non-finite inputs show "—"; zero is a value. Output never follows the device locale: thousands are
/// grouped with ",", negatives use U+2212, rounding happens in Decimal (.plain) and a value rounding to zero has no sign.
/// No formatter is cached, so every function is a pure static call from any isolation domain.
public enum DisplayFormat {
    public static let missing = "—"
    /// What VoiceOver reads for `missing` (S1-00); pages pass displayed values through `spoken(_:)`.
    public static let missingSpoken = "无数据"
    static let minus = "\u{2212}"

    /// 00 §6.2: list and detail durations, P50 / P95 / P99, single millisecond readings. Callers always pick one.
    public enum DurationStyle: Sendable, Equatable { case list, percentile, millis }

    // MARK: Money (6.1)

    /// "$" + grouping + fixed digits. `small` shows "< $0.01" for values above 0 and below one cent where a page asks for it.
    public static func money(_ value: Decimal?, digits: Int = 2, small: Bool = false) -> String {
        guard let value, !value.isNaN else { return missing }
        if small, value > 0, value < Decimal(sign: .plus, exponent: -2, significand: 1) { return "< $0.01" }
        return currency(value, minFraction: digits, maxFraction: digits)
    }

    /// Cards without room: K as the only unit, two digits; whether to switch to K follows the value rounded to cents.
    public static func moneyCompact(_ value: Decimal?) -> String {
        guard let value, !value.isNaN else { return missing }
        guard abs(rounded(value, digits: 2)) >= 1_000 else { return currency(value, minFraction: 2, maxFraction: 2) }
        return currency(value / 1_000, minFraction: 2, maxFraction: 2) + "K"
    }

    /// A single log row: four digits below $1, two from $1 (judged after rounding to four digits); zero is "$0.00".
    public static func moneyLineItem(_ value: Decimal?) -> String {
        guard let value, !value.isNaN else { return missing }
        let fine = rounded(value, digits: 4)
        return money(value, digits: fine == 0 || abs(fine) >= 1 ? 2 : 4)
    }

    /// Echo of an amount the administrator typed (confirmations, pending rows): never rounded, at least two digits.
    public static func moneyExact(_ value: Decimal?) -> String {
        guard let value, !value.isNaN else { return missing }
        return currency(value, minFraction: 2, maxFraction: nil)
    }

    // MARK: Counts and rates (6.2)

    public static func grouped(_ value: Int?) -> String {
        guard let value else { return missing }
        let digits = String(value.magnitude)
        return (value < 0 ? minus : "") + group(digits)
    }

    public static func compact(_ value: Int?) -> String {
        guard let value else { return missing }
        return compact(decimal: Decimal(value))
    }

    public static func compact(_ value: Double?) -> String {
        guard let value = decimalValue(value) else { return missing }
        return compact(decimal: value)
    }

    /// One decimal below 10 (0.4, 2.0), whole numbers from 10 after rounding; 0 is "0".
    public static func rpm(_ value: Double?) -> String {
        guard let value = decimalValue(value), value >= 0 else { return missing }
        if value == 0 { return "0" }
        return rounded(value, digits: 1) < 10 ? number(value, minFraction: 1, maxFraction: 1) : number(value, minFraction: 0, maxFraction: 0)
    }

    /// Backend 0–1 ratios (error_rate, sla …) as percentages with one decimal.
    public static func ratioPercent(_ value: Double?) -> String {
        guard let value = decimalValue(value) else { return missing }
        return number(value * 100, minFraction: 1, maxFraction: 1) + "%"
    }

    /// Values that already are percentages (alert metric_value / threshold, share bars).
    public static func percent(_ value: Double?) -> String {
        guard let value = decimalValue(value) else { return missing }
        return number(value, minFraction: 1, maxFraction: 1) + "%"
    }

    /// `ratio` = current ÷ previous − 1: "↑ 12.3%" / "↓ 3.2%", no colour and no sign; rounding to zero is "0.0%".
    public static func change(_ ratio: Double?) -> String {
        guard let ratio = decimalValue(ratio) else { return missing }
        let percent = rounded(ratio * 100, digits: 1)
        if percent == 0 { return "0.0%" }
        return (percent > 0 ? "↑ " : "↓ ") + number(abs(percent), minFraction: 1, maxFraction: 1) + "%"
    }

    /// The only general decimal format (D15): grouping, trailing zeros trimmed down to `minFractionDigits`.
    public static func decimal(_ value: Double?, minFractionDigits: Int = 0, maxFractionDigits: Int) -> String {
        guard let value = decimalValue(value) else { return missing }
        return number(value, minFraction: minFractionDigits, maxFraction: max(minFractionDigits, maxFractionDigits))
    }

    // MARK: Durations (6.2)

    public static func duration(_ milliseconds: Double?, style: DurationStyle) -> String {
        guard let value = decimalValue(milliseconds) else { return missing }
        return duration(decimal: value, style: style)
    }

    public static func duration(_ milliseconds: Int?, style: DurationStyle) -> String {
        guard let milliseconds else { return missing }
        return duration(decimal: Decimal(milliseconds), style: style)
    }

    // MARK: Time (6.2, 6.3)

    /// "刚刚" within a minute either way, "N 分钟前" within the hour, then 今天 / 昨天 / M月d日 + HH:MM. `now` is the caller's
    /// server-corrected clock; day boundaries and the time of day follow `timeZone` (the server's, 00 §6.3).
    public static func relativeTime(_ date: Date?, now: Date, timeZone: TimeZone) -> String {
        guard let date else { return missing }
        let elapsed = now.timeIntervalSince(date)
        if abs(elapsed) < 60 { return "刚刚" }
        if elapsed > 0, elapsed < 3_600 { return "\(Int(elapsed / 60)) 分钟前" }
        let calendar = gregorian(timeZone)
        let time = clock(date, calendar: calendar)
        if calendar.isDate(date, inSameDayAs: now) { return "今天 " + time }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "昨天 " + time
        }
        let day = calendar.dateComponents([.month, .day], from: date)
        return "\(day.month ?? 0)月\(day.day ?? 0)日 " + time
    }

    /// m:ss, or h:mm:ss from one hour; seconds round up and never go below 0:00.
    public static func countdown(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, let total = Int(exactly: max(0, seconds.rounded(.up))) else { return missing }
        let hours = total / 3_600, minutes = total % 3_600 / 60, rest = total % 60
        return hours > 0 ? "\(hours):\(pad(minutes)):\(pad(rest))" : "\(minutes):\(pad(rest))"
    }

    /// Recomputed from the absolute target on every tick instead of counting down a stored number (00 §6.2).
    public static func countdown(until target: Date?, now: Date) -> String {
        guard let target else { return missing }
        return countdown(target.timeIntervalSince(now))
    }

    /// Whole minutes rounded up, at least 1; from 60 minutes "X 小时 Y 分钟" ("X 小时" when Y is 0).
    public static func minutesLeft(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite, let minutes = Int(exactly: max(1, (seconds / 60).rounded(.up))) else { return missing }
        guard minutes >= 60 else { return "\(minutes) 分钟" }
        let rest = minutes % 60
        return "\(minutes / 60) 小时" + (rest == 0 ? "" : " \(rest) 分钟")
    }

    public static func clock(_ date: Date?, timeZone: TimeZone) -> String {
        guard let date else { return missing }
        return clock(date, calendar: gregorian(timeZone))
    }

    // MARK: Accessibility

    /// A displayed value as VoiceOver should read it: the missing mark reads as `missingSpoken`, anything else as shown.
    public static func spoken(_ text: String) -> String { text == missing ? missingSpoken : text }

    // MARK: Internals shared inside Sub2Core

    /// `value` rounded half away from zero to `digits` fraction digits, entirely in Decimal (formerly DashboardPresentation.fixed).
    static func rounded(_ value: Decimal, digits: Int) -> Decimal {
        var source = value, result = Decimal()
        NSDecimalRound(&result, &source, digits, .plain)
        return result
    }

    /// Finite doubles keep their shortest decimal spelling ("0.0045" stays 0.0045), so rounding matches what was received.
    static func decimalValue(_ value: Double?) -> Decimal? {
        guard let value, value.isFinite else { return nil }
        if let parsed = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")), !parsed.isNaN { return parsed }
        let converted = Decimal(value)
        return converted.isNaN ? nil : converted
    }

    private static func currency(_ value: Decimal, minFraction: Int, maxFraction: Int?) -> String {
        let (negative, body) = parts(value, minFraction: minFraction, maxFraction: maxFraction)
        return (negative ? minus : "") + "$" + body
    }

    static func number(_ value: Decimal, minFraction: Int, maxFraction: Int?, grouping: Bool = true) -> String {
        let (negative, body) = parts(value, minFraction: minFraction, maxFraction: maxFraction, grouping: grouping)
        return (negative ? minus : "") + body
    }

    /// Sign and digits of `value` rounded to `maxFraction` (nil keeps every digit). Rounding to zero drops the sign.
    private static func parts(_ value: Decimal, minFraction: Int, maxFraction: Int?, grouping: Bool = true) -> (Bool, String) {
        let value = maxFraction.map { rounded(value, digits: $0) } ?? value
        guard value != 0 else { return (false, "0" + (minFraction > 0 ? "." + String(repeating: "0", count: minFraction) : "")) }
        let text = NSDecimalNumber(decimal: abs(value)).stringValue
        let pieces = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        var fraction = pieces.count == 2 ? String(pieces[1]) : ""
        while fraction.count > minFraction, fraction.hasSuffix("0") { fraction.removeLast() }
        if fraction.count < minFraction { fraction += String(repeating: "0", count: minFraction - fraction.count) }
        let integer = String(pieces[0])
        return (value < 0, (grouping ? group(integer) : integer) + (fraction.isEmpty ? "" : "." + fraction))
    }

    private static func group(_ digits: String) -> String {
        var result = ""
        for (index, character) in digits.enumerated() {
            if index > 0, (digits.count - index) % 3 == 0 { result.append(",") }
            result.append(character)
        }
        return result
    }

    private static let compactUnits: [(divisor: Decimal, suffix: String)] = [(1, ""), (1_000, "K"), (1_000_000, "M"), (1_000_000_000, "B")]

    /// The unit follows the rounded value: 999,950 is "1M", not "1000K"; B is the largest unit.
    private static func compact(decimal value: Decimal) -> String {
        var index = compactUnits.lastIndex { abs(value) >= $0.divisor } ?? 0
        while true {
            let digits = index == 0 ? 0 : 1
            let scaled = value / compactUnits[index].divisor
            if index + 1 < compactUnits.count, abs(rounded(scaled, digits: digits)) >= 1_000 { index += 1; continue }
            return number(scaled, minFraction: 0, maxFraction: digits, grouping: false) + compactUnits[index].suffix
        }
    }

    private static func duration(decimal milliseconds: Decimal, style: DurationStyle) -> String {
        guard milliseconds >= 0 else { return missing }
        let seconds = milliseconds / 1_000
        switch style {
        case .list:
            let digits = rounded(seconds, digits: 1) >= 100 ? 0 : 1
            return number(seconds, minFraction: digits, maxFraction: digits) + "s"
        case .percentile, .millis:
            if rounded(milliseconds, digits: 0) < 1_000 { return number(milliseconds, minFraction: 0, maxFraction: 0) + "ms" }
            let digits = rounded(seconds, digits: 1) >= 10 ? 0 : 1
            return number(seconds, minFraction: digits, maxFraction: digits) + "s"
        }
    }

    private static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func clock(_ date: Date, calendar: Calendar) -> String {
        let time = calendar.dateComponents([.hour, .minute], from: date)
        return pad(time.hour ?? 0) + ":" + pad(time.minute ?? 0)
    }

    private static func pad(_ value: Int) -> String { value < 10 ? "0\(value)" : String(value) }
}
