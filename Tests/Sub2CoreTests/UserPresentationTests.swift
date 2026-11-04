import Foundation
import Testing
@testable import Sub2Core

private func member(balance: Decimal, status: String = "active", threshold: Decimal? = nil, type: String? = nil, recharged: Decimal? = nil) -> AdminUser {
    AdminUser(id: 3, email: "wang@example.invalid", balance: balance, status: status, totalRecharged: recharged,
              balanceNotifyThreshold: threshold, balanceNotifyThresholdType: type)
}

struct LowBalanceCase: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let user: AdminUser
    let global: UserLowBalanceGlobal
    let threshold: Decimal?
    let isLow: Bool
}

private let globalOn = UserLowBalanceGlobal(enabled: true, threshold: 10)
private let globalOff = UserLowBalanceGlobal(enabled: false, threshold: 10)

private let lowBalanceCases: [LowBalanceCase] = [
    .init(testDescription: "用户固定阈值", user: member(balance: Decimal(string: "19.99")!, threshold: 20, type: "fixed"), global: .off, threshold: 20, isLow: true),
    .init(testDescription: "余额等于阈值不标", user: member(balance: 20, threshold: 20, type: "fixed"), global: globalOn, threshold: 20, isLow: false),
    .init(testDescription: "全局开、无用户阈值", user: member(balance: 9), global: globalOn, threshold: 10, isLow: true),
    .init(testDescription: "全局关、无用户阈值", user: member(balance: 9), global: globalOff, threshold: nil, isLow: false),
    .init(testDescription: "全局关但有用户阈值", user: member(balance: 4, threshold: 5), global: globalOff, threshold: 5, isLow: true),
    .init(testDescription: "全局阈值 0", user: member(balance: 0), global: UserLowBalanceGlobal(enabled: true, threshold: 0), threshold: nil, isLow: false),
    .init(testDescription: "全局阈值缺失", user: member(balance: 0), global: UserLowBalanceGlobal(enabled: true, threshold: nil), threshold: nil, isLow: false),
    .init(testDescription: "百分比、总充值 100", user: member(balance: Decimal(string: "9.99")!, threshold: 10, type: "percentage", recharged: 100),
          global: .off, threshold: 10, isLow: true),
    .init(testDescription: "百分比、总充值 300", user: member(balance: 20, threshold: 10, type: "percentage", recharged: 300), global: .off, threshold: 30, isLow: true),
    .init(testDescription: "百分比、总充值 0 按美元", user: member(balance: 9, threshold: 10, type: "percentage", recharged: 0), global: .off, threshold: 10, isLow: true),
    .init(testDescription: "百分比、旧服务端无总充值按美元", user: member(balance: 11, threshold: 10, type: "percentage"), global: .off, threshold: 10, isLow: false),
    .init(testDescription: "百分比套在全局阈值上", user: member(balance: 15, type: "percentage", recharged: 200), global: globalOn, threshold: 20, isLow: true),
    .init(testDescription: "用户阈值 0 不回落全局", user: member(balance: 1, threshold: 0), global: globalOn, threshold: 0, isLow: false),
    .init(testDescription: "负余额低于阈值", user: member(balance: -3), global: globalOn, threshold: 10, isLow: true),
    .init(testDescription: "禁用不标", user: member(balance: 1, status: "disabled", threshold: 20), global: globalOn, threshold: 20, isLow: false),
]

@Test(arguments: lowBalanceCases)
func lowBalanceFollowsQuickTopupRules(_ example: LowBalanceCase) {
    #expect(UserPresentation.lowBalanceThreshold(user: example.user, global: example.global) == example.threshold)
    #expect(UserPresentation.isLowBalance(user: example.user, global: example.global) == example.isLow)
}

@Test func globalLowBalanceComesFromPublicSettings() throws {
    let on = try JSONDecoder().decode(PublicSettings.self, from: Data(#"{"balance_low_notify_enabled":true,"balance_low_notify_threshold":5}"#.utf8))
    #expect(UserLowBalanceGlobal(settings: on) == UserLowBalanceGlobal(enabled: true, threshold: 5))
    let old = try JSONDecoder().decode(PublicSettings.self, from: Data("{}".utf8))
    #expect(UserLowBalanceGlobal(settings: old) == .off)
    #expect(UserLowBalanceGlobal.off == UserLowBalanceGlobal(enabled: false, threshold: nil))
}

@Test func listMarkPrefersPendingThenDisabledThenLowBalance() {
    let disabledLow = member(balance: 1, status: "disabled", threshold: 20), low = member(balance: 1), rich = member(balance: 100)
    #expect(UserPresentation.listMark(user: disabledLow, hasPendingBalance: true, global: globalOn) == .pending)
    #expect(UserPresentation.listMark(user: rich, hasPendingBalance: true, global: globalOn) == .pending)
    #expect(UserPresentation.listMark(user: disabledLow, hasPendingBalance: false, global: globalOn) == .disabled)
    #expect(UserPresentation.listMark(user: low, hasPendingBalance: false, global: globalOn) == .lowBalance)
    #expect(UserPresentation.listMark(user: low, hasPendingBalance: false, global: .off) == nil)
    #expect(UserPresentation.listMark(user: rich, hasPendingBalance: false, global: globalOn) == nil)
    #expect(UserListMark.allCases.map(\.label) == ["待核对", "禁用", "余额低"])
}

@Test func namesInitialsAndWords() {
    let named = AdminUser(id: 1, email: "wang@example.invalid", username: "  王小明 ")
    #expect(UserPresentation.displayName(named) == "王小明" && named.displayName == "王小明")
    #expect(UserPresentation.displayName(username: " ", email: "alice@example.invalid") == "alice")
    #expect(UserPresentation.displayName(username: nil, email: "no-at-sign") == "no-at-sign")
    #expect(UserPresentation.initial("alice") == "A" && UserPresentation.initial("王小明") == "王")
    #expect(UserPresentation.initial("élan") == "É" && UserPresentation.initial("7号") == "7" && UserPresentation.initial("") == "?")
    #expect(UserPresentation.statusWord("active") == "启用" && UserPresentation.statusWord("disabled") == "禁用")
    #expect(UserPresentation.statusWord("frozen") == "frozen" && UserPresentation.statusWord("") == "—")
    #expect(UserPresentation.roleWord("user") == "用户" && UserPresentation.roleWord("vendor") == "供应商" && UserPresentation.roleWord("admin") == "管理员")
    #expect(UserPresentation.roleWord("owner") == "owner" && UserPresentation.roleWord(nil) == "—" && UserPresentation.roleWord("") == "—")
}
