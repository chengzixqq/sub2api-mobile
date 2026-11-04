import Foundation

// 60 §14 (S6-14): the add / edit / renew sheet's form as a value. The bodies and their checks are S6-10's ProxyCreateRequest and
// ProxyUpdateRequest; this decides what goes into them, which sections show in which order and what each one says. The words are
// ProxyEditCopy's, the write's failures ProxyWriteFailure's (ProxyEditOutcome.swift).

/// 14.1: + adds and 编辑 edits; an expired proxy (or one stopped past its day, which ··· also offers as 续期…) is renewed.
public enum ProxyEditMode: String, Sendable, Equatable {
    case add, edit, renew

    public static func resolve(_ proxy: AdminProxy?, now: Date) -> ProxyEditMode {
        guard let proxy else { return .add }
        return ProxyStatusToggle(proxy, now: now) == .renew ? .renew : .edit
    }
    public var title: String {
        switch self {
        case .add: "添加代理"
        case .edit: "编辑代理"
        case .renew: "续期代理"
        }
    }
}

/// The form's sections; 名称与协议, 地址 and 认证 are the design's one “名称地址认证” block.
public enum ProxyEditSection: String, Sendable, CaseIterable {
    case name, address, auth, expiry, fallback, status

    /// 14.3: renewing puts the expiry and the status first; adding has no status.
    public static func order(for mode: ProxyEditMode) -> [ProxyEditSection] {
        switch mode {
        case .renew: [.expiry, .status, .fallback, .name, .address, .auth]
        case .edit: [.name, .address, .auth, .expiry, .fallback, .status]
        case .add: [.name, .address, .auth, .expiry, .fallback]
        }
    }
    public func title(in mode: ProxyEditMode) -> String {
        switch self {
        case .name: "名称与协议"
        case .address: "地址"
        case .auth: "认证（可选）"
        case .expiry: mode == .renew ? "有效期 · 续期" : "有效期"
        case .fallback: "到期回退"
        case .status: "状态"
        }
    }
}

public enum ProxyProtocolChoice: String, Sendable, CaseIterable {
    case http, https, socks5, socks5h
    public var title: String { rawValue.uppercased() }
    public init?(wire: String?) { self.init(rawValue: (wire ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) }
}

public enum ProxyExpiryChoice: Hashable, Sendable {
    case keep, never, days(Int), custom
    public static let presetDays = [30, 90]
    /// Accessibility identifiers: keep, never, 30, 90, custom.
    public var identifier: String {
        switch self {
        case .keep: "keep"
        case .never: "never"
        case .days(let days): String(days)
        case .custom: "custom"
        }
    }
}

public struct ProxyExpiryOption: Sendable, Equatable, Identifiable {
    public let choice: ProxyExpiryChoice
    public let title: String
    public var id: String { choice.identifier }
}

/// 14.2: every other proxy of the catalog in its order. Only an active one before its expiry can be a backup (the fallback chain
/// skips the rest); the others stay listed, greyed, with 停用 or 已过期.
public struct ProxyBackupCandidate: Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let isSelectable: Bool
    public let note: String?

    public static func make(from proxies: [AdminProxy], excluding id: Int?, now: Date) -> [ProxyBackupCandidate] {
        proxies.filter { $0.id != id }.map { proxy in
            let lapsed = proxy.expiresAt.map { $0 <= now } ?? false
            let note: String? = switch proxy.status ?? "active" {
            case "active": lapsed ? "已过期" : nil
            case "inactive": "停用"
            default: "已过期"
            }
            return ProxyBackupCandidate(id: proxy.id, name: ProxyPresentation.displayName(proxy), isSelectable: note == nil, note: note)
        }
    }
}

/// Why the form cannot be sent (14.4); lengths in UTF-8 bytes as the server's columns count them. Those without a footnote only
/// grey the button; the lapsed-keep rule speaks through the status footnote.
public enum ProxyEditIssue: Sendable, Equatable {
    case nameRequired, nameTooLong, hostRequired, hostTooLong, portMissing, portOutOfRange, usernameTooLong, passwordTooLong
    case customDaysMissing, customDaysInvalid, backupRequired, lapsedKeepActive

