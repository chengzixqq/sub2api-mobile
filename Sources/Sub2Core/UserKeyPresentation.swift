import Foundation

/// 30 §7 (S3-12): the user's grant as the key cards read it, the edit page's base (S3D1-13). Rates are the user's own.
public struct UserKeyAccess: Sendable, Equatable {
    public var allowedGroups: Set<Int>
    public var restrictPublicGroups: Bool
    public var groupRates: [Int: Decimal]
    public init(allowedGroups: Set<Int> = [], restrictPublicGroups: Bool = false, groupRates: [Int: Decimal] = [:]) {
        self.allowedGroups = allowedGroups; self.restrictPublicGroups = restrictPublicGroups; self.groupRates = groupRates
    }
    public init(baseline: UserBaseline) {
        self.init(allowedGroups: baseline.allowedGroups, restrictPublicGroups: baseline.restrictPublicGroups, groupRates: baseline.groupRates)
    }
}

/// A key's spend today: unavailable when api-keys-usage failed or a read-only token never asked for it (R14).
public enum UserKeyTodayCost: Sendable, Equatable { case value(Decimal), unavailable }

/// The collapsed card's usage line (30 §7.3).
public struct UserKeyUsageLine: Sendable, Equatable {
    /// “$12.30 / $50.00”, or “今日 $2.80” without a quota.
    public let text: String
    /// “24.6%”, or “不限额度”.
    public let trailing: String
    /// 0…1 with a quota; nil without one.
    public let progress: Double?
    /// caution from 75%, critical from 90%; nil below and without a quota.
    public let tone: Tone?
}

/// One cell of 速率限制 (30 §7.3).
public struct UserKeyRateWindow: Sendable, Equatable, Identifiable {
    public enum Span: String, Sendable, CaseIterable {
        case fiveHours = "5h", oneDay = "1d", sevenDays = "7d"
        public var title: String {
            switch self { case .fiveHours: "5 小时"; case .oneDay: "1 天"; case .sevenDays: "7 天" }
        }
    }
    public let span: Span
    /// “42.0%”, or “不限” without a limit.
    public let headline: String
    /// “$2.10 / $5”, or “已用 $0.00”.
    public let reading: String
    public let progress: Double?
    public let tone: Tone?
    /// “11:20 重置”: only with a limit and a window that has started.
    public let resetText: String?
    public var id: Span { span }
}

public enum UserKeyRateLimits: Sendable, Equatable {
    /// No window has a limit or any use: one line instead of three empty cells.
    case none
    case windows([UserKeyRateWindow])
}

/// One row of 换分组 (30 §7.3); S3-13's new key form offers the same rows.
public struct UserKeyGroupOption: Sendable, Equatable, Identifiable {
    /// nil: 不绑定分组.
    public let groupID: Int?
    public let title: String
    public let subtitle: String
    /// A subscription group without the user's active subscription cannot be chosen.
    public let isEnabled: Bool
    public let isCurrent: Bool
    /// An exclusive standard group the user lacks: choosing it grants it too.
    public let grantsAccess: Bool
    public var id: Int { groupID ?? 0 }
}

/// 30 §7.4: one kind of change per PUT, never mixed (the server applies fields, then the reset, then the group).
public enum UserKeyChange: Sendable, Equatable {
    case group(from: Int?, to: Int?)
    case status(AdminAPIKeyUpdateRequest.Status)
    case resetRateLimit

    /// 不绑定分组 sends `group_id` 0.
    public func request() throws -> AdminAPIKeyUpdateRequest {
        switch self {
        case .group(_, let to): try AdminAPIKeyUpdateRequest(groupID: to ?? 0)
        case .status(let status): try AdminAPIKeyUpdateRequest(status: status)
        case .resetRateLimit: try AdminAPIKeyUpdateRequest(resetRateLimitUsage: true)
        }
    }
    /// Named in the leave confirmation's “已经立即生效” (30 §6.4).
    public func operationName(keyName: String) -> String {
        switch self {
        case .group: "Key「\(keyName)」换分组"
        case .status(.inactive): "Key「\(keyName)」停用"
        case .status(.active): "Key「\(keyName)」启用"
        case .resetRateLimit: "Key「\(keyName)」重置速率限制"
        }
    }
}

