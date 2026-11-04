import Foundation

// 60 §13.3–§13.5 (S6-12): the detail's own words and rows. The status card, latency, facts, expiry sentence, proxy URL and delete
// rule are ProxyPresentation's.

public enum ProxyDetailCopy {
    public static let objectNoun = "代理"
    public static let testRequestFailed = "测试请求失败，请稍后再试"
    public static let qualityFailed = "代理质量检测失败"
    public static let copiedURL = "已复制代理 URL"
    public static let noAccounts = "暂无账号使用此代理"
    public static let accountsUnavailable = "暂时无法加载 · 重试"
    public static let gone = "已删除"
    public static let retesting = "地址已修改，正在重新测试"
    public static let unconfirmed = "结果未确认，请刷新核对后再操作"
    public static let understood = "知道了"
    public static let viewFallbackAccounts = "查看被改走的账号"

    public static func qualityDone(score: Int, grade: String) -> String { "质量检测完成：评分 \(score)（\(grade)）" }
    /// “已停用 hk-02 · 在用的 3 个账号不受影响”; without accounts just the name.
    public static func disabled(name: String, accountCount: Int) -> String {
        accountCount > 0 ? "已停用 \(name) · 在用的 \(accountCount) 个账号不受影响" : "已停用 \(name)"
    }
    public static func enabled(name: String) -> String { "已启用 \(name)" }
    /// `reason` is the error's catalog text (R11), never the server's message.
    public static func statusFailed(_ toggle: ProxyStatusToggle, reason: String) -> String {
        (toggle == .enable ? "启用" : "停用") + "没有成功：" + reason
    }
    public static func undoFailed(reason: String) -> String { "撤销没有成功：" + reason }
    public static func deleteFailed(reason: String) -> String { "删除没有成功：" + reason }
    public static func accountsMeta(_ count: Int) -> String { "\(count) 个" }
    public static func fallbackLink(_ count: Int) -> String { "被改走的账号 \(count) 个" }
}

/// The ··· entry after 质量检测: 停用 an active proxy, 启用 a stopped one, 续期 (the edit sheet) an expired one.
public enum ProxyStatusToggle: Sendable, Equatable {
    case disable, enable, renew

    /// `now` is the server's clock. The sweep marks only active proxies, so one stopped before its day came is still “inactive”;
    /// enabled as it is, the next sweep would move its accounts off (60 §14.4 wants a new expiry first), so it is renewed too.
    public init(_ proxy: AdminProxy, now: Date) {
        switch proxy.status ?? "active" {
        case "expired": self = .renew
        case "inactive": self = proxy.expiresAt.map { $0 <= now } == true ? .renew : .enable
        default: self = .disable
        }
    }
    public var menuTitle: String {
        switch self {
        case .disable: "停用代理"
        case .enable: "启用代理"
        case .renew: "续期…"
        }
    }
    /// The PUT's status; nil for 续期, which opens the sheet.
    public var target: ProxyStatusChange? {
        switch self {
        case .disable: .inactive
        case .enable: .active
        case .renew: nil
        }
    }
    /// What 撤销 writes back.
    public var undoTarget: ProxyStatusChange? {
        switch self {
        case .disable: .active
        case .enable: .inactive
        case .renew: nil
        }
    }
}

/// 13.4's two “不能删除” boxes: accounts still on the proxy (only 知道了), or accounts moved off it that the delete would strand.
public enum ProxyDeleteBlock: Sendable, Equatable, Identifiable {
    case inUse(name: String, accounts: Int)
    case fallback(name: String, accounts: Int)

