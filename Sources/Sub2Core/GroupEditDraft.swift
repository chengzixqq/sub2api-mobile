import Foundation

// 50 §3.2–§3.5 (S5-10): the group sheet's form as a value — its defaults, checks, what it sends and how a lost result is matched.
// The bodies and their own checks are S5-01's GroupCreateRequest / GroupUpdateRequest; the words are GroupEditCopy's.

/// 订阅限额 · 每个订阅.
public enum GroupLimitPeriod: String, CaseIterable, Sendable {
    case daily, weekly, monthly
    public var title: String {
        switch self {
        case .daily: "每日"
        case .weekly: "每周"
        case .monthly: "每月"
        }
    }
}

/// Why the form cannot be sent; those without a footnote only grey the button (or outline the field).
public enum GroupEditIssue: Sendable, Equatable {
    case nameRequired, nameTooLong, nameTaken, rateInvalid, rpmInvalid
    case limitInvalid(GroupLimitPeriod)

    public var footnote: String? {
        switch self {
        case .nameTaken: GroupErrorCopy.reasonText("GROUP_EXISTS", context: .write)
        case .nameTooLong: UserKeyFormCopy.nameTooLong
        default: nil
        }
    }
}

/// The form's texts as typed. An edit sends only what changed (and may change); a new group is created active (POST has no
/// status). Platform and billing type are chosen only when creating.
public struct GroupEditDraft: Sendable, Equatable {
    /// ent's group.name MaxLen(100) counts UTF-8 bytes.
    public static let nameByteLimit = 100
    public static let rateStep = Decimal(string: "0.1")!
    /// The stepper's floor; a typed rate only has to be above 0.
    public static let minimumSteppedRate = Decimal(string: "0.1")!
    public static let rpmMaximum = Int(Int32.max)
    public static let defaultPlatform = "anthropic"
    /// The Core checks' ceiling for rates and amounts.
    static let amountMaximum = Decimal(string: "999999999999.99999999")!

    /// nil creates.
    public let original: AdminGroup?
    public var name: String
    public var description: String
    /// A new group's other platform drops the accounts picked so far (3.3).
    public var platform: String {
        didSet { if isNew, platform != oldValue { members = members.resetting(platform: platform) } }
    }
    public var isActive: Bool
    public var isExclusive: Bool
    public var rateText: String
    public var subscriptionType: String
    /// Blank is 0 (不限); 0 and a missing value both open blank.
    public var rpmText: String
    /// Blank is no limit.
    public var dailyLimit: String
    public var weeklyLimit: String
    public var monthlyLimit: String
    /// 成员账号 N (S5-11): none for a new group; an edit's arrive with `membersLoaded`.
    public var members: GroupMemberDraft

    /// 3.2: name and description blank, Anthropic, active, public, ×1.0, standard billing, no RPM limit, no subscription limits.
    public static func creating() -> GroupEditDraft {
        GroupEditDraft(original: nil, name: "", description: "", platform: defaultPlatform, isActive: true, isExclusive: false, rateText: "1.0",
                       subscriptionType: "standard", rpmText: "", dailyLimit: "", weeklyLimit: "", monthlyLimit: "")
    }
    public init(editing group: AdminGroup) {
        self.init(original: group, name: group.name, description: group.description ?? "", platform: group.platform,
                  isActive: group.status == "active", isExclusive: group.isExclusive ?? false, rateText: group.rateMultiplier.map(Self.rateString) ?? "",
                  subscriptionType: group.subscriptionType ?? "standard", rpmText: group.rpmLimit.flatMap { $0 == 0 ? nil : String($0) } ?? "",
                  dailyLimit: Self.amountString(group.dailyLimitUSD), weeklyLimit: Self.amountString(group.weeklyLimitUSD),
                  monthlyLimit: Self.amountString(group.monthlyLimitUSD))
    }
    private init(original: AdminGroup?, name: String, description: String, platform: String, isActive: Bool, isExclusive: Bool, rateText: String,
                 subscriptionType: String, rpmText: String, dailyLimit: String, weeklyLimit: String, monthlyLimit: String) {
        self.original = original; self.name = name; self.description = description; self.platform = platform; self.isActive = isActive
        self.isExclusive = isExclusive; self.rateText = rateText; self.subscriptionType = subscriptionType; self.rpmText = rpmText
        self.dailyLimit = dailyLimit; self.weeklyLimit = weeklyLimit; self.monthlyLimit = monthlyLimit
        members = original == nil ? .new(platform: platform) : .pending(platform: platform)
    }
    /// The edit's members as the detail reads them; once only.
    public mutating func membersLoaded(_ accounts: [UpstreamAccount]) { members = members.loaded(accounts) }

