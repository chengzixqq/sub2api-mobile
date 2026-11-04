import Foundation

// 50 §3.3 成员账号 N and the member half of §3.4 (S5-11): the group sheet's members as a value — who is in, who joins in the order
// picked, who leaves in the members' order — what the section says, and what 创建 / 保存 sends after the group's own write.
// The writes themselves are S5-03's (GroupMemberBatchRequest) through S5-08's GroupMemberWriter.

/// 50 §3.4: a new group is created first and its members written with the id it got; an edit sends PUT only for changed fields,
/// then the members; only members changed → no PUT.
public enum GroupEditSteps: Sendable, Equatable {
    case createGroup(thenMembers: Bool)
    case updateGroup(thenMembers: Bool)
    case membersOnly
    /// An edit without any change: 保存 is greyed.
    case nothing

    public static func resolve(isNew: Bool, hasFieldChanges: Bool, hasMemberChanges: Bool) -> GroupEditSteps {
        if isNew { return .createGroup(thenMembers: hasMemberChanges) }
        if hasFieldChanges { return .updateGroup(thenMembers: hasMemberChanges) }
        return hasMemberChanges ? .membersOnly : .nothing
    }
    public var sendsGroupWrite: Bool {
        switch self {
        case .createGroup, .updateGroup: true
        case .membersOnly, .nothing: false
        }
    }
    public var sendsMembers: Bool {
        switch self {
        case .createGroup(let then), .updateGroup(let then): then
        case .membersOnly: true
        case .nothing: false
        }
    }
}

/// What goes out once the group's own step went through.
public struct GroupMemberCommitPlan: Sendable {
    public let request: GroupMemberBatchRequest
    /// Joining in the order picked, then leaving in the members' order: the per-item page's names and states (5.2).
    public let accounts: [UpstreamAccount]
    public var snapshots: [Int: GroupBatchAccount] {
        Dictionary(accounts.map { ($0.id, GroupBatchAccount($0)) }, uniquingKeysWith: { first, _ in first })
    }
}

/// The sheet's members: an edit opens with the group's members once read (the detail's query, R19), a new group with none.
/// A member taken out stays listed under 将移出 and may be added back; an account picked again is not added twice.
public struct GroupMemberDraft: Sendable, Equatable {
    /// 3.3 成员行's right-hand side.
    public enum Trailing: Sendable, Equatable { case newlyAdded, schedulable, badge(AccountDisplayState) }
    public struct Row: Sendable, Identifiable {
        public let account: UpstreamAccount
        /// Joins on 创建 / 保存.
        public let isNew: Bool
        public var id: Int { account.id }
        public func display(now: Date) -> AccountDisplayState { AccountDisplayState(account, now: now) }
        /// 新加入 first; then 可调度 for the available state, else its badge (a timed one counts down).
        public func trailing(now: Date) -> Trailing {
            if isNew { return .newlyAdded }
            let display = display(now: now)
            return display.state == .available ? .schedulable : .badge(display)
        }
    }

    public let platform: String
    /// An edit's members are not read yet: nothing to count, nothing to add.
    public let isLoaded: Bool
    /// The server's order (urgency).
    public let original: [UpstreamAccount]
    /// The order picked.
    public let added: [UpstreamAccount]
    /// The members' order.
    public let removedIDs: [Int]

    private init(platform: String, isLoaded: Bool, original: [UpstreamAccount], added: [UpstreamAccount], removedIDs: [Int]) {
        self.platform = platform; self.isLoaded = isLoaded; self.original = original; self.added = added; self.removedIDs = removedIDs
    }
    public static func new(platform: String) -> GroupMemberDraft { GroupMemberDraft(platform: platform, isLoaded: true, original: [], added: [], removedIDs: []) }
    public static func pending(platform: String) -> GroupMemberDraft { GroupMemberDraft(platform: platform, isLoaded: false, original: [], added: [], removedIDs: []) }
    public init(platform: String, original: [UpstreamAccount]) { self.init(platform: platform, isLoaded: true, original: original, added: [], removedIDs: []) }
    /// The edit's members once read; a draft that has them already stays as it is.
    public func loaded(_ members: [UpstreamAccount]) -> GroupMemberDraft { isLoaded ? self : GroupMemberDraft(platform: platform, original: members) }

