import Foundation
import Testing
@testable import Sub2Core

// 50 §3.2–§3.5 (S5-10): the group sheet's form — defaults, checks, what it sends, how a lost result is matched — and its words.

private func amount(_ raw: String) -> Decimal { Decimal(string: raw)! }
private let premium = AdminGroup(id: 1, name: "高级组", description: "", platform: "anthropic", rateMultiplier: amount("0.8"), rpmLimit: 0)
private let standardGroup = AdminGroup(id: 2, name: "标准组", description: "", platform: "openai", rateMultiplier: amount("0.8"), rpmLimit: 600)
private let enterprise = AdminGroup(id: 4, name: "企业专线", description: "", platform: "openai", rateMultiplier: amount("1.2"), isExclusive: true,
                                    subscriptionType: "subscription", dailyLimitUSD: 20, weeklyLimitUSD: 100, monthlyLimitUSD: 300, rpmLimit: 120)
/// An older server's group: no rate, RPM, exclusivity, billing or description.
private let legacy = AdminGroup(id: 7, name: "旧组", platform: "anthropic", rateMultiplier: nil, isExclusive: nil, subscriptionType: nil, rpmLimit: nil)
private let demoGroups = [premium, standardGroup, enterprise, legacy]
private let everyField = Set(GroupPermissions.Field.allCases)

private func text(_ data: Data) -> String { String(decoding: data, as: UTF8.self) }
private func sent(_ draft: GroupEditDraft, editable: Set<GroupPermissions.Field> = everyField) throws -> String? {
    try draft.updateRequest(editable: editable).map { text(try $0.requestBody()) }
}
private func editing(_ group: AdminGroup, _ change: (inout GroupEditDraft) -> Void) -> GroupEditDraft {
    var draft = GroupEditDraft(editing: group)
    change(&draft)
    return draft
}
private func named(_ name: String) -> GroupEditDraft {
    var draft = GroupEditDraft.creating()
    draft.name = name
    return draft
}

@Test func creatingStartsWithTheWebDefaults() throws {
    var draft = GroupEditDraft.creating()
    #expect(draft.isNew && draft.original == nil)
    #expect(draft.name.isEmpty && draft.description.isEmpty && draft.platform == "anthropic")
    #expect(draft.isActive && !draft.isExclusive && !draft.isSubscription)
    #expect(draft.rateText == "1.0" && draft.subscriptionType == "standard" && draft.rpmText.isEmpty)
    #expect(GroupLimitPeriod.allCases.allSatisfy { draft[limit: $0].isEmpty })
    #expect(!draft.hasUnsavedChanges)
    draft.name = "Claude 夜间组"
    #expect(draft.hasUnsavedChanges)
    let body = text(try draft.createRequest().requestBody())
    #expect(body == #"{"daily_limit_usd":null,"description":"","is_exclusive":false,"monthly_limit_usd":null,"name":"Claude 夜间组","platform":"anthropic","rate_multiplier":1,"rpm_limit":0,"subscription_type":"standard","weekly_limit_usd":null}"#)
}

@Test func editingStartsFromTheGroup() {
    let draft = GroupEditDraft(editing: enterprise)
    #expect(!draft.isNew && draft.platform == "openai" && !draft.hasUnsavedChanges)
    #expect(draft.rateText == "1.2" && draft.rpmText == "120" && draft.isExclusive && draft.isSubscription && draft.isActive)
    #expect(draft.dailyLimit == "20" && draft.weeklyLimit == "100" && draft.monthlyLimit == "300")
    var whole = premium
    whole.rateMultiplier = 1
    #expect(GroupEditDraft(editing: whole).rateText == "1.0")
    #expect(GroupEditDraft(editing: legacy).rateText.isEmpty)
    #expect(GroupEditDraft(editing: premium).rpmText.isEmpty && GroupEditDraft(editing: legacy).rpmText.isEmpty)
    var off = premium
    off.status = "inactive"
    #expect(!GroupEditDraft(editing: off).isActive)
    let old = GroupEditDraft(editing: legacy)
    #expect(!old.isExclusive && old.subscriptionType == "standard" && old.description.isEmpty && !old.isSubscription)
}

