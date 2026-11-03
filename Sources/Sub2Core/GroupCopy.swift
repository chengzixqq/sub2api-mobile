import Foundation

/// A confirmation dialog's words: title, body lines and the confirming button; the other button is always 取消.
public struct GroupConfirmation: Sendable, Equatable {
    public static let cancelTitle = "取消"
    public let title: String
    public let lines: [String]
    public let confirmTitle: String
    public let isDestructive: Bool
    public init(title: String, lines: [String], confirmTitle: String, isDestructive: Bool = false) {
        self.title = title; self.lines = lines; self.confirmTitle = confirmTitle; self.isDestructive = isDestructive
    }
    public var message: String { lines.joined(separator: "\n") }
}

/// 50 §2.3 状态卡 of an active group (an inactive one shows GroupCopy.inactiveCard instead).
public struct GroupStatusCardCopy: Sendable, Equatable {
    public let title: String
    /// “1 个不可用”, or “共 N 个账号” when every account is available.
    public let trailing: String
    /// The two big figures; the page colours them for none / low.
    public let available: String
    public let total: String
    /// Only for a group without available accounts.
    public let warning: String?
    public var figure: String { "\(available) / \(total) 个账号可用" }
}

/// A member parsed once when the members change; the status card's countdown only passes a new `now` (S5-06).
public struct GroupMemberSnapshot: Sendable, Equatable {
    public let id: Int
    public let name: String
    public let input: AccountStateInput
    public init(_ account: UpstreamAccount) { id = account.id; name = account.name; input = AccountStateInput(account) }
}

/// 2.3 最早恢复 (S5D2a-02): a member is back when the last of its running windows ends, so each member's latest running window
/// counts and the group takes the earliest of those. Only members in a timed state with scheduling on come back by waiting.
public struct GroupRecovery: Sendable, Equatable {
    public let target: Date
    /// Members coming back in the same second as `target`.
    public let count: Int
    /// The first of them in member order.
    public let accountName: String

    /// “最早 4:37 后恢复 1 个 · 名称”; several in the same second: “最早 4:37 后恢复 2 个 · 名称 等”.
    public func text(now: Date) -> String {
        "最早 \(DisplayFormat.countdown(until: target, now: now)) 后恢复 \(DisplayFormat.grouped(count)) 个 · \(accountName)" + (count > 1 ? " 等" : "")
    }
    public static func earliest(members: [GroupMemberSnapshot], now: Date) -> GroupRecovery? {
        let timed = members.compactMap { member -> (name: String, end: Date)? in
            let state = AccountDisplayState(member.input, now: now)
            guard state.state.isLimited, !state.isStopped, let end = AccountListLocal.recovery(member.input, now: now) else { return nil }
            return (member.name, end)
        }
        guard let first = timed.min(by: { $0.end < $1.end }) else { return nil }
        let second = Int(first.end.timeIntervalSince1970)
        let tied = timed.filter { Int($0.end.timeIntervalSince1970) == second }
        return GroupRecovery(target: first.end, count: tied.count, accountName: tied.first?.name ?? first.name)
    }
}

/// 50 §0.5 and §2.3 words. The delete title, its first line and its receipt come from DeleteConfirmationCopy with `objectNoun`.
public enum GroupCopy {
    public static let objectNoun = "分组"

