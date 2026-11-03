import Foundation
import Testing
@testable import Sub2Core

// U-02: the App's one rate format — three decimals rounded .plain, trailing zeros trimmed down to one, “×” in front.

private func rate(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }

@Test(arguments: [("0.125", "×0.125"), ("0.130", "×0.13"), ("1.100", "×1.1"), ("1", "×1.0"), ("0.1255", "×0.126"), ("0", "×0.0"),
                  ("2.9995", "×3.0"), ("2.999", "×2.999"), ("0.05", "×0.05"), ("1234.5", "×1,234.5"), ("1.23456789", "×1.235")])
func multiplierRoundsToThreeAndTrims(raw: String, expected: String) {
    #expect(DisplayFormat.multiplier(rate(raw)) == expected)
}

@Test func multiplierWritesMissingForNilAndNaN() {
    #expect(DisplayFormat.multiplier(nil) == "—")
    #expect(DisplayFormat.multiplier(Decimal.nan) == "—")
}

@Test func multiplierNumberDropsSign() {
    #expect(DisplayFormat.multiplierNumber(rate("0.8")) == "0.8")
    #expect(DisplayFormat.multiplierNumber(1) == "1.0")
    #expect(DisplayFormat.multiplierNumber(rate("1.23456")) == "1.235")
    #expect(DisplayFormat.multiplierNumber(Decimal.nan) == "—")
}

/// Only when both sides read the same at three decimals but differ do both keep every digit (“×0.13 → ×0.13” never shows).
@Test func multiplierChangeWidensOnlyWhenEqualText() {
    func change(_ old: String?, _ new: String?) -> [String] {
        let pair = DisplayFormat.multiplierChange(from: old.map(rate), to: new.map(rate))
        return [pair.from, pair.to]
    }
    #expect(change("0.13", "0.1304") == ["×0.13", "×0.1304"])
    #expect(change("0.1301", "0.1304") == ["×0.1301", "×0.1304"])
    #expect(change("0.1251", "0.1254") == ["×0.1251", "×0.1254"])
    #expect(change("1", "1.0004") == ["×1.0", "×1.0004"])
    #expect(change("0.1254", "0.1256") == ["×0.125", "×0.126"])
    #expect(change("0.8", "0.9") == ["×0.8", "×0.9"])
    #expect(change("0.125", "0.13") == ["×0.125", "×0.13"])
    #expect(change("0.80", "0.8") == ["×0.8", "×0.8"])
    #expect(change(nil, "1") == ["—", "×1.0"])
    #expect(change("1", nil) == ["×1.0", "—"])
}
