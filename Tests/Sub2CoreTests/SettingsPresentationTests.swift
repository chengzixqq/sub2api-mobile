import Foundation
import Testing
@testable import Sub2Core

private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Test func sectionsAreNumberedOverTheOnesShown() {
    let all = SettingsPresentation.visibleSections(showsNotifications: true, hasCurrentSite: true, hasPending: true)
    #expect(all.map(\.section) == SettingsPresentation.Section.allCases)
    #expect(all.map(\.ordinal) == ["壹", "贰", "叁", "肆", "伍", "陆", "柒", "捌"])
    #expect(all.map(\.section.title) == ["界面模式", "外观", "安全", "通知", "站点", "当前站点", "待核对", "关于"])

    let noPush = SettingsPresentation.visibleSections(showsNotifications: false, hasCurrentSite: true, hasPending: true)
    #expect(noPush.first { $0.section == .sites }?.ordinal == "肆")
    let calm = SettingsPresentation.visibleSections(showsNotifications: true, hasCurrentSite: true, hasPending: false)
    #expect(calm.last?.section == .about && calm.last?.ordinal == "柒")
    let bare = SettingsPresentation.visibleSections(showsNotifications: false, hasCurrentSite: false, hasPending: false)
    #expect(bare.map(\.section) == [.interface, .appearance, .security, .sites, .about])
}

@Test func identityLineShowsEmailAndRole() {
    #expect(SettingsPresentation.identityLine(email: "admin@example.com", role: "admin") == "admin@example.com · 管理员")
    #expect(SettingsPresentation.identityLine(email: "admin@example.com", role: nil) == "admin@example.com")
    #expect(SettingsPresentation.identityLine(email: "admin@example.com", role: "owner") == "admin@example.com")
    #expect(SettingsPresentation.identityLine(email: nil, role: "admin") == "—")
    #expect(SettingsPresentation.identityLine(email: " ", role: "admin") == "—")
}

@Test func sessionBindingHintFollowsTheNativeMode() {
    let base = "站点开启了会话绑定；切换网络可能需要重新登录"
    let advice = base + "。可请站长把原生客户端绑定方式设为 device"
    #expect(SettingsPresentation.sessionBindingHint(authMethod: .jwt, bindingEnabled: false, nativeMode: "strict") == nil)
    #expect(SettingsPresentation.sessionBindingHint(authMethod: .jwt, bindingEnabled: nil, nativeMode: nil) == nil)
    #expect(SettingsPresentation.sessionBindingHint(authMethod: .jwt, bindingEnabled: true, nativeMode: nil) == base)
    #expect(SettingsPresentation.sessionBindingHint(authMethod: .jwt, bindingEnabled: true, nativeMode: "device") == nil)
    #expect(SettingsPresentation.sessionBindingHint(authMethod: .jwt, bindingEnabled: true, nativeMode: "off") == nil)
    #expect(SettingsPresentation.sessionBindingHint(authMethod: .jwt, bindingEnabled: true, nativeMode: "strict") == advice)
    #expect(SettingsPresentation.sessionBindingHint(authMethod: .jwt, bindingEnabled: true, nativeMode: "ua_only") == advice)
    // The server reads an empty mode as strict.
    #expect(SettingsPresentation.sessionBindingHint(authMethod: .jwt, bindingEnabled: true, nativeMode: "") == advice)
    #expect(SettingsPresentation.sessionBindingHint(authMethod: .jwt, bindingEnabled: true, nativeMode: "later") == base)
    // Admin Key and sat_ have no session to bind.
    #expect(SettingsPresentation.sessionBindingHint(authMethod: .adminAPIKey, bindingEnabled: true, nativeMode: nil) == nil)
    #expect(SettingsPresentation.sessionBindingHint(authMethod: .adminAccessToken, bindingEnabled: true, nativeMode: "strict") == nil)
}

