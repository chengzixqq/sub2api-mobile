import Foundation

// S5-08: 50 §2.4 the member row's actions and §4 添加账号's words, candidates and dock. The member write itself, its receipts and
// per-item results are S5-03's (GroupMembers.swift, GroupBatchOutcome.swift).

/// 50 §2.4 成员左滑 · 状态动作, beside 移出. The confirmation, receipt and undo are S2-06's AccountActions'.
public enum GroupMemberStatusAction: Sendable, Equatable, CaseIterable {
    case recover, enableScheduling, stopScheduling
    /// AccountActionKind's verbs.
    public var title: String {
        switch self {
        case .recover: AccountActionKind.recover.verb
        case .enableScheduling: AccountActionKind.setSchedulable(true).verb
        case .stopScheduling: AccountActionKind.setSchedulable(false).verb
        }
    }
    public var systemImage: String {
        switch self {
        case .recover: "arrow.counterclockwise"
        case .enableScheduling: "play.fill"
        case .stopScheduling: "pause.fill"
        }
    }
}

public enum GroupMemberPresentation {
    public static let removeTitle = "移出"

    /// 错误 / 过载 / 限流 / 临时不可调度 → 恢复状态 (scheduling off too); 暂停 → 启用调度; 正常 → 停止调度. An account its expiry
    /// paused (S2D1-20) and a disabled one get none, only 移出.
    public static func statusAction(for account: UpstreamAccount, now: Date) -> GroupMemberStatusAction? {
        switch AccountDisplayState(account, now: now).state {
        case .error, .overloaded, .rateLimited, .tempUnschedulable: .recover
        case .paused: isExpired(account, now: now) ? nil : .enableScheduling
        case .available: .stopScheduling
        case .inactive: nil
        }
    }
    /// 2.4 “账号正常”: the state F04 counts as available.
    public static func isAvailable(_ account: UpstreamAccount, now: Date) -> Bool { AccountDisplayState(account, now: now).state == .available }
    /// Only the last available account of an active group is asked about; any other removal goes at once.
    public static func removalNeedsConfirmation(_ account: UpstreamAccount, in group: AdminGroup, now: Date) -> Bool {
        isAvailable(account, now: now) && group.status == "active" && group.activeAccountCount == 1
    }
    public static func removalConfirmation(accountName: String, groupName: String, siteName: String) -> GroupConfirmation {
        GroupConfirmation(title: "把「\(accountName)」移出「\(groupName)」？",
                          lines: ["站点 \(siteName)", "它是这个分组唯一可用的账号，移出后这个分组的新请求会失败。账号本身保留。"],
                          confirmTitle: "仍然移出", isDestructive: true)
    }

    private static func isExpired(_ account: UpstreamAccount, now: Date) -> Bool {
        let input = AccountStateInput(account)
        guard input.autoPauseOnExpired == true, let expiresAt = input.expiresAt else { return false }
        return expiresAt <= now
    }
}

/// 4.3 底部坞 of the sheet opened on a group.
public struct GroupPickerDock: Sendable, Equatable {
    public let preview: String
    public let buttonTitle: String
    public let isEnabled: Bool
    public init(preview: String, buttonTitle: String, isEnabled: Bool) { self.preview = preview; self.buttonTitle = buttonTitle; self.isEnabled = isEnabled }
}

