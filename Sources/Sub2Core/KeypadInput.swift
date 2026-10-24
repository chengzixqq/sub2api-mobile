import Foundation

/// A key of the big-number keypad (design `KeypadSheet`, 30 §3.3).
public enum KeypadKey: Hashable, Sendable {
    case digit(Int)
    case decimalPoint
    case delete
    case clear

    /// The 3 × 4 pad: 1–9, ".", 0, delete.
    public static let pad: [KeypadKey] = (1...9).map(KeypadKey.digit) + [.decimalPoint, .digit(0), .delete]

    /// A typed character: half-width digits and "."; anything else (full-width digits, signs, separators) is not a key.
    public init?(_ character: Character) {
        if character == "." { self = .decimalPoint; return }
        guard character.isASCII, let digit = character.wholeNumberValue else { return nil }
        self = .digit(digit)
    }
}

/// 30 §3.7: the keypad's input rules as a pure function, so every keypad (top-up / refund 7 digits with 2 decimals, redeem
/// face values 6 and 2, the Face ID threshold 6 and 0 up to 100,000) shares one set of rules. A refused key returns `text`.
public enum KeypadInput {
    /// `maxDigits` counts every digit, the decimal part included (the point does not count); a full text takes neither digits
    /// nor the point. "." on an empty text is ignored, a lone "0" is replaced by the next digit, and with `maximum` a key
    /// whose result would exceed it is refused.
    public static func apply(_ key: KeypadKey, to text: String, maxDigits: Int, maxFractionDigits: Int, maximum: Decimal? = nil) -> String {
        let next: String
        switch key {
        case .delete: return String(text.dropLast())
        case .clear: return ""
        case .decimalPoint:
            guard maxFractionDigits > 0, !text.isEmpty, !text.contains("."), digitCount(text) < maxDigits else { return text }
            next = text + "."
        case .digit(let digit):
            guard (0...9).contains(digit), digitCount(text) < maxDigits else { return text }
            if let point = text.firstIndex(of: "."), text[text.index(after: point)...].count >= maxFractionDigits { return text }
            next = text == "0" ? String(digit) : text + String(digit)
        }
        if let maximum, let value = value(of: next), value > maximum { return text }
        return next
    }

    /// A system text field's new text entered again key by key from empty, so typing or pasting into it follows the same
    /// rules; characters that are not keys are dropped.
    public static func retype(_ text: String, maxDigits: Int, maxFractionDigits: Int, maximum: Decimal? = nil) -> String {
        text.compactMap(KeypadKey.init).reduce("") {
            apply($1, to: $0, maxDigits: maxDigits, maxFractionDigits: maxFractionDigits, maximum: maximum)
        }
    }

    /// The typed amount as an exact Decimal (never through Double); "12." is 12, an empty text is nil, and anything the
    /// keypad cannot produce is nil.
    public static func value(of text: String) -> Decimal? {
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        guard let integer = parts.first, !integer.isEmpty, integer.utf8.allSatisfy(isDigit),
              parts.count == 1 || parts[1].utf8.allSatisfy(isDigit) else { return nil }
        return Decimal(string: text.hasSuffix(".") ? String(integer) : text, locale: Locale(identifier: "en_US_POSIX"))
    }

    private static func digitCount(_ text: String) -> Int { text.utf8.filter(isDigit).count }
    private static func isDigit(_ byte: UInt8) -> Bool { (48...57).contains(byte) }
}