@Test func nameRulesTrimCountBytesAndCatchTakenNames() {
    let taken = GroupEditDraft.takenNames(in: demoGroups, excluding: nil)
    func issues(_ name: String, taken: Set<String> = taken) -> [GroupEditIssue] { named(name).issues(takenNames: taken) }
    #expect(issues("   ") == [.nameRequired])
    #expect(issues("  高级组 ") == [.nameTaken])
    #expect(GroupEditIssue.nameTaken.footnote == "已有同名分组。")
    #expect(issues(String(repeating: "组", count: 33)).isEmpty)
    #expect(issues(String(repeating: "组", count: 34)) == [.nameTooLong])
    #expect(GroupEditIssue.nameTooLong.footnote == UserKeyFormCopy.nameTooLong)
    #expect(issues(String(repeating: "a", count: 100)).isEmpty)
    #expect(issues(String(repeating: "a", count: 101)) == [.nameTooLong])
    #expect(issues("claude", taken: ["Claude"]).isEmpty)
    #expect(GroupEditIssue.nameRequired.footnote == nil && GroupEditIssue.rateInvalid.footnote == nil)
}

@Test func takenNamesExcludeTheGroupItself() {
    let others = GroupEditDraft.takenNames(in: demoGroups, excluding: 1)
    #expect(!others.contains("高级组") && others.contains("标准组"))
    #expect(GroupEditDraft.takenNames(in: demoGroups, excluding: nil) == Set(demoGroups.map(\.name)))
    #expect(GroupEditDraft(editing: premium).issues(takenNames: others).isEmpty)
    let renamed = editing(standardGroup) { $0.name = "高级组" }
    #expect(renamed.issues(takenNames: GroupEditDraft.takenNames(in: demoGroups, excluding: 2)) == [.nameTaken])
}

