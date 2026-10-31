import Foundation

/// 30 §5.2: what a user can be granted, from the session's group directory (`include_inactive=true`). Only active standard
/// groups count; exclusive ones are granted one by one, public ones through the restriction switch.
public struct UserGroupCatalog: Sendable, Equatable {
    public let exclusive: [AdminGroup]
    public let publicGroups: [AdminGroup]
    /// Active exclusive subscription groups: granted in the web's subscription management, never through allowed_groups.
    public let subscriptionGroupNames: [String]
    public init(groups: [AdminGroup]) {
        let active = groups.filter { $0.status == "active" }.sorted(by: AdminGroup.displayOrder)
        // An older server without subscription_type has no subscription groups yet.
        let standard = active.filter { ($0.subscriptionType ?? "standard") == "standard" }
        exclusive = standard.filter { $0.isExclusive == true }
        publicGroups = standard.filter { $0.isExclusive != true }
        subscriptionGroupNames = active.filter { $0.isExclusive == true && $0.subscriptionType == "subscription" }.map(\.name)
    }
    public static let empty = UserGroupCatalog(groups: [])
    public var exclusiveIDs: Set<Int> { Set(exclusive.map(\.id)) }
    public var publicIDs: Set<Int> { Set(publicGroups.map(\.id)) }
    /// “企业专线、海外专线是订阅分组，要在 Web 的订阅管理里开通。”
    public var subscriptionNote: String? {
        subscriptionGroupNames.isEmpty ? nil : subscriptionGroupNames.joined(separator: "、") + "是订阅分组，要在 Web 的订阅管理里开通。"
    }
}

/// The server's user when the edit page opened (30 §6.2); polling never overwrites it (§6.6). Every field is `var` so an
/// immediate write (a key's group change, a replaced group) can move the base along with the draft.
public struct UserBaseline: Sendable, Equatable {
    public var userID: Int
    public var email: String
    public var username: String
    public var notes: String
    /// nil for a role this App does not know.
    public var role: AdminUserRole?
    public var status: String
    public var concurrency: Int?
    public var rpmLimit: Int?
    public var allowedGroups: Set<Int>
    public var restrictPublicGroups: Bool
    public var groupRates: [Int: Decimal]
    public var attributes: [Int: String]
    public init(user: AdminUser, attributes: [UserAttributeValue] = []) {
        userID = user.id; email = user.email; username = user.username ?? ""; notes = user.notes ?? ""
        role = user.role.flatMap(AdminUserRole.init(rawValue:)); status = user.status
        concurrency = user.concurrency; rpmLimit = user.rpmLimit
        allowedGroups = Set(user.allowedGroups ?? []); restrictPublicGroups = user.restrictPublicGroups ?? false
        groupRates = user.groupRates ?? [:]; self.attributes = UserAttributeEdits.values(attributes)
    }
}

/// The two saved segments of the user form; the App maps them to its own segment type.
public enum UserDraftSection: Sendable, CaseIterable {
    case basic, access
    public var title: String {
        switch self { case .basic: "基础"; case .access: "权限与并发" }
    }
    /// The segment mark read aloud: “基础，有 1 项要修改”.
    public func spokenIssues(_ count: Int) -> String { spoken(issues: count, changed: 0) }
    /// “权限与并发，有 1 项要修改、已改 2 项”; just the title when there is neither.
    public func spoken(issues: Int, changed: Int) -> String {
        let parts = (issues > 0 ? ["有 \(issues) 项要修改"] : []) + (changed > 0 ? ["已改 \(changed) 项"] : [])
        return parts.isEmpty ? title : title + "，" + parts.joined(separator: "、")
    }
}

/// One row of the form, in the names 30 §6.4 uses for “已改 N 项”, the leave confirmation and “同时保存：…”.
public enum UserDraftField: Hashable, Sendable {
    case email, username, notes, attribute(id: Int, name: String), password, initialBalance, status
    case role, exclusiveGroups, publicGroups, groupRates, concurrency, rpmLimit

    public var title: String {
        switch self {
        case .email: "邮箱"
        case .username: "用户名"
        case .notes: "备注"
        case .attribute(_, let name): name
        case .password: "密码"
        case .initialBalance: "初始余额"
        case .status: "状态"
        case .role: "角色"
        case .exclusiveGroups: "专属分组"
        case .publicGroups: "公开分组"
        case .groupRates: "专属倍率"
        case .concurrency: "并发数"
        case .rpmLimit: "RPM 上限"
        }
    }
    public var section: UserDraftSection {
        switch self {
        case .email, .username, .notes, .attribute, .password, .initialBalance, .status: .basic
        case .role, .exclusiveGroups, .publicGroups, .groupRates, .concurrency, .rpmLimit: .access
        }
    }
    public static func names(_ fields: [UserDraftField]) -> String { fields.map(\.title).joined(separator: "、") }
}

