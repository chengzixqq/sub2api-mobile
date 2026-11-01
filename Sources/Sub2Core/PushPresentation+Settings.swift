import Foundation

// 60 §7.3–§7.5 (S6-24): the push settings page's rules beyond PushPresentation.swift — which local controls are usable, the
// whole-object subscription edits, the quiet-hour pickers' clock, the scope choices and how a failed test or write reads.

extension PushPresentation {
    public static let localSectionTitle = "本机"
    public static let contentSectionTitle = "推送内容"
    public static let otherTargetsTitle = "其他接收方式"
    public static let apnsSectionTitle = "站点 APNs 配置"
    public static let localToggleTitle = "在本机接收推送"
    public static let severityRowTitle = "告警级别"
    public static let platformScopeTitle = "平台范围"
    public static let groupScopeTitle = "分组范围"
    public static let quietHoursTitle = "免打扰"
    public static let quietStartTitle = "开始"
    public static let quietEndTitle = "结束"
    public static let allPlatformsOption = "全部平台"
    public static let allGroupsOption = "全部分组"
    public static let platformLimitNote = "最多选 \(PushSubscription.maxPlatforms) 个平台"
    public static let groupLimitNote = "最多选 \(PushSubscription.maxGroupIDs) 个分组"
    public static let targetObjectNoun = "接收方式"
    public static let deleteTargetRow = "删除接收方式…"
    public static let deleteTargetConsequence = "这个地址不再收到推送，要恢复需重新添加。"
    /// 60 §7.4: this phone's target is turned off with the switch, not deleted here.
    public static let localTargetDeleteHint = "本机用推送通知页的“在本机接收推送”开关关闭"
    public static let targetGone = "这个接收方式已不存在"
    public static let deleteUnconfirmed = "删除结果未确认，请刷新核对后再操作"
    public static let refreshFailed = "刷新失败 · 重试"

    public static func deleteFailed(reason: String) -> String { "删除没有成功：" + reason }
    public static func subscriptionNotSaved(reason: String) -> String { "推送内容没有保存：" + reason }
    /// INVALID_PUSH_SUBSCRIPTION's `metadata.field` as the control it belongs to; nil for `body` and anything else.
    public static func subscriptionFieldTitle(_ field: String?) -> String? {
        switch field {
        case "events": "推送事件"
        case "min_severity": severityRowTitle
        case "group_ids": groupScopeTitle
        case "platforms": platformScopeTitle
        case "quiet_hours": quietHoursTitle
        default: nil
        }
    }
}

/// 60 §7.3 本机 and §7.5. A switch turned on stays usable to turn off after the site's APNs stops being ready; a failed list
/// greys everything, as does a switch or test already running.
public struct PushLocalControls: Sendable, Equatable {
    public let toggleEnabled: Bool
    /// “站点配好 APNs 后才能打开” while the switch is greyed for that reason.
    public let toggleNote: String?
    public let testEnabled: Bool
    /// 推送内容 edits this phone's target, so it needs one.
    public let showsSubscription: Bool

    public init(state: PushLocalState, config: PushAPNsConfig?, configPending: Bool, listFailed: Bool, isBusy: Bool) {
        let blockedByAPNs = state != .on && !PushPresentation.canEnableLocal(config)
        toggleEnabled = !listFailed && !configPending && !isBusy && !blockedByAPNs
        toggleNote = blockedByAPNs ? PushPresentation.localToggleNeedsAPNs : nil
        testEnabled = !listFailed && !isBusy && state.canSendTest
        showsSubscription = !listFailed && state != .off
    }
}

/// Each control's change as a new whole subscription (PUT replaces it); the input is never changed.
public enum PushSubscriptionEdit {
    /// The window a first switch-on gets (00 §7.3's example).
    public static let defaultQuietHours = PushQuietHours(startMinute: 23 * 60, endMinute: 7 * 60)!

    public static func setting(_ event: PushEvent, on: Bool, in subscription: PushSubscription) -> PushSubscription {
        var next = subscription
        let chosen = on ? Set(subscription.events).union([event]) : Set(subscription.events).subtracting([event])
        next.events = PushEvent.allCases.filter(chosen.contains)
        return next
    }
    public static func setting(minSeverity: PushSeverity, in subscription: PushSubscription) -> PushSubscription {
        var next = subscription
        next.minSeverity = minSeverity
        return next
    }
    public static func setting(platforms: [String], in subscription: PushSubscription) -> PushSubscription {
        var next = subscription
        next.platforms = platforms
        return next
    }
    public static func setting(groupIDs: [Int], in subscription: PushSubscription) -> PushSubscription {
        var next = subscription
        next.groupIDs = groupIDs
        return next
    }
    /// On keeps a window already set; off is `quiet_hours: null`.
    public static func setting(quietHours on: Bool, in subscription: PushSubscription) -> PushSubscription {
        var next = subscription
        next.quietHours = on ? subscription.quietHours ?? defaultQuietHours : nil
        return next
    }
    /// A minute outside the day changes nothing.
    public static func setting(quietStart minute: Int, in subscription: PushSubscription) -> PushSubscription {
        let end = (subscription.quietHours ?? defaultQuietHours).endMinute
        return window(PushQuietHours(startMinute: minute, endMinute: end), in: subscription)
    }
    public static func setting(quietEnd minute: Int, in subscription: PushSubscription) -> PushSubscription {
        let start = (subscription.quietHours ?? defaultQuietHours).startMinute
        return window(PushQuietHours(startMinute: start, endMinute: minute), in: subscription)
    }