    /// N is `active_api_keys` (U39); without it the number is left out.
    public static func disableConfirmation(name: String, siteName: String, activeAPIKeys: Int?) -> GroupConfirmation {
        let keys = activeAPIKeys.map { " \(DisplayFormat.grouped($0)) 个" } ?? ""
        return GroupConfirmation(title: "停用「\(name)」？",
                                 lines: ["站点 \(siteName)", "使用这个分组的\(keys) API 密钥会被拒绝（提示“所属分组已停用”）。可以随时重新启用。"],
                                 confirmTitle: "停用分组")
    }
    public static func disabledReceipt(name: String) -> String { "已停用「\(name)」" }
    public static func enabledReceipt(name: String) -> String { "已启用「\(name)」" }
    public static func duplicateReceipt(newName: String, memberCount: Int) -> String {
        "已复制为「\(newName)」 · 停用中 · \(DisplayFormat.grouped(memberCount)) 个成员账号"
    }
    public static func createdReceipt(name: String) -> String { "已创建「\(name)」" }
    /// `droppedFields`: the vendor's PUT came back without some submitted fields (50 §3.4 step 5).
    public static func savedReceipt(name: String, droppedFields: Bool = false) -> String {
        "已保存「\(name)」" + (droppedFields ? " · 部分字段无权修改，未生效" : "")
    }
    /// 3.4 新建 step 1: only a public group (always created active) with nothing available after creation is confirmed.
    public static func createConfirmation(_ request: GroupCreateRequest, siteName: String, availableAfter: Int,
                                          catalog: MetaCatalog? = nil) -> GroupConfirmation? {
        guard !request.isExclusive, availableAfter == 0 else { return nil }
        let platform = GroupFormat.platformName(request.platform, catalog: catalog)
        return GroupConfirmation(title: "创建公开分组「\(request.name)」？",
                                 lines: ["站点 \(siteName) · \(platform) · 费率倍数 \(GroupFormat.rateText(request.rateMultiplier))",
                                         "创建后所有用户新建 API 密钥时都能选它，但现在没有可用账号，选它的请求会失败。"],
                                 confirmTitle: "仍然创建")
    }
    /// 0.5 删除后果行, zero rows left out. Without stats (older server, vendor, simple mode, a failed or slow read) the key and
    /// subscription rows are said without numbers (S5D2a-03); simple mode refuses a group with members, so no member row.
    public static func deleteConsequences(stats: GroupStats?, group: AdminGroup, isSimpleMode: Bool = false) -> [String] {
        let isSubscription = group.subscriptionType == "subscription"
        var lines: [String] = []
        switch stats {
        case let stats?:
            if stats.totalAPIKeys > 0 { lines.append(keysDeleted(" \(DisplayFormat.grouped(stats.totalAPIKeys)) 个")) }
            if isSubscription, stats.subscriptionsTotal > 0 {
                let active = stats.subscriptionsActive > 0 ? "（生效中 \(DisplayFormat.grouped(stats.subscriptionsActive)) 条）" : ""
                lines.append("删除 \(DisplayFormat.grouped(stats.subscriptionsTotal)) 条订阅记录\(active)。")
            }
        case nil:
            lines.append(keysDeleted(""))
            if isSubscription { lines.append("删除这个分组的全部订阅记录。") }
        }
        let members = group.accountCount ?? 0
        if !isSimpleMode, members > 0 { lines.append("\(DisplayFormat.grouped(members)) 个成员账号移出分组，账号本身保留。") }
        return lines
    }
    private static func keysDeleted(_ count: String) -> String {
        "使用这个分组的\(count) API 密钥会被拒绝（提示“所属分组已删除”），需在用户的 Key 里换分组。"
    }

    // MARK: 2.3 详情