public struct UserDraftIssue: Sendable, Equatable {
    public let field: UserDraftField
    public let message: String
    public init(field: UserDraftField, message: String) { self.field = field; self.message = message }
}

/// The “专属倍率” box of the group sheet (30 §6.3).
public enum UserRateInput: Sendable, Equatable {
    /// Left blank: the group's default rate applies.
    case useDefault
    case rate(Decimal)
    case invalid
    public init(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { self = .useDefault; return }
        // Decimal(string:) reads only a prefix ("1,5" is 1), so the whole text must be a plain decimal first.
        guard trimmed.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")), UserWriteValidation.isValidRate(value) else {
            self = .invalid; return
        }
        self = .rate(value)
    }
    public static let errorMessage = UserWriteValidation.rateMessage
}

/// The whole new / edit user form (30 §5.3, §6.3) as plain values. The edit page compares it with a `UserBaseline`.
public struct UserAccessDraft: Sendable, Equatable {
    public var email = ""
    public var username = ""
    public var notes = ""
    public var password = ""
    public var status = "active"
    public var role: AdminUserRole? = .user
    public var concurrency: Int? = 1
    public var adjustmentNotes = ""
    public var rpmLimit: Int? = 0
    /// New user only: the text as typed; blank sends no balance.
    public var initialBalance = ""
    public var exclusiveGroupIDs: Set<Int> = []
    public var restrictPublicGroups = false
    /// The ticked public groups; they count only while the restriction is on.
    public var publicGroupIDs: Set<Int> = []
    /// Edit only: the exclusive rates as the form shows them.
    public var groupRates: [Int: Decimal] = [:]
    public var attributes: [Int: String] = [:]

    /// 30 §5.3 defaults: user, concurrency 1, RPM 0, public groups not restricted.
    public init() {}
    public init(editing baseline: UserBaseline, catalog: UserGroupCatalog) {
        email = baseline.email; username = baseline.username; notes = baseline.notes
        status = baseline.status; role = baseline.role; concurrency = baseline.concurrency; rpmLimit = baseline.rpmLimit
        exclusiveGroupIDs = baseline.allowedGroups.intersection(catalog.exclusiveIDs)
        restrictPublicGroups = baseline.restrictPublicGroups
        publicGroupIDs = baseline.restrictPublicGroups ? baseline.allowedGroups.intersection(catalog.publicIDs) : catalog.publicIDs
        groupRates = baseline.groupRates; attributes = baseline.attributes
    }
    /// Whether leaving the new user page asks “放弃新建用户？” (30 §5.1).
    public var hasContent: Bool {
        var compared = self
        if !compared.restrictPublicGroups { compared.publicGroupIDs = [] }
        return compared != UserAccessDraft()
    }
}

// MARK: - 分组授权与倍率

