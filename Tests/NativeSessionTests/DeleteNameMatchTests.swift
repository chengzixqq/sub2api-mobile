import Testing
@testable import NativeSessionSupport

private let redeemCode = "a3f09c1be27d4f60918c3b5e7a2fd4e8"
private let allRules: [DeleteNameMatch.Rule] = [.exact, .caseInsensitive, .suffix(4)]

@Test(arguments: [("王小明", "王小明", true), ("脚本 key", "脚本 Key", false), ("王小", "王小明", false), ("王小明明", "王小明", false)])
func exactRequiresTheWholeNameInTheSameCase(input: String, expected: String, matches: Bool) {
    #expect(DeleteNameMatch.matches(input: input, expected: expected, rule: .exact) == matches)
}

@Test(arguments: [(" 王小明\n", "王小明", DeleteNameMatch.Rule.exact), ("王小明", "  王小明 ", .exact), (" A3F0 ", "a3f0", .caseInsensitive),
                  (" D4E8\t", redeemCode, .suffix(4))])
func surroundingWhitespaceIsIgnoredOnBothSides(input: String, expected: String, rule: DeleteNameMatch.Rule) {
    #expect(DeleteNameMatch.matches(input: input, expected: expected, rule: rule))
}

@Test func emptyOrBlankInputNeverMatches() {
    for rule in allRules {
        #expect(DeleteNameMatch.matches(input: "", expected: "王小明", rule: rule) == false, "\(rule)")
        #expect(DeleteNameMatch.matches(input: "  \n", expected: redeemCode, rule: rule) == false, "\(rule)")
    }
}

@Test func emptyExpectedNeverMatches() {
    // Nothing typed must never delete something whose name happens to be blank.
    for rule in allRules {
        #expect(DeleteNameMatch.matches(input: "", expected: "", rule: rule) == false, "\(rule)")
        #expect(DeleteNameMatch.matches(input: "", expected: "   ", rule: rule) == false, "\(rule)")
    }
}

@Test func caseInsensitiveComparesTheWholeName() {
    #expect(DeleteNameMatch.matches(input: "ABC-key", expected: "abc-KEY", rule: .caseInsensitive))
    #expect(DeleteNameMatch.matches(input: "abc", expected: "abc-key", rule: .caseInsensitive) == false)
}

@Test func suffixTakesTheLastCharactersInAnyCase() {
    #expect(DeleteNameMatch.matches(input: "d4e8", expected: redeemCode, rule: .suffix(4)))
    #expect(DeleteNameMatch.matches(input: "D4E8", expected: redeemCode, rule: .suffix(4)))
    #expect(DeleteNameMatch.matches(input: "4e8", expected: redeemCode, rule: .suffix(4)) == false)
    #expect(DeleteNameMatch.matches(input: "fd4e8", expected: redeemCode, rule: .suffix(4)) == false)
    #expect(DeleteNameMatch.matches(input: redeemCode, expected: redeemCode, rule: .suffix(4)) == false)
    #expect(DeleteNameMatch.target(expected: redeemCode, rule: .suffix(4)) == "d4e8")
}

@Test func suffixLongerThanTheExpectedTextUsesAllOfIt() {
    // A hand-written compensation code may be three characters long (min=3 on the server).
    #expect(DeleteNameMatch.target(expected: "ab1", rule: .suffix(4)) == "ab1")
    #expect(DeleteNameMatch.matches(input: "AB1", expected: "ab1", rule: .suffix(4)))
    #expect(DeleteNameMatch.matches(input: "b1", expected: "ab1", rule: .suffix(4)) == false)
}

@Test func suffixIsTakenAfterTrimmingTheExpectedText() {
    #expect(DeleteNameMatch.target(expected: "  xyz-1234 \n", rule: .suffix(4)) == "1234")
    #expect(DeleteNameMatch.matches(input: "1234", expected: "  xyz-1234 \n", rule: .suffix(4)))
}

@Test func nonPositiveSuffixNeverMatches() {
    for rule: DeleteNameMatch.Rule in [.suffix(0), .suffix(-2)] {
        #expect(DeleteNameMatch.target(expected: "abcd", rule: rule) == "", "\(rule)")
        #expect(DeleteNameMatch.matches(input: "", expected: "abcd", rule: rule) == false, "\(rule)")
        #expect(DeleteNameMatch.matches(input: "abcd", expected: "abcd", rule: rule) == false, "\(rule)")
    }
}

@Test func fullNameTargetsAreTheTrimmedName() {
    #expect(DeleteNameMatch.target(expected: " 王小明 ", rule: .exact) == "王小明")
    #expect(DeleteNameMatch.target(expected: "ABC-key", rule: .caseInsensitive) == "ABC-key")
}