/// What 撤销 of a group change needs, kept when the change succeeded.
public struct UserKeyGroupUndo: Sendable, Equatable {
    public let keyID: Int
    public let keyName: String
    public let fromGroupID: Int?
    public let toGroupID: Int?
    /// The change granted the target group (UserKeyPresentation.newlyGranted), so 撤销 withdraws it.
    public let newlyGranted: Bool
    public init(keyID: Int, keyName: String, fromGroupID: Int?, toGroupID: Int?, newlyGranted: Bool) {
        self.keyID = keyID; self.keyName = keyName; self.fromGroupID = fromGroupID; self.toGroupID = toGroupID; self.newlyGranted = newlyGranted
    }
    /// Putting the key back, withdrawing nothing.
    public var keyChange: UserKeyChange { .group(from: toGroupID, to: fromGroupID) }
}

public enum UserKeyGroupUndoPlan: Sendable, Equatable {
    /// E04: the key back and the grant withdrawn in one transaction (`revoke_group_access_id`).
    case exact(AdminAPIKeyUpdateRequest)
    case keyOnly(AdminAPIKeyUpdateRequest)
    /// 30 §0.6 without E04: the key back, then the user's allowed_groups without the group.
    case twoStep(AdminAPIKeyUpdateRequest, revokeGroupID: Int)
}

/// What the key segment tells the edit page (S3D1-13): a change took effect or was undone, with the grant it moved.
public enum UserKeyImmediateEvent: Sendable, Equatable {
    case applied(name: String, grantedGroupID: Int?)
    case withdrawn(name: String, revokedGroupID: Int?)
}

/// How a key write failed (30 §7.4, §7.5). Fixed words per reason; the server's message is never shown (00 §3.4).
public enum UserKeyWriteFailure: Sendable, Equatable {
    /// 404 API_KEY_NOT_FOUND: the card leaves.
    case keyGone
    /// 404 GROUP_NOT_FOUND: the group directory is read again.
    case groupGone
    case groupInactive
    case subscriptionRequired
    /// 409 GROUP_STILL_IN_USE: an exact undo was rolled back as a whole.
    case groupStillInUse
    /// Lost connection, an unreadable reply, 502 / 504 or a 503 without its own reason: read back once, never resent (R06).
    case unconfirmed
    /// Catalog text.
    case rejected(String)

    /// nil for a cancelled write or a security prompt the administrator cancelled.
    public init?(_ error: any Error) {
        if error is CancellationError { return nil }
        guard let api = error as? APIError else { self = .rejected(error.localizedDescription); return }
        if api.securityOutcome == .cancelled { return nil }
        switch (api.statusCode, api.reason) {
        case (404?, "API_KEY_NOT_FOUND"?): self = .keyGone
        case (404?, "GROUP_NOT_FOUND"?): self = .groupGone
        case (_, "GROUP_NOT_ACTIVE"?): self = .groupInactive
        case (_, "SUBSCRIPTION_REQUIRED"?): self = .subscriptionRequired
        case (409?, "GROUP_STILL_IN_USE"?): self = .groupStillInUse
        default: self = Self.isUnconfirmed(api) ? .unconfirmed : .rejected(api.localizedDescription)
        }
    }
    public var message: String {
        switch self {
        case .keyGone: "这个 Key 已被删除"
        case .groupGone: "分组不存在"
        case .groupInactive: "这个分组已停用"
        case .subscriptionRequired: "用户没有这个分组的有效订阅"
        case .groupStillInUse: "该分组还有其他 Key 在用，授权没有收回"
        case .unconfirmed: "结果未确认，请刷新核对后再操作"
        case .rejected(let text): text
        }
    }
    /// A refresh that failed before sending was never sent.
    private static func isUnconfirmed(_ api: APIError) -> Bool {
        guard api != .refreshDeferred else { return false }
        guard let status = api.statusCode else { return api.kind == .transport || api == .invalidResponse }
        return RequestPolicy.isRetryableStatus(status, marker: api.reason)
    }
}

/// 30 §7.3–§7.5: the key cards' words and the write plans. `now` is the server-corrected clock, days follow the server's zone.
public enum UserKeyPresentation {
    // MARK: 段落文案