extension UserAccessDraft {
    /// With the restriction off every public group is usable and shows ticked.
    public func allowsPublicGroup(_ id: Int) -> Bool { !restrictPublicGroups || publicGroupIDs.contains(id) }
    /// Either way every public group is ticked again (turning it off re-ticks all, as on the web).
    public func settingRestrictPublicGroups(_ on: Bool, catalog: UserGroupCatalog) -> UserAccessDraft {
        var copy = self
        copy.restrictPublicGroups = on; copy.publicGroupIDs = catalog.publicIDs
        return copy
    }
    /// “新添加 · 保存后生效”.
    public func addedExclusiveGroups(from baseline: UserBaseline, catalog: UserGroupCatalog) -> Set<Int> {
        exclusiveGroupIDs.subtracting(baseline.allowedGroups.intersection(catalog.exclusiveIDs))
    }
    /// “保存后移除 · N 个 Key 会无法调用” and the receipt's extra sentence.
    public func removedExclusiveGroups(from baseline: UserBaseline, catalog: UserGroupCatalog) -> Set<Int> {
        baseline.allowedGroups.intersection(catalog.exclusiveIDs).subtracting(exclusiveGroupIDs)
    }
    /// 30 §5.3: ticked exclusive groups plus, with the restriction on, the ticked public ones.
    public func allowedGroupsForCreate() -> [Int] {
        exclusiveGroupIDs.union(restrictPublicGroups ? publicGroupIDs : []).sorted()
    }
    /// 30 §6.4: the server's list is the base. Ids the directory does not know (disabled, subscription, gone) stay; turning
    /// the restriction off drops every public id; keeping it off leaves the server's public ids alone.
    public func allowedGroups(from baseline: UserBaseline, catalog: UserGroupCatalog) -> [Int] {
        let unknown = baseline.allowedGroups.subtracting(catalog.exclusiveIDs.union(catalog.publicIDs))
        let publicPart: Set<Int>
        if restrictPublicGroups { publicPart = publicGroupIDs }
        else if baseline.restrictPublicGroups { publicPart = [] }
        else { publicPart = baseline.allowedGroups.intersection(catalog.publicIDs) }
        return unknown.union(exclusiveGroupIDs).union(publicPart).sorted()
    }
    /// Changed or new rates, nil for a cleared one, and nil for a removed exclusive group that had a rate (whatever the draft
    /// still holds for it, so “撤回” restores it). Empty when nothing changed: `{}` would clear every rate on the server.
    public func groupRateChanges(from baseline: UserBaseline, catalog: UserGroupCatalog) -> [Int: Decimal?] {
        let removed = removedExclusiveGroups(from: baseline, catalog: catalog)
        var changes = [Int: Decimal?]()
        for (id, rate) in groupRates where !removed.contains(id) && baseline.groupRates[id] != rate { changes.updateValue(rate, forKey: id) }
        for id in baseline.groupRates.keys where groupRates[id] == nil || removed.contains(id) { changes.updateValue(nil, forKey: id) }
        return changes
    }
    func exclusiveGroupsChanged(from baseline: UserBaseline, catalog: UserGroupCatalog) -> Bool {
        exclusiveGroupIDs != baseline.allowedGroups.intersection(catalog.exclusiveIDs)
    }
    func publicGroupsChanged(from baseline: UserBaseline, catalog: UserGroupCatalog) -> Bool {
        if restrictPublicGroups != baseline.restrictPublicGroups { return true }
        return restrictPublicGroups && publicGroupIDs != baseline.allowedGroups.intersection(catalog.publicIDs)
    }
    /// Rate changes other than the nulls a removed exclusive group brings with it.
    func rateFieldChanged(from baseline: UserBaseline, catalog: UserGroupCatalog) -> Bool {
        let removed = removedExclusiveGroups(from: baseline, catalog: catalog)
        return groupRateChanges(from: baseline, catalog: catalog).keys.contains { !removed.contains($0) }
    }
}

// MARK: - 改动字段与请求体

extension UserAccessDraft {
    /// Form order: email, username, notes, attributes (definition order), password, status, role, exclusive groups, public
    /// groups, exclusive rates, concurrency, RPM limit. Removing an exclusive group with a rate counts as “专属分组” only.
    public func changedFields(from baseline: UserBaseline, catalog: UserGroupCatalog, definitions: [UserAttributeDefinition]) -> [UserDraftField] {
        let edited = attributeChanges(from: baseline, definitions: definitions)
        let account: [(UserDraftField, Bool)] = [(.email, trimmedEmail != baseline.email), (.username, username != baseline.username),
                                                 (.notes, notes != baseline.notes)]
        let attributes = definitions.filter { edited[$0.id] != nil }.map { UserDraftField.attribute(id: $0.id, name: $0.name) }
        let rest: [(UserDraftField, Bool)] = [
            (.password, !password.isEmpty), (.status, status != baseline.status), (.role, changedRole(from: baseline) != nil),
            (.exclusiveGroups, exclusiveGroupsChanged(from: baseline, catalog: catalog)), (.publicGroups, publicGroupsChanged(from: baseline, catalog: catalog)),
            (.groupRates, rateFieldChanged(from: baseline, catalog: catalog)), (.concurrency, changedConcurrency(from: baseline) != nil),
            (.rpmLimit, changedRPMLimit(from: baseline) != nil)
        ]
        return account.filter { $0.1 }.map { $0.0 } + attributes + rest.filter { $0.1 }.map { $0.0 }
    }
    /// 30 §6.4: only what changed. A change to the exclusive or public grant sends the full allowed_groups together with
    /// restrict_public_groups; adjustment notes go only with concurrency; never a balance. nil when no user field changed
    /// (attributes alone are written by their own PUT).
    public func updateRequest(from baseline: UserBaseline, catalog: UserGroupCatalog) -> UserUpdateRequest? {
        let grants = exclusiveGroupsChanged(from: baseline, catalog: catalog) || publicGroupsChanged(from: baseline, catalog: catalog)
        let request = UserUpdateRequest(
            email: trimmedEmail == baseline.email ? nil : trimmedEmail, password: password,
            username: username == baseline.username ? nil : username, notes: notes == baseline.notes ? nil : notes,
            role: changedRole(from: baseline), concurrency: changedConcurrency(from: baseline), rpmLimit: changedRPMLimit(from: baseline),
            adjustmentNotes: adjustmentNotes, status: status == baseline.status ? nil : status,
            allowedGroups: grants ? allowedGroups(from: baseline, catalog: catalog) : nil, restrictPublicGroups: grants ? restrictPublicGroups : nil,
            groupRates: groupRateChanges(from: baseline, catalog: catalog))
        return request.hasChanges ? request : nil
    }
    /// 30 §5.4 step 5: no group rates when creating; a blank initial balance is left out.
    public func createRequest() throws -> UserCreateRequest {
        let balance = try Self.initialBalance(initialBalance)
        return UserCreateRequest(email: email, password: password, username: username, notes: notes, role: role ?? .user,
                                 concurrency: concurrency ?? 1, rpmLimit: rpmLimit ?? 0, balance: balance,
                                 allowedGroups: allowedGroupsForCreate(), restrictPublicGroups: restrictPublicGroups)
    }
    /// The values for `PUT admin/users/:id/attributes`; `baseline` is nil for a new user.
    public func attributeChanges(from baseline: UserBaseline?, definitions: [UserAttributeDefinition]) -> [Int: String] {
        UserAttributeEdits.changes(original: baseline?.attributes ?? [:], draft: attributes, definitions: definitions)
    }
    var trimmedEmail: String { email.trimmingCharacters(in: .whitespacesAndNewlines) }
    private func changedRole(from baseline: UserBaseline) -> AdminUserRole? { role == baseline.role ? nil : role }
    private func changedConcurrency(from baseline: UserBaseline) -> Int? { concurrency == baseline.concurrency ? nil : concurrency }
    private func changedRPMLimit(from baseline: UserBaseline) -> Int? { rpmLimit == baseline.rpmLimit ? nil : rpmLimit }
}

