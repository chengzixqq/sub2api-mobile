import Foundation

/// 20 §3.1: the detail's edit sections in page order. 基础 and 调度 are S2-10's; S2-12 fills in the models and advanced
/// sheets (S2D1-08).
public enum AccountEditSection: String, Sendable, CaseIterable, Identifiable {
    case basic, sched, models, adv
    public var id: Self { self }
    public var title: String {
        switch self {
        case .basic: "基础"
        case .sched: "调度"
        case .models: "模型"
        case .adv: "高级"
        }
    }
    /// Design AE_PART_TITLES.
    public var sheetTitle: String {
        switch self {
        case .basic: "编辑基础信息"
        case .sched: "编辑调度"
        case .models: "编辑模型"
        case .adv: "编辑高级设置"
        }
    }
}

/// The fields of the 基础 and 调度 sheets in sheet order; `title` names them in receipts and the discard question.
public enum AccountEditField: String, Sendable, CaseIterable {
    case name, status, notes
    case concurrency, priority, rateMultiplier, loadFactor, groups, expiresAt, autoPauseOnExpired, quotaDaily, quotaWeekly, quotaTotal

    public var title: String {
        switch self {
        case .name: "名称"
        case .status: "账号状态"
        case .notes: "备注"
        case .concurrency: "并发数"
        case .priority: "优先级"
        case .rateMultiplier: "账号计费倍率"
        case .loadFactor: "负载因子"
        case .groups: "分组"
        case .expiresAt: "过期时间"
        case .autoPauseOnExpired: "过期自动暂停调度"
        case .quotaDaily: "日限额"
        case .quotaWeekly: "周限额"
        case .quotaTotal: "总限额"
        }
    }
    public var section: AccountEditSection { [.name, .status, .notes].contains(self) ? .basic : .sched }
}

/// 20 §3.3 账号状态: the stored status, where `inactive`, the old `disabled` and anything unknown read as 停用.
public enum AccountEditStatus: String, Sendable, CaseIterable {
    case active, inactive, error
    public init(accountStatus: String) { self = Self(rawValue: accountStatus) ?? .inactive }
    public var title: String {
        switch self {
        case .active: "正常"
        case .inactive: "停用"
        case .error: "错误"
        }
    }
    var patchStatus: AccountPatchRequest.Status {
        switch self {
        case .active: .active
        case .inactive: .inactive
        case .error: .error
        }
    }
}

/// 20 §3.3 日 / 周 / 总限额: `extra.quota_*_limit`, flattened onto the account with their used amounts.
public enum AccountQuota: String, Sendable, CaseIterable {
    case daily, weekly, total
    public var field: AccountEditField {
        switch self {
        case .daily: .quotaDaily
        case .weekly: .quotaWeekly
        case .total: .quotaTotal
        }
    }
    public var extraKey: String {
        switch self {
        case .daily: "quota_daily_limit"
        case .weekly: "quota_weekly_limit"
        case .total: "quota_limit"
        }
    }
    /// A set limit; 0 or less is no limit.
    public func limit(in account: UpstreamAccount) -> Decimal? {
        let top: Decimal?
        switch self {
        case .daily: top = account.quotaDailyLimit
        case .weekly: top = account.quotaWeeklyLimit
        case .total: top = account.quotaLimit
        }
        guard let value = top ?? account.extra?[extraKey]?.decimalValue, value > 0 else { return nil }
        return value
    }
    public func used(in account: UpstreamAccount) -> Decimal? {
        switch self {
        case .daily: account.quotaDailyUsed
        case .weekly: account.quotaWeeklyUsed
        case .total: account.quotaUsed
        }
    }
}

/// The sheet's editable copy of an account (20 §3.3). Text fields keep what was typed; `AccountEditForm` checks and compares it.
public struct AccountEditDraft: Equatable, Sendable {
    public var name: String
    public var status: AccountEditStatus
    public var notes: String
    public var concurrency: Int?
    public var priority: Int?
    /// The Decimal's own spelling; "" when missing.
    public var rateMultiplier: String
    /// "" for the default (missing or 0 or less).
    public var loadFactor: String
    /// S2D1-07: the account's order (each group's priority); new ones go last.
    public var groupIDs: [Int]
    /// nil: never expires (0 or less reads the same).
    public var expiresAt: Int64?
    public var autoPauseOnExpired: Bool
    public var quotaDaily: String
    public var quotaWeekly: String
    public var quotaTotal: String

    public init(_ account: UpstreamAccount) {
        name = account.name
        status = AccountEditStatus(accountStatus: account.status)
        notes = account.notes ?? ""
        concurrency = account.concurrency
        priority = account.priority
        rateMultiplier = account.rateMultiplier.map(Self.spelling) ?? ""
        loadFactor = account.loadFactor.flatMap { $0 > 0 ? String($0) : nil } ?? ""
        groupIDs = Self.groupOrder(account)
        expiresAt = account.expiresAt.flatMap { $0 > 0 ? $0 : nil }
        autoPauseOnExpired = account.autoPauseOnExpired ?? false
        quotaDaily = AccountQuota.daily.limit(in: account).map(Self.spelling) ?? ""
        quotaWeekly = AccountQuota.weekly.limit(in: account).map(Self.spelling) ?? ""
        quotaTotal = AccountQuota.total.limit(in: account).map(Self.spelling) ?? ""
    }

    /// `group_ids` in its order, or `groups`' when it is empty; then any group only `groups` names.
    public static func groupOrder(_ account: UpstreamAccount) -> [Int] {
        var seen = Set<Int>()
        return (account.groupIDs + account.groups.map(\.id)).filter { seen.insert($0).inserted }
    }
    public subscript(quota: AccountQuota) -> String {
        get {
            switch quota {
            case .daily: quotaDaily
            case .weekly: quotaWeekly
            case .total: quotaTotal
            }
        }
        set {
            switch quota {
            case .daily: quotaDaily = newValue
            case .weekly: quotaWeekly = newValue
            case .total: quotaTotal = newValue
            }
        }
    }
    static func spelling(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
}

/// What one sheet saves (20 §3.4): field names for the receipt and the discard question, the PATCH with only the changed keys,
/// and the request that writes the old values back (nil: no 撤销). Printing shows names and keys only (S2D1-10).
public struct AccountEditChange: Sendable, Equatable {
    public let fieldNames: [String]
    public let request: AccountPatchRequest
    public let undo: AccountPatchRequest?
    public init(fieldNames: [String], request: AccountPatchRequest, undo: AccountPatchRequest?) {
        self.fieldNames = fieldNames; self.request = request; self.undo = undo
    }
    /// Groups changed: the mixed-channel check applies and the group directory's counts move.
    public var touchesGroups: Bool { request.groupIDs != nil }
}

extension AccountEditChange: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "AccountEditChange(\(fieldNames.joined(separator: "、")); \(request)" + (undo.map { "; undo \($0)" } ?? "") + ")"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}