    /// The members left in their order, then the ones joining.
    public var rows: [Row] {
        let removed = Set(removedIDs)
        return original.filter { !removed.contains($0.id) }.map { Row(account: $0, isNew: false) } + added.map { Row(account: $0, isNew: true) }
    }
    /// 成员账号 N and the footnote's n.
    public var count: Int { original.count - removedIDs.count + added.count }
    public var hasChanges: Bool { !added.isEmpty || !removedIDs.isEmpty }
    public var addedCount: Int { added.count }
    public var removedCount: Int { removedIDs.count }
    /// The picker leaves out what is listed; a member taken out may be picked back.
    public var excludedIDs: Set<Int> { Set(rows.map(\.id)) }
    public var removedNames: [String] {
        let removed = Set(removedIDs)
        return original.filter { removed.contains($0.id) }.map(\.name)
    }

    /// The listed ones are skipped; a member taken out comes back in its place (no change); the rest join in this order.
    public func adding(_ accounts: [UpstreamAccount]) -> GroupMemberDraft {
        var listed = excludedIDs, restored = Set<Int>(), joining: [UpstreamAccount] = []
        let members = Set(original.map(\.id))
        for account in accounts where listed.insert(account.id).inserted {
            if members.contains(account.id) { restored.insert(account.id) } else { joining.append(account) }
        }
        return GroupMemberDraft(platform: platform, isLoaded: isLoaded, original: original, added: added + joining,
                                removedIDs: removedIDs.filter { !restored.contains($0) })
    }
    /// One joining is dropped; a member goes under 将移出; an unknown id changes nothing.
    public func removing(_ accountID: Int) -> GroupMemberDraft {
        if added.contains(where: { $0.id == accountID }) {
            return GroupMemberDraft(platform: platform, isLoaded: isLoaded, original: original, added: added.filter { $0.id != accountID }, removedIDs: removedIDs)
        }
        guard original.contains(where: { $0.id == accountID }), !removedIDs.contains(accountID) else { return self }
        let removing = Set(removedIDs + [accountID])
        return GroupMemberDraft(platform: platform, isLoaded: isLoaded, original: original, added: added,
                                removedIDs: original.map(\.id).filter(removing.contains))
    }
    /// 3.3 新建改平台时清空已选成员 (a new group has no members of its own).
    public func resetting(platform: String) -> GroupMemberDraft { .new(platform: platform) }

    /// x: the listed accounts the group would schedule now (S5-02's rule); nil until an edit's members are read.
    public func availableAfter(now: Date) -> Int? {
        isLoaded ? GroupPresentation.availableAfter(members: rows.map(\.account), platform: platform, now: now) : nil
    }
    /// y: the same rule on the members as they are.
    public func availableNow(now: Date) -> Int? { isLoaded ? GroupPresentation.availableAfter(members: original, platform: platform, now: now) : nil }
    /// A listed member counts down a window: the rows redraw every second.
    public func hasCountdown(now: Date) -> Bool { rows.contains { !$0.isNew && $0.display(now: now).countdownTarget != nil } }

    /// nil without a change. Joining without priorities (the server's default 50), never confirmed for a mixed channel.
    public func commitPlan() throws -> GroupMemberCommitPlan? {
        guard hasChanges else { return nil }
        let request = try GroupMemberBatchRequest(add: added.map { GroupMemberAdd(accountID: $0.id) }, remove: removedIDs)
        let removed = Set(removedIDs)
        return GroupMemberCommitPlan(request: request, accounts: added + original.filter { removed.contains($0.id) })
    }