/// 50 §4 添加账号. A composite group takes accounts of any concrete platform, so its words name no platform.
public enum GroupPickerPresentation {
    /// Schedulable first, then paused or disabled, then the rest (error and timed states).
    public enum Tier: Int, Sendable, Comparable {
        case schedulable, idle, other
        public static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rawValue < rhs.rawValue }
    }
    /// Inside the group editor (S5-11).
    public static let draftTitle = "添加账号"
    /// BlockFailureRow adds “ · 重试”.
    public static let failedTitle = "账号加载失败"
    /// An available candidate's state, in the ok colour (the others show AccountStatusBadge).
    public static let schedulableText = "可调度"
    public static let noMatch = "没有匹配的账号"

    public static func title(groupName: String) -> String { "添加到「\(groupName)」" }
    public static func searchPrompt(platform: String, catalog: MetaCatalog? = nil) -> String { "搜索" + spaced(platform, catalog) + "账号" }
    public static func sectionTitle(platform: String, catalog: MetaCatalog? = nil) -> String {
        isComposite(platform) ? "账号" : "\(GroupFormat.platformName(platform, catalog: catalog)) 账号"
    }
    public static func footnote(platform: String, catalog: MetaCatalog? = nil) -> String {
        guard !isComposite(platform) else { return "组合分组可以加入任意具体平台的账号。" }
        return "只列出 \(GroupFormat.platformName(platform, catalog: catalog)) 账号：其他平台的账号不会被这个分组调度。个别账号失败不影响其他账号。"
    }
    /// From the read without a search: no account of the platform, every one already a member, else the search found none.
    public static func emptyText(platform: String, catalog: MetaCatalog? = nil, platformTotal: Int, available: Int) -> String {
        if platformTotal == 0 { return "还没有" + spaced(platform, catalog) + "账号" }
        if available == 0 { return sectionTitle(platform: platform, catalog: catalog) + "都已在这个分组里" }
        return noMatch
    }
    public static func tier(_ state: AccountScheduleState) -> Tier {
        switch state {
        case .available: .schedulable
        case .paused, .inactive: .idle
        case .error, .overloaded, .rateLimited, .tempUnschedulable: .other
        }
    }
    /// Opened on a group (`memberOf`): its members are left out; the editor's drafts (`excluded`) always are. Then by tier, each in
    /// the server's order.
    public static func candidates(_ rows: [UpstreamAccount], memberOf groupID: Int?, excluded: Set<Int>, now: Date) -> [UpstreamAccount] {
        rows.filter { row in !excluded.contains(row.id) && !(groupID.map(row.groupIDs.contains) ?? false) }
            .enumerated()
            .map { (tier: tier(AccountDisplayState($0.element, now: now).state), index: $0.offset, row: $0.element) }
            .sorted { ($0.tier, $0.index) < ($1.tier, $1.index) }
            .map(\.row)
    }
    /// “已停止调度 · OAuth · 已在 高级组、Claude Code 组” or “API Key · 未分组”; names through the session's group directory.
    public static func secondLine(_ account: UpstreamAccount, now: Date, directory: (Int) -> String?) -> String {
        let groups = AccountRowPresentation.groupNames(account, directory: directory)
        let parts = [AccountDisplayState(account, now: now).isStopped ? AccountDisplayState.stoppedMark : nil,
                     AccountNaming.typeName(platform: account.platform, type: account.type),
                     groups.isEmpty ? AccountRowPresentation.ungrouped : "已在 " + groups.joined(separator: "、")]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }
    public static func statusText(_ display: AccountDisplayState) -> String? { display.state == .available ? schedulableText : nil }
    /// x = the group's available now, y = x plus the picked accounts it would schedule now (S5-02's availableAfter), z = the
    /// members after joining.
    public static func dock(selected: [UpstreamAccount], group: AdminGroup, now: Date) -> GroupPickerDock {
        guard !selected.isEmpty else { return GroupPickerDock(preview: "选择要加入的账号", buttonTitle: "加入", isEnabled: false) }
        let before = group.activeAccountCount ?? 0
        let after = before + GroupPresentation.availableAfter(members: selected, platform: group.platform, now: now)
        let total = (group.accountCount ?? 0) + selected.count
        let preview = "加入后可用 \(DisplayFormat.grouped(before)) → \(DisplayFormat.grouped(after)) / \(DisplayFormat.grouped(total))"
        return GroupPickerDock(preview: preview, buttonTitle: "加入 \(DisplayFormat.grouped(selected.count)) 个账号", isEnabled: true)
    }
    /// The editor's 添加 N; greyed by the caller at 0.
    public static func draftAddTitle(count: Int) -> String { "添加 \(DisplayFormat.grouped(count))" }

    private static func isComposite(_ platform: String) -> Bool { platform == "composite" }
    /// “ OpenAI ”, or nothing for a composite group.
    private static func spaced(_ platform: String, _ catalog: MetaCatalog?) -> String {
        isComposite(platform) ? "" : " \(GroupFormat.platformName(platform, catalog: catalog)) "
    }
}