    public static let noticeLead = "这一段立即生效"
    public static let noticeTail = "，不用保存，也不随“放弃更改”撤回"
    public static let notice = noticeLead + noticeTail
    public static let sectionTitle = "API Key"
    public static let footnote = "换分组、停用的回执里可以撤销；重置速率限制、删除不能撤销。"
    public static let emptyTitle = "还没有 Key"
    public static func emptyDetail(adminKeyWrites: Bool) -> String {
        adminKeyWrites ? "可以在这里替用户新建；用户也可以在 Web 端「API 密钥」里自己创建。"
            : "用户在 Web 端「API 密钥」里自己创建；创建后可以在这里换分组、重置速率限制。"
    }
    public static let listFailed = "Key 加载失败"
    public static let refreshFailed = "Key 刷新失败，显示的是上次读取的内容"
    public static let newKey = "新建 Key"
    public static let gapTag = "需后端新增"
    public static let gapDisable = "停用 Key"
    public static let gapDelete = "删除 Key"
    /// Design `keyGap`: E01 is missing, so the placeholders explain instead of acting.
    public static func gapTitle(_ what: String) -> String { "\(what) 需要后端新增接口" }
    public static let gapMessage = "管理员现在只能查看用户的 Key、换分组、重置速率限制。替用户新建、停用、删除 Key 要等后端加上管理接口；这里只是占位，不会执行任何操作。"
    public static let gapDismiss = "知道了"

    // MARK: 卡片

    public static func sectionMeta(_ keys: [AdminAPIKey], now: Date, simpleMode: Bool) -> String {
        AdminAPIKeyStatus.sectionMeta(keys.map { $0.status(now: now) }, simpleMode: simpleMode)
    }
    /// Active keys show none (30 §7.3).
    public static func badge(_ key: AdminAPIKey, now: Date, simpleMode: Bool) -> String? { key.status(now: now).badge(simpleMode: simpleMode) }
    /// Drawn in the secondary colour.
    public static func isIdle(_ key: AdminAPIKey, now: Date, simpleMode: Bool) -> Bool { !key.status(now: now).countsAsActive(simpleMode: simpleMode) }
    /// `key_masked` only; never a plaintext (30 §7.7).
    public static func mask(_ key: AdminAPIKey) -> String {
        guard let mask = key.keyMasked, !mask.isEmpty else { return DisplayFormat.missing }
        return mask
    }
    /// The toggle's spoken label: name, badge, mask.
    public static func spokenHeader(_ key: AdminAPIKey, now: Date, simpleMode: Bool) -> String {
        ([key.displayName, badge(key, now: now, simpleMode: simpleMode), mask(key)] as [String?]).compactMap { $0 }.joined(separator: "，")
    }
    public static func usageLine(_ key: AdminAPIKey, today: UserKeyTodayCost) -> UserKeyUsageLine {
        guard key.quota > 0 else {
            let spent = if case .value(let value) = today { DisplayFormat.money(value) } else { DisplayFormat.missing }
            return UserKeyUsageLine(text: "今日 " + spent, trailing: "不限额度", progress: nil, tone: nil)
        }
        return UserKeyUsageLine(text: DisplayFormat.money(key.quotaUsed) + " / " + DisplayFormat.money(key.quota),
                                trailing: percent(key.quotaUsed, of: key.quota), progress: progress(key.quotaUsed, of: key.quota),
                                tone: meterTone(key.quotaUsed, of: key.quota))
    }
    /// “标准组 · 专属倍率 ×0.9 · 最近使用 3 分钟前”; “不绑定分组 · 未使用”; a group the directory lacks is “分组 #7”, without a rate.
    public static func metaLine(_ key: AdminAPIKey, groups: [AdminGroup], access: UserKeyAccess, now: Date, zone: ServerTimeZone) -> String {
        let lastUse = key.lastUsedAt.map { "最近使用 " + DisplayFormat.relativeTime($0, now: now, timeZone: zone.timeZone) } ?? "未使用"
        guard let id = key.groupID, id > 0 else { return "不绑定分组 · " + lastUse }
        guard let group = groups.first(where: { $0.id == id }) else { return "分组 #\(id) · " + lastUse }
        return [group.name, rateLabel(group, access: access, inSheet: false), lastUse].joined(separator: " · ")
    }
    /// “至 2026-12-31” by the server's day, or “永久有效”.
    public static func expiryText(_ date: Date?, zone: ServerTimeZone) -> String {
        date.map { "至 " + zone.dayString($0) } ?? "永久有效"
    }
    /// Without `api_keys.current_concurrency` the server reports 0 for unknown too, so it reads “—”.
    public static func concurrencyText(_ value: Int?, supported: Bool) -> String {
        guard supported, let value else { return DisplayFormat.missing }
        return DisplayFormat.grouped(value)
    }
    public static func lastIPText(_ ip: String?) -> String {
        let trimmed = ip?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? DisplayFormat.missing : trimmed
    }
    /// “白名单 198.51.100.0/24 · 黑名单 203.0.113.9”, several joined with “、”; “未设置”.
    public static func ipRuleText(whitelist: [String], blacklist: [String]) -> String {
        let parts = [whitelist.isEmpty ? nil : "白名单 " + whitelist.joined(separator: "、"),
                     blacklist.isEmpty ? nil : "黑名单 " + blacklist.joined(separator: "、")].compactMap { $0 }
        return parts.isEmpty ? "未设置" : parts.joined(separator: " · ")
    }