    public var isNew: Bool { original == nil }
    public var isSubscription: Bool { subscriptionType == "subscription" }
    public var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    public subscript(limit period: GroupLimitPeriod) -> String {
        get {
            switch period {
            case .daily: dailyLimit
            case .weekly: weeklyLimit
            case .monthly: monthlyLimit
            }
        }
        set {
            switch period {
            case .daily: dailyLimit = newValue
            case .weekly: weeklyLimit = newValue
            case .monthly: monthlyLimit = newValue
            }
        }
    }
    /// What the sheet opened with.
    private var opening: GroupEditDraft { original.map(GroupEditDraft.init(editing:)) ?? .creating() }
    /// The members read after opening are not a change; joining or leaving is.
    public var hasUnsavedChanges: Bool {
        let start = opening
        var fields = self
        fields.members = start.members
        return fields != start || members.hasChanges
    }

    // MARK: - 校验

    /// The other groups' names, exactly (the server's unique index tells case apart).
    public static func takenNames(in groups: [AdminGroup], excluding id: Int?) -> Set<String> {
        Set(groups.filter { $0.id != id }.map(\.name))
    }
    /// A new group checks every field; an edit only the texts changed since it opened, so an older server's missing rate or RPM
    /// is not flagged.
    public func issues(takenNames: Set<String>) -> [GroupEditIssue] {
        let start = opening
        var found: [GroupEditIssue] = []
        if isNew || name != start.name, let issue = nameIssue(takenNames: takenNames) { found.append(issue) }
        if isNew || rateText != start.rateText, rate == nil { found.append(.rateInvalid) }
        if isNew || rpmText != start.rpmText, rpm == nil { found.append(.rpmInvalid) }
        if isSubscription {
            for period in GroupLimitPeriod.allCases where isNew || self[limit: period] != start[limit: period] {
                if limit(period) == nil { found.append(.limitInvalid(period)) }
            }
        }
        return found
    }
    /// No issue, and something to send: always for a new group, an edit only with a change it may make or a member change.
    public func isSubmittable(takenNames: Set<String>, editable: Set<GroupPermissions.Field>) -> Bool {
        guard issues(takenNames: takenNames).isEmpty else { return false }
        return isNew ? (try? createRequest()) != nil : hasFieldChanges(editable: editable) || members.hasChanges
    }
    public func hasFieldChanges(editable: Set<GroupPermissions.Field>) -> Bool {
        ((try? updateRequest(editable: editable)) ?? nil) != nil
    }
    public func steps(editable: Set<GroupPermissions.Field>) -> GroupEditSteps {
        .resolve(isNew: isNew, hasFieldChanges: hasFieldChanges(editable: editable), hasMemberChanges: members.hasChanges)
    }
    /// 3.3 成员账号 N 的脚注; nil until an edit's members are read. “分组正常” is the state after saving.
    public func membersFootnote(now: Date) -> GroupMemberFootnote? {
        guard let after = members.availableAfter(now: now) else { return nil }
        return GroupMemberDraftCopy.footnote(isNew: isNew, isPublic: !isExclusive, isActiveAfterSave: isActive, count: members.count, availableAfter: after,
                                             availableNow: members.availableNow(now: now))
    }
    private func nameIssue(takenNames: Set<String>) -> GroupEditIssue? {
        let trimmed = trimmedName
        if trimmed.isEmpty { return .nameRequired }
        if trimmed.utf8.count > Self.nameByteLimit { return .nameTooLong }
        return takenNames.contains(trimmed) ? .nameTaken : nil
    }