@Test func bindingModeIsReadOnlyForABoundAccountSessionWithoutPendingCompliance() {
    let admin = AdminMe.User(id: 1, email: "admin@example.com", role: "admin")
    let bound = AdminMe(authMethod: .jwt, user: admin, security: .init(sessionBindingEnabled: true))
    #expect(SettingsPresentation.readsBindingMode(me: bound, authMethod: .jwt))
    #expect(SettingsPresentation.readsBindingMode(me: bound, authMethod: .adminAPIKey) == false)
    #expect(SettingsPresentation.readsBindingMode(me: AdminMe(authMethod: .jwt, user: admin), authMethod: .jwt) == false)
    let unaccepted = AdminMe(authMethod: .jwt, user: admin, security: .init(sessionBindingEnabled: true), compliance: .init(required: true))
    #expect(SettingsPresentation.readsBindingMode(me: unaccepted, authMethod: .jwt) == false)
    // 00 §1.2: only the admin role reads admin/settings; the server refuses a workspace vendor there (403 FORBIDDEN).
    let vendor = AdminMe(authMethod: .jwt, user: .init(id: 2, email: "vendor@example.com", role: "vendor"),
                         workspace: .init(id: 3, name: "工作区"), security: .init(sessionBindingEnabled: true))
    #expect(SettingsPresentation.readsBindingMode(me: vendor, authMethod: .jwt) == false)
}

@Test func removeSiteMessageAddsTheRevocationOnlyForAccessTokens() {
    let existing = "主站\n站点配置和本机凭据将被清除。旧身份的未决余额记录仍保留，之后仅可在 Web 后台核对。"
    #expect(SettingsPresentation.removeSiteMessage(name: "主站", authentication: .password) == existing)
    #expect(SettingsPresentation.removeSiteMessage(name: "主站", authentication: .adminKey) == existing)
    #expect(SettingsPresentation.removeSiteMessage(name: "主站", authentication: .accessToken) == existing + "\n同时吊销这个管理访问令牌")
}

@Test func sessionsRowDependsOnTheSignInAndTheServer() {
    #expect(SettingsPresentation.sessionsRow(authMethod: .jwt, fallback: .password, sessionsSupported: true) == .available)
    #expect(SettingsPresentation.sessionsRow(authMethod: .jwt, fallback: .password, sessionsSupported: false) == .hidden)
    #expect(SettingsPresentation.sessionsRow(authMethod: .adminAPIKey, fallback: .adminKey, sessionsSupported: true) == .notApplicable)
    #expect(SettingsPresentation.sessionsRow(authMethod: .adminAccessToken, fallback: .accessToken, sessionsSupported: true) == .notApplicable)
    #expect(SettingsPresentation.sessionsRow(authMethod: nil, fallback: .password, sessionsSupported: true) == .available)
    #expect(SettingsPresentation.sessionsRow(authMethod: nil, fallback: .accessToken, sessionsSupported: true) == .notApplicable)
}

@Test func tokenAndPushRowsNeedTheirCapabilityAndNoWorkspace() {
    let all = AdminMe.Server(capabilities: [Capability.adminAccessTokens.rawValue, Capability.pushNotifications.rawValue])
    let owner = AdminMe(authMethod: .jwt, user: .init(role: "admin"), server: all)
    #expect(SettingsPresentation.showsAccessTokens(owner))
    #expect(SettingsPresentation.showsNotifications(owner))
    let vendor = AdminMe(authMethod: .jwt, workspace: .init(id: 3), server: all)
    #expect(SettingsPresentation.showsAccessTokens(vendor) == false)
    #expect(SettingsPresentation.showsNotifications(vendor) == false)
    let old = AdminMe(authMethod: .jwt)
    #expect(SettingsPresentation.showsAccessTokens(old) == false)
    #expect(SettingsPresentation.showsNotifications(old) == false)
}

@Test func activeTokenCountLeavesExpiredTokensOut() throws {
    let json = #"[{"id":1,"expires_at":null},{"id":2,"expires_at":"2027-02-01T00:00:00Z"},{"id":3,"expires_at":"2020-01-01T00:00:00Z"},{"id":4}]"#
    let tokens = try JSONDecoder().decode([AdminAccessToken].self, from: Data(json.utf8))
    #expect(SettingsPresentation.activeTokenCount(tokens, now: now) == 3)
}

