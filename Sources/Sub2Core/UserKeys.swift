import Foundation

/// 30 §7.3 (R13): the one Key status, shared by the user's Key cards and the group's API key page (50 §6). Only the key itself
/// counts: a disabled user or group is told elsewhere.
public enum AdminAPIKeyStatus: String, CaseIterable, Sendable {
    case active, inactive
    case quotaExhausted = "quota_exhausted"
    case expired

    /// `effective_status` when it is one of the four known values; missing, empty or unknown values derive locally.
    /// `now` is the caller's server-corrected clock.
    public static func resolve(effectiveStatus: String?, status: String, expiresAt: Date?, quota: Decimal, quotaUsed: Decimal,
                               now: Date) -> AdminAPIKeyStatus {
        if let effectiveStatus, let known = AdminAPIKeyStatus(rawValue: effectiveStatus) { return known }
        return derive(status: status, expiresAt: expiresAt, quota: quota, quotaUsed: quotaUsed, now: now)
    }

    /// Backend `EffectiveStatusAt`: any stored status other than active / quota_exhausted / expired (the legacy disabled
    /// included) is inactive; a stored quota_exhausted / expired stays; then a passed expiry; then a used-up quota (0 = unlimited).
    public static func derive(status: String, expiresAt: Date?, quota: Decimal, quotaUsed: Decimal, now: Date) -> AdminAPIKeyStatus {
        switch status {
        case AdminAPIKeyStatus.active.rawValue: break
        case AdminAPIKeyStatus.quotaExhausted.rawValue: return .quotaExhausted
        case AdminAPIKeyStatus.expired.rawValue: return .expired
        default: return .inactive
        }
        if let expiresAt, now > expiresAt { return .expired }
        if quota > 0, quotaUsed >= quota { return .quotaExhausted }
        return .active
    }

    public var title: String {
        switch self {
        case .active: "活跃"
        case .inactive: "已停用"
        case .quotaExhausted: "额度耗尽"
        case .expired: "已过期"
        }
    }

    /// The card header badge; active keys show none. With `run_mode == simple` the gateway skips expiry and quota checks.
    public func badge(simpleMode: Bool) -> String? {
        switch self {
        case .active: nil
        case .inactive: title
        case .quotaExhausted, .expired: simpleMode ? title + " · 仍可调用" : title
        }
    }

    /// Does not follow the run mode; a page may still dim a card by `countsAsActive`.
    public var tone: Tone {
        switch self {
        case .active: .ok
        case .quotaExhausted: .caution
        case .inactive, .expired: .neutral
        }
    }

    public func countsAsActive(simpleMode: Bool) -> Bool {
        switch self {
        case .active: true
        case .inactive: false
        case .quotaExhausted, .expired: simpleMode
        }
    }

    /// Section header meta: "3 个 · 活跃 2", "0 个" without keys.
    public static func sectionMeta(_ statuses: [AdminAPIKeyStatus], simpleMode: Bool) -> String {
        let total = DisplayFormat.grouped(statuses.count) + " 个"
        guard !statuses.isEmpty else { return total }
        return total + " · 活跃 " + DisplayFormat.grouped(statuses.filter { $0.countsAsActive(simpleMode: simpleMode) }.count)
    }
}
