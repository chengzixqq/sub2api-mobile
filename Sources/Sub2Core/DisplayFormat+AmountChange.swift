import Foundation

/// 40 §1.4 增减 for amounts (X31: beside DisplayFormat.swift, whose body is frozen). Arrows only give the direction, never a colour
/// or a sign (40 §0.4).
extension DisplayFormat {
    /// The difference in money: “↑ $86.20”, “↓ $17.30”; no difference after rounding is “$0.00”, either side missing “—”.
    public static func amountChange(current: Decimal?, previous: Decimal?) -> String {
        guard let current, let previous, !current.isNaN, !previous.isNaN else { return missing }
        let difference = rounded(current - previous, digits: 2)
        guard difference != 0 else { return money(0) }
        return (difference > 0 ? "↑ " : "↓ ") + money(abs(difference))
    }

    /// current ÷ previous − 1 through `change` (“↑ 8.2%”); nil when either side is missing or the previous one is not above zero.
    public static func ratioChange(current: Decimal?, previous: Decimal?) -> String? {
        guard let current, let previous, !current.isNaN, !previous.isNaN, previous > 0 else { return nil }
        return change(NSDecimalNumber(decimal: current / previous - 1).doubleValue)
    }

    /// 利润明细: a percentage when both sides are above zero, otherwise the difference in money (a loss has no meaningful ratio).
    public static func profitChange(current: Decimal?, previous: Decimal?) -> String? {
        guard let current, let previous, !current.isNaN, !previous.isNaN else { return nil }
        guard current > 0, previous > 0 else { return amountChange(current: current, previous: previous) }
        return ratioChange(current: current, previous: previous)
    }

    /// “↑ 8.2% · 比昨天同时”; without a change “比昨天同时 —”.
    public static func changeLine(_ change: String?, label: String) -> String {
        guard let change, change != missing else { return label + " " + missing }
        return change + " · " + label
    }
}
