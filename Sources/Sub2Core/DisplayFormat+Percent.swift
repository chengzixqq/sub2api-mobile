import Foundation

/// Whole-number shares (X31: beside DisplayFormat.swift, whose body is frozen). The analytics tiles' only one (S4D2b-07): Token
/// 缓存读占, the endpoint and request-type tiles, the duration bars, the error shares and the model page (S4-17…S4-19).
extension DisplayFormat {
    /// A 0–1 ratio as a percentage without decimals: 0.5404 is “54%”, 0.995 “100%”, 0.0049 “0%”; missing or not finite “—”.
    public static func wholePercent(_ ratio: Double?) -> String {
        guard let ratio, ratio.isFinite else { return missing }
        return decimal(ratio * 100, maxFractionDigits: 0) + "%"
    }
}
