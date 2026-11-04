import Foundation
import Testing
@testable import Sub2Core

private func amount(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }

@Test func amountChangeWritesTheDifferenceWithADirectionArrow() {
    #expect(DisplayFormat.amountChange(current: amount("186.2"), previous: amount("100")) == "↑ $86.20")
    #expect(DisplayFormat.amountChange(current: amount("82.7"), previous: amount("100")) == "↓ $17.30")
    #expect(DisplayFormat.amountChange(current: amount("-12.3"), previous: 0) == "↓ $12.30")
    #expect(DisplayFormat.amountChange(current: amount("1234.5"), previous: amount("-10")) == "↑ $1,244.50")
    #expect(DisplayFormat.amountChange(current: amount("5.001"), previous: amount("5")) == "$0.00")
    #expect(DisplayFormat.amountChange(current: nil, previous: amount("5")) == "—")
    #expect(DisplayFormat.amountChange(current: amount("5"), previous: nil) == "—")
}

@Test func ratioChangeNeedsAPreviousValueAboveZero() {
    #expect(DisplayFormat.ratioChange(current: amount("108.2"), previous: amount("100")) == "↑ 8.2%")
    #expect(DisplayFormat.ratioChange(current: amount("90"), previous: amount("100")) == "↓ 10.0%")
    #expect(DisplayFormat.ratioChange(current: 0, previous: amount("100")) == "↓ 100.0%")
    #expect(DisplayFormat.ratioChange(current: amount("100.04"), previous: amount("100")) == "0.0%")
    #expect(DisplayFormat.ratioChange(current: amount("100"), previous: 0) == nil)
    #expect(DisplayFormat.ratioChange(current: amount("100"), previous: amount("-5")) == nil)
    #expect(DisplayFormat.ratioChange(current: nil, previous: amount("100")) == nil)
}

@Test func profitChangeUsesAPercentageOnlyWhenBothSidesAreAboveZero() {
    #expect(DisplayFormat.profitChange(current: amount("108.2"), previous: amount("100")) == "↑ 8.2%")
    #expect(DisplayFormat.profitChange(current: amount("86.2"), previous: 0) == "↑ $86.20")
    #expect(DisplayFormat.profitChange(current: amount("-10"), previous: amount("20")) == "↓ $30.00")
    #expect(DisplayFormat.profitChange(current: amount("50"), previous: amount("-36.2")) == "↑ $86.20")
    #expect(DisplayFormat.profitChange(current: 0, previous: 0) == "$0.00")
    #expect(DisplayFormat.profitChange(current: nil, previous: amount("5")) == nil)
    #expect(DisplayFormat.profitChange(current: amount("5"), previous: nil) == nil)
}

@Test func changeLineJoinsTheChangeAndTheComparisonLabel() {
    #expect(DisplayFormat.changeLine("↑ 8.2%", label: "比昨天同时") == "↑ 8.2% · 比昨天同时")
    #expect(DisplayFormat.changeLine(DisplayFormat.profitChange(current: amount("86.2"), previous: 0), label: "比昨天同时")
            == "↑ $86.20 · 比昨天同时")
    #expect(DisplayFormat.changeLine(nil, label: "比昨天同时") == "比昨天同时 —")
    #expect(DisplayFormat.changeLine(DisplayFormat.missing, label: "比前 7 天同期") == "比前 7 天同期 —")
}
