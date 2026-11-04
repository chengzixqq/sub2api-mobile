import Foundation

/// The group actions of the list swipes, the long-press / ⋯ menu and the detail button row. `rawValue` is the suffix of the
/// identifiers `group.menu.<raw>`, `group.swipe.<raw>` and `group.action.<raw>` (S5D2a-04); never rename a case.
public enum GroupAction: String, CaseIterable, Sendable {
    case edit, addAccounts, disable, enable, duplicate, delete
    /// Menu items and the button row (启用分组 / 添加账号 / 编辑分组).
    public var menuTitle: String {
        switch self {
        case .edit: "编辑分组"
        case .addAccounts: "添加账号"
        case .disable: "停用分组…"
        case .enable: "启用分组"
        case .duplicate: "复制分组"
        case .delete: "删除分组…"
        }
    }
    public var swipeTitle: String {
        switch self {
        case .edit: "编辑"
        case .addAccounts: "添加账号"
        case .disable: "停用"
        case .enable: "启用"
        case .duplicate: "复制"
        case .delete: "删除"
        }
    }
    /// Red, after a divider in the menu.
    public var isDestructive: Bool { self == .delete }
}

public struct GroupMenuItem: Sendable, Equatable, Identifiable {
    public let action: GroupAction
    public let entry: GroupPermissions.Entry
    public var id: GroupAction { action }
}

public struct GroupButton: Sendable, Equatable, Identifiable {
    public let action: GroupAction
    public let entry: GroupPermissions.Entry
    public let isPrimary: Bool
    public var id: GroupAction { action }
}

/// 50 §0.7 and 00 §2.6.3 for the group pages. Without `admin/me` the site administrator is assumed (as ProxyAccess); a vendor
/// cannot sign in yet (U01), so its rules are kept for later and only unit tested.
public struct GroupPermissions: Sendable, Equatable {
    /// Show an entry when `isShown` and wrap its write in `.readOnlyGate()`, so a read-only token greys it instead of hiding it;
    /// a member entry may be `.readOnly` without one (S5-中-12), so those also disable unless `isEnabled`. Never read an Entry
    /// as a Bool. Swipes come only from `leadingSwipe` / `trailingSwipe`, which already drop read-only ones.
    public enum Entry: Sendable, Equatable {
        case hidden, enabled, readOnly
        public var isShown: Bool { self != .hidden }
        public var isEnabled: Bool { self == .enabled }
    }
    public enum Field: String, CaseIterable, Sendable { case name, description, platform, status, exclusive, rateMultiplier, billingType, rpmLimit, limits }
    public enum FieldAccess: Sendable, Equatable { case editable, readOnly, hidden }
    public static let billingManagedNote = "计费由站长管理。"
    /// U37: a vendor changes memberships from the account detail.
    public static let vendorMembersFootnote = "调整成员请在账号详情里修改分组"
    /// S5-中-12: beside the greyed members entries of `membersBatchUnsupported`.
    public static let membersBatchUnsupportedNote = "服务器暂不支持批量调整成员"

    public let isVendor: Bool
    public let isSimpleMode: Bool
    public let isReadOnlyToken: Bool
    private let groupOps: Bool
    private let groupBilling: Bool
    private let supportsMemberBatch: Bool

    /// `supportsMemberBatch`: `groups.member_batch`, and no 500 GROUP_REPOSITORY_UNSUPPORTED yet in this session.
    public init(me: AdminMe?, isReadOnlyToken: Bool, supportsMemberBatch: Bool = true) {
        isVendor = me?.workspace != nil; isSimpleMode = me?.isSimpleRunMode ?? false; self.isReadOnlyToken = isReadOnlyToken
        groupOps = me?.workspace?.permissions?.groupOps ?? false; groupBilling = me?.workspace?.permissions?.groupBilling ?? false
        self.supportsMemberBatch = supportsMemberBatch
    }

    /// The vendor's POST is refused by its route list; simple mode creates with name, description and platform.
    public var canCreate: Entry { entry(!isVendor) }
    public var canEdit: Entry { entry(!isVendor || groupOps || groupBilling) }
    /// Simple mode drops the status field on PUT.
    public var canToggleStatus: Entry { entry(!isSimpleMode && (!isVendor || groupOps)) }
    public var canDuplicate: Entry { entry(!isVendor && !isSimpleMode) }
    /// Simple mode refuses a group that still has accounts (409 GROUP_NOT_EMPTY).
    public var canDelete: Entry { entry(!isVendor) }
    /// Simple mode cannot bind accounts to a composite group (SIMPLE_MODE_GROUP_NOT_BINDABLE), and greys the members of the
    /// others where they cannot go in one batch (S5-中-12): the one-by-one fallback would unbind its composite groups.
    public func canEditMembers(_ group: AdminGroup) -> Entry {
        let base = entry(!isVendor && !(isSimpleMode && group.platform == "composite"))
        return base == .enabled && membersBatchUnsupported ? .readOnly : base
    }
    /// Simple mode without the batch; an older server in standard mode still goes one by one.
    public var membersBatchUnsupported: Bool { isSimpleMode && !supportsMemberBatch }
    public var membersFootnote: String? { isVendor ? Self.vendorMembersFootnote : nil }

