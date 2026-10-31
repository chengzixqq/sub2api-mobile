import Foundation

/// The rules of one 基础 or 调度 sheet over its base account (20 §3.3, §3.4): what may be edited, which fields changed, what is
/// wrong with them, and the PATCH with only the changed keys (top level directly, extra keys in `extra_patch`) plus its undo.
/// `now` is always the site's ServerClock time (20 §0.6).
public struct AccountEditForm: Sendable {
    public let section: AccountEditSection
    public let base: UpstreamAccount
    private let initial: AccountEditDraft

    public init(section: AccountEditSection, base: UpstreamAccount) {
        self.section = section; self.base = base; initial = AccountEditDraft(base)
    }

    /// An account in error goes to 停用 or stays in error; recovering it is 恢复状态's job.
    public var statusOptions: [AccountEditStatus] { initial.status == .error ? [.error, .inactive] : [.active, .inactive] }
    public var statusFootnote: String { initial.status == .error ? AccountEditCopy.errorStatusNote : AccountEditCopy.statusNote }
    public var showsQuota: Bool { Self.supportsQuota(type: base.type) }
    /// While the upstream rate sync is on the server refuses a new rate (409 UPSTREAM_BILLING_RATE_SYNC_CONFLICT): read-only.
    public var isRateLocked: Bool { base.extra?["upstream_billing_rate_sync_enabled"]?.boolValue == true }
    /// The backend's IsAPIKeyOrBedrock (service/account.go).
    public static func supportsQuota(type: String) -> Bool { type == "apikey" || type == "bedrock" }

    /// This section's fields that differ from the base, valid or not, in sheet order.
    public func changedFields(_ draft: AccountEditDraft) -> [AccountEditField] {
        fields.filter { state(of: $0, in: draft) != .unchanged }
    }
    /// The changed fields that cannot be sent, with what to say under them.
    public func errors(_ draft: AccountEditDraft, now: Date) -> [AccountEditField: String] {
        var errors: [AccountEditField: String] = [:]
        for field in fields {
            if case .invalid(let message) = state(of: field, in: draft, now: now) { errors[field] = message }
        }
        return errors
    }
    /// nil when nothing changed or something changed cannot be sent.
    public func change(_ draft: AccountEditDraft, now: Date) -> AccountEditChange? {
        var request = AccountPatchRequest(), undo = AccountPatchRequest(), names: [String] = []
        for field in fields {
            switch state(of: field, in: draft, now: now) {
            case .unchanged: continue
            case .invalid: return nil
            case .changed(let edit):
                edit.apply(&request, &undo)
                names.append(field.title)
            }
        }
        return names.isEmpty ? nil : AccountEditChange(fieldNames: names, request: request, undo: undo)
    }

    private var fields: [AccountEditField] {
        AccountEditField.allCases.filter { $0.section == section && (showsQuota || AccountQuota(field: $0) == nil) }
    }

    // MARK: - One field

    private struct Edit: Sendable {
        let apply: @Sendable (inout AccountPatchRequest, inout AccountPatchRequest) -> Void
    }
    private enum FieldState: Equatable {
        case unchanged, invalid(String), changed(Edit)
        static func == (lhs: FieldState, rhs: FieldState) -> Bool {
            switch (lhs, rhs) {
            case (.unchanged, .unchanged): true
            case (.invalid(let a), .invalid(let b)): a == b
            case (.changed, .changed): true
            default: false
            }
        }
    }
    private static func changed(_ apply: @escaping @Sendable (inout AccountPatchRequest, inout AccountPatchRequest) -> Void) -> FieldState {
        .changed(Edit(apply: apply))
    }