    // MARK: 速率限制

    public static let rateTitle = "速率限制"
    public static let rateCaption = "滚动窗口 · 0 = 不限"
    public static let rateNoneCaption = "未设置"
    public static let rateNoneLine = "5 小时、1 天、7 天都不限额"

    public static func rateLimits(_ key: AdminAPIKey, now: Date, zone: ServerTimeZone) -> UserKeyRateLimits {
        let windows: [(UserKeyRateWindow.Span, Decimal, Decimal, Date?)] = [
            (.fiveHours, key.rateLimit5h, key.usage5h, key.reset5hAt), (.oneDay, key.rateLimit1d, key.usage1d, key.reset1dAt),
            (.sevenDays, key.rateLimit7d, key.usage7d, key.reset7dAt),
        ]
        guard windows.contains(where: { $0.1 > 0 || $0.2 > 0 }) else { return .none }
        return .windows(windows.map { span, limit, used, reset in
            guard limit > 0 else {
                return UserKeyRateWindow(span: span, headline: "不限", reading: "已用 " + DisplayFormat.money(used), progress: nil, tone: nil, resetText: nil)
            }
            return UserKeyRateWindow(span: span, headline: percent(used, of: limit), reading: DisplayFormat.money(used) + " / " + limitText(limit),
                                     progress: progress(used, of: limit), tone: meterTone(used, of: limit),
                                     resetText: resetText(reset, now: now, zone: zone))
        })
    }
    /// “11:20 重置”, “明天 08:02 重置”, “10月28日 08:02 重置” by the server's clock and day (R20); a past or missing time is nil.
    public static func resetText(_ reset: Date?, now: Date, zone: ServerTimeZone) -> String? {
        guard let reset, reset > now else { return nil }
        let calendar = zone.calendar, time = DisplayFormat.clock(reset, timeZone: zone.timeZone)
        if calendar.isDate(reset, inSameDayAs: now) { return time + " 重置" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(reset, inSameDayAs: tomorrow) {
            return "明天 " + time + " 重置"
        }
        let day = calendar.dateComponents([.month, .day], from: reset)
        return "\(day.month ?? 0)月\(day.day ?? 0)日 " + time + " 重置"
    }
    /// 重置速率限制 shows while any window has a limit or any use.
    public static func showsResetAction(_ key: AdminAPIKey) -> Bool {
        [key.rateLimit5h, key.rateLimit1d, key.rateLimit7d, key.usage5h, key.usage1d, key.usage7d].contains { $0 > 0 }
    }

    // MARK: 操作行与 ⋯

    public static let changeGroupAction = "换分组"
    public static let resetAction = "重置速率限制"
    /// ⋯ needs E01; a tombstone never shows.
    public static func showsStatusMenu(_ key: AdminAPIKey, adminKeyWrites: Bool) -> Bool { adminKeyWrites && !key.isTombstone }
    /// The stored status decides (30 §7.3): inactive (and the legacy disabled) offers 启用.
    public static func statusTarget(_ key: AdminAPIKey) -> AdminAPIKeyUpdateRequest.Status {
        ["inactive", "disabled"].contains(key.status) ? .active : .inactive
    }
    public static func statusMenuTitle(_ key: AdminAPIKey) -> String { statusTarget(key) == .active ? "启用 Key" : "停用 Key" }

    // MARK: 换分组 sheet

    public static func groupSheetTitle(keyName: String) -> String { "换分组 · \(keyName)" }
    public static let groupSheetFootnote = "选中即生效；回执里可以撤销。"

    /// 不绑定分组 first, then every active group in sort order (the directory's order).
    public static func groupOptions(groups: [AdminGroup], access: UserKeyAccess, subscriptions: [AdminUserSubscription], currentGroupID: Int?,
                                    now: Date) -> [UserKeyGroupOption] {
        let current = currentGroupID.flatMap { $0 > 0 ? $0 : nil }
        let unbound = UserKeyGroupOption(groupID: nil, title: "不绑定分组", subtitle: "这个 Key 不属于任何分组", isEnabled: true, isCurrent: current == nil,
                                         grantsAccess: false)
        return [unbound] + groups.filter { $0.status == "active" }.map { group in
            option(group, access: access, subscriptions: subscriptions, isCurrent: group.id == current, now: now)
        }
    }
    /// The server's rule (user_subscription_repo.go): active and not yet expired.
    public static func hasActiveSubscription(_ subscriptions: [AdminUserSubscription], groupID: Int, now: Date) -> Bool {
        subscriptions.contains { $0.groupID == groupID && $0.status == "active" && ($0.expiresAt.map { $0 > now } ?? true) }
    }
    /// An active exclusive standard group the base lacks. Never the reply's `auto_granted_group_access`, which is true for
    /// every exclusive standard target, one the user had included (30 §7.4).
    public static func newlyGranted(target: AdminGroup?, access: UserKeyAccess) -> Bool {
        guard let target, isGrantable(target) else { return false }
        return !access.allowedGroups.contains(target.id)
    }

    // MARK: 写与回执

    public static func groupReceipt(keyName: String, targetName: String?, newlyGranted: Bool) -> String {
        guard let targetName else { return "「\(keyName)」已不绑定分组" }
        return newlyGranted ? "已改到「\(targetName)」，并为用户添加了这个分组" : "「\(keyName)」已改到「\(targetName)」"
    }
    /// The target's name in a receipt; one the directory lacks is “分组 #7”.
    public static func groupName(_ id: Int, groups: [AdminGroup]) -> String { groups.first { $0.id == id }?.name ?? "分组 #\(id)" }
    public static func groupUndoPlan(_ undo: UserKeyGroupUndo, exactUndoSupported: Bool) throws -> UserKeyGroupUndoPlan {
        let back = try undo.keyChange.request()
        guard undo.newlyGranted, let granted = undo.toGroupID, granted > 0 else { return .keyOnly(back) }
        guard exactUndoSupported else { return .twoStep(back, revokeGroupID: granted) }
        return .exact(try AdminAPIKeyUpdateRequest(groupID: undo.fromGroupID ?? 0, revokeGroupAccessID: granted))
    }
    /// 撤销 binds the key to its old group, and binding an exclusive standard group grants it (admin_group.go): one the base
    /// no longer has cannot be gone back to without granting it again, so that change offers no 撤销 (as 30 §0.6 replace-group).
    public static func groupUndoAvailable(from: AdminGroup?, access: UserKeyAccess) -> Bool { !newlyGranted(target: from, access: access) }
    /// After 409 GROUP_STILL_IN_USE the whole transaction was rolled back, so the key is put back alone.
    public static let undoKeptGrantReceipt = "Key 已还原；该分组还有其他 Key 在用，授权保留"
    public static let twoStepPartialReceipt = "Key 已还原，但分组授权没收回，请在权限与并发里手动移除"
    /// The fresh allowed_groups without the group; ids the directory does not know stay.
    public static func allowedGroupsAfterRevoke(_ current: [Int]?, revoking id: Int) -> [Int] {
        Set(current ?? []).subtracting([id]).sorted()
    }

    public static func statusReceipt(keyName: String, requested: AdminAPIKeyUpdateRequest.Status, result: AdminAPIKey?, now: Date,
                                     simpleMode: Bool) -> String {
        guard requested == .active else { return "已停用「\(keyName)」" }
        guard stillBlocked(requested: requested, result: result, now: now, simpleMode: simpleMode) else { return "已启用「\(keyName)」" }
        return result?.status(now: now) == .expired ? "已启用，但 Key 已过期，仍不能调用" : "已启用，但 Key 额度已用完，仍不能调用"
    }
    /// Enabling changes only the status (applyAPIKeyUpdate): an expired or used-up key still cannot call, unless run_mode is simple.
    public static func stillBlocked(requested: AdminAPIKeyUpdateRequest.Status, result: AdminAPIKey?, now: Date, simpleMode: Bool) -> Bool {
        guard requested == .active, !simpleMode, let status = result?.status(now: now) else { return false }
        return status == .expired || status == .quotaExhausted
    }
    /// 撤销 writes `previous.status` back, only when it is one the server accepts (the legacy disabled reads as inactive).
    public static func statusUndo(previous: AdminAPIKeyPrevious?) -> AdminAPIKeyUpdateRequest.Status? {
        switch previous?.status {
        case "active": .active
        case "inactive", "disabled": .inactive
        default: nil
        }
    }
    /// An older server ignores `status` and answers 200: the key kept its status.
    public static func statusTook(_ requested: AdminAPIKeyUpdateRequest.Status, in key: AdminAPIKey) -> Bool { key.status == requested.rawValue }
    public static func statusIgnored(_ requested: AdminAPIKeyUpdateRequest.Status) -> String {
        requested == .inactive ? "这个站点还不支持停用 Key" : "这个站点还不支持启用 Key"
    }

    public static func resetConfirmationTitle(keyName: String) -> String { "重置「\(keyName)」的速率限制用量？" }
    public static let resetConfirmationMessage = "5 小时、1 天、7 天三个窗口的已用额度会归零，立即生效，不能撤销。"
    public static let resetConfirm = "重置用量"
    public static let resetReceipt = "速率限制已重置"

    public static func failureReceipt(_ failure: UserKeyWriteFailure, undoing: Bool) -> String {
        undoing ? "撤销没有成功：" + failure.message : failure.message
    }
    /// R06: a reply nobody saw is read back once; true when the key shows the change.
    public static func readBackConfirms(_ change: UserKeyChange, readBack key: AdminAPIKey) -> Bool {
        guard !key.isTombstone else { return false }
        switch change {
        case .group(_, let to): return (key.groupID ?? 0) == (to ?? 0)
        case .status(let status): return key.status == status.rawValue
        case .resetRateLimit: return key.usage5h == 0 && key.usage1d == 0 && key.usage7d == 0
        }
    }

    // MARK: - 内部

    private static func option(_ group: AdminGroup, access: UserKeyAccess, subscriptions: [AdminUserSubscription], isCurrent: Bool,
                               now: Date) -> UserKeyGroupOption {
        let platform = AccountNaming.platformName(group.platform, catalog: nil)
        if group.subscriptionType == "subscription" {
            let has = hasActiveSubscription(subscriptions, groupID: group.id, now: now)
            return UserKeyGroupOption(groupID: group.id, title: group.name, subtitle: platform + (has ? " · 订阅分组 · 有效订阅" : " · 订阅分组 · 需要这个分组的有效订阅"),
                                      isEnabled: has, isCurrent: isCurrent, grantsAccess: false)
        }
        let exclusive = group.isExclusive == true, allowed = access.allowedGroups.contains(group.id)
        let grants = exclusive && !allowed
        let refused = !exclusive && access.restrictPublicGroups && !allowed
        let subtitle = [platform, exclusive ? "专属分组" : "公开分组", rateLabel(group, access: access, inSheet: true)].joined(separator: " · ")
            + (grants ? " · 会同时授予这个分组" : "") + (refused ? " · 用户被限制，调用会被拒绝" : "")
        return UserKeyGroupOption(groupID: group.id, title: group.name, subtitle: subtitle, isEnabled: true, isCurrent: isCurrent, grantsAccess: grants)
    }
    private static func isGrantable(_ group: AdminGroup) -> Bool {
        group.status == "active" && group.isExclusive == true && (group.subscriptionType ?? "standard") == "standard"
    }
    /// “专属倍率 ×1.3” (the user's own), else the group's: “默认 ×0.8” on a card, “默认倍率 ×0.8” in the sheet; the server's
    /// default is 1.
    private static func rateLabel(_ group: AdminGroup, access: UserKeyAccess, inSheet: Bool) -> String {
        if let rate = access.groupRates[group.id] { return "专属倍率 " + UserEditCopy.rateText(rate) }
        return (inSheet ? "默认倍率 " : "默认 ") + UserEditCopy.rateText(group.rateMultiplier ?? 1)
    }
    /// A whole limit has no decimals (“$5”), any other two (“$7.50”).
    private static func limitText(_ value: Decimal) -> String {
        DisplayFormat.money(value, digits: DisplayFormat.rounded(value, digits: 0) == value ? 0 : 2)
    }
    private static func percent(_ used: Decimal, of limit: Decimal) -> String {
        DisplayFormat.percent(NSDecimalNumber(decimal: used * 100 / limit).doubleValue)
    }
    private static func progress(_ used: Decimal, of limit: Decimal) -> Double {
        min(max(NSDecimalNumber(decimal: used / limit).doubleValue, 0), 1)
    }
    /// Design `UeMeter`: caution from 75%, critical from 90%.
    private static func meterTone(_ used: Decimal, of limit: Decimal) -> Tone? {
        let ratio = used / limit
        if ratio >= Decimal(string: "0.9")! { return .critical }
        return ratio >= Decimal(string: "0.75")! ? .caution : nil
    }
}