    /// `group` nil is a new group. The server silently drops fields this identity may not change, so they show read-only.
    public func access(_ field: Field, in group: AdminGroup?) -> FieldAccess {
        let base = baseAccess(field, in: group)
        return isReadOnlyToken && base == .editable ? .readOnly : base
    }
    public func editableFields(in group: AdminGroup?) -> Set<Field> { Set(Field.allCases.filter { access($0, in: group) == .editable }) }
    /// Under the billing fields when a vendor may not change them.
    public func billingNote(for group: AdminGroup?) -> String? {
        !isSimpleMode && isVendor && !mayChangeBilling(group) ? Self.billingManagedNote : nil
    }
    /// groups/:id/stats, the key and subscription rows and their pages: refused for vendors and in simple mode.
    public var showsStats: Bool { !isVendor && !isSimpleMode }
    public var showsKeysAndSubscriptions: Bool { showsStats }
    /// Only the usage-summary (the list's 今日, the detail's three amounts) and capacity-summary reads. The detail's
    /// 请求 · Tokens · 账号成本 line (dashboard/groups) shows in every mode (S5D2a-13).
    public var showsUsageAndCapacity: Bool { !isSimpleMode }
    /// The list row's third line and the billing parts of the detail subtitle.
    public var showsBillingRow: Bool { !isSimpleMode }

    /// 编辑分组、添加账号、停用分组… / 启用分组、复制分组、删除分组…; hidden ones left out. The page also drops
    /// 添加账号 until it has somewhere to send it.
    public func menu(for group: AdminGroup) -> [GroupMenuItem] {
        let items: [(GroupAction, Entry)] = [(.edit, canEdit), (.addAccounts, canEditMembers(group)), (toggle(group), canToggleStatus),
                                             (.duplicate, canDuplicate), (.delete, canDelete)]
        return items.filter { $0.1.isShown }.map { GroupMenuItem(action: $0.0, entry: $0.1) }
    }
    /// The list's right swipe: 添加账号 on an active group.
    public func leadingSwipe(for group: AdminGroup) -> [GroupAction] {
        group.status == "active" && canEditMembers(group) == .enabled ? [.addAccounts] : []
    }
    /// The list's left swipe: 编辑, then 停用 / 启用.
    public func trailingSwipe(for group: AdminGroup) -> [GroupAction] {
        (canEdit == .enabled ? [.edit] : []) + (canToggleStatus == .enabled ? [toggle(group)] : [])
    }
    /// 2.3 按钮行. A hidden button is dropped and the other keeps its weight: 编辑分组 is never promoted.
    public func buttonRow(for group: AdminGroup, health: GroupHealth) -> [GroupButton] {
        let row: [(GroupAction, Bool)] = switch health {
        case .off: [(.enable, true), (.edit, false)]
        case .noAvailable, .low: [(.addAccounts, true), (.edit, false)]
        case .ok: [(.addAccounts, false), (.edit, true)]
        }
        return row.compactMap { action, isPrimary in
            let shown: Entry = switch action {
            case .enable, .disable: canToggleStatus
            case .addAccounts: canEditMembers(group)
            default: canEdit
            }
            return shown.isShown ? GroupButton(action: action, entry: shown, isPrimary: isPrimary) : nil
        }
    }

    private func entry(_ allowed: Bool) -> Entry {
        guard allowed else { return .hidden }
        return isReadOnlyToken ? .readOnly : .enabled
    }
    private func toggle(_ group: AdminGroup) -> GroupAction { group.status == "active" ? .disable : .enable }
    private func mayChangeBilling(_ group: AdminGroup?) -> Bool { !isVendor || (groupBilling && group?.billingLocked != true) }
    private func baseAccess(_ field: Field, in group: AdminGroup?) -> FieldAccess {
        let isNew = group == nil
        if isSimpleMode {
            switch field {
            case .name, .description: return .editable
            case .platform: return isNew ? .editable : .readOnly
            default: return .hidden
            }
        }
        let mayOperate = !isVendor || groupOps
        switch field {
        case .platform, .billingType: return isNew ? .editable : .readOnly
        case .status: return isNew || !mayOperate ? .readOnly : .editable
        case .name, .description, .exclusive, .rpmLimit: return mayOperate ? .editable : .readOnly
        case .rateMultiplier, .limits: return mayChangeBilling(group) ? .editable : .readOnly
        }
    }
}
