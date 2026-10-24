import Foundation
import Testing
@testable import Sub2Core

private func amount(_ raw: String) -> Decimal { Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX"))! }
/// "5" is a digit, "." the decimal point, "<" delete and "C" clear.
private func key(_ symbol: Character) -> KeypadKey {
    switch symbol {
    case ".": .decimalPoint
    case "<": .delete
    case "C": .clear
    default: .digit(symbol.wholeNumberValue ?? -1)
    }
}
private func typed(_ keys: String, into text: String = "", maxDigits: Int = 7, maxFractionDigits: Int = 2, maximum: Decimal? = nil) -> String {
    keys.reduce(text) { KeypadInput.apply(key($1), to: $0, maxDigits: maxDigits, maxFractionDigits: maxFractionDigits, maximum: maximum) }
}

// 30 §3.3 and the design's `KeypadSheet.press()`: seven digits in all, two of them after the point.
@Test(arguments: [
    ("", "5", "5"), ("", ".", ""), ("", "0", "0"), ("0", "0", "0"), ("0", "5", "5"), ("0", ".", "0."), ("0.", "5", "0.5"),
    ("0.", "0", "0.0"), ("0.0", "7", "0.07"), ("12", ".", "12."), ("12.", ".", "12."), ("12.3", "4", "12.34"), ("12.34", "5", "12.34"),
    ("12.34", ".", "12.34"), ("1234567", "8", "1234567"), ("1234567", ".", "1234567"), ("123456", ".", "123456."),
    ("123456.", "7", "123456.7"), ("123456.7", "8", "123456.7"), ("10", "0", "100"), ("", "1234567", "1234567"), ("", "12345678", "1234567"),
    ("", "00012", "12"), ("", "0.123", "0.12")
])
func keypadFollowsDesignRules(text: String, keys: String, expected: String) {
    #expect(typed(keys, into: text) == expected)
}

// 60 §10.3 and the design's `vmoKeypadNext`: redeem face values take six digits.
@Test(arguments: [("123456", "7", "123456"), ("12345", ".", "12345."), ("12345.", "6", "12345.6"), ("123456", ".", "123456"),
                  ("0", "5", "5"), ("0", ".", "0."), ("1.2", "34", "1.23")])
func digitLimitIsConfigurableForRedeemFaceValue(text: String, keys: String, expected: String) {
    #expect(typed(keys, into: text, maxDigits: 6) == expected)
}

// 60 §3.4 threshold: whole dollars, six digits, at most 100,000; the lower bound 1 is checked on saving.
@Test(arguments: [("10", ".", "10"), ("", ".", ""), ("99999", "9", "99999"), ("10000", "0", "100000"), ("100000", "0", "100000"),
                  ("100000", "<", "10000"), ("0", "7", "7"), ("", "0", "0"), ("", "250", "250"), ("", "1000000", "100000")])
func integerKeypadRejectsDecimalPointAndRespectsMaximum(text: String, keys: String, expected: String) {
    #expect(typed(keys, into: text, maxDigits: 6, maxFractionDigits: 0, maximum: 100_000) == expected)
}

@Test func maximumRefusesOnlyTheKeyThatWouldPassIt() {
    #expect(typed("9", into: "99.9", maximum: amount("99.99")) == "99.99")
    #expect(typed("9", into: "99.99", maximum: amount("99.99")) == "99.99")
    #expect(typed("1", into: "10", maximum: 100) == "10")
    #expect(typed(".", into: "100", maximum: 100) == "100.")
    #expect(typed("0", into: "100.", maximum: 100) == "100.0")
    #expect(typed("1", into: "100.", maximum: 100) == "100.")
}

@Test func deleteAndClearEditTheText() {
    #expect(typed("<", into: "12.5") == "12.")
    #expect(typed("<", into: "12.") == "12")
    #expect(typed("<", into: "") == "")
    #expect(typed("C", into: "12.5") == "")
    #expect(typed("C", into: "") == "")
    for invalid in [KeypadKey.digit(10), .digit(-1)] {
        #expect(KeypadInput.apply(invalid, to: "12", maxDigits: 7, maxFractionDigits: 2) == "12")
    }
}

@Test func valueParsesExactDecimalWithoutDouble() {
    #expect(KeypadInput.value(of: "") == nil)
    #expect(KeypadInput.value(of: "12.") == 12)
    #expect(KeypadInput.value(of: "0.") == 0)
    #expect(KeypadInput.value(of: "0") == 0)
    #expect(KeypadInput.value(of: "0.07") == amount("0.07"))
    #expect(KeypadInput.value(of: "123456.7") == amount("123456.7"))
    #expect(KeypadInput.value(of: "1234567") == 1_234_567)
    #expect(KeypadInput.value(of: "99999.99") == amount("99999.99"))
}

@Test func valueRefusesTextTheKeypadCannotProduce() {
    for text in [".", "-1", "1e3", "1,000", " 12", "１２", "1.2.3", "abc"] {
        #expect(KeypadInput.value(of: text) == nil, "\(text)")
    }
}

@Test func charactersMapToKeysOnlyForHalfWidthDigitsAndPoint() {
    #expect(KeypadKey(Character("7")) == .digit(7))
    #expect(KeypadKey(Character("0")) == .digit(0))
    #expect(KeypadKey(Character(".")) == .decimalPoint)
    for other: Character in ["１", "-", ",", " ", "e", "a", "٣"] {
        #expect(KeypadKey(other) == nil, "\(other)")
    }
}

// D22: the Face ID threshold sheet re-enters its text field's text through the keypad rules.
@Test(arguments: [("", ""), ("250", "250"), ("000250", "250"), ("100000", "100000"), ("100001", "10000"), ("1000000", "100000"),
                  ("999999", "99999"), ("12.5", "125"), ("1,000", "1000"), ("１２", ""), ("-5", "5"), ("0", "0")])
func retypeFiltersThresholdTextLikeTheKeypad(text: String, expected: String) {
    #expect(KeypadInput.retype(text, maxDigits: 6, maxFractionDigits: 0, maximum: 100_000) == expected)
}

@Test func retypeKeepsDecimalsWhereTheKeypadAllowsThem() {
    #expect(KeypadInput.retype("12.345", maxDigits: 7, maxFractionDigits: 2) == "12.34")
    #expect(KeypadInput.retype(".5", maxDigits: 7, maxFractionDigits: 2) == "5")
    #expect(KeypadInput.retype("1.2.3", maxDigits: 7, maxFractionDigits: 2) == "1.23")
}

@Test func padLayoutMatchesDesign() {
    let digits = (1...9).map(KeypadKey.digit)
    #expect(KeypadKey.pad == digits + [.decimalPoint, .digit(0), .delete])
}