    // MARK: - 输入

    /// ±0.1 from the typed rate, or from the opening one (else 1.0) when it does not read; never below 0.1.
    public mutating func stepRate(up: Bool) {
        let current = rate ?? Self.decimal(opening.rateText) ?? 1
        let next = up ? current + Self.rateStep : max(current - Self.rateStep, Self.minimumSteppedRate)
        rateText = Self.rateString(next)
    }
    /// RPM keeps ASCII digits only.
    public static func digitsOnly(_ text: String) -> String { String(text.filter { $0.isASCII && $0.isNumber }) }
    /// meta.catalog's platforms the App knows, composite left out, in the catalog's order; GroupPlatform.concrete without one.
    public static func platformOptions(catalog: MetaCatalog?) -> [String] {
        var seen = Set<String>()
        let listed = (catalog?.platforms ?? []).map(\.id).filter { GroupPlatform.concrete.contains($0) && seen.insert($0).inserted }
        return listed.isEmpty ? GroupPlatform.concrete : listed
    }

    // MARK: - 请求

    /// 3.4 新建 2: the three limits only for subscription billing (blank = null); standard billing sends them all null.
    public func createRequest() throws -> GroupCreateRequest {
        guard let rate, let rpm else { throw Self.invalid }
        let limits = try GroupLimitPeriod.allCases.map { period -> GroupLimitChange in
            guard isSubscription else { return .unlimited }
            guard let value = limit(period) else { throw Self.invalid }
            return value.map(GroupLimitChange.amount) ?? .unlimited
        }
        let request = GroupCreateRequest(name: trimmedName, description: description, platform: platform, rateMultiplier: rate, isExclusive: isExclusive,
                                         subscriptionType: subscriptionType, rpmLimit: rpm, dailyLimitUSD: limits[0], weeklyLimitUSD: limits[1],
                                         monthlyLimitUSD: limits[2])
        try request.validate()
        return request
    }
    /// 3.4 编辑 1: only fields changed and in `editable`; never platform or billing type. A limit cleared goes as null. nil when
    /// there is nothing to send. A name goes only once typed in: the server keeps outer spaces, so an untouched one is not trimmed.
    public func updateRequest(editable: Set<GroupPermissions.Field>) throws -> GroupUpdateRequest? {
        guard let original else { return nil }
        let start = opening
        var request = GroupUpdateRequest()
        if editable.contains(.name), name != start.name, trimmedName != original.name { request.name = trimmedName }
        if editable.contains(.description), description != (original.description ?? "") { request.description = description }
        if editable.contains(.exclusive), isExclusive != (original.isExclusive ?? false) { request.isExclusive = isExclusive }
        if editable.contains(.status), isActive != (original.status == "active") { request.status = isActive ? "active" : "inactive" }
        if editable.contains(.rateMultiplier), rateText != start.rateText {
            guard let rate else { throw Self.invalid }
            if rate != original.rateMultiplier { request.rateMultiplier = rate }
        }
        if editable.contains(.rpmLimit), rpmText != start.rpmText {
            guard let rpm else { throw Self.invalid }
            if rpm != (original.rpmLimit ?? 0) { request.rpmLimit = rpm }
        }
        if editable.contains(.limits), isSubscription { try addLimitChanges(to: &request, from: start, original: original) }
        guard request.hasChanges else { return nil }
        try request.validate()
        return request
    }
    /// 编辑确认 (S5-02) with the members' line and, once they are read, the zeroing check (S5-11); nil for a new group. An edit of
    /// members only passes an empty request.
    public func diff(_ request: GroupUpdateRequest, now: Date) -> GroupEditDiff? {
        original.map {
            GroupEditDiff(original: $0, update: request, membersAdded: members.addedCount, membersRemoved: members.removedCount,
                          availableNow: members.availableNow(now: now), availableAfter: members.availableAfter(now: now))
        }
    }
    private func addLimitChanges(to request: inout GroupUpdateRequest, from start: GroupEditDraft, original: AdminGroup) throws {
        let current: [GroupLimitPeriod: Decimal?] = [.daily: original.dailyLimitUSD, .weekly: original.weeklyLimitUSD, .monthly: original.monthlyLimitUSD]
        for period in GroupLimitPeriod.allCases where self[limit: period] != start[limit: period] {
            guard let value = limit(period) else { throw Self.invalid }
            guard value != (current[period] ?? nil) else { continue }
            let change = value.map(GroupLimitChange.amount) ?? .unlimited
            switch period {
            case .daily: request.dailyLimitUSD = change
            case .weekly: request.weeklyLimitUSD = change
            case .monthly: request.monthlyLimitUSD = change
            }
        }
    }

