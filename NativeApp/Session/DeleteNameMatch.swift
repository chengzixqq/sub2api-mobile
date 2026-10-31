import Foundation

/// C-2: what the delete confirmation asks to be typed (60 §0.4). The whole name, compared as is or in any case, or a redeem
/// code's last characters in any case. Trimming and “nothing typed never matches” are BiometricGate.deleteNameMatches's.
enum DeleteNameMatch {
    enum Rule: Equatable, Sendable { case exact, caseInsensitive, suffix(Int) }

    /// The text to type: the trimmed name, or its last `n` characters (all of it when shorter; nothing for `n` ≤ 0).
    static func target(expected: String, rule: Rule) -> String {
        let trimmed = expected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .suffix(let count) = rule else { return trimmed }
        guard count > 0 else { return "" }
        return String(trimmed.suffix(count))
    }

    static func matches(input: String, expected: String, rule: Rule) -> Bool {
        switch rule {
        case .exact: BiometricGate.deleteNameMatches(input, expected: expected)
        case .caseInsensitive: BiometricGate.deleteNameMatches(input, expected: expected, caseInsensitive: true)
        case .suffix: BiometricGate.deleteNameMatches(input, expected: target(expected: expected, rule: rule), caseInsensitive: true)
        }
    }
}

/// The delete confirmation's wording (design `confirmDelete`, 60 §0.4) and the one receipt every chapter shows after a delete.
/// Nouns written in Latin letters are spaced from the Chinese around them: “删除 Key「脚本」？” (30 §7.4).
enum DeleteConfirmationCopy {
    static let faceIDButton = "用 Face ID 删除"
    static let faceIDLine = "确认后验证 Face ID。"

    /// One space where a Latin letter or digit meets a Chinese character.
    static func joined(_ head: String, _ tail: String) -> String {
        guard let last = head.last, let first = tail.first else { return head + tail }
        let spaced = (isLatin(last) && isChinese(first)) || (isChinese(last) && isLatin(first))
        return spaced ? head + " " + tail : head + tail
    }

    static func title(objectNoun: String, displayName: String) -> String {
        biometricReason(objectNoun: objectNoun, displayName: displayName) + "？"
    }
    static func siteLine(siteName: String) -> String { "站点 \(siteName) · 删除后不能恢复。" }
    /// The site line, then what goes with the object, then with Face ID on the line saying it is verified next.
    static func message(siteLine: String, consequences: [String], confirmation: DeleteConfirmation) -> String {
        let lines = consequences.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return ([siteLine] + lines + (confirmation == .biometric ? [faceIDLine] : [])).joined(separator: "\n")
    }
    static func confirmTitle(objectNoun: String, confirmation: DeleteConfirmation) -> String {
        confirmation == .biometric ? faceIDButton : joined("删除", objectNoun)
    }
    /// Above the field. A redeem code's last characters are never printed here.
    static func inputLabel(expected: String, rule: DeleteNameMatch.Rule) -> String {
        let target = DeleteNameMatch.target(expected: expected, rule: rule)
        if case .suffix = rule { return "输入末 \(target.count) 位确认删除" }
        return "输入「\(target)」确认删除"
    }
    static func inputPlaceholder(objectNoun: String, expected: String, rule: DeleteNameMatch.Rule, custom: String?) -> String {
        if let custom { return custom }
        if case .suffix = rule { return "末 \(DeleteNameMatch.target(expected: expected, rule: rule).count) 位" }
        return joined(objectNoun, "名称")
    }
    /// The line under the system prompt; a redeem code's display name is already masked.
    static func biometricReason(objectNoun: String, displayName: String) -> String {
        joined("删除", objectNoun) + "「\(displayName)」"
    }
    static func deletedReceipt(objectNoun: String, displayName: String) -> String {
        joined("已删除", objectNoun) + "「\(displayName)」"
    }

    private static func isLatin(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }
    private static func isChinese(_ character: Character) -> Bool {
        character.unicodeScalars.first?.properties.isIdeographic == true
    }
}