    public static let inactiveCard = "已停用 · 使用此分组的 API 密钥会被拒绝"
    /// `totalAPIKeys` only adds the “no key uses it” sentence to an empty group; nil adds nothing.
    public static func statusCard(health: GroupHealth, buckets: GroupBuckets, totalAPIKeys: Int?) -> GroupStatusCardCopy {
        let trailing = buckets.unavailable > 0 ? "\(DisplayFormat.grouped(buckets.unavailable)) 个不可用" : "共 \(DisplayFormat.grouped(buckets.total)) 个账号"
        let warning: String? = if health != .noAvailable { nil } else if buckets.total > 0 {
            "没有可用的账号，这个分组的新请求会失败。先让成员账号恢复或启用调度，或加入同平台的可用账号。"
        } else {
            "分组里还没有账号，新请求会失败。" + (totalAPIKeys == 0 ? "目前也没有 API 密钥使用它。" : "")
        }
        return GroupStatusCardCopy(title: health.cardTitle(buckets), trailing: trailing, available: DisplayFormat.grouped(buckets.available),
                                   total: DisplayFormat.grouped(buckets.total), warning: warning)
    }
    /// “其中 s 个账号限流中但已停止调度，计入暂停·停用”: s members in a timed state with scheduling off; their state's word when
    /// they share one, “受限” when mixed; nil when s is 0.
    public static func stoppedLimitedNote(members: [GroupMemberSnapshot], now: Date) -> String? {
        let stopped = members.map { AccountDisplayState($0.input, now: now) }.filter { $0.state.isLimited && $0.isStopped }
        guard let first = stopped.first else { return nil }
        let word = stopped.allSatisfy { $0.state == first.state } ? first.state.label : GroupBucket.limited.label
        return "其中 \(DisplayFormat.grouped(stopped.count)) 个账号\(word)但已停止调度，计入暂停·停用"
    }
    /// 壹 · 成员账号 meta.
    public static func membersMeta(count: Int) -> String? {
        switch count {
        case ..<1: nil
        case 1: "1 个"
        default: "\(DisplayFormat.grouped(count)) 个 · 不可用在前"
        }
    }
    /// U38: `isGroupScoped` when today-stats echoed the group id.
    public static func membersTodayFootnote(isGroupScoped: Bool) -> String {
        isGroupScoped ? "成员行的“今日”只算这个分组的请求（按 Key 所属分组）。"
            : "成员行的“今日”是账号今日，含这个账号在其他分组的用量；分组今日按 Key 所属分组统计。"
    }
    public static func addAccountsRow(platform: String, catalog: MetaCatalog? = nil) -> String {
        platform == "composite" ? "添加账号" : "添加 \(GroupFormat.platformName(platform, catalog: catalog)) 账号"
    }
    public static let capacityMissing = "容量 —"
    /// Why no capacity line has a ceiling.
    public static func capacityEmptyNote(group: AdminGroup, buckets: GroupBuckets) -> String {
        if group.status != "active" { return "停用的分组不统计容量" }
        if buckets.total == 0 { return "没有成员账号" }
        return buckets.available == 0 ? "没有可调度的账号" : "暂无容量数据"
    }
    public static let opsDisabled = "运维监控未开启"
    /// 叁 · 记录与关联 right-hand values.
    public static func last24Hours(_ count: Int?) -> String { count.map { "近 24 小时 \(DisplayFormat.grouped($0)) 条" } ?? DisplayFormat.missing }
    public static func apiKeysValue(_ count: Int?) -> String { count.map { "\(DisplayFormat.grouped($0)) 个" } ?? DisplayFormat.missing }
    public static func activeSubscriptionsValue(_ count: Int?) -> String { count.map { "生效中 \(DisplayFormat.grouped($0)) 个" } ?? DisplayFormat.missing }
}

/// 50 §3.4 编辑确认. `update` holds the edited fields (nil = unchanged); a field equal to the original makes no line.
public struct GroupEditDiff: Sendable {
    public let original: AdminGroup
    public let update: GroupUpdateRequest
    public let membersAdded: Int
    public let membersRemoved: Int
    /// availableAfter(...) now and after saving; nil skips the zeroing check.
    public let availableNow: Int?
    public let availableAfter: Int?

    public init(original: AdminGroup, update: GroupUpdateRequest, membersAdded: Int = 0, membersRemoved: Int = 0, availableNow: Int? = nil,
                availableAfter: Int? = nil) {
        self.original = original; self.update = update; self.membersAdded = membersAdded; self.membersRemoved = membersRemoved
        self.availableNow = availableNow; self.availableAfter = availableAfter
    }

