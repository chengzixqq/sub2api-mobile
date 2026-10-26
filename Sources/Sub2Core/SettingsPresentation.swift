import Foundation

/// 60 §3.3: what the settings page shows, apart from the views. Sign-in wording comes from AuthPresentation (D10), pending
/// rows from PendingMoneyWriteLine (D16), numbers and times from DisplayFormat (R10).
public enum SettingsPresentation {
    /// In page order; the numbers 壹… count only the sections shown.
    public enum Section: String, CaseIterable, Sendable {
        case interface, appearance, security, notifications, sites, currentSite, pending, about
        public var title: String {
            switch self {
            case .interface: "界面模式"
            case .appearance: "外观"
            case .security: "安全"
            case .notifications: "通知"
            case .sites: "站点"
            case .currentSite: "当前站点"
            case .pending: "待核对"
            case .about: "关于"
            }
        }
    }
    public struct NumberedSection: Equatable, Sendable, Identifiable {
        public let section: Section
        public let ordinal: String
        public var id: Section { section }
    }
    /// 通知 needs `push.notifications` outside a workspace, 当前站点 a connected site, 待核对 a record (an unreadable file is
    /// the notice at the top of the page).
    public static func visibleSections(showsNotifications: Bool, hasCurrentSite: Bool, hasPending: Bool) -> [NumberedSection] {
        let shown = Section.allCases.filter { section in
            switch section {
            case .notifications: showsNotifications
            case .currentSite: hasCurrentSite
            case .pending: hasPending
            default: true
            }
        }
        return shown.enumerated().map { index, section in
            NumberedSection(section: section, ordinal: ChineseOrdinal.text(index + 1))
        }
    }

    public static let mainModeTitle = "主模式"
    public static let mainModeSubtitle = "概览 · 账号 · 用户 · 监控，适合日常处理"
    public static let simpleModeTitle = "简化模式（表格）"
    public static let simpleModeSubtitle = "视图列表 + 表格，适合快速筛查大量数据"
    /// U42: shown greyed in this version.
    public static let simpleModeBadge = "设计中"
    public static let faceIDTitle = "高风险操作需要 Face ID"
    /// The coverage list of 60 §3.4 in one line; it changes with the list.
    public static let faceIDSubtitle = "删除、批量操作、更换账号凭据，以及超过门槛的充值 / 退款、新建用户初始余额、余额兑换码和余额补偿"
    public static let faceIDUnavailableSubtitle = "这台设备没有设置 Face ID / 触控 ID"
    public static let thresholdTitle = "金额门槛"
    public static let thresholdSubtitle = "单笔或合计超过这个金额时验证"
    public static let sessionsUnavailableSubtitle = "Admin Key 与访问令牌没有登录会话"
    public static let sessionBindingNotice = "站点开启了会话绑定；切换网络可能需要重新登录"
    public static let sessionBindingAdvice = "可请站长把原生客户端绑定方式设为 device"

    public static func thresholdText(_ value: Decimal) -> String { DisplayFormat.money(value, digits: 0) }
    /// 60 §3.3 通知; “已停用” needs stage 6's device list.
    public static func pushStatus(isRegistered: Bool) -> String { isRegistered ? "已开启" : "未开启" }

    /// “admin@example.com · 管理员”; “—” while admin/me has no email (60 §3.5).
    public static func identityLine(email: String?, role: String?) -> String {
        guard let email = email?.trimmingCharacters(in: .whitespacesAndNewlines), !email.isEmpty else { return DisplayFormat.missing }
        guard let title = role.flatMap(AdminUserRole.init(rawValue:))?.title else { return email }
        return email + " · " + title
    }

    /// 00 §1.2. Binding applies to account sessions only, so Admin Key and `sat_` never see it; device and off need no notice,
    /// strict and ua_only (an empty mode is strict on the server) get the advice; an unknown or unread mode only the notice.
    public static func sessionBindingHint(authMethod: AdminAuthMethod?, bindingEnabled: Bool?, nativeMode: String?) -> String? {
        guard authMethod == .jwt, bindingEnabled == true else { return nil }
        switch nativeMode {
        case "device", "off": return nil
        case "strict", "ua_only", "": return sessionBindingNotice + "。" + sessionBindingAdvice
        default: return sessionBindingNotice
        }
    }
    /// `GET admin/settings` is read only for the hint, only by the admin role (00 §1.2; a workspace vendor gets 403 there), and
    /// not before compliance is accepted (it would answer 423).
    public static func readsBindingMode(me: AdminMe, authMethod: AdminAuthMethod?) -> Bool {
        authMethod == .jwt && me.isAdministrator && me.security.sessionBindingEnabled == true && me.compliance.required != true
    }

    /// The existing confirmation; a `sat_` site also revokes its token (00 §1.7.5 step 3).
    public static func removeSiteMessage(name: String, authentication: AuthenticationKind) -> String {
        "\(name)\n站点配置和本机凭据将被清除。旧身份的未决余额记录仍保留，之后仅可在 Web 后台核对。"
            + (authentication == .accessToken ? "\n同时吊销这个管理访问令牌" : "")
    }

    public enum SessionsRow: Sendable, Equatable {
        /// An account sign-in on a server without `auth/sessions` (non-JSON 404).
        case hidden
        /// Admin Key and access tokens: shown but not tappable.
        case notApplicable
        case available
    }
    public static func sessionsRow(authMethod: AdminAuthMethod?, fallback: AuthenticationKind, sessionsSupported: Bool) -> SessionsRow {
        let isAccount = switch authMethod {
        case .jwt: true
        case .adminAPIKey, .adminAccessToken: false
        case .other, nil: fallback == .password
        }
        guard isAccount else { return .notApplicable }
        return sessionsSupported ? .available : .hidden
    }
    public static func showsAccessTokens(_ me: AdminMe) -> Bool { me.has(.adminAccessTokens) && me.workspace == nil }
    public static func showsNotifications(_ me: AdminMe) -> Bool { me.has(.pushNotifications) && me.workspace == nil }
    /// 60 §3.3 “有效令牌数”: not expired; a missing or unreadable expiry never expires.
    public static func activeTokenCount(_ tokens: [AdminAccessToken], now: Date) -> Int {
        tokens.filter { token in ServerTime.parseTimestamp(token.expiresAt).map { $0 > now } ?? true }.count
    }

    public struct PendingRow: Equatable, Sendable {
        public let title: String
        public let detail: String
        public let amount: String?
        public init(title: String, detail: String, amount: String?) { self.title = title; self.detail = detail; self.amount = amount }
    }
    /// The shared title and detail line (00 §2.5.5) with the record's site in front; amounts echo what was typed.
    public static func pendingRow(siteName: String, summary: PendingMoneyWriteSummary, now: Date, timeZone: TimeZone) -> PendingRow {
        let line = PendingMoneyWriteLine(summary)
        let time = summary.createdAt.map { DisplayFormat.relativeTime($0, now: now, timeZone: timeZone) }
        let amount: String? = switch line.amount {
        case .money(let value): DisplayFormat.moneyExact(value)
        case .allBalance: PendingMoneyWriteLine.allBalanceText
        case nil: nil
        }
        return PendingRow(title: line.title, detail: siteName + " · " + line.detail(relativeTime: time), amount: amount)
    }
}