    public var section: ProxyEditSection {
        switch self {
        case .nameRequired, .nameTooLong: .name
        case .hostRequired, .hostTooLong, .portMissing, .portOutOfRange: .address
        case .usernameTooLong, .passwordTooLong: .auth
        case .customDaysMissing, .customDaysInvalid: .expiry
        case .backupRequired: .fallback
        case .lapsedKeepActive: .status
        }
    }
    public var footnote: String? {
        switch self {
        case .nameTooLong: "名称最多 \(ProxyWriteCheck.nameLimit) 字节"
        case .hostTooLong: "主机地址最多 \(ProxyWriteCheck.hostLimit) 字节"
        case .portOutOfRange: "端口必须在 1-65535 之间"
        case .usernameTooLong: "用户名最多 \(ProxyWriteCheck.credentialLimit) 字节"
        case .passwordTooLong: "密码最多 \(ProxyWriteCheck.credentialLimit) 字节"
        case .customDaysInvalid: "天数要在 1-9999 之间"
        case .backupRequired: ProxyEditCopy.backupRequired
        case .nameRequired, .hostRequired, .portMissing, .customDaysMissing, .lapsedKeepActive: nil
        }
    }
}

/// 14.1's object bar while renewing: “jp-tokyo-1” and “SOCKS5H · 192.0.2.88:1080 · 1 个账号仍在用”.
public struct ProxyRenewTarget: Sendable, Equatable {
    public let name: String
    public let detail: String
    public var line: String { name + " · " + detail }
}

/// The sheet's form. The password is never prefilled and every description writes <redacted> for it.
public struct ProxyEditDraft: Sendable, Equatable {
    public static let defaultWarnDays = 7
    public static let warnDaysBounds = 1...30
    public static let customDaysBounds = 1...9999
    static let portBounds = 1...65_535
    static let portDigits = 5, customDigits = 4
    static let secondsPerDay: TimeInterval = 86_400

    public let mode: ProxyEditMode
    public let original: AdminProxy?
    public var name: String
    public var scheme: ProxyProtocolChoice
    public var host: String
    /// ASCII digits only, at most 5.
    public var portText: String { didSet { portText = Self.sanitizePort(portText) } }
    public var username: String
    public var password: String
    public private(set) var expiry: ProxyExpiryChoice
    /// ASCII digits only, at most 4.
    public var customDaysText: String { didSet { customDaysText = Self.sanitizeCustomDays(customDaysText) } }
    public var warnDays: Int
    public var fallback: ProxyFallbackMode
    public var backupID: Int?
    public var status: ProxyStatusChange
    private let baseline: Fields

    /// SOCKS5, never expires, warns 7 days ahead, no fallback.
    public static func adding() -> ProxyEditDraft {
        ProxyEditDraft(mode: .add, original: nil, fields: Fields(name: "", scheme: .socks5, host: "", port: "", username: "", password: "",
                                                                 expiry: .never, customDays: "", warnDays: defaultWarnDays,
                                                                 fallback: ProxyFallbackMode.none, backupID: nil, status: .active))
    }
    /// The shown proxy, without its password. A proxy being renewed opens as 停用 (a PUT takes only active / inactive, as on the Web)
    /// until a new expiry is picked; an unknown protocol reads as SOCKS5.
    public init(editing proxy: AdminProxy, now: Date) {
        let mode = ProxyEditMode.resolve(proxy, now: now)
        let fallback = ProxyFallbackMode(rawValue: proxy.fallbackMode ?? "") ?? ProxyFallbackMode.none
        let status: ProxyStatusChange = mode == .renew ? .inactive : ProxyStatusChange(rawValue: proxy.status ?? "") ?? .active
        self.init(mode: mode, original: proxy, fields: Fields(
            name: proxy.name, scheme: ProxyProtocolChoice(wire: proxy.scheme) ?? .socks5, host: proxy.host, port: proxy.port.map(String.init) ?? "",
            username: proxy.username ?? "", password: "", expiry: proxy.expiresAt == nil ? .never : .keep, customDays: "",
            warnDays: proxy.expiryWarnDays ?? Self.defaultWarnDays, fallback: fallback, backupID: fallback == .proxy ? proxy.backupProxyID : nil,
            status: status))
    }
    private init(mode: ProxyEditMode, original: AdminProxy?, fields: Fields) {
        self.mode = mode; self.original = original; baseline = fields
        name = fields.name; scheme = fields.scheme; host = fields.host; portText = fields.port; username = fields.username
        password = fields.password; expiry = fields.expiry; customDaysText = fields.customDays; warnDays = fields.warnDays
        fallback = fields.fallback; backupID = fields.backupID; status = fields.status
    }