    public func lines(siteName: String, activeAPIKeys: Int?) -> [String] {
        var lines = ["站点 \(siteName) · 分组「\(original.name)」"]
        if let name = newName { lines.append("名称 \(original.name) → \(name)") }
        if descriptionChanged { lines.append("描述已修改") }
        if let rate = newRate {
            let pair = DisplayFormat.multiplierChange(from: original.rateMultiplier, to: rate)
            lines.append("费率倍数 \(pair.from) → \(pair.to)")
        }
        if let rpm = newRPM { lines.append("每用户 RPM \(GroupFormat.rpmText(original.rpmLimit)) → \(GroupFormat.rpmText(rpm))") }
        for limit in limitChanges { lines.append("\(limit.title)限额 \(GroupFormat.limitText(limit.old)) → \(GroupFormat.limitText(limit.new))") }
        if let exclusive = newExclusive {
            lines.append(exclusive ? "公开 → 专属：之后只有分配了这个分组的用户能选它" : "专属 → 公开：之后所有用户新建 API 密钥时都能选它")
        }
        if isDisabling { lines.append("停用分组（\(activeAPIKeys.map { "\(DisplayFormat.grouped($0)) 个 " } ?? "")API 密钥会被拒绝）") }
        if isEnabling { lines.append("启用分组") }
        let members = [(membersAdded, "加入"), (membersRemoved, "移出")].filter { $0.0 > 0 }.map { "\($0.1) \(DisplayFormat.grouped($0.0)) 个" }
        if !members.isEmpty { lines.append("成员：" + members.joined(separator: " · ")) }
        if newRate != nil { lines.append("此后的请求按新倍率计费，已产生的记录不变。") }
        if isDestructive { lines.append("保存后这个分组没有可用的账号，新请求会失败。") }
        return lines
    }
    /// Rate, RPM, exclusivity, a limit or disabling changed, or saving leaves nothing available. Names, the description,
    /// members and enabling go straight through.
    public var requiresConfirmation: Bool {
        newRate != nil || newRPM != nil || newExclusive != nil || !limitChanges.isEmpty || isDisabling || isDestructive
    }
    /// Availability drops from above 0 to 0 while the group stays active (disabling in the same save says it instead).
    public var isDestructive: Bool {
        guard let before = availableNow, let after = availableAfter else { return false }
        return before > 0 && after == 0 && (update.status ?? original.status) == "active"
    }
    public func confirmation(siteName: String, activeAPIKeys: Int?) -> GroupConfirmation {
        GroupConfirmation(title: "保存「\(update.name ?? original.name)」的修改？", lines: lines(siteName: siteName, activeAPIKeys: activeAPIKeys),
                          confirmTitle: isDestructive ? "仍然保存" : "保存修改", isDestructive: isDestructive)
    }

    private var newName: String? { update.name.flatMap { $0 == original.name ? nil : $0 } }
    private var descriptionChanged: Bool { update.description.map { $0 != (original.description ?? "") } ?? false }
    private var newRate: Decimal? { update.rateMultiplier.flatMap { $0 == original.rateMultiplier ? nil : $0 } }
    private var newRPM: Int? { update.rpmLimit.flatMap { $0 == (original.rpmLimit ?? 0) ? nil : $0 } }
    private var newExclusive: Bool? { update.isExclusive.flatMap { $0 == (original.isExclusive ?? false) ? nil : $0 } }
    private var isDisabling: Bool { original.status == "active" && update.status == "inactive" }
    private var isEnabling: Bool { original.status != "active" && update.status == "active" }
    private var limitChanges: [(title: String, old: Decimal?, new: Decimal?)] {
        let limits: [(String, GroupLimitChange?, Decimal?)] = [("每日", update.dailyLimitUSD, original.dailyLimitUSD),
                                                               ("每周", update.weeklyLimitUSD, original.weeklyLimitUSD),
                                                               ("每月", update.monthlyLimitUSD, original.monthlyLimitUSD)]
        return limits.compactMap { title, change, old in
            guard let change else { return nil }
            let new: Decimal? = switch change { case .unlimited: nil; case .amount(let value): value }
            return new == old ? nil : (title, old, new)
        }
    }
}