@Test(arguments: [("分组A", "分组A"), ("分组a", "分组A"), (" 分组A ", "分组A"), ("", "分组A"), ("分组", "分组A"), ("x", ""), ("Key", "key")])
func fullNameRulesAgreeWithBiometricGate(input: String, expected: String) {
    #expect(DeleteNameMatch.matches(input: input, expected: expected, rule: .exact)
            == BiometricGate.deleteNameMatches(input, expected: expected))
    #expect(DeleteNameMatch.matches(input: input, expected: expected, rule: .caseInsensitive)
            == BiometricGate.deleteNameMatches(input, expected: expected, caseInsensitive: true))
}

@Test func titleAndDefaultSiteLineFollowTheDesign() {
    #expect(DeleteConfirmationCopy.title(objectNoun: "用户", displayName: "王小明") == "删除用户「王小明」？")
    #expect(DeleteConfirmationCopy.title(objectNoun: "兑换码", displayName: "····d4e8") == "删除兑换码「····d4e8」？")
    #expect(DeleteConfirmationCopy.siteLine(siteName: "主站") == "站点 主站 · 删除后不能恢复。")
}

@Test func messageListsTheSiteLineThenConsequences() {
    let site = DeleteConfirmationCopy.siteLine(siteName: "主站")
    #expect(DeleteConfirmationCopy.message(siteLine: site, consequences: ["名下 2 个 Key 一并删除。"], confirmation: .typeName)
            == "站点 主站 · 删除后不能恢复。\n名下 2 个 Key 一并删除。")
    #expect(DeleteConfirmationCopy.message(siteLine: site, consequences: [], confirmation: .typeName) == site)
    #expect(DeleteConfirmationCopy.message(siteLine: site, consequences: ["", " "], confirmation: .typeName) == site)
    #expect(DeleteConfirmationCopy.message(siteLine: site, consequences: ["名下 2 个 Key 一并删除。"], confirmation: .biometric)
            == "站点 主站 · 删除后不能恢复。\n名下 2 个 Key 一并删除。\n确认后验证 Face ID。")
    #expect(DeleteConfirmationCopy.message(siteLine: site, consequences: [], confirmation: .biometric) == site + "\n确认后验证 Face ID。")
}

@Test func buttonsAndInputFollowTheMode() {
    #expect(DeleteConfirmationCopy.confirmTitle(objectNoun: "分组", confirmation: .typeName) == "删除分组")
    #expect(DeleteConfirmationCopy.confirmTitle(objectNoun: "分组", confirmation: .biometric) == "用 Face ID 删除")
    #expect(DeleteConfirmationCopy.inputLabel(expected: "王小明", rule: .exact) == "输入「王小明」确认删除")
    #expect(DeleteConfirmationCopy.inputLabel(expected: redeemCode, rule: .suffix(4)) == "输入末 4 位确认删除")
    #expect(DeleteConfirmationCopy.inputLabel(expected: "ab1", rule: .suffix(4)) == "输入末 3 位确认删除")
    #expect(DeleteConfirmationCopy.inputPlaceholder(objectNoun: "用户", expected: "王小明", rule: .exact, custom: nil) == "用户名称")
    #expect(DeleteConfirmationCopy.inputPlaceholder(objectNoun: "兑换码", expected: redeemCode, rule: .suffix(4), custom: nil) == "末 4 位")
    #expect(DeleteConfirmationCopy.inputPlaceholder(objectNoun: "用户", expected: "a@example.com", rule: .exact, custom: "用户邮箱")
            == "用户邮箱")
    #expect(DeleteConfirmationCopy.biometricReason(objectNoun: "用户", displayName: "王小明") == "删除用户「王小明」")
}

@Test func latinNounsAreSpacedFromChinese() {
    #expect(DeleteConfirmationCopy.joined("删除", "用户") == "删除用户")
    #expect(DeleteConfirmationCopy.joined("删除", "Key") == "删除 Key")
    #expect(DeleteConfirmationCopy.joined("Key", "名称") == "Key 名称")
    #expect(DeleteConfirmationCopy.joined("删除", "2FA") == "删除 2FA")
    #expect(DeleteConfirmationCopy.joined("Key", "「脚本」") == "Key「脚本」")
    #expect(DeleteConfirmationCopy.title(objectNoun: "Key", displayName: "脚本") == "删除 Key「脚本」？")
    #expect(DeleteConfirmationCopy.confirmTitle(objectNoun: "Key", confirmation: .typeName) == "删除 Key")
    #expect(DeleteConfirmationCopy.inputPlaceholder(objectNoun: "Key", expected: "脚本", rule: .exact, custom: nil) == "Key 名称")
    #expect(DeleteConfirmationCopy.biometricReason(objectNoun: "Key", displayName: "脚本") == "删除 Key「脚本」")
}

@Test func deletedReceiptSpacesLatinNouns() {
    #expect(DeleteConfirmationCopy.deletedReceipt(objectNoun: "Key", displayName: "脚本") == "已删除 Key「脚本」")
    #expect(DeleteConfirmationCopy.deletedReceipt(objectNoun: "用户", displayName: "王小明") == "已删除用户「王小明」")
    #expect(DeleteConfirmationCopy.deletedReceipt(objectNoun: "兑换码", displayName: "····d4e8") == "已删除兑换码「····d4e8」")
}
