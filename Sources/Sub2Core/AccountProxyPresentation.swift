import Foundation

// 20 §3.3 / §3.4: the detail's 代理 section and its picker. `now` is the site clock, `timeZone` the server's.

public struct AccountProxyHint: Sendable, Equatable {
    public let text: String
    public let tone: Tone
    public init(text: String, tone: Tone) { self.text = text; self.tone = tone }
}

/// The proxy row: the name, “{协议} · {到期词}” and the monospaced address; “无代理”; or, with only `proxy_id`, “代理 #id”.
public struct AccountProxyRowContent: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case direct, proxy, unresolved }
    public let kind: Kind
    public let title: String
    public let detail: String?
    public let expiry: ProxyExpiryWord?
    public let address: String?
    /// Set: the row pushes the proxy's detail (U23); nil: it opens the picker.
    public let proxyID: Int?
    public init(kind: Kind, title: String, detail: String?, expiry: ProxyExpiryWord?, address: String?, proxyID: Int?) {
        self.kind = kind; self.title = title; self.detail = detail; self.expiry = expiry; self.address = address; self.proxyID = proxyID
    }
}

/// 已回退: the proxy expired and the server moved the account; “恢复原代理” moves it back.
public struct AccountProxyFallbackLine: Sendable, Equatable {
    public let originID: Int
    /// The name, or “#id” once the proxy is deleted.
    public let originName: String
    public let title: String
    public let detail: String
    public init(originID: Int, originName: String, title: String, detail: String) {
        self.originID = originID; self.originName = originName; self.title = title; self.detail = detail
    }
}

public struct AccountProxySectionContent: Sendable, Equatable {
    public let row: AccountProxyRowContent
    public let hint: AccountProxyHint?
    public let fallback: AccountProxyFallbackLine?
    public let footnote: String
}

/// One active proxy of the picker: a badge while it is about to expire, then “N 个账号在用 · {地区} · {到期词}”.
public struct AccountProxyOption: Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let address: String
    public let badge: String?
    public let meta: String
}

public struct AccountProxyPickerContent: Sendable, Equatable {
    public let options: [AccountProxyOption]
    /// The current proxy is not among them (expired or stopped).
    public let currentNote: AccountProxyHint?
}

public enum AccountProxyPresentation {
    public static let directTitle = "无代理"
    public static let directDetail = "直连上游"
    public static let pickerFootnote = "只列出启用中的代理；已停用、已过期的代理在“代理”里管理。"

    public static func section(_ account: UpstreamAccount, now: Date, timeZone: ServerTimeZone) -> AccountProxySectionContent {
        let fallback = fallbackLine(account)
        return AccountProxySectionContent(row: row(account, now: now, timeZone: timeZone), hint: hint(account.proxy), fallback: fallback,
                                          footnote: fallback == nil ? AccountProxyCopy.footnote : AccountProxyCopy.fallbackFootnote)
    }

    /// Active proxies only, newest first (then the higher id); `current` / `currentID` are the account's.
    public static func picker(_ proxies: [AdminProxy], current: AccountProxy?, currentID: Int?, now: Date,
                              timeZone: ServerTimeZone) -> AccountProxyPickerContent {
        let active = proxies.filter(\.isActive).sorted { lhs, rhs in
            let left = lhs.createdAt ?? .distantPast, right = rhs.createdAt ?? .distantPast
            return left == right ? lhs.id > rhs.id : left > right
        }
        let options = active.map { option($0, now: now, timeZone: timeZone) }
        let id = current?.id ?? currentID
        guard let id, !active.contains(where: { $0.id == id }) else { return AccountProxyPickerContent(options: options, currentNote: nil) }
        return AccountProxyPickerContent(options: options, currentNote: currentNote(current, id: id))
    }

    /// “SOCKS5”; empty when unknown.
    public static func protocolLabel(_ raw: String?) -> String { raw?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() ?? "" }

    /// The original proxy's name or “#id”; nil when the account is not fallen back.
    public static func originName(_ account: UpstreamAccount) -> String? {
        guard let id = account.proxyFallbackOriginID else { return nil }
        let name = account.proxyFallbackOriginName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "#\(id)" : name
    }

    // MARK: - Pieces

