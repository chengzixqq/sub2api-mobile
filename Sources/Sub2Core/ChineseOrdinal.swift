import Foundation

/// Section numbers of the search directory and the settings page (60 §1.3, §3.3): 壹…拾; other numbers stay Arabic.
public enum ChineseOrdinal {
    private static let numerals = ["壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌", "玖", "拾"]

    public static func text(_ number: Int) -> String {
        numerals.indices.contains(number - 1) ? numerals[number - 1] : String(number)
    }
}