    private static func window(_ quietHours: PushQuietHours?, in subscription: PushSubscription) -> PushSubscription {
        guard let quietHours else { return subscription }
        var next = subscription
        next.quietHours = quietHours
        return next
    }
}

/// The quiet-hour pickers show a wall clock: their dates are minutes of 2001-01-01 in GMT, so the device's zone never shifts
/// them. `DatePicker` gets `.environment(\.timeZone, PushQuietClock.timeZone)`.
public enum PushQuietClock {
    public static let timeZone = TimeZone(secondsFromGMT: 0)!

    /// Clamped to the day.
    public static func date(minuteOfDay minute: Int) -> Date {
        let clamped = min(max(minute, 0), PushQuietHours.minutesPerDay - 1)
        return Date(timeIntervalSinceReferenceDate: TimeInterval(clamped * 60))
    }
    public static func minuteOfDay(_ date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

/// One row of the platform or group scope picker.
public struct PushScopeOption<ID: Hashable & Sendable>: Identifiable, Sendable, Equatable {
    public let id: ID
    public let title: String
    public init(id: ID, title: String) { self.id = id; self.title = title }
}

/// The scope pickers' rows: the catalog's or directory's order, then what is chosen but no longer listed, so it can be
/// seen and cleared.
public enum PushScopeOptions {
    public static func platforms(catalog: MetaCatalog, selected: [String]) -> [PushScopeOption<String>] {
        let listed = catalog.platforms.map { PushScopeOption(id: $0.id, title: AccountNaming.platformName($0.id, catalog: catalog)) }
        let known = Set(listed.map(\.id))
        let extra = unique(selected.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty && !known.contains($0) })
        return listed + extra.map { PushScopeOption(id: $0, title: AccountNaming.platformName($0, catalog: catalog)) }
    }
    public static func groups(_ groups: [AdminGroup], selected: [Int]) -> [PushScopeOption<Int>] {
        let listed = groups.map { PushScopeOption(id: $0.id, title: $0.name) }
        let known = Set(listed.map(\.id))
        return listed + unique(selected.filter { !known.contains($0) }).map { PushScopeOption(id: $0, title: "分组 #\($0)") }
    }
    /// Chosen → removed; a new one past `limit` → nil (the picker shows the limit); otherwise appended.
    public static func toggling<ID: Hashable>(_ id: ID, in selection: [ID], limit: Int) -> [ID]? {
        if selection.contains(id) { return selection.filter { $0 != id } }
        return selection.count < limit ? selection + [id] : nil
    }

    private static func unique<Value: Hashable>(_ values: [Value]) -> [Value] {
        var seen = Set<Value>()
        return values.filter { seen.insert($0).inserted }
    }
}

/// 60 §7.4 发送测试推送. Never resent (R06).
public enum PushTestOutcome: Equatable, Sendable {
    case sent
    /// 503 PUSH_NOT_CONFIGURED or 502 PUSH_DELIVERY_FAILED: the list is read again, the target may have been stopped.
    case refused(String)
    /// 404 PUSH_DEVICE_NOT_FOUND.
    case gone
    case failed(String)
    case cancelled

    public static func classify(_ error: any Error) -> PushTestOutcome {
        if error is CancellationError { return .cancelled }
        guard let api = error as? APIError else { return .failed(error.localizedDescription) }
        if api.securityOutcome == .cancelled { return .cancelled }
        if PushWriteFailure.isGone(api) { return .gone }
        switch (api.statusCode, api.reason) {
        case (503?, "PUSH_NOT_CONFIGURED"?), (502?, "PUSH_DELIVERY_FAILED"?): return .refused(PushPresentation.failureMessage(api))
        default: return .failed(PushPresentation.failureMessage(api))
        }
    }
}

/// A failed subscription save or target delete, as AnnouncementWriteFailure.
public enum PushWriteFailure: Equatable, Sendable {
    /// 404 PUSH_DEVICE_NOT_FOUND (also another administrator's target).
    case gone
    /// Lost connection, an unreadable reply, 502 / 504 or a 503 without its own reason: it may have happened.
    case unconfirmed
    /// Compliance or step-up cleared it; the notice.
    case reconfirm(String)
    case cancelled
    case rejected(String)

    public static let notFoundReason = "PUSH_DEVICE_NOT_FOUND"
    static let invalidSubscriptionReason = "INVALID_PUSH_SUBSCRIPTION"

    public static func isGone(_ error: any Error) -> Bool {
        guard let api = error as? APIError else { return false }
        return api.statusCode == 404 && api.reason == notFoundReason
    }
    public static func classify(_ error: any Error) -> PushWriteFailure {
        if error is CancellationError { return .cancelled }
        guard let api = error as? APIError else { return .rejected(error.localizedDescription) }
        switch api.securityOutcome {
        case .passed?: return .reconfirm(api.localizedDescription)
        case .cancelled?: return .cancelled
        case .blocked?, nil: break
        }
        if isGone(api) { return .gone }
        // A refresh that failed before sending was never sent.
        guard api != .refreshDeferred else { return .rejected(api.localizedDescription) }
        guard let status = api.statusCode else { return api.kind == .transport || api == .invalidResponse ? .unconfirmed : .rejected(api.localizedDescription) }
        if RequestPolicy.isRetryableStatus(status, marker: api.reason) { return .unconfirmed }
        if status == 400, api.reason == invalidSubscriptionReason, let control = PushPresentation.subscriptionFieldTitle(api.metadata["field"]) {
            return .rejected(control + "的值不被站点接受")
        }
        return .rejected(PushPresentation.failureMessage(api))
    }
}