    public var id: String {
        switch self {
        case .inUse(let name, let count): "inUse-\(name)-\(count)"
        case .fallback(let name, let count): "fallback-\(name)-\(count)"
        }
    }
    public var title: String {
        switch self {
        case .inUse(let name, _), .fallback(let name, _): "不能删除「\(name)」"
        }
    }
    public var message: String {
        switch self {
        case .inUse(_, let count): "该代理已有 \(count) 个账号使用，无法删除。先在这些账号的编辑页里换掉代理。"
        case .fallback(_, let count): "\(count) 个账号到期时从这个代理改走，删除后它们就恢复不了原代理。先恢复这些账号，或在账号详情里处理。"
        }
    }
    /// “查看被改走的账号” needs the page, which needs `proxies.fallback_accounts`.
    public func offersFallbackPage(hasCapability: Bool) -> Bool {
        guard case .fallback = self else { return false }
        return hasCapability
    }
    /// Before asking for the name: nil when the proxy may be deleted.
    public static func before(_ proxy: AdminProxy) -> ProxyDeleteBlock? {
        let name = ProxyPresentation.displayName(proxy)
        switch ProxyPresentation.deleteRestriction(proxy) {
        case .allowed: return nil
        case .hasAccounts(let count): return .inUse(name: name, accounts: count)
        case .hasFallbackAccounts(let count): return .fallback(name: name, accounts: count)
        }
    }
    public static func isInUseConflict(_ error: APIError) -> Bool { error.statusCode == 409 && error.reason == ProxyReason.inUse }
    /// 409 PROXY_IN_USE with `metadata.fallback_account_count`; without it the caller reads the proxy again (`resolveInUse`).
    public static func fromConflict(_ error: APIError, name: String) -> ProxyDeleteBlock? {
        ProxyReason.fallbackAccountCount(in: error).map { .fallback(name: name, accounts: $0) }
    }
    /// The 409 said someone uses it: the fresh counts decide, at least one account; the shown proxy when the read failed.
    public static func resolveInUse(refreshed: AdminProxy?, local: AdminProxy) -> ProxyDeleteBlock {
        let proxy = refreshed ?? local
        let name = ProxyPresentation.displayName(proxy)
        if case .hasFallbackAccounts(let count) = ProxyPresentation.deleteRestriction(proxy) { return .fallback(name: name, accounts: count) }
        return .inUse(name: name, accounts: max(1, proxy.accountCount ?? 0))
    }
}

/// One key-value line of 壹 有效期 or 叁 连接.
public struct ProxyKV: Sendable, Equatable, Identifiable {
    public enum Key: String, Sendable { case expiresAt, warnDays, remaining, fallback, scheme, port, host, username, password, createdAt }
    public let key: Key
    public let label: String
    public let value: String
    public let isMonospaced: Bool
    public var id: Key { key }
    public init(key: Key, label: String, value: String, isMonospaced: Bool = false) {
        self.key = key; self.label = label; self.value = value; self.isMonospaced = isMonospaced
    }
}

