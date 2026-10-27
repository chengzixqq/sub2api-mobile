import Foundation

/// 30 §2.3 壹 · API Key: the summary line under the section title. `groups` and `idle` are the second line's first two pieces.
public struct UserKeySummary: Sendable, Equatable {
    /// “3 个 · 活跃 2”, “0 个”.
    public let meta: String
    /// The names joined with “、”, or “还没有 Key”.
    public let title: String
    /// Distinct group names in key order; a key without a group is “未绑定分组”.
    public let groups: [String]
    /// Keys that cannot call: “脚本 已停用”.
    public let idle: [String]
    /// “最近使用 3 分钟前” or “未使用”.
    public let lastUse: String
    /// Without keys, what to do about it; nil otherwise.
    public let emptyNote: String?

    /// The second line: groups, idle keys and the latest use, “ · ” between the pieces and “、” inside them.
    public var detail: String {
        if let emptyNote { return emptyNote }
        return [groups.joined(separator: "、"), idle.joined(separator: "、"), lastUse].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    public var spokenLabel: String { "API Key \(meta)，\(title)，\(detail)" }
}

/// 30 §2.3 叁 · 档案: one label and value.
public struct UserProfileRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String
    public let value: String
}

/// 30 §2.4 the ⋯ menu, top to bottom; the delete item is red and last.
public enum UserDetailMenuItem: Sendable, Hashable {
    case edit
    case setStatus(enable: Bool)
    case compensation
    case delete

    public var title: String {
        switch self {
        case .edit: "编辑用户"
        case .setStatus(let enable): enable ? "启用用户" : "禁用用户"
        case .compensation: "发放兑换码（补偿）…"
        case .delete: "删除用户…"
        }
    }
    public var isDestructive: Bool { self == .delete }
}

/// How an enable or disable that did not go through is told (30 §2.5), and whether the profile is read again to show the
/// server's state.
public struct UserStatusFailure: Sendable, Equatable {
    public let text: String
    public let readsBack: Bool
    public init(text: String, readsBack: Bool) { self.text = text; self.readsBack = readsBack }
}

/// 30 §2.3–§2.5 the user detail's wording and decisions; the page only draws them.
public enum UserDetailPresentation {
    public static let ledgerPeekSize = 5
    /// 30 §2.6: the profile and today's spend while the page is shown in the foreground.
    public static let liveRefreshInterval: TimeInterval = 60
    public static let loadingTitle = "用户详情"
    public static let loadFailed = "加载用户失败"
    public static let notFound = "这个用户不存在或已删除"
    public static let balanceLabel = "可用余额"
    public static let topUpTitle = "＋ 充值"
    public static let refundTitle = "退款"
    public static let disabledTitle = "已禁用"
    public static let disabledDetail = "不能登录，名下的 Key 也不能调用"
    public static let enableTitle = "启用"
    public static let keysTitle = "API Key"
    public static let ledgerTitle = "充值与调整记录"
    public static let profileTitle = "档案"
    public static let logsTitle = "使用记录"
    public static let logsDetail = "用量明细 · 错误请求"
    public static let keysFootnote = "换分组、速率限制、平台限额都在“编辑用户 · Key 与限额”，立即生效。"
    public static let noRecords = "暂无记录"
    static let unconfirmed = "结果未确认，已刷新为服务器当前状态"
    static let serverFailed = "操作失败：服务器未能完成请求"

    // MARK: 余额头部

    /// “今日消费 $2.80 · 本月 $86.10”; today unknown reads “今日消费 —”, month unknown leaves “ · 本月 …” out.
    public static func balanceSubline(today: Decimal?, month: Decimal?) -> String {
        "今日消费 " + DisplayFormat.money(today) + (month.map { " · 本月 " + DisplayFormat.money($0) } ?? "")
    }
    public static func balanceSpoken(balance: Decimal, today: Decimal?, month: Decimal?, isLow: Bool) -> String {
        var parts = [balanceLabel + " " + DisplayFormat.money(balance), "今日消费 " + DisplayFormat.spoken(DisplayFormat.money(today))]
        if let month { parts.append("本月 " + DisplayFormat.money(month)) }
        if isLow { parts.append(UserListMark.lowBalance.label) }
        return parts.joined(separator: "，")
    }

    // MARK: 壹 · API Key

    /// `now` is the server-corrected clock; `groupNames` comes from the session's group directory (X11).
    public static func keySummary(_ keys: [AdminAPIKey], groupNames: [Int: String], now: Date, timeZone: TimeZone, simpleMode: Bool,
                                  canManageKeys: Bool) -> UserKeySummary {
        let statuses = keys.map { $0.status(now: now) }
        let meta = AdminAPIKeyStatus.sectionMeta(statuses, simpleMode: simpleMode)
        guard !keys.isEmpty else {
            return UserKeySummary(meta: meta, title: "还没有 Key", groups: [], idle: [], lastUse: "未使用",
                                  emptyNote: canManageKeys ? "可以在编辑用户里新建" : "用户在 Web 端创建 Key 后显示在这里")
        }
        var groups: [String] = []
        for key in keys {
            let name = groupName(key.groupID, names: groupNames)
            if !groups.contains(name) { groups.append(name) }
        }
        let idle = zip(keys, statuses).filter { !$0.1.countsAsActive(simpleMode: simpleMode) }.map { "\($0.0.displayName) \($0.1.title)" }
        let latest = keys.compactMap(\.lastUsedAt).max()
        let lastUse = latest.map { "最近使用 " + DisplayFormat.relativeTime($0, now: now, timeZone: timeZone) } ?? "未使用"
        return UserKeySummary(meta: meta, title: keys.map(\.displayName).joined(separator: "、"), groups: groups, idle: idle, lastUse: lastUse,
                              emptyNote: nil)
    }
    private static func groupName(_ id: Int?, names: [Int: String]) -> String {
        guard let id, id > 0 else { return "未绑定分组" }
        return names[id] ?? "分组 #\(id)"
    }