@Test func rateAcceptsPositiveDecimalsOnly() throws {
    func issues(_ raw: String) -> [GroupEditIssue] {
        var draft = named("费率组")
        draft.rateText = raw
        return draft.issues(takenNames: [])
    }
    for bad in ["", "0", "0.0", "-1", ".5", "1.", "1.2.3", "abc", "1000000000000"] { #expect(issues(bad) == [.rateInvalid], "\(bad)") }
    for good in ["0.05", "0.1", "1", "1.25", " 0.9 ", "999999999999.99999999"] { #expect(issues(good).isEmpty, "\(good)") }
    for comma in ["1,5", "1，5", "1．5"] {
        var draft = named("费率组")
        draft.rateText = comma
        #expect(try draft.createRequest().rateMultiplier == amount("1.5"), "\(comma)")
    }
}

@Test func rateStepperMovesByOneTenthAndStopsAtOneTenth() {
    func stepped(_ raw: String, up: Bool, from start: GroupEditDraft = .creating()) -> String {
        var draft = start
        draft.rateText = raw
        draft.stepRate(up: up)
        return draft.rateText
    }
    #expect(stepped("0.8", up: true) == "0.9")
    #expect(stepped("0.9", up: true) == "1.0")
    #expect(stepped("1.25", up: true) == "1.35")
    #expect(stepped("0.2", up: false) == "0.1")
    #expect(stepped("0.1", up: false) == "0.1")
    #expect(stepped("0.15", up: false) == "0.1")
    #expect(stepped("abc", up: true, from: GroupEditDraft(editing: premium)) == "0.9")
    #expect(stepped("abc", up: true) == "1.1")
}

@Test func rpmAcceptsDigitsUpToInt32Max() throws {
    #expect(GroupEditDraft.digitsOnly("6 0a") == "60")
    #expect(GroupEditDraft.digitsOnly("６０").isEmpty)
    var draft = named("限流组")
    draft.rpmText = "2147483647"
    #expect(draft.issues(takenNames: []).isEmpty)
    #expect(try draft.createRequest().rpmLimit == Int(Int32.max))
    draft.rpmText = "2147483648"
    #expect(draft.issues(takenNames: []) == [.rpmInvalid])
    draft.rpmText = ""
    #expect(try draft.createRequest().rpmLimit == 0)
    #expect(try sent(editing(premium) { $0.rpmText = "0" }) == nil)
}

@Test func limitsAcceptBlankOrNonNegativeAmounts() {
    var draft = named("订阅组")
    draft.subscriptionType = "subscription"
    for good in ["", "0", "20", "20.5"] {
        draft.dailyLimit = good
        #expect(draft.issues(takenNames: []).isEmpty, "\(good)")
    }
    draft.dailyLimit = "-1"
    #expect(draft.issues(takenNames: []) == [.limitInvalid(.daily)])
    draft.dailyLimit = ""
    draft.weeklyLimit = "abc"
    #expect(draft.issues(takenNames: []) == [.limitInvalid(.weekly)])
    draft.weeklyLimit = ""
    draft[limit: .monthly] = "abc"
    #expect(draft.issues(takenNames: []) == [.limitInvalid(.monthly)])
    draft.subscriptionType = "standard"
    #expect(draft.issues(takenNames: []).isEmpty)
    #expect(GroupLimitPeriod.allCases.map(\.title) == ["每日", "每周", "每月"])
}

@Test func createRequestFollowsTheBillingType() throws {
    var draft = named("  订阅夜间组 ")
    draft.platform = "openai"
    draft.subscriptionType = "subscription"
    draft.dailyLimit = "20"
    draft.subscriptionType = "standard"
    let standard = try draft.createRequest()
    #expect(standard.name == "订阅夜间组" && standard.platform == "openai" && standard.subscriptionType == "standard")
    #expect(standard.dailyLimitUSD == .unlimited && standard.weeklyLimitUSD == .unlimited && standard.monthlyLimitUSD == .unlimited)
    draft.subscriptionType = "subscription"
    draft.monthlyLimit = "300"
    let subscription = try draft.createRequest()
    #expect(subscription.dailyLimitUSD == .amount(20) && subscription.weeklyLimitUSD == .unlimited && subscription.monthlyLimitUSD == .amount(300))
}

@Test func updateRequestCarriesOnlyChangedEditableFields() throws {
    #expect(try sent(editing(premium) { $0.name = "高级组 A" }) == #"{"name":"高级组 A"}"#)
    #expect(try sent(editing(premium) { $0.rateText = "0.9" }) == #"{"rate_multiplier":0.9}"#)
    #expect(try sent(editing(premium) { $0.rateText = "0.80" }) == nil)
    #expect(try sent(editing(premium) { $0.rpmText = "60" }) == #"{"rpm_limit":60}"#)
    #expect(try sent(editing(premium) { $0.isActive = false }) == #"{"status":"inactive"}"#)
    #expect(try sent(editing(premium) { $0.isActive = false; $0.isActive = true }) == nil)
    #expect(try sent(editing(premium) { $0.isExclusive = true }) == #"{"is_exclusive":true}"#)
    #expect(try sent(editing(premium) { $0.description = "夜间备用" }) == #"{"description":"夜间备用"}"#)
    #expect(try sent(editing(premium) { _ in }) == nil)
    #expect(try sent(editing(premium) { $0.rateText = "0.9" }, editable: everyField.subtracting([.rateMultiplier])) == nil)
    let simple = editing(premium) { $0.name = "高级组 B"; $0.rpmText = "60"; $0.isExclusive = true }
    #expect(try sent(simple, editable: [.name, .description]) == #"{"name":"高级组 B"}"#)
}

@Test func updateRequestClearsALimitWithNullAndNeverSendsPlatformOrBilling() throws {
    #expect(try sent(editing(enterprise) { $0.dailyLimit = "" }) == #"{"daily_limit_usd":null}"#)
    var open = enterprise
    open.dailyLimitUSD = nil
    #expect(try sent(editing(open) { $0.dailyLimit = "" }) == nil)
    let moved = try sent(editing(premium) { $0.name = "高级组 C"; $0.platform = "openai"; $0.subscriptionType = "subscription" }) ?? ""
    #expect(moved == #"{"name":"高级组 C"}"#)
}

@Test func editValidatesOnlyFieldsTheUserTouched() throws {
    var draft = GroupEditDraft(editing: legacy)
    #expect(draft.rateText.isEmpty && draft.rpmText.isEmpty && draft.issues(takenNames: []).isEmpty)
    draft.name = "旧组 2"
    #expect(try sent(draft) == #"{"name":"旧组 2"}"#)
    #expect(draft.isSubmittable(takenNames: [], editable: everyField))
    draft.rateText = "0"
    #expect(draft.issues(takenNames: []) == [.rateInvalid])
    #expect(!draft.isSubmittable(takenNames: [], editable: everyField))
    #expect(!GroupEditDraft(editing: premium).isSubmittable(takenNames: [], editable: everyField))
    #expect(named("新分组").isSubmittable(takenNames: [], editable: everyField))
}

/// The Web and the server keep outer spaces, so a stored "高级组 " must not be renamed by an edit that left the name alone.
@Test func anUntouchedNameWithOuterSpacesIsNotSent() throws {
    var padded = premium
    padded.name = "高级组 "
    #expect(try sent(editing(padded) { _ in }) == nil)
    #expect(!GroupEditDraft(editing: padded).isSubmittable(takenNames: ["高级组"], editable: everyField))
    #expect(try sent(editing(padded) { $0.description = "夜间备用" }) == #"{"description":"夜间备用"}"#)
    let trimmed = editing(padded) { $0.name = "高级组" }
    #expect(try sent(trimmed) == #"{"name":"高级组"}"#)
    #expect(trimmed.issues(takenNames: ["高级组"]) == [.nameTaken])
}

@Test func unsavedChangesCompareWithTheOpeningValues() {
    #expect(!GroupEditDraft.creating().hasUnsavedChanges)
    #expect(named("x").hasUnsavedChanges)
    var draft = GroupEditDraft(editing: premium)
    #expect(!draft.hasUnsavedChanges)
    draft.isExclusive.toggle()
    #expect(draft.hasUnsavedChanges)
    draft.isExclusive.toggle()
    #expect(!draft.hasUnsavedChanges)
    draft.stepRate(up: true)
    #expect(draft.hasUnsavedChanges)
    draft.stepRate(up: false)
    #expect(!draft.hasUnsavedChanges && draft.rateText == "0.8")
}

@Test func platformOptionsComeFromTheCatalogWithoutComposite() {
    let builtin = GroupEditDraft.platformOptions(catalog: .builtin)
    #expect(builtin == MetaCatalog.builtin.platforms.map(\.id) && builtin.allSatisfy(GroupPlatform.concrete.contains))
    let mixed = MetaCatalog(platforms: [.init(id: "openai", displayName: "OpenAI"), .init(id: "composite", displayName: "组合"),
                                        .init(id: "newplat", displayName: "New"), .init(id: "anthropic", displayName: "Anthropic")], platformAuth: [:])
    #expect(GroupEditDraft.platformOptions(catalog: mixed) == ["openai", "anthropic"])
    #expect(GroupEditDraft.platformOptions(catalog: nil) == GroupPlatform.concrete)
    let unknown = MetaCatalog(platforms: [.init(id: "newplat", displayName: "New")], platformAuth: [:])
    #expect(GroupEditDraft.platformOptions(catalog: unknown) == GroupPlatform.concrete)
}

@Test func diffAsksOnlyForRiskyChanges() throws {
    let quiet = editing(premium) { $0.name = "高级组 A"; $0.description = "新的说明" }
    let quietRequest = try #require(try quiet.updateRequest(editable: everyField))
    let quietDiff = try #require(quiet.diff(quietRequest, now: Date()))
    #expect(!quietDiff.requiresConfirmation)
    let risky = editing(premium) { $0.stepRate(up: true) }
    let riskyRequest = try #require(try risky.updateRequest(editable: everyField))
    let riskyDiff = try #require(risky.diff(riskyRequest, now: Date()))
    #expect(riskyDiff.requiresConfirmation)
    let confirmation = riskyDiff.confirmation(siteName: "X", activeAPIKeys: nil)
    #expect(confirmation.title == "保存「高级组」的修改？" && confirmation.confirmTitle == "保存修改")
    #expect(confirmation.lines == ["站点 X · 分组「高级组」", "费率倍数 ×0.8 → ×0.9", "此后的请求按新倍率计费，已产生的记录不变。"])
    #expect(GroupEditDraft.creating().diff(GroupUpdateRequest(name: "x"), now: Date()) == nil)
}

@Test func reconcileTakesOnlyANewExactNameOnTheSamePlatform() {
    let request = GroupCreateRequest(name: "Claude 夜间组")
    let created = AdminGroup(id: 12, name: "Claude 夜间组", platform: "anthropic")
    #expect(GroupEditReconcile.created(request, in: [premium, created], knownIDs: [1, 2]) == created)
    #expect(GroupEditReconcile.created(request, in: [AdminGroup(id: 12, name: "Claude 夜间组", platform: "openai")], knownIDs: [1]) == nil)
    #expect(GroupEditReconcile.created(request, in: [AdminGroup(id: 12, name: "Claude 夜间组 2", platform: "anthropic")], knownIDs: [1]) == nil)
    #expect(GroupEditReconcile.created(request, in: [created], knownIDs: [1, 12]) == nil)
    let rate = GroupUpdateRequest(rateMultiplier: amount("0.9"))
    var saved = premium
    saved.rateMultiplier = amount("0.9")
    #expect(GroupEditReconcile.saved(rate, server: saved) && !GroupEditReconcile.saved(rate, server: premium))
    #expect(GroupEditReconcile.droppedFields(rate, response: premium) && !GroupEditReconcile.droppedFields(rate, response: saved))
}

@Test func groupEditCopyMatchesTheSpec() {
    #expect(GroupEditCopy.basicFootnote(isNew: true, isExclusive: false, isActive: true, showsExclusive: true, showsStatus: false, isSimpleMode: false)
            == "公开：所有用户新建 API 密钥时都能选它。创建后立即可用，需要时可在详情里停用。平台和计费类型创建后不能修改；组合路由（Composite）分组在 Web 中创建。")
    #expect(GroupEditCopy.basicFootnote(isNew: false, isExclusive: true, isActive: false, showsExclusive: true, showsStatus: true, isSimpleMode: false)
            == "专属：只有分配了这个分组的用户能选它。停用：使用这个分组的 API 密钥会被拒绝。")
    #expect(GroupEditCopy.basicFootnote(isNew: false, isExclusive: true, isActive: true, showsExclusive: false, showsStatus: true, isSimpleMode: false).isEmpty)
    #expect(GroupEditCopy.basicFootnote(isNew: true, isExclusive: false, isActive: true, showsExclusive: false, showsStatus: false, isSimpleMode: true)
            == "平台创建后不能修改。")
    #expect(GroupEditCopy.billingFootnote(managedNote: nil)
            == "费率倍数：1.0 = 标准费率，0.5 = 半价，2.0 = 双倍。每用户 RPM：每位用户在本分组每分钟最多请求数，留空或 0 = 不限。")
    #expect(GroupEditCopy.billingFootnote(managedNote: GroupPermissions.billingManagedNote) == "计费由站长管理。")
    #expect(GroupEditCopy.limitsFootnote == "留空 = 无限制；超过限额的订阅请求会被拒绝。")
    #expect(GroupEditCopy.standardBillingNote == "标准（余额）计费从用户余额扣除，没有订阅限额。")
    #expect(GroupEditCopy.webNote == "模型白名单、组合路由、图片计费、客户端限制在 Web 中编辑。")
    #expect(GroupEditCopy.title(isNew: true) == "新建分组" && GroupEditCopy.title(isNew: false) == "编辑分组")
    #expect(GroupEditCopy.submitTitle(isNew: true) == "创建" && GroupEditCopy.submitTitle(isNew: false) == "保存")
    let lost = KeyedWriteFailure(disposition: .unconfirmed(.transport, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil)
    let busy = KeyedWriteFailure(disposition: .unconfirmed(.storeUnavailable, retryNotBefore: nil), key: "k", actionID: nil, lastError: nil)
    #expect(GroupEditCopy.unconfirmedText(lost, keyed: true).contains("可以核对，或用同一编号重试，不会重复执行"))
    #expect(GroupEditCopy.unconfirmedText(busy, keyed: true) == "服务器暂时无法受理，稍后用同一编号重试")
    #expect(GroupEditCopy.unconfirmedText(APIError.server(status: 502, reason: nil), keyed: true) == KeyedWriteFailure.unconfirmedMessage)
    #expect(GroupEditCopy.unconfirmedText(APIError(kind: .transport, message: "无法连接站点"), keyed: false)
            == "结果未确认：服务器可能已执行。请先读取服务器状态核对，本页不会再自动发送。")
    #expect(GroupEditCopy.savingText(nil) == "正在保存…" && GroupEditCopy.savingText(.confirming(retry: 1)) == "正在确认结果…")
    #expect(GroupEditCopy.savingText(.waitingForServer(elapsedSeconds: 12)) == "服务器仍在处理 · 已等待 12 秒")
    #expect(GroupEditCopy.checkNote(.notFound) == "服务器上还没有找到这个分组，可能仍在处理。")
    #expect(GroupEditCopy.checkNote(.differs) == "服务器上的分组还不是这次的修改。")
    #expect(GroupEditCopy.notApplied(isNew: true) == "服务器上没有这次的新建，可以重新创建。")
}

