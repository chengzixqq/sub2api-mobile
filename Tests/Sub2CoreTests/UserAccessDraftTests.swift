import Foundation
import Testing
@testable import Sub2Core

private func amount(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }
private func group(_ id: Int, _ name: String, exclusive: Bool, type: String? = "standard", status: String = "active", sort: Int? = nil) -> AdminGroup {
    AdminGroup(id: id, name: name, status: status, isExclusive: exclusive, subscriptionType: type, sortOrder: sort)
}
/// Exclusive standard 5–8, public 2 and 3; 99 is a group the directory does not know (disabled or deleted).
private let catalog = UserGroupCatalog(groups: [
    group(2, "标准组", exclusive: false), group(3, "默认组", exclusive: false),
    group(5, "Claude Code 组", exclusive: true), group(6, "测试专线", exclusive: true), group(7, "备用专线", exclusive: true), group(8, "Codex 专线", exclusive: true)
])
private let company = UserAttributeDefinition(id: 1, key: "company", name: "公司", type: "text", isRequired: true)
private let tags = UserAttributeDefinition(id: 2, key: "tags", name: "标签", type: "multi_select", isRequired: true)

private func baseline(allowed: [Int]? = [], restrict: Bool? = false, rates: [Int: Decimal]? = nil, role: String = "user", email: String = "person@example.invalid",
                      attributes: [UserAttributeValue] = [UserAttributeValue(attributeID: 1, value: "Studio-K")]) -> UserBaseline {
    UserBaseline(user: AdminUser(id: 24, email: email, username: "示例", status: "active", role: role, concurrency: 2, notes: "备注", rpmLimit: 0,
                                 allowedGroups: allowed, groupRates: rates, restrictPublicGroups: restrict), attributes: attributes)
}
private func bodyKeys(_ request: UserUpdateRequest?) throws -> Set<String> {
    let body = try #require(request).requestBody()
    return Set(try #require(JSONSerialization.jsonObject(with: body) as? [String: Any]).keys)
}
private func bodyJSON(_ request: UserUpdateRequest?) throws -> [String: Any] {
    let body = try #require(request).requestBody()
    return try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

// MARK: - 分组目录

/// 30 §5.2: only active standard groups, exclusive or public, in sort order (missing sort counts as 0, then id).
@Test func catalogKeepsOnlyActiveStandardGroupsInSortOrder() {
    let mixed = UserGroupCatalog(groups: [
        group(5, "Claude Code 组", exclusive: true, sort: 2), group(8, "Codex 专线", exclusive: true, sort: 1),
        group(2, "标准组", exclusive: false, sort: 2), group(1, "高级组", exclusive: false, sort: 1), group(3, "默认组", exclusive: false, type: nil),
        group(6, "测试组", exclusive: true, status: "disabled"), group(4, "企业专线", exclusive: true, type: "subscription"),
        group(9, "公开订阅", exclusive: false, type: "subscription")
    ])
    #expect(mixed.exclusive.map(\.id) == [8, 5])
    #expect(mixed.publicGroups.map(\.id) == [3, 1, 2])
    #expect(mixed.exclusiveIDs == [5, 8] && mixed.publicIDs == [1, 2, 3])
}

@Test func subscriptionNoteListsActiveExclusiveSubscriptionGroups() {
    let groups = [group(4, "企业专线", exclusive: true, type: "subscription"), group(12, "海外专线", exclusive: true, type: "subscription"),
                  group(13, "停用订阅", exclusive: true, type: "subscription", status: "disabled"), group(9, "公开订阅", exclusive: false, type: "subscription")]
    #expect(UserGroupCatalog(groups: groups).subscriptionNote == "企业专线、海外专线是订阅分组，要在 Web 的订阅管理里开通。")
    #expect(catalog.subscriptionNote == nil && UserGroupCatalog.empty.subscriptionNote == nil)
}

// MARK: - 新建

/// 30 §5.3 defaults; §5.1 asks before leaving only when something was filled in.
@Test func newUserDraftDefaults() {
    let draft = UserAccessDraft()
    #expect(draft.role == .user && draft.status == "active" && draft.concurrency == 1 && draft.rpmLimit == 0)
    #expect(!draft.restrictPublicGroups && !draft.hasContent)
    var filled = draft; filled.email = "a"
    var granted = draft; granted.exclusiveGroupIDs = [5]
    #expect(filled.hasContent && granted.hasContent)
    let toggled = draft.settingRestrictPublicGroups(true, catalog: catalog).settingRestrictPublicGroups(false, catalog: catalog)
    #expect(!toggled.hasContent)
}

/// 30 §5.3: allowed_groups = ticked exclusive groups + (with the restriction on) ticked public groups.
@Test func createAllowedGroupsAddPublicOnlyWhenRestricted() throws {
    var draft = UserAccessDraft()
    draft.email = "new@example.invalid"; draft.password = "abcdef"
    draft.exclusiveGroupIDs = [5]; draft.publicGroupIDs = [2, 3]
    #expect(draft.allowedGroupsForCreate() == [5])
    let open = try JSONSerialization.jsonObject(with: draft.createRequest().requestBody()) as? [String: Any]
    #expect(open?["allowed_groups"] as? [Int] == [5] && open?["restrict_public_groups"] as? Bool == false)
    draft.restrictPublicGroups = true
    #expect(draft.allowedGroupsForCreate() == [2, 3, 5])
    let restricted = try JSONSerialization.jsonObject(with: draft.createRequest().requestBody()) as? [String: Any]
    #expect(restricted?["allowed_groups"] as? [Int] == [2, 3, 5] && restricted?["restrict_public_groups"] as? Bool == true)
}

@Test func createRequestFromDraft() throws {
    var draft = UserAccessDraft()
    draft.email = "new@example.invalid"; draft.password = "abcdef"; draft.concurrency = 3; draft.rpmLimit = 60
    draft.role = nil; draft.groupRates = [5: 2]
    let plain = try #require(JSONSerialization.jsonObject(with: draft.createRequest().requestBody()) as? [String: Any])
    #expect(plain["balance"] == nil && plain["role"] as? String == "user" && plain["group_rates"] == nil)
    #expect(plain["concurrency"] as? Int == 3 && plain["rpm_limit"] as? Int == 60)
    draft.initialBalance = "20.5"
    let funded = try draft.createRequest()
    #expect(funded.balance == amount("20.5"))
    draft.initialBalance = "abc"
    #expect(throws: APIError.self) { _ = try draft.createRequest() }
}

// MARK: - 编辑：allowed_groups 组装

/// 30 §6.4: the server's list is the base; ids the directory does not know stay.
@Test func editAllowedGroupsKeepUnknownIDsAndApplyUIChanges() throws {
    let base = baseline(allowed: [2, 5, 6, 99], restrict: true)
    var draft = UserAccessDraft(editing: base, catalog: catalog)
    #expect(draft.exclusiveGroupIDs == [5, 6] && draft.publicGroupIDs == [2])
    draft.exclusiveGroupIDs = [5, 8]; draft.publicGroupIDs = [2, 3]
    #expect(draft.allowedGroups(from: base, catalog: catalog) == [2, 3, 5, 8, 99])
    #expect(draft.addedExclusiveGroups(from: base, catalog: catalog) == [8] && draft.removedExclusiveGroups(from: base, catalog: catalog) == [6])
    let fields = draft.changedFields(from: base, catalog: catalog, definitions: [])
    #expect(fields == [.exclusiveGroups, .publicGroups])
    let request = try #require(draft.updateRequest(from: base, catalog: catalog))
    #expect(request.allowedGroups == [2, 3, 5, 8, 99] && request.restrictPublicGroups == true)
}

@Test func turningRestrictionOffDropsEveryPublicGroup() throws {
    let base = baseline(allowed: [2, 3, 5, 99], restrict: true)
    let draft = UserAccessDraft(editing: base, catalog: catalog).settingRestrictPublicGroups(false, catalog: catalog)
    #expect(draft.allowedGroups(from: base, catalog: catalog) == [5, 99])
    let request = try #require(draft.updateRequest(from: base, catalog: catalog))
    #expect(request.restrictPublicGroups == false && request.allowedGroups == [5, 99])
}

@Test func restrictionStayingOffKeepsServerPublicIDs() {
    let base = baseline(allowed: [2, 5], restrict: false)
    let untouched = UserAccessDraft(editing: base, catalog: catalog)
    #expect(untouched.updateRequest(from: base, catalog: catalog) == nil)
    var draft = untouched
    draft.exclusiveGroupIDs.insert(8)
    #expect(draft.allowedGroups(from: base, catalog: catalog) == [2, 5, 8])
    #expect(draft.changedFields(from: base, catalog: catalog, definitions: []) == [.exclusiveGroups])
}

/// Turning the restriction off ticks every public group again, as on the web; the original draft is left alone.
@Test func togglingRestrictionTicksAllPublicGroups() {
    var draft = UserAccessDraft(editing: baseline(allowed: [2], restrict: true), catalog: catalog)
    #expect(draft.allowsPublicGroup(2) && !draft.allowsPublicGroup(3))
    let off = draft.settingRestrictPublicGroups(false, catalog: catalog)
    #expect(catalog.publicIDs.allSatisfy(off.allowsPublicGroup))
    let on = off.settingRestrictPublicGroups(true, catalog: catalog)
    #expect(on.restrictPublicGroups && on.publicGroupIDs == catalog.publicIDs)
    #expect(draft.publicGroupIDs == [2] && draft.restrictPublicGroups)
    draft.publicGroupIDs = []
    #expect(!draft.allowsPublicGroup(2))
}

// MARK: - 编辑：倍率差异

/// 30 §6.4 专属倍率: changed values, cleared ones as null, and null for a removed exclusive group that had a rate.
@Test func groupRateChangesSendChangedClearedAndRemovedExclusive() throws {
    let base = baseline(allowed: [5, 6, 7], rates: [5: amount("1.3"), 6: amount("1.5"), 2: amount("0.8")])
    var draft = UserAccessDraft(editing: base, catalog: catalog)
    draft.groupRates[5] = amount("1.25"); draft.groupRates[2] = nil; draft.groupRates[3] = 2
    draft.exclusiveGroupIDs = [5]
    let expected: [Int: Decimal?] = [5: amount("1.25"), 2: nil, 3: 2, 6: nil]
    #expect(draft.groupRateChanges(from: base, catalog: catalog) == expected)
    #expect(draft.changedFields(from: base, catalog: catalog, definitions: []) == [.exclusiveGroups, .groupRates])
    let body = try #require(draft.updateRequest(from: base, catalog: catalog)).requestBody()
    #expect(String(decoding: body, as: UTF8.self) == #"{"allowed_groups":[5],"group_rates":{"2":null,"3":2,"5":1.25,"6":null},"restrict_public_groups":false}"#)
    var removedOnly = UserAccessDraft(editing: base, catalog: catalog)
    removedOnly.exclusiveGroupIDs = [5, 7]
    let cleared: [Int: Decimal?] = [6: nil]
    #expect(removedOnly.groupRateChanges(from: base, catalog: catalog) == cleared)
    #expect(removedOnly.changedFields(from: base, catalog: catalog, definitions: []) == [.exclusiveGroups])
}

@Test func unchangedRatesSendNoGroupRatesKey() throws {
    let base = baseline(allowed: [5], rates: [5: amount("1.3")])
    var draft = UserAccessDraft(editing: base, catalog: catalog)
    draft.notes = "新备注"
    let request = try #require(draft.updateRequest(from: base, catalog: catalog))
    #expect(request.groupRates == nil)
    #expect(try bodyKeys(request) == ["notes"])
}

// MARK: - 编辑：只发改动字段

/// One edit of the 30 §6.4 table each; nothing else may travel with it.
enum UserDraftSingleEdit: CaseIterable, Sendable {
    case email, clearUsername, clearNotes, password, status, role, concurrencyWithNote, concurrency, rpm, exclusive, restriction, rate

    func applied(to draft: UserAccessDraft) -> UserAccessDraft {
        var edited = draft
        switch self {
        case .email: edited.email = " b@example.invalid "
        case .clearUsername: edited.username = ""
        case .clearNotes: edited.notes = ""
        case .password: edited.password = "new-secret"
        case .status: edited.status = "disabled"
        case .role: edited.role = .vendor
        case .concurrencyWithNote: edited.concurrency = 4; edited.adjustmentNotes = "扩容"
        case .concurrency: edited.concurrency = 4
        case .rpm: edited.rpmLimit = 60
        case .exclusive: edited.exclusiveGroupIDs.insert(8)
        case .restriction: edited = edited.settingRestrictPublicGroups(true, catalog: catalog)
        case .rate: edited.groupRates[5] = amount("1.5")
        }
        return edited
    }
    var keys: Set<String> {
        switch self {
        case .email: ["email"]
        case .clearUsername: ["username"]
        case .clearNotes: ["notes"]
        case .password: ["password"]
        case .status: ["status"]
        case .role: ["role"]
        case .concurrencyWithNote: ["adjustment_notes", "concurrency"]
        case .concurrency: ["concurrency"]
        case .rpm: ["rpm_limit"]
        case .exclusive, .restriction: ["allowed_groups", "restrict_public_groups"]
        case .rate: ["group_rates"]
        }
    }
}

@Test(arguments: UserDraftSingleEdit.allCases)
func updateRequestContainsOnlyChangedFields(edit: UserDraftSingleEdit) throws {
    let base = baseline(allowed: [5])
    let request = edit.applied(to: UserAccessDraft(editing: base, catalog: catalog)).updateRequest(from: base, catalog: catalog)
    #expect(try bodyKeys(request) == edit.keys)
    let json = try bodyJSON(request)
    #expect(json["balance"] == nil)
    switch edit {
    case .email: #expect(json["email"] as? String == "b@example.invalid")
    case .clearUsername: #expect(json["username"] as? String == "")
    case .clearNotes: #expect(json["notes"] as? String == "")
    default: break
    }
}

/// S3D1-10: whatever part of the grant changed, allowed_groups and restrict_public_groups travel together.
@Test func allowedGroupsAlwaysTravelWithRestrictFlag() throws {
    let base = baseline(allowed: [5, 2], restrict: true)
    var draft = UserAccessDraft(editing: base, catalog: catalog)
    draft.exclusiveGroupIDs.insert(8)
    let request = try #require(draft.updateRequest(from: base, catalog: catalog))
    #expect(request.allowedGroups == [2, 5, 8] && request.restrictPublicGroups == true)
    let immediate = UserUpdateRequest(allowedGroups: [5], restrictPublicGroups: false)
    #expect(try bodyKeys(immediate) == ["allowed_groups", "restrict_public_groups"])
}

/// 30 §6.4 step 5: attributes are written by their own PUT.
@Test func noChangesOrAttributesOnlyBuildNoUserRequest() {
    let base = baseline()
    let untouched = UserAccessDraft(editing: base, catalog: catalog)
    #expect(untouched.updateRequest(from: base, catalog: catalog) == nil)
    #expect(untouched.changedFields(from: base, catalog: catalog, definitions: [company]).isEmpty)
    var draft = untouched
    draft.attributes[1] = "新公司"
    #expect(draft.updateRequest(from: base, catalog: catalog) == nil)
    #expect(draft.changedFields(from: base, catalog: catalog, definitions: [company]) == [.attribute(id: 1, name: "公司")])
    #expect(draft.attributeChanges(from: base, definitions: [company]) == [1: "新公司"])
}

@Test func changedFieldsNameSectionsAndOrder() {
    let base = baseline()
    var draft = UserAccessDraft(editing: base, catalog: catalog)
    draft.concurrency = 4; draft.role = .admin; draft.attributes[1] = "新公司"; draft.notes = "改过"
    let fields = draft.changedFields(from: base, catalog: catalog, definitions: [company])
    #expect(fields == [.notes, .attribute(id: 1, name: "公司"), .role, .concurrency])
    #expect(UserDraftField.names(fields) == "备注、公司、角色、并发数")
    #expect(fields.map(\.section) == [.basic, .basic, .access, .access])
    let all: [UserDraftField] = [.email, .username, .password, .initialBalance, .status, .exclusiveGroups, .publicGroups, .groupRates, .rpmLimit]
    #expect(all.map(\.title) == ["邮箱", "用户名", "密码", "初始余额", "状态", "专属分组", "公开分组", "专属倍率", "RPM 上限"])
    #expect(all.map(\.section) == [.basic, .basic, .basic, .basic, .basic, .access, .access, .access, .access])
}

// MARK: - 本地校验

/// 30 §5.3 校验列 and §5.4 step 1.
@Test func createValidationMessages() {
    var draft = UserAccessDraft()
    let empty = draft.issues(against: nil, definitions: [company, tags])
    #expect(empty.map(\.message) == ["请输入邮箱", "请填写 公司", "请输入密码"])
    #expect(empty.first?.field == .email && empty[1].field == .attribute(id: 1, name: "公司"))
    #expect(UserAccessDraft.pendingIssuesMessage(4) == "还有 4 项需要填写或修改")
    draft.email = "a@b"; draft.password = "abcde"; draft.attributes[1] = "Studio-K"
    #expect(draft.issues(against: nil, definitions: [company]).map(\.message) == ["邮箱格式不对", "至少 6 位"])
    draft.email = "a@b.example"; draft.password = String(repeating: "密", count: 25)
    #expect(draft.issues(against: nil, definitions: []).map(\.message) == ["不能超过 72 字节"])
    draft.password = String(repeating: "密", count: 6)
    #expect(draft.issues(against: nil, definitions: []).isEmpty)
    for text in ["abc", "-1", "1.123456789", "1e3", "1,5", "12abc"] {
        draft.initialBalance = text
        #expect(draft.issues(against: nil, definitions: []).map(\.field) == [.initialBalance], "\(text)")
        #expect(draft.issues(against: nil, definitions: []).first?.message == "不是合法金额")
    }
    for text in ["", "0", "12.12345678", " 20 "] {
        draft.initialBalance = text
        #expect(draft.issues(against: nil, definitions: []).isEmpty, "\(text)")
    }
    // A new user's request carries no rates, so none are checked.
    draft.groupRates = [5: 0]
    #expect(draft.issues(against: nil, definitions: []).isEmpty)
}

@Test func editValidationOnlyChecksChangedValues() {
    let base = baseline(allowed: [5], rates: [5: amount("1.2345")], role: "admin", email: "legacy-address")
    var draft = UserAccessDraft(editing: base, catalog: catalog)
    #expect(draft.issues(against: base, definitions: [company]).isEmpty)
    draft.email = "still-bad"
    #expect(draft.issues(against: base, definitions: []).map(\.message) == ["邮箱格式不对"])
    draft.email = base.email; draft.groupRates[5] = 0
    #expect(draft.issues(against: base, definitions: []).map(\.message) == ["要大于 0，最多 3 位小数"])
    #expect(draft.issues(against: base, definitions: []).first?.field == .groupRates)
    draft.groupRates[5] = amount("1.2345"); draft.status = "disabled"
    #expect(draft.issues(against: base, definitions: []) == [UserDraftIssue(field: .status, message: "管理员不能禁用")])
    // A required attribute added later is asked for when editing too (default, as on the web).
    let unfilled = baseline(attributes: [])
    #expect(UserAccessDraft(editing: unfilled, catalog: catalog).issues(against: unfilled, definitions: [company, tags]).map(\.message) == ["请填写 公司"])
}

@Test func draftSectionsSpeakTheirIssues() {
    #expect(UserDraftSection.basic.title == "基础" && UserDraftSection.access.title == "权限与并发")
    #expect(UserDraftSection.basic.spokenIssues(1) == "基础，有 1 项要修改")
    #expect(UserDraftSection.access.spoken(issues: 1, changed: 2) == "权限与并发，有 1 项要修改、已改 2 项")
    #expect(UserDraftSection.access.spoken(issues: 0, changed: 0) == "权限与并发")
}

/// 30 §6.3 分组 sheet: the whole text must be a number, since Decimal(string:) reads only a prefix.
@Test func rateInputParsing() {
    for text in ["", "  "] { #expect(UserRateInput(text: text) == .useDefault) }
    #expect(UserRateInput(text: "1.3") == .rate(amount("1.3")) && UserRateInput(text: " 1.3 ") == .rate(amount("1.3")))
    #expect(UserRateInput(text: "0.001") == .rate(amount("0.001")))
    for text in ["0", "-1", "1.2345", "abc", "1,5", "1.2abc", "1e3", ".5"] { #expect(UserRateInput(text: text) == .invalid, "\(text)") }
    #expect(UserRateInput.errorMessage == "要大于 0，最多 3 位小数")
}

// MARK: - 读回比对

private func server(username: String? = "别人改的", concurrency: Int? = 4, allowed: [Int]? = [5, 8], restrict: Bool? = true, rates: [Int: Decimal]? = nil) -> AdminUser {
    AdminUser(id: 24, email: "person@example.invalid", username: username, status: "active", role: "user", concurrency: concurrency, notes: nil,
              allowedGroups: allowed, groupRates: rates, restrictPublicGroups: restrict)
}

/// 30 §6.5: only what the request carried is compared, from a GET.
@Test func readbackComparesOnlySentFields() {
    let sent = UserUpdateRequest(password: "new-secret", notes: "", concurrency: 4, allowedGroups: [8, 5], restrictPublicGroups: true,
                                 groupRates: [5: amount("1.3"), 6: nil])
    #expect(UserAccessDraft.readback(sent: sent, server: server(rates: [5: amount("1.3")])) == .matches)
    #expect(UserAccessDraft.readback(sent: sent, server: server(concurrency: 3, rates: [5: amount("1.3")])) == .differs)
    #expect(UserAccessDraft.readback(sent: sent, server: server(rates: [5: amount("1.3"), 6: 2])) == .differs)
    #expect(UserAccessDraft.readback(sent: sent, server: server(rates: [5: amount("1.30000001")])) == .matches)
    let cleared = UserUpdateRequest(allowedGroups: [], restrictPublicGroups: false)
    #expect(UserAccessDraft.readback(sent: cleared, server: server(allowed: nil, restrict: nil)) == .matches)
}

/// S3D1-18: a password alone cannot be read back.
@Test func readbackUndeterminedForPasswordOnly() {
    #expect(UserAccessDraft.readback(sent: UserUpdateRequest(password: "new-secret"), server: server()) == .undetermined)
    let withConcurrency = UserUpdateRequest(password: "new-secret", concurrency: 4, adjustmentNotes: "扩容")
    #expect(UserAccessDraft.readback(sent: withConcurrency, server: server()) == .matches)
    #expect(UserAccessDraft.readback(sent: withConcurrency, server: server(concurrency: 3)) == .differs)
}

// MARK: - 随机密码

private struct SplitMix64: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// 30 §5.3 生成随机密码: xxxx-xxxx-xxxx, letters and digits without 0 O o 1 l I.
@Test func randomPasswordFormatAndStrength() {
    var first = SplitMix64(state: 42), second = SplitMix64(state: 42)
    #expect(UserAccessDraft.randomPassword(using: &first) == UserAccessDraft.randomPassword(using: &second))
    let passwords = (0..<200).map { _ in UserAccessDraft.randomPassword() }
    for password in passwords {
        #expect(password.range(of: #"^[A-Za-z0-9]{4}-[A-Za-z0-9]{4}-[A-Za-z0-9]{4}$"#, options: .regularExpression) != nil)
        #expect(!password.contains(where: { "0Oo1lI".contains($0) }))
        var draft = UserAccessDraft()
        draft.email = "a@example.invalid"; draft.password = password
        #expect(draft.issues(against: nil, definitions: []).isEmpty)
    }
    #expect(Set(passwords).count > 1)
}