    private static func row(_ account: UpstreamAccount, now: Date, timeZone: ServerTimeZone) -> AccountProxyRowContent {
        guard let proxy = account.proxy else {
            guard let id = account.proxyID, id > 0 else {
                return AccountProxyRowContent(kind: .direct, title: directTitle, detail: nil, expiry: nil, address: nil, proxyID: nil)
            }
            return AccountProxyRowContent(kind: .unresolved, title: "代理 #\(id)", detail: nil, expiry: nil, address: nil, proxyID: id)
        }
        let word = ProxyExpiry.describe(proxy, now: now, timeZone: timeZone)
        let detail = [protocolLabel(proxy.scheme), word.text].filter { !$0.isEmpty }.joined(separator: " · ")
        return AccountProxyRowContent(kind: .proxy, title: displayName(proxy.name, id: proxy.id), detail: detail, expiry: word,
                                      address: address(proxy), proxyID: proxy.id)
    }
    private static func address(_ proxy: AccountProxy) -> String? {
        let host = proxy.host?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !host.isEmpty else { return nil }
        let scheme = proxy.scheme.map { "\($0)://" } ?? ""
        return scheme + host + (proxy.port.map { ":\($0)" } ?? "")
    }
    private static func hint(_ proxy: AccountProxy?) -> AccountProxyHint? {
        switch proxy?.status {
        case "expired": AccountProxyHint(text: AccountProxyCopy.expiredHint, tone: .critical)
        case "inactive": AccountProxyHint(text: AccountProxyCopy.inactiveHint, tone: .neutral)
        default: nil
        }
    }
    private static func fallbackLine(_ account: UpstreamAccount) -> AccountProxyFallbackLine? {
        guard let id = account.proxyFallbackOriginID, let origin = originName(account) else { return nil }
        let now = account.proxy.map { displayName($0.name, id: $0.id) } ?? account.proxyID.flatMap { $0 > 0 ? "代理 #\($0)" : nil } ?? "直连"
        return AccountProxyFallbackLine(originID: id, originName: origin, title: "已回退：原代理 \(origin)", detail: "原代理到期后已改为\(now)")
    }
    private static func option(_ proxy: AdminProxy, now: Date, timeZone: ServerTimeZone) -> AccountProxyOption {
        let word = ProxyExpiry.describe(proxy, now: now, timeZone: timeZone)
        let usage = proxy.accountCount.map { $0 > 0 ? "\($0) 个账号在用" : "没有账号在用" }
        let meta = [usage, proxy.regionText, word.isSoon ? nil : word.text].compactMap { $0 }.joined(separator: " · ")
        return AccountProxyOption(id: proxy.id, name: displayName(proxy.name, id: proxy.id), address: proxy.address,
                                  badge: word.isSoon ? word.text : nil, meta: meta)
    }
    private static func currentNote(_ current: AccountProxy?, id: Int) -> AccountProxyHint {
        let name = current.map { displayName($0.name, id: $0.id) } ?? "#\(id)"
        let tail = "不在可选列表里。选一个启用中的代理，或改为无代理。"
        switch current?.status {
        case "expired": return AccountProxyHint(text: "当前代理 \(name) 已过期，\(tail)", tone: .critical)
        case "inactive": return AccountProxyHint(text: "当前代理 \(name) 已停用，\(tail)", tone: .neutral)
        default: return AccountProxyHint(text: "当前代理 \(name) \(tail)", tone: .neutral)
        }
    }
    private static func displayName(_ name: String, id: Int) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "代理 #\(id)" : trimmed
    }
}

/// 20 §3.4 代理 and 恢复原代理 wording.
public enum AccountProxyCopy {
    /// The one field name handed to AccountPatchFlow, so its receipt reads “已保存：代理 → hk-02”.
    public static func fieldName(_ proxyName: String?) -> String { "代理 → \(proxyName ?? AccountProxyPresentation.directTitle)" }
    public static func revertTitle(_ origin: String) -> String { "恢复原代理「\(origin)」？" }
    public static func revertMessage(_ origin: String) -> String { "账号改回走 \(origin)，出口 IP 随之改变。恢复后不能撤销。" }
    public static let revertAction = "恢复原代理"
    public static func reverted(_ origin: String) -> String { "已恢复原代理「\(origin)」" }
    public static func revertFailed(reason: String) -> String { "恢复原代理没有成功：\(reason)" }
    public static let notInFallback = "这个账号已不在回退状态"
    public static let originUnavailable = "原代理已删除、停用或过期，续期并启用后才能恢复"
    public static let viewOrigin = "查看原代理"
    public static let unconfirmed = "恢复原代理结果未确认"
    public static let expiredHint = "代理已过期，这个账号仍挂在上面。换一个启用中的代理，或改为无代理。"
    public static let inactiveHint = "代理已停用，不在可选列表里；可以换一个，或改为无代理。"
    public static let footnote = "选中即生效，回执里可撤销。"
    public static let fallbackFootnote = "选中即生效，回执里可撤销。恢复原代理不能撤销。"
}