    /// Without `now` the expiry is not checked against the clock (changedFields).
    private func state(of field: AccountEditField, in draft: AccountEditDraft, now: Date? = nil) -> FieldState {
        switch field {
        case .name, .status, .notes: basicState(of: field, in: draft)
        case .concurrency, .priority, .rateMultiplier, .loadFactor: numberState(of: field, in: draft)
        case .groups: groupsState(draft)
        case .expiresAt, .autoPauseOnExpired: expiryState(of: field, in: draft, now: now)
        case .quotaDaily, .quotaWeekly, .quotaTotal: AccountQuota(field: field).map { quotaState($0, in: draft) } ?? .unchanged
        }
    }
    private func basicState(of field: AccountEditField, in draft: AccountEditDraft) -> FieldState {
        switch field {
        case .name:
            let name = Self.trimmed(draft.name), old = base.name
            guard name != Self.trimmed(old) else { return .unchanged }
            guard !name.isEmpty else { return .invalid(AccountEditCopy.nameRequired) }
            return Self.changed { $0.name = name; $1.name = old }
        case .status:
            let target = draft.status.patchStatus, old = initial.status.patchStatus
            guard draft.status != initial.status else { return .unchanged }
            return Self.changed { $0.status = target; $1.status = old }
        default:
            let notes = Self.trimmed(draft.notes), old = base.notes ?? ""
            guard notes != Self.trimmed(old) else { return .unchanged }
            return Self.changed { $0.notes = notes; $1.notes = old }
        }
    }
    private func numberState(of field: AccountEditField, in draft: AccountEditDraft) -> FieldState {
        switch field {
        case .concurrency:
            guard let value = draft.concurrency, value != base.concurrency else { return .unchanged }
            let old = base.concurrency ?? 0
            return Self.changed { $0.concurrency = value; $1.concurrency = old }
        case .priority:
            guard let value = draft.priority, value != base.priority else { return .unchanged }
            let old = base.priority ?? 0
            return Self.changed { $0.priority = value; $1.priority = old }
        case .rateMultiplier:
            guard !isRateLocked, draft.rateMultiplier != initial.rateMultiplier else { return .unchanged }
            guard let value = Self.decimal(draft.rateMultiplier) else { return .invalid(AccountEditCopy.rateInvalid) }
            guard value != base.rateMultiplier else { return .unchanged }
            let old = base.rateMultiplier ?? 1
            return Self.changed { $0.rateMultiplier = value; $1.rateMultiplier = old }
        default:
            guard draft.loadFactor != initial.loadFactor else { return .unchanged }
            guard let value = Self.loadFactor(draft.loadFactor) else { return .invalid(AccountEditCopy.loadFactorInvalid) }
            let old = max(base.loadFactor ?? 0, 0)
            guard value != old else { return .unchanged }
            return Self.changed { $0.loadFactor = value; $1.loadFactor = old }
        }
    }
    /// Compared as sets; sent in the sheet's order, and the undo in the base's (S2D1-07).
    private func groupsState(_ draft: AccountEditDraft) -> FieldState {
        guard Set(draft.groupIDs) != Set(initial.groupIDs) else { return .unchanged }
        let target = draft.groupIDs, old = initial.groupIDs
        return Self.changed { $0.groupIDs = target; $1.groupIDs = old }
    }
    /// 不过期 sends 0; the switch counts only while there is an expiry. A changed expiry must lie ahead of `now`.
    private func expiryState(of field: AccountEditField, in draft: AccountEditDraft, now: Date?) -> FieldState {
        if field == .autoPauseOnExpired {
            guard draft.expiresAt != nil, draft.autoPauseOnExpired != initial.autoPauseOnExpired else { return .unchanged }
            let target = draft.autoPauseOnExpired, old = initial.autoPauseOnExpired
            return Self.changed { $0.autoPauseOnExpired = target; $1.autoPauseOnExpired = old }
        }
        guard draft.expiresAt != initial.expiresAt else { return .unchanged }
        if let value = draft.expiresAt, let now, !AccountExpiry.isFuture(value, now: now) { return .invalid(AccountEditCopy.futureRequired) }
        let target = draft.expiresAt ?? 0, old = initial.expiresAt ?? 0
        return Self.changed { $0.expiresAt = target; $1.expiresAt = old }
    }
    /// Empty or 0 is no limit: the key goes out as null. Only the limit is written; used amounts stay (20 §3.3 脚注).
    private func quotaState(_ quota: AccountQuota, in draft: AccountEditDraft) -> FieldState {
        guard draft[quota] != initial[quota] else { return .unchanged }
        guard let value = Self.limit(draft[quota]) else { return .invalid(AccountEditCopy.quotaInvalid) }
        let old = quota.limit(in: base)
        guard value != old else { return .unchanged }
        let key = quota.extraKey, target = Self.patchValue(value), undo = Self.patchValue(old)
        return Self.changed { $0.extraPatch[key] = target; $1.extraPatch[key] = undo }
    }

    // MARK: - Parsing (ASCII digits only)