@Test func pendingRowsPrefixTheSiteToTheSharedLine() {
    let created = now.addingTimeInterval(-300)
    let refund = PendingMoneyWriteSummary(subject: .balance(.subtract, amount: Decimal(string: "12.5")!), createdAt: created,
                                          userID: 1, userDisplayName: "Alice")
    #expect(SettingsPresentation.pendingRow(siteName: "主站", summary: refund, now: now, timeZone: shanghai)
            == .init(title: "退款结果待核对", detail: "主站 · Alice · 5 分钟前 · 未确认是否入账", amount: "$12.50"))
    let wipe = PendingMoneyWriteSummary(subject: .balance(.set, amount: 0), createdAt: nil, userID: 9)
    #expect(SettingsPresentation.pendingRow(siteName: "旧站", summary: wipe, now: now, timeZone: shanghai)
            == .init(title: "退款结果待核对", detail: "旧站 · 用户 #9 · 未确认是否入账", amount: "全部余额"))
    let batch = PendingMoneyWriteSummary(subject: .redeemBatch(count: 20, total: 200), createdAt: created)
    #expect(SettingsPresentation.pendingRow(siteName: "主站", summary: batch, now: now, timeZone: shanghai)
            == .init(title: "兑换码生成结果待核对", detail: "主站 · 20 个 · 5 分钟前 · 未确认是否生成", amount: "$200.00"))
    let grant = PendingMoneyWriteSummary(subject: .compensation(.concurrency, value: 2), createdAt: created, userID: 3, userDisplayName: "王小明")
    #expect(SettingsPresentation.pendingRow(siteName: "主站", summary: grant, now: now, timeZone: shanghai)
            == .init(title: "补偿结果待核对", detail: "主站 · 王小明 · 5 分钟前 · 未确认是否发放", amount: nil))
}

@Test func pushStatusAndThresholdText() {
    #expect(SettingsPresentation.pushStatus(isRegistered: true) == "已开启")
    #expect(SettingsPresentation.pushStatus(isRegistered: false) == "未开启")
    #expect(SettingsPresentation.thresholdText(100) == "$100")
    #expect(SettingsPresentation.thresholdText(100_000) == "$100,000")
}

// S3-07, C-26: an older login's record at this address is checked here; only another address's opens its site.
@Test func pendingRowOfSameAddressOldLoginIsCheckedHereWithNote() {
    let refund = PendingMoneyWriteSummary(subject: .balance(.subtract, amount: Decimal(string: "12.5")!), createdAt: now.addingTimeInterval(-300),
                                          userID: 1, userDisplayName: "Alice")
    let row = SettingsPresentation.pendingRow(siteName: "主站", summary: refund, now: now, timeZone: shanghai, origin: .sameAddressOldLogin)
    #expect(row.action == .check)
    #expect(row.originNote == "本站点的旧登录下发起")
    #expect(row.title == "退款结果待核对" && row.detail == "主站 · Alice · 5 分钟前 · 未确认是否入账" && row.amount == "$12.50")
}

@Test func pendingRowOfOtherAddressOpensOriginalSite() {
    let grant = PendingMoneyWriteSummary(subject: .compensation(.balance, value: 10), createdAt: now, userID: 3, userDisplayName: "王小明")
    let row = SettingsPresentation.pendingRow(siteName: "旧站", summary: grant, now: now, timeZone: shanghai, origin: .otherAddress)
    #expect(row.action == .openOriginalSite)
    #expect(row.originNote == nil)
}

@Test func pendingRowDefaultsToCurrentSite() {
    let batch = PendingMoneyWriteSummary(subject: .redeemBatch(count: 20, total: 200), createdAt: now)
    let row = SettingsPresentation.pendingRow(siteName: "主站", summary: batch, now: now, timeZone: shanghai)
    #expect(row.action == .check && row.originNote == nil)
    #expect(row == SettingsPresentation.PendingRow(title: "兑换码生成结果待核对", detail: "主站 · 20 个 · 刚刚 · 未确认是否生成", amount: "$200.00"))
}