public enum ProxyDetailRows {
    /// 到期日 (“2026-10-22” / 永不过期) and 到期提醒; without the sentence also 剩余 and 到期回退. Days on the server's calendar.
    public static func expiry(_ proxy: AdminProxy, backupName: String?, hasNote: Bool, now: Date, timeZone: ServerTimeZone) -> [ProxyKV] {
        let rows = [ProxyKV(key: .expiresAt, label: "到期日", value: proxy.expiresAt.map(timeZone.dayString) ?? "永不过期"),
                    ProxyKV(key: .warnDays, label: "到期提醒", value: proxy.expiryWarnDays.map { "提前 \($0) 天" } ?? DisplayFormat.missing)]
        guard !hasNote else { return rows }
        let word = ProxyExpiry.describe(proxy, now: now, timeZone: timeZone)
        let remaining = switch word.kind {
        case .never: "不限"
        case .idle: DisplayFormat.missing
        default: word.text
        }
        return rows + [ProxyKV(key: .remaining, label: "剩余", value: remaining),
                       ProxyKV(key: .fallback, label: "到期回退", value: fallbackText(proxy, backupName: backupName))]
    }
    /// 协议, 端口 (no grouping), 主机 and 用户名 monospaced, 密码 never shown, 创建时间 as a server day.
    public static func connection(_ proxy: AdminProxy, timeZone: ServerTimeZone) -> [ProxyKV] {
        let scheme = AccountProxyPresentation.protocolLabel(proxy.scheme)
        let host = proxy.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = proxy.username?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let hasPassword = !(proxy.password ?? "").isEmpty
        return [ProxyKV(key: .scheme, label: "协议", value: scheme.isEmpty ? DisplayFormat.missing : scheme),
                ProxyKV(key: .port, label: "端口", value: proxy.port.map(String.init) ?? DisplayFormat.missing),
                ProxyKV(key: .host, label: "主机", value: host.isEmpty ? DisplayFormat.missing : host, isMonospaced: !host.isEmpty),
                ProxyKV(key: .username, label: "用户名", value: username.isEmpty ? DisplayFormat.missing : username, isMonospaced: !username.isEmpty),
                ProxyKV(key: .password, label: "密码", value: hasPassword ? "••••••" : "未设置"),
                ProxyKV(key: .createdAt, label: "创建时间", value: proxy.createdAt.map(timeZone.dayString) ?? DisplayFormat.missing)]
    }
    /// 贰's second line: “Anthropic · OAuth”.
    public static func accountDetail(_ account: ProxyAccountRef, catalog: MetaCatalog?) -> String {
        AccountNaming.platformName(account.platform, catalog: catalog) + " · " + AccountNaming.typeName(platform: account.platform, type: account.type)
    }
    /// 壹's “被改走的账号 2 个 ›”, only with `proxies.fallback_accounts` and a count above 0.
    public static func fallbackLink(_ proxy: AdminProxy, hasCapability: Bool) -> String? {
        guard hasCapability, let count = proxy.fallbackAccountCount, count > 0 else { return nil }
        return ProxyDetailCopy.fallbackLink(count)
    }

    /// “不回退”, “回退直连”, “备用 sg‑01” (a non-breaking hyphen) or “备用 —”.
    private static func fallbackText(_ proxy: AdminProxy, backupName: String?) -> String {
        switch ProxyFallbackMode(rawValue: proxy.fallbackMode ?? "") ?? ProxyFallbackMode.none {
        case .none: return "不回退"
        case .direct: return "回退直连"
        case .proxy:
            let name = backupName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return "备用 " + (name.isEmpty ? DisplayFormat.missing : name.replacingOccurrences(of: "-", with: "\u{2011}"))
        }
    }
}

/// 13.4 质量检测's receipt. The server answers 200 with a score even when the base probe failed: only a passed base probe with a
/// score and grade is a success.
public struct ProxyQualityNotice: Sendable, Equatable {
    public let text: String
    public let tone: Tone
    public init(text: String, tone: Tone) { self.text = text; self.tone = tone }
    public init(_ result: ProxyQualityResult) {
        let grade = result.grade?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if result.baseConnectivityPassed, let score = result.score, !grade.isEmpty {
            self.init(text: ProxyDetailCopy.qualityDone(score: score, grade: grade), tone: .ok)
        } else {
            self.init(text: ProxyDetailCopy.qualityFailed, tone: .critical)
        }
    }
}

/// How a detail write failed (00 §2.4, R06): none is resent on its own.
public enum ProxyDetailFailure: Equatable, Sendable {
    /// 404 PROXY_NOT_FOUND.
    case gone
    /// Lost connection, an unreadable reply, 502 / 504 or a 503 without its own reason: read back.
    case unconfirmed
    /// Compliance or step-up cleared it: the notice, then the action again.
    case reconfirm(String)
    case cancelled
    /// Catalog text.
    case rejected(String)

    public static func isGone(_ error: any Error) -> Bool {
        guard let api = error as? APIError else { return false }
        return api.statusCode == 404 && api.reason == ProxyReason.notFound
    }
    public static func classify(_ error: any Error) -> ProxyDetailFailure {
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
        guard let status = api.statusCode else {
            return api.kind == .transport || api == .invalidResponse ? .unconfirmed : .rejected(api.localizedDescription)
        }
        return RequestPolicy.isRetryableStatus(status, marker: api.reason) ? .unconfirmed : .rejected(api.localizedDescription)
    }
}