    // MARK: - 数值

    private var rate: Decimal? { Self.decimal(rateText).flatMap { $0 > 0 && $0 <= Self.amountMaximum ? $0 : nil } }
    /// Blank is 0.
    private var rpm: Int? {
        let text = rpmText.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return 0 }
        guard text == Self.digitsOnly(text), let value = Int(text), value <= Self.rpmMaximum else { return nil }
        return value
    }
    /// .some(nil) is blank (no limit); nil does not read.
    private func limit(_ period: GroupLimitPeriod) -> Decimal?? {
        let text = self[limit: period].trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return .some(nil) }
        guard let value = Self.decimal(text), value <= Self.amountMaximum else { return nil }
        return .some(value)
    }
    /// Digits with an optional fraction; a comma, a full-width comma or a full-width full stop reads as the decimal point.
    static func decimal(_ text: String) -> Decimal? {
        var value = text.trimmingCharacters(in: .whitespaces)
        for mark in [",", "，", "．"] { value = value.replacingOccurrences(of: mark, with: ".") }
        guard value.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let parsed = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")), !parsed.isNaN else { return nil }
        return parsed
    }
    /// 0.8 → 0.8, 1 → 1.0, 1.25 → 1.25.
    static func rateString(_ value: Decimal) -> String {
        let text = NSDecimalNumber(decimal: value).stringValue
        return text.contains(".") ? text : text + ".0"
    }
    private static func amountString(_ value: Decimal?) -> String { value.map { NSDecimalNumber(decimal: $0).stringValue } ?? "" }
    private static let invalid = APIError(kind: .validation, message: "请检查分组表单。")
}

/// 3.4 / 3.5: matching what the server holds against what was sent.
public enum GroupEditReconcile {
    /// 新建核对: the exact name on the same platform, a group that was not in the list when it was sent. Group names are unique on
    /// the server and the form already kept out the names it knew, so that row is this creation.
    public static func created(_ request: GroupCreateRequest, in rows: [AdminGroup], knownIDs: Set<Int>) -> AdminGroup? {
        rows.first { $0.name == request.name && $0.platform == request.platform && !knownIDs.contains($0.id) }
    }
    /// 编辑核对: only the fields sent.
    public static func saved(_ request: GroupUpdateRequest, server: AdminGroup) -> Bool { request.matches(server) }
    /// A 2xx that does not hold what was sent: the server dropped fields this identity may not change (a vendor's scope).
    public static func droppedFields(_ request: GroupUpdateRequest, response: AdminGroup) -> Bool { !request.matches(response) }
}

extension GroupUpdateRequest {
    var hasChanges: Bool {
        name != nil || description != nil || rateMultiplier != nil || isExclusive != nil || status != nil || subscriptionType != nil
            || rpmLimit != nil || dailyLimitUSD != nil || weeklyLimitUSD != nil || monthlyLimitUSD != nil
    }
}