/// 50 §0.8 reason → fixed words and what the page does (R11: the server's message is never shown). Anything else keeps the
/// catalog's text, including its HTTP fallback.
public struct GroupErrorCopy: Sendable, Equatable {
    public enum Context: Sendable, Equatable { case read, write, members, capacity }
    public enum Action: Sendable, Equatable {
        case show
        /// 409 GROUP_EXISTS: red text under the name field, the sheet stays open.
        case nameField
        /// The group is gone: the detail shows `deleted` and the list drops it; a delete counts as done.
        case treatAsDeleted
        /// Switch to the per-account member fallback (0.4.4).
        case useLegacyMembers
        /// The capacity block shows “—”.
        case showMissing
    }
    public static let deleted = "这个分组已删除"
    public let message: String
    public let action: Action
    /// The page logs the reason (never the message): wrong member or capacity parameters the App should not have sent.
    public let logs: Bool

    public static func resolve(_ error: APIError, context: Context) -> GroupErrorCopy {
        let reason = error.reason ?? ""
        if context == .capacity {
            return GroupErrorCopy(message: DisplayFormat.missing, action: .showMissing,
                                  logs: error.statusCode == 400 && capacityParameterReasons.contains(reason))
        }
        if error.statusCode == 404, deletedReasons.contains(reason) { return GroupErrorCopy(message: deleted, action: .treatAsDeleted, logs: false) }
        let expected = [409: ["GROUP_EXISTS", "GROUP_NOT_EMPTY"], 400: ["SIMPLE_MODE_GROUP_NOT_BINDABLE"] + memberParameterReasons,
                        403: ["SIMPLE_MODE_OPERATION_UNSUPPORTED", "FORBIDDEN"], 500: ["GROUP_REPOSITORY_UNSUPPORTED"]]
        if let status = error.statusCode, expected[status]?.contains(reason) == true, let copy = entry(reason, context: context) { return copy }
        return GroupErrorCopy(message: error.localizedDescription, action: .show, logs: false)
    }
    /// KeyedWriteFailure and other local errors keep their own description.
    public static func message(for error: any Error, context: Context) -> String {
        if let error = error as? APIError { return resolve(error, context: context).message }
        return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
    /// The same table by reason alone, for per-item results that carry no HTTP status; nil when the table has no row.
    public static func reasonText(_ reason: String, context: Context) -> String? {
        if context == .capacity { return capacityParameterReasons.contains(reason) ? DisplayFormat.missing : nil }
        if deletedReasons.contains(reason) { return deleted }
        return entry(reason, context: context)?.message
    }

    private static let deletedReasons: Set = ["GROUP_NOT_FOUND", "RESOURCE_NOT_FOUND"]
    private static let memberParameterReasons = ["EMPTY_MEMBER_CHANGE", "TOO_MANY_ACCOUNTS", "ACCOUNT_IN_BOTH_LISTS", "INVALID_ACCOUNT_ID", "INVALID_GROUP_ID"]
    private static let capacityParameterReasons: Set = ["INVALID_GROUP_ID", "TOO_MANY_IDS"]
    private static func entry(_ reason: String, context: Context) -> GroupErrorCopy? {
        switch reason {
        case "GROUP_EXISTS": GroupErrorCopy(message: "已有同名分组。", action: .nameField, logs: false)
        case "GROUP_NOT_EMPTY": GroupErrorCopy(message: "分组里还有账号，先移出成员再删除。", action: .show, logs: false)
        case "SIMPLE_MODE_GROUP_NOT_BINDABLE": GroupErrorCopy(message: "简易模式下不能给组合分组添加账号。", action: .show, logs: false)
        case "SIMPLE_MODE_OPERATION_UNSUPPORTED": GroupErrorCopy(message: "简易模式下不支持此操作。", action: .show, logs: false)
        case "FORBIDDEN": GroupErrorCopy(message: "你的工作区没有这个权限。", action: .show, logs: false)
        case _ where context == .members && memberParameterReasons.contains(reason):
            GroupErrorCopy(message: "提交的成员有误，请重试。", action: .show, logs: true)
        case "GROUP_REPOSITORY_UNSUPPORTED" where context == .members:
            GroupErrorCopy(message: "服务器暂不支持批量调整成员。", action: .useLegacyMembers, logs: false)
        default: nil
        }
    }
}