    private static let decimalPattern = #"^[0-9]+(\.[0-9]+)?$"#
    static func decimal(_ text: String) -> Decimal? {
        guard text.range(of: decimalPattern, options: .regularExpression) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }
    /// "" and "0" are the default (0); otherwise 1–10000.
    static func loadFactor(_ text: String) -> Int? {
        guard !text.isEmpty else { return 0 }
        guard text.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil, let value = Int(text), value <= 10_000 else { return nil }
        return value
    }
    /// nil when the text is not an amount; `.some(nil)` (empty or 0) is no limit.
    static func limit(_ text: String) -> Decimal?? {
        guard !text.isEmpty else { return .some(nil) }
        guard let value = decimal(text) else { return nil }
        return .some(value > 0 ? value : nil)
    }
    private static func patchValue(_ value: Decimal?) -> JSONPatchValue { value.map { .set(.number($0)) } ?? .delete }
    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}

extension AccountQuota {
    init?(field: AccountEditField) {
        guard let match = Self.allCases.first(where: { $0.field == field }) else { return nil }
        self = match
    }
}

/// 20 §3.3–§3.5 wording of the edit sections, their sheets and the save flow.
public enum AccountEditCopy {
    public static let nameRequired = "请输入账号名称"
    public static let rateInvalid = "账号计费倍率需要是不小于 0 的数字"
    public static let loadFactorInvalid = "负载因子为 1–10000 的整数；留空或 0 恢复默认"
    /// Design aeInvalid.
    public static let quotaInvalid = "填写美元金额，留空表示不限"
    public static let futureRequired = "到期时间要晚于现在"
    public static let statusNote = "限流、过载等运行状态不在这里改"
    public static let errorStatusNote = "清除错误用账号详情里的“恢复状态”"
    public static let priorityNote = "越小越优先"
    public static let rateNote = "0 表示不计费，仅影响账号计费"
    public static let loadFactorNote = "越大越常被选中"
    public static let loadFactorDefault = "默认"
    public static let ungrouped = "未分组"
    public static let autoPauseNote = "到期自动暂停调度"
    public static let quotaTitle = "配额"
    public static let quotaKinds = "日 / 周 / 总限额"
    public static let quotaUnlimited = "不限"
    public static let quotaSectionNote = "留空表示不限"
    /// Web's note while the upstream rate sync is on (EditAccountModal.vue).
    public static let rateLockedNote = "当前倍率由上游声明的基准倍率（不含高峰）自动维护。"
    public static let quotaFootnote = "任一项达到后暂停调度；修改限额不重置已用额度。重置时间和用量提醒在 Web 中设置。"
    public static let discardTitle = "放弃未保存的改动？"
    public static let discardConfirm = "放弃改动"
    public static let keepEditing = "继续编辑"
    public static let conflictTitle = AccountActionCopy.modifiedElsewhere
    public static let overwrite = "用我的修改覆盖"
    public static let reload = "重新载入"
    /// Design aePut.
    public static let mixedChannelTitle = "混合渠道警告"
    public static let mixedChannelContinue = "继续保存"
    public static let notApplied = "没有保存成功"
    public static let retry = "重试"
    public static let unconfirmed = AccountActionCopy.unconfirmed
    public static let recheck = "刷新核对"
    public static let undoConflict = "撤销没有成功：账号已被修改"
    public static let needsRefresh = "先刷新账号"
    public static let reloadFailed = "读取账号失败"
    public static let openWeb = "在 Web 中编辑"

    public static func quotaTitle(_ quota: AccountQuota) -> String { quota.field.title }
    /// 已用 $x; nil when the server sent no amount.
    public static func quotaUsed(_ amount: Decimal?) -> String? { amount.map { "已用 " + DisplayFormat.money($0) } }
    /// ×1.2: DisplayFormat.decimal, up to three digits (BACKLOG “倍率的显示位数”, the account side).
    public static func rate(_ value: Decimal?) -> String {
        guard let value else { return DisplayFormat.missing }
        return "×" + DisplayFormat.decimal(NSDecimalNumber(decimal: value).doubleValue, maxFractionDigits: 3)
    }
    /// 已保存：the first three names, then “等 N 项”.
    public static func savedReceipt(_ names: [String]) -> String {
        names.count > 3 ? "已保存：\(names.prefix(3).joined(separator: "、")) 等 \(names.count) 项" : "已保存：\(names.joined(separator: "、"))"
    }
    /// Every name: a sheet has at most ten fields.
    public static func discardMessage(_ names: [String]) -> String { "\(names.count) 项改动不会保存：\(names.joined(separator: "、"))" }
    public static func rejected(reason: String) -> String { "服务器拒绝了这次修改（\(reason)）" }
    public static func undoFailed(_ reason: String) -> String { "撤销没有成功：\(reason)" }
}