    /// Renewing: any new expiry switches the status back to 正常 (it can still be set to 停用 after).
    public mutating func selectExpiry(_ choice: ProxyExpiryChoice) {
        expiry = choice
        if mode == .renew, choice != .keep { status = .active }
    }

    public static func sanitizePort(_ raw: String) -> String { digits(raw, limit: portDigits) }
    public static func sanitizeCustomDays(_ raw: String) -> String { digits(raw, limit: customDigits) }
    public var port: Int? { Int(portText) }
    /// The custom days when they are 1–9999.
    public var customDays: Int? { Int(customDaysText).flatMap { Self.customDaysBounds.contains($0) ? $0 : nil } }
    /// 1–30, widened to the proxy's own value when it lies outside.
    public var warnDaysRange: ClosedRange<Int> {
        min(Self.warnDaysBounds.lowerBound, baseline.warnDays)...max(Self.warnDaysBounds.upperBound, baseline.warnDays)
    }
    public var isLapsedKeep: Bool { mode == .renew && expiry == .keep }
    public var submitTitle: String {
        switch mode {
        case .add: "添加"
        case .renew where expiry != .keep: "续期"
        default: "保存"
        }
    }
    /// Changed back is unchanged; a typed password is a change.
    public var hasUnsavedChanges: Bool { fields != baseline }

    /// 保持 <the server's day> (when editing a proxy that has one; “（已过期）” while renewing), 永不过期, 30 天, 90 天, 自定义.
    public func expiryOptions(timeZone: ServerTimeZone) -> [ProxyExpiryOption] {
        var options: [ProxyExpiryOption] = []
        if mode != .add, let date = original?.expiresAt {
            options.append(ProxyExpiryOption(choice: .keep, title: "保持 " + timeZone.dayString(date) + (mode == .renew ? "（已过期）" : "")))
        }
        options.append(ProxyExpiryOption(choice: .never, title: "永不过期"))
        options += ProxyExpiryChoice.presetDays.map { ProxyExpiryOption(choice: .days($0), title: "\($0) 天") }
        return options + [ProxyExpiryOption(choice: .custom, title: "自定义")]
    }
    /// N days = now + N × 86400 seconds (14.4); nil never expires (or custom days not yet valid).
    public func expiresAt(now: Date) -> Date? {
        switch expiry {
        case .keep: original?.expiresAt
        case .never: nil
        case .days(let days): now.addingTimeInterval(Double(days) * Self.secondsPerDay)
        case .custom: customDays.map { now.addingTimeInterval(Double($0) * Self.secondsPerDay) }
        }
    }

