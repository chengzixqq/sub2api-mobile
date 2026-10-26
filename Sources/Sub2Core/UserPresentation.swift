import Foundation

/// The one mark a user row shows (30 §1.3), by priority: 待核对 > 禁用 > 余额低. The page draws a different shape for each.
public enum UserListMark: Sendable, Equatable, CaseIterable {
    case pending, disabled, lowBalance
    public var label: String {
        switch self {
        case .pending: "待核对"
        case .disabled: "禁用"
        case .lowBalance: "余额低"
        }
    }
}

/// settings/public's global low-balance reminder; `off` while it is unknown (an old server or not read yet).
public struct UserLowBalanceGlobal: Sendable, Equatable {
    public let enabled: Bool
    public let threshold: Decimal?
    public static let off = UserLowBalanceGlobal(enabled: false, threshold: nil)
    public init(enabled: Bool, threshold: Decimal?) { self.enabled = enabled; self.threshold = threshold }
    public init(settings: PublicSettings) {
        self.init(enabled: settings.balanceLowNotifyEnabled ?? false, threshold: settings.balanceLowNotifyThreshold)
    }
}

/// 30 §0.3 and §1.3: names, words and the low-balance rule shared by the list, the detail header and the quick top-up strip.
public enum UserPresentation {
    public static func displayName(_ user: AdminUser) -> String { user.displayName }
    /// The trimmed username, otherwise the part of the email before “@”.
    public static func displayName(username: String?, email: String) -> String {
        if let name = username?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty { return name }
        return String(email.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false).first ?? Substring(email))
    }
    /// The avatar letter: the first character, upper-cased when it is a letter; “?” for an empty name.
    public static func initial(_ displayName: String) -> String { displayName.first.map { $0.uppercased() } ?? "?" }

    /// The threshold `quick-topup` compares with (admin_quick_topup_repo.go): the user's own threshold even while the global
    /// reminder is off, otherwise the global one only while it is on and above 0. A percentage is of `total_recharged` only
    /// when that is above 0; otherwise the number is dollars, as on the server (U26). A user threshold of 0 never falls back.
    public static func lowBalanceThreshold(user: AdminUser, global: UserLowBalanceGlobal) -> Decimal? {
        let globalBase = global.enabled ? global.threshold.flatMap { $0 > 0 ? $0 : nil } : nil
        guard let base = user.balanceNotifyThreshold ?? globalBase else { return nil }
        if user.balanceNotifyThresholdType == "percentage", let recharged = user.totalRecharged, recharged > 0 { return recharged * base / 100 }
        return base
    }
    /// Only active users; a balance below a positive threshold. Never the design's fixed $10.
    public static func isLowBalance(user: AdminUser, global: UserLowBalanceGlobal) -> Bool {
        guard user.status == "active", let threshold = lowBalanceThreshold(user: user, global: global) else { return false }
        return threshold > 0 && user.balance < threshold
    }
    public static func listMark(user: AdminUser, hasPendingBalance: Bool, global: UserLowBalanceGlobal) -> UserListMark? {
        if hasPendingBalance { return .pending }
        if user.status == "disabled" { return .disabled }
        return isLowBalance(user: user, global: global) ? .lowBalance : nil
    }

    /// “启用 / 禁用”, never “正常 / 停用”; an unknown status is shown as sent.
    public static func statusWord(_ status: String) -> String {
        switch status {
        case "active": "启用"
        case "disabled": "禁用"
        case "": DisplayFormat.missing
        default: status
        }
    }
    /// “用户 / 供应商 / 管理员”; an unknown role is shown as sent.
    public static func roleWord(_ role: String?) -> String {
        guard let role, !role.isEmpty else { return DisplayFormat.missing }
        return AdminUserRole(rawValue: role)?.title ?? role
    }
}