    // MARK: 贰 · 充值与调整记录

    /// “总充值 $60.00” from balance-history (not users.total_recharged); no meta without records.
    public static func ledgerMeta(_ page: BalanceHistoryPage) -> String? {
        page.items.isEmpty ? nil : UserLedger.rechargedText(page.totalRecharged)
    }
    /// “全部 N 条” only when there are more than the five shown.
    public static func ledgerMoreText(total: Int) -> String? {
        total > ledgerPeekSize ? "全部 \(DisplayFormat.grouped(total)) 条" : nil
    }
    public static func ledgerPeek(_ page: BalanceHistoryPage) -> [BalanceHistoryItem] { Array(page.items.prefix(ledgerPeekSize)) }

    // MARK: 叁 · 档案

    /// 用户 ID, 状态, 角色 (with “ · 你” for the signed-in administrator), 并发上限 (0 is “不限制”).
    public static func profileRows(_ user: AdminUser, isSelf: Bool) -> [UserProfileRow] {
        let role = UserPresentation.roleWord(user.role) + (isSelf ? " · 你" : "")
        let concurrency = user.concurrency.map { $0 == 0 ? "不限制" : DisplayFormat.grouped($0) } ?? DisplayFormat.missing
        return [UserProfileRow(id: "id", label: "用户 ID", value: String(user.id)),
                UserProfileRow(id: "status", label: "状态", value: UserPresentation.statusWord(user.status)),
                UserProfileRow(id: "role", label: "角色", value: role),
                UserProfileRow(id: "concurrency", label: "并发上限", value: concurrency)]
    }
    /// 30 §0.1: the same id as `/admin/me`'s user (S3D1-14); unknown is never self.
    public static func isSelf(_ user: AdminUser, meID: Int?) -> Bool { meID == user.id }

    // MARK: ⋯ 菜单

    /// Administrators cannot be disabled or deleted (the server answers 500 without a reason), so those items are left out.
    public static func menuItems(for user: AdminUser) -> [UserDetailMenuItem] {
        guard user.role != AdminUserRole.admin.rawValue else { return [.edit, .compensation] }
        return [.edit, .setStatus(enable: user.status == "disabled"), .compensation, .delete]
    }
    public static func menuNote(for user: AdminUser, isSelf: Bool) -> String? {
        if isSelf { return "这是你当前登录的账号。管理员不能禁用或删除。" }
        return user.role == AdminUserRole.admin.rawValue ? "管理员不能禁用或删除。" : nil
    }

    // MARK: 启用 / 禁用

    /// “已禁用 王小明 · 2 个 Key 停止调用” (the count left out when 0 or unknown), “已启用 王小明”.
    public static func statusReceipt(displayName: String, disabling: Bool, activeKeyCount: Int?) -> String {
        guard disabling else { return "已启用 \(displayName)" }
        guard let count = activeKeyCount, count > 0 else { return "已禁用 \(displayName)" }
        return "已禁用 \(displayName) · \(DisplayFormat.grouped(count)) 个 Key 停止调用"
    }
    /// Never the server's message (00 §3.4). A result that may have run, a 500 without a reason and anything else the server
    /// answered read the profile back; a read-only token and a refusal made here changed nothing.
    public static func statusFailure(_ error: any Error) -> UserStatusFailure {
        if let failure = error as? KeyedWriteFailure {
            guard case .needsNewKey = failure.disposition else { return UserStatusFailure(text: unconfirmed, readsBack: true) }
            return UserStatusFailure(text: failure.localizedDescription, readsBack: true)
        }
        guard let error = error as? APIError else { return UserStatusFailure(text: unconfirmed, readsBack: true) }
        if error.kind == .readOnly || error.reason == "ACCESS_TOKEN_READ_ONLY" {
            return UserStatusFailure(text: error.localizedDescription, readsBack: false)
        }
        if error.kind == .transport { return UserStatusFailure(text: unconfirmed, readsBack: true) }
        guard let status = error.statusCode else { return UserStatusFailure(text: error.localizedDescription, readsBack: false) }
        if (500..<600).contains(status), error.reason == nil { return UserStatusFailure(text: serverFailed, readsBack: true) }
        return UserStatusFailure(text: error.localizedDescription, readsBack: true)
    }

    // MARK: 删除用户（S3-11 也用）

    /// The server deletes the user's keys with it; an unknown count still says so.
    public static func deleteConsequences(keyCount: Int?) -> [String] {
        guard let keyCount else { return ["名下的 Key 会一并删除。"] }
        return keyCount > 0 ? ["名下 \(DisplayFormat.grouped(keyCount)) 个 Key 一并删除。"] : []
    }
    /// The whole display name; the whole email when the username is blank.
    public static func deleteExpectedText(_ user: AdminUser) -> String {
        let name = user.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? user.email : user.displayName
    }
    public static func deleteSiteLine(siteName: String) -> String { "站点 \(siteName)" }
}

extension AdminMe {
    /// `server.run_mode == simple` (S3D1-21): expired and quota-exhausted keys still call and RPM is not counted.
    public var isSimpleRunMode: Bool { server.runMode?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "simple" }
}