    public func issues(backups: [ProxyBackupCandidate]) -> [ProxyEditIssue] {
        let name = Self.trimmed(name), host = Self.trimmed(host)
        var found: [ProxyEditIssue] = []
        if name.isEmpty { found.append(.nameRequired) } else if name.utf8.count > ProxyWriteCheck.nameLimit { found.append(.nameTooLong) }
        if host.isEmpty { found.append(.hostRequired) } else if host.utf8.count > ProxyWriteCheck.hostLimit { found.append(.hostTooLong) }
        if portText.isEmpty { found.append(.portMissing) } else if !Self.portBounds.contains(port ?? 0) { found.append(.portOutOfRange) }
        if Self.trimmed(username).utf8.count > ProxyWriteCheck.credentialLimit { found.append(.usernameTooLong) }
        if Self.trimmed(password).utf8.count > ProxyWriteCheck.credentialLimit { found.append(.passwordTooLong) }
        if expiry == .custom, customDays == nil { found.append(customDaysText.isEmpty ? .customDaysMissing : .customDaysInvalid) }
        if fallback == .proxy, !hasUsableBackup(backups) { found.append(.backupRequired) }
        if isLapsedKeep, status == .active { found.append(.lapsedKeepActive) }
        return found
    }
    /// Nothing wrong, and for an edit at least one key to send.
    public func isSubmittable(backups: [ProxyBackupCandidate], now: Date) -> Bool {
        guard issues(backups: backups).isEmpty else { return false }
        return mode == .add || updateRequest(now: now).hasChanges
    }
    /// The first problem of the section that has words.
    public func issueNote(for section: ProxyEditSection, backups: [ProxyBackupCandidate]) -> String? {
        issues(backups: backups).first { $0.section == section && $0.footnote != nil }?.footnote
    }

    /// `POST`: text trimmed; an empty username or password, never expiring and a backup without the backup-proxy fallback are
    /// left out. Throws what the form would not let through.
    public func createRequest(now: Date) throws -> ProxyCreateRequest {
        if expiry == .custom, customDays == nil { throw ProxyWriteCheck.error() }
        let request = ProxyCreateRequest(name: Self.trimmed(name), scheme: scheme.rawValue, host: Self.trimmed(host), port: port ?? 0,
                                         username: username, password: password, expiresAt: expiresAt(now: now), fallbackMode: fallback,
                                         backupProxyID: fallback == .proxy ? backupID : nil, expiryWarnDays: warnDays)
        try request.validate()
        return request
    }
    /// `PUT`: only what changed (14.2). Status while editing when changed; while renewing whenever a new expiry is picked (kept,
    /// the server leaves the proxy expired). 永不过期 clears an expiry; leaving the backup-proxy fallback clears the backup.
    public func updateRequest(now: Date) -> ProxyUpdateRequest {
        guard let original else { return ProxyUpdateRequest() }
        var request = ProxyUpdateRequest()
        if Self.trimmed(name) != Self.trimmed(original.name) { request.name = Self.trimmed(name) }
        // Against the form's start: an unknown protocol opened as SOCKS5 is not a change.
        if scheme != baseline.scheme { request.scheme = scheme.rawValue }
        if Self.trimmed(host) != Self.trimmed(original.host) { request.host = Self.trimmed(host) }
        if let port, port != original.port { request.port = port }
        if Self.trimmed(username) != Self.trimmed(original.username ?? "") { request.username = Self.trimmed(username) }
        if !Self.trimmed(password).isEmpty { request.password = password }
        request.status = mode == .renew ? (expiry == .keep ? nil : status) : (status != baseline.status ? status : nil)
        request.expiresAt = expiryChange(from: original, now: now)
        if fallback != baseline.fallback { request.fallbackMode = fallback }
        request.backupProxyID = backupChange(from: original)
        if warnDays != baseline.warnDays { request.expiryWarnDays = warnDays }
        return request
    }