    /// By ids: UpstreamAccount is not Equatable.
    public static func == (lhs: GroupMemberDraft, rhs: GroupMemberDraft) -> Bool {
        lhs.platform == rhs.platform && lhs.isLoaded == rhs.isLoaded && lhs.original.map(\.id) == rhs.original.map(\.id)
            && lhs.added.map(\.id) == rhs.added.map(\.id) && lhs.removedIDs == rhs.removedIDs
    }
}

/// 3.3 成员账号 N 的脚注.
public struct GroupMemberFootnote: Sendable, Equatable {
    public let text: String
    public let isCritical: Bool
    public init(text: String, isCritical: Bool) { self.text = text; self.isCritical = isCritical }
}

/// 50 §3.3 / §3.4 words of the members section and of the receipt after the group was saved. 可调度 is S5-08's
/// GroupPickerPresentation.schedulableText; the member receipt itself is S5-03's GroupMemberReceipt.
public enum GroupMemberDraftCopy {
    public static let newTag = "新加入"
    public static let emptyPublicWarning = "公开分组没有可用账号时，选它的请求会失败。"
    public static let emptyLater = "可以现在添加，也可以创建后在详情里添加。"

    public static func sectionTitle(count: Int) -> String { "成员账号 \(DisplayFormat.grouped(count))" }
    /// “添加 Anthropic 账号…”, or “添加账号…” for a composite group.
    public static func addRowTitle(platform: String, catalog: MetaCatalog? = nil) -> String { GroupCopy.addAccountsRow(platform: platform, catalog: catalog) + "…" }
    public static func removedLine(_ names: [String]) -> String? { names.isEmpty ? nil : "将移出：" + names.joined(separator: "、") }
    /// The “−” button's spoken label.
    public static func removeLabel(name: String) -> String { "\(GroupMemberPresentation.removeTitle) \(name)" }
    /// A new group without members: the public warning, then when to add. Otherwise “创建后可用 x / n” or “保存后可用 x / n”, with
    /// “（现在 y）” only when an edit changes it; red when nothing is available and the group is active after saving.
    public static func footnote(isNew: Bool, isPublic: Bool, isActiveAfterSave: Bool, count: Int, availableAfter: Int, availableNow: Int?) -> GroupMemberFootnote {
        if isNew, count == 0 { return GroupMemberFootnote(text: (isPublic ? emptyPublicWarning : "") + emptyLater, isCritical: false) }
        let current = isNew ? nil : availableNow.flatMap { $0 == availableAfter ? nil : "（现在 \(DisplayFormat.grouped($0))）" }
        let text = "\(isNew ? "创建" : "保存")后可用 \(DisplayFormat.grouped(availableAfter)) / \(DisplayFormat.grouped(count))" + (current ?? "")
        return GroupMemberFootnote(text: text, isCritical: availableAfter == 0 && isActiveAfterSave)
    }
    /// 0.8 网络错误 / 超时 after the group was saved: “已保存「高级组」 · 成员改动未确认”.
    public static func unconfirmedAfterSave(_ prefix: GroupMemberReceipt.Prefix) -> String { joined(prefix, GroupMemberReceipt.unconfirmed.text) }
    /// A refusal of the members after the group was saved: “<前缀> · 成员没有改动：<原因>”.
    public static func rejectedAfterSave(_ prefix: GroupMemberReceipt.Prefix, reason: String) -> String { joined(prefix, "成员没有改动：" + reason) }
    /// 50 §0.7, U37: hidden for a vendor (its POST is refused) and for simple mode's composite group; a new group follows the
    /// identity; a read-only token, or simple mode without the member batch (S5-中-12), greys it and keeps it shown.
    public static func membersEntry(_ permissions: GroupPermissions, group: AdminGroup?) -> GroupPermissions.Entry {
        if let group { return permissions.canEditMembers(group) }
        if permissions.isVendor { return .hidden }
        return permissions.isReadOnlyToken || permissions.membersBatchUnsupported ? .readOnly : .enabled
    }

    private static func joined(_ prefix: GroupMemberReceipt.Prefix, _ tail: String) -> String {
        [prefix.text, tail].compactMap { $0 }.joined(separator: " · ")
    }
}