// MARK: - 第一轮用户反馈（U-13）

@Test func zeroLimitDetection() {
    var draft = named("订阅组")
    draft.subscriptionType = "subscription"
    #expect(!draft.hasZeroLimit && draft.zeroLimitPeriods().isEmpty)
    for (text, isZero) in [("0", true), ("0.00", true), (" 0 ", true), ("", false), ("20", false), ("0.5", false), ("abc", false)] {
        draft.dailyLimit = text
        #expect(draft.hasZeroLimit == isZero, "\(text)")
        #expect(draft.zeroLimitPeriods() == (isZero ? [.daily] : []), "\(text)")
    }
    draft.dailyLimit = ""
    for period in GroupLimitPeriod.allCases {
        var one = draft
        one[limit: period] = "0"
        #expect(one.zeroLimitPeriods() == [period] && one.hasZeroLimit)
    }
    draft.weeklyLimit = "0"
    draft.monthlyLimit = "0.0"
    #expect(draft.zeroLimitPeriods() == [.weekly, .monthly])
    let opened = GroupEditDraft(editing: AdminGroup(id: 9, name: "零限额组", platform: "openai", subscriptionType: "subscription", dailyLimitUSD: 0))
    #expect(opened.zeroLimitPeriods() == [.daily])
    #expect(GroupEditCopy.zeroLimitNote == "服务器对 0 的处理还不一致，可能等于不限；要不限请留空")
}

@Test func unconfirmedCloseMessageMembers() {
    let created = "服务器可能已经创建了这个分组。关闭后不再保留这次的编号，分组列表会重新读取；再次新建前先在列表里核对，避免重复。"
    let saved = "服务器可能已经保存了这次修改。关闭后分组列表会重新读取，再次修改前先在详情里核对。"
    let members = "这次的成员调整还没有发送，关闭后需要到详情里重新调整。"
    #expect(GroupEditCopy.unconfirmedCloseMessage(isNew: true, hasMemberChanges: false) == created)
    #expect(GroupEditCopy.unconfirmedCloseMessage(isNew: false, hasMemberChanges: false) == saved)
    #expect(GroupEditCopy.unconfirmedCloseMessage(isNew: true, hasMemberChanges: true) == created + members)
    #expect(GroupEditCopy.unconfirmedCloseMessage(isNew: false, hasMemberChanges: true) == saved + members)
}
