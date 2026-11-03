import Foundation

/// Rate multipliers (X31: beside DisplayFormat.swift, whose body is frozen). The App's one rate format (U-02): three decimals
/// rounded .plain, trailing zeros trimmed down to one, “×” in front — 0.125 “×0.125”, 0.130 “×0.13”, 1 “×1.0”, 0.1255 “×0.126”.
/// New code calls these directly; GroupFormat.rateText, UserEditCopy.rateText and AccountEditCopy.rate only forward here.
extension DisplayFormat {
    /// “×0.8”, “×1.0”, “×0.125”; missing or NaN “—”.
    public static func multiplier(_ value: Decimal?) -> String {
        guard let value, !value.isNaN else { return missing }
        return "×" + multiplierNumber(value)
    }

    /// The same digits without “×”, for a rate box's placeholder (“默认 0.8”).
    public static func multiplierNumber(_ value: Decimal) -> String {
        guard !value.isNaN else { return missing }
        return number(value, minFraction: 1, maxFraction: 3)
    }

    /// A confirmation's “a → b”. When both sides read the same at three decimals but differ, both keep every digit
    /// (“×0.13 → ×0.1304”), so a real change never reads as “×0.13 → ×0.13”.
    public static func multiplierChange(from old: Decimal?, to new: Decimal?) -> (from: String, to: String) {
        let from = multiplier(old), to = multiplier(new)
        guard from == to, let old, let new, !old.isNaN, !new.isNaN, old != new else { return (from, to) }
        return ("×" + number(old, minFraction: 1, maxFraction: nil), "×" + number(new, minFraction: 1, maxFraction: nil))
    }
}