// MARK: - 本地校验

extension UserAccessDraft {
    static let invalidAmountMessage = "不是合法金额"
    /// `baseline` is nil for a new user. In form order, so the first issue picks the segment and row to show. When editing,
    /// only changed values are checked, except required attributes (as on the web).
    public func issues(against baseline: UserBaseline?, definitions: [UserAttributeDefinition]) -> [UserDraftIssue] {
        emailIssues(against: baseline) + attributeIssues(definitions) + passwordIssues(isNew: baseline == nil)
            + accountIssues(against: baseline) + limitIssues(against: baseline)
    }
    public static func pendingIssuesMessage(_ count: Int) -> String { "还有 \(count) 项需要填写或修改" }
    /// Blank → nil (the site default balance applies); otherwise a non-negative amount with at most 8 decimals.
    public static func initialBalance(_ text: String) throws -> Decimal? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard trimmed.range(of: #"^[0-9]+(\.[0-9]{1,8})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: trimmed, locale: Locale(identifier: "en_US_POSIX")),
              (try? PendingBalanceOperation.validateAmount(value)) != nil else {
            throw APIError(kind: .validation, message: invalidAmountMessage)
        }
        return value
    }
    private func emailIssues(against baseline: UserBaseline?) -> [UserDraftIssue] {
        let value = trimmedEmail
        guard baseline.map({ value != $0.email }) ?? true else { return [] }
        if value.isEmpty { return [UserDraftIssue(field: .email, message: "请输入邮箱")] }
        return UserWriteValidation.isEmail(value) ? [] : [UserDraftIssue(field: .email, message: "邮箱格式不对")]
    }
    /// Read-only types (multi_select, unknown) are never written, so they are not required here (U28).
    private func attributeIssues(_ definitions: [UserAttributeDefinition]) -> [UserDraftIssue] {
        definitions.filter { $0.isRequired && !$0.isReadOnly && (attributes[$0.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { UserDraftIssue(field: .attribute(id: $0.id, name: $0.name), message: "请填写 \($0.name)") }
    }
    private func passwordIssues(isNew: Bool) -> [UserDraftIssue] {
        let message: String?
        if password.isEmpty { message = isNew ? "请输入密码" : nil }
        else if !UserWriteValidation.isLongEnough(password) { message = "至少 6 位" }
        else if !UserWriteValidation.fitsBcrypt(password) { message = "不能超过 72 字节" }
        else { message = nil }
        return message.map { [UserDraftIssue(field: .password, message: $0)] } ?? []
    }
    /// The initial balance, disabling an administrator (U30: the server answers a 500 without reason) and changed rates
    /// (edit only: a new user's request carries none).
    private func accountIssues(against baseline: UserBaseline?) -> [UserDraftIssue] {
        var issues = [UserDraftIssue]()
        guard let baseline else {
            return Self.isValidInitialBalance(initialBalance) ? [] : [UserDraftIssue(field: .initialBalance, message: Self.invalidAmountMessage)]
        }
        if baseline.role == .admin, status == "disabled", baseline.status != status {
            issues.append(UserDraftIssue(field: .status, message: "管理员不能禁用"))
        }
        let changedRates = groupRates.filter { baseline.groupRates[$0.key] != $0.value }.values
        if changedRates.contains(where: { !UserWriteValidation.isValidRate($0) }) {
            issues.append(UserDraftIssue(field: .groupRates, message: UserWriteValidation.rateMessage))
        }
        return issues
    }
    private func limitIssues(against baseline: UserBaseline?) -> [UserDraftIssue] {
        let limits: [(UserDraftField, Int?, Int?)] = [(.concurrency, concurrency, baseline?.concurrency), (.rpmLimit, rpmLimit, baseline?.rpmLimit)]
        return limits.compactMap { field, value, original in
            guard let value, baseline == nil || value != original, !UserWriteValidation.isLimit(value) else { return nil }
            return UserDraftIssue(field: field, message: UserWriteValidation.limitMessage)
        }
    }
    private static func isValidInitialBalance(_ text: String) -> Bool {
        do { _ = try initialBalance(text); return true } catch { return false }
    }
}

// MARK: - 读回比对与随机密码

/// 30 §6.5 after an unconfirmed save (S3D1-18). `undetermined`: the request carried nothing comparable (only a password).
public enum UserReadbackOutcome: Sendable, Equatable { case matches, differs, undetermined }

extension UserAccessDraft {
    /// The frozen request against `GET admin/users/:id` (a PUT reply has no group rates). Only the fields the request carried
    /// are compared, so another administrator's unrelated edit does not count; password and adjustment notes cannot be read.
    public static func readback(sent: UserUpdateRequest, server user: AdminUser) -> UserReadbackOutcome {
        let checks = readbackChecks(sent: sent, server: user)
        if checks.isEmpty { return .undetermined }
        return checks.allSatisfy { $0 } ? .matches : .differs
    }
    private static func readbackChecks(sent: UserUpdateRequest, server user: AdminUser) -> [Bool] {
        var checks = [Bool]()
        if let email = sent.email { checks.append(user.email == email) }
        if let username = sent.username { checks.append((user.username ?? "") == username) }
        if let notes = sent.notes { checks.append((user.notes ?? "") == notes) }
        if let role = sent.role { checks.append(user.role == role.rawValue) }
        if let status = sent.status { checks.append(user.status == status) }
        if let concurrency = sent.concurrency { checks.append(user.concurrency == concurrency) }
        if let rpmLimit = sent.rpmLimit { checks.append(user.rpmLimit == rpmLimit) }
        if let allowed = sent.allowedGroups { checks.append(Set(user.allowedGroups ?? []) == Set(allowed)) }
        if let restrict = sent.restrictPublicGroups { checks.append((user.restrictPublicGroups ?? false) == restrict) }
        if let rates = sent.groupRates { checks.append(ratesMatch(rates, server: user.groupRates ?? [:])) }
        return checks
    }
    /// The server keeps float64, so its value is compared at the 3 decimals a rate may have; a cleared rate must be gone.
    private static func ratesMatch(_ sent: [Int: Decimal?], server: [Int: Decimal]) -> Bool {
        sent.allSatisfy { entry in
            guard let rate = entry.value else { return server[entry.key] == nil }
            return server[entry.key].map { DisplayFormat.rounded($0, digits: 3) } == DisplayFormat.rounded(rate, digits: 3)
        }
    }

    /// Letters and digits without the look-alikes 0 O o 1 l I: 56 symbols, 12 of them, about 70 bits.
    private static let passwordAlphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnpqrstuvwxyz23456789")
    /// 30 §5.3 生成随机密码: “xxxx-xxxx-xxxx”.
    public static func randomPassword() -> String {
        var generator = SystemRandomNumberGenerator()
        return randomPassword(using: &generator)
    }
    public static func randomPassword<G: RandomNumberGenerator>(using generator: inout G) -> String {
        var groups = [String]()
        for _ in 0..<3 {
            var group = ""
            for _ in 0..<4 { group.append(passwordAlphabet[Int.random(in: 0..<passwordAlphabet.count, using: &generator)]) }
            groups.append(group)
        }
        return groups.joined(separator: "-")
    }
}