    /// The section's footer under any issue note (14.3).
    public func footnote(for section: ProxyEditSection, timeZone: ServerTimeZone) -> String? {
        switch section {
        case .name: scheme == .socks5h ? ProxyEditCopy.socks5hFootnote : nil
        case .address, .auth: nil
        case .expiry:
            mode == .renew ? ProxyEditCopy.renewFootnote(lapsedOn: original?.expiresAt.map { ProxyExpiry.monthDay($0, timeZone: timeZone) })
                : ProxyEditCopy.expiryFootnote
        case .fallback: ProxyEditCopy.fallbackFootnote(fallback)
        case .status: statusFootnote
        }
    }
    public var renewTarget: ProxyRenewTarget? {
        guard mode == .renew, let original else { return nil }
        let count = max(0, original.accountCount ?? 0)
        return ProxyRenewTarget(name: ProxyPresentation.displayName(original),
                                detail: ProxyPresentation.addressLine(original) + " · " + (count > 0 ? "\(count) 个账号仍在用" : "没有账号在用"))
    }
    /// 代理添加成功; 已续期 · <名称> 恢复正常 when a renewal came back active; otherwise 代理更新成功.
    public func successReceipt(saved: AdminProxy) -> String {
        switch mode {
        case .add: ProxyEditCopy.added
        case .renew where saved.status == ProxyStatusChange.active.rawValue: ProxyEditCopy.renewed(name: ProxyPresentation.displayName(saved))
        default: ProxyEditCopy.updated
        }
    }

    // MARK: - Internals

    private struct Fields: Sendable, Equatable {
        var name: String, scheme: ProxyProtocolChoice, host: String, port: String, username: String, password: String
        var expiry: ProxyExpiryChoice, customDays: String, warnDays: Int, fallback: ProxyFallbackMode, backupID: Int?, status: ProxyStatusChange
    }
    /// Custom days only while chosen, a backup only with the backup-proxy fallback.
    private var fields: Fields {
        Fields(name: name, scheme: scheme, host: host, port: portText, username: username, password: password, expiry: expiry,
               customDays: expiry == .custom ? customDaysText : "", warnDays: warnDays, fallback: fallback,
               backupID: fallback == .proxy ? backupID : nil, status: status)
    }
    private var statusFootnote: String? {
        if isLapsedKeep {
            return status == .active ? ProxyEditCopy.lapsedKeepActive : ProxyEditCopy.lapsedKeepIdle(stillExpired: original?.status == "expired")
        }
        if status == .inactive { return ProxyEditCopy.inactiveFootnote(accountCount: max(0, original?.accountCount ?? 0)) }
        return mode == .renew ? ProxyEditCopy.renewedStatus : nil
    }
    /// A selectable candidate, or the backup the proxy already had (kept as it is even if it can no longer be picked).
    private func hasUsableBackup(_ backups: [ProxyBackupCandidate]) -> Bool {
        guard let backupID else { return false }
        if baseline.fallback == .proxy, backupID == baseline.backupID { return true }
        return backups.contains { $0.id == backupID && $0.isSelectable }
    }
    private func expiryChange(from original: AdminProxy, now: Date) -> ProxyFieldChange<Date>? {
        switch expiry {
        case .keep: nil
        case .never: original.expiresAt == nil ? nil : .clear
        case .days, .custom: expiresAt(now: now).map { .set($0) }
        }
    }
    private func backupChange(from original: AdminProxy) -> ProxyFieldChange<Int>? {
        guard fallback == .proxy else { return baseline.fallback == .proxy && original.backupProxyID != nil ? .clear : nil }
        guard let backupID, backupID != original.backupProxyID else { return nil }
        return .set(backupID)
    }
    static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    static func digits(_ raw: String, limit: Int) -> String { String(raw.filter { $0.isASCII && $0.isNumber }.prefix(limit)) }
}

extension ProxyEditDraft: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "ProxyEditDraft(mode: \(mode.rawValue), name: \(name), address: \(scheme.rawValue)://\(host):\(portText), password: \(ProxyWriteCheck.mask(password)))"
    }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["mode": mode.rawValue, "name": name, "address": "\(scheme.rawValue)://\(host):\(portText)",
                                "password": ProxyWriteCheck.mask(password)], displayStyle: .struct)
    }
}
