import Foundation

// 60 §13.4 被改走的账号页 (S6-13): its words and rules. A failed account is worded by its `code` alone, never by the server's
// message (R11); the list rows, the confirmation and the receipts are built here.

/// 全部恢复 sends `{}` (every account moved off the proxy, not limited to 500); a row's swipe sends its one id.
public enum ProxyFallbackScope: Sendable, Hashable, Identifiable {
    case all
    case account(Int)

    public var accountIDs: [Int] {
        switch self {
        case .all: []
        case .account(let id): [id]
        }
    }
    public var id: String {
        switch self {
        case .all: "all"
        case .account(let id): "account-\(id)"
        }
    }
}

/// An account the last revert did not restore, listed on the page.
public struct ProxyFallbackFailureLine: Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let reason: String
    /// critical; caution when the list read again no longer has it (it may have been restored after all).
    public let tone: Tone
    public init(id: Int, name: String, reason: String, tone: Tone) { self.id = id; self.name = name; self.reason = reason; self.tone = tone }
}

/// A receipt's words and tone.
public struct ProxyFallbackNotice: Sendable, Equatable {
    public let text: String
    public let tone: Tone
    public init(text: String, tone: Tone) { self.text = text; self.tone = tone }
    public var systemImage: String {
        switch tone {
        case .ok: "checkmark.circle"
        case .caution, .critical: "exclamationmark.triangle"
        default: "info.circle"
        }
    }
}

/// A lost reply, read back: none of the accounts sent is listed any more, or some still are.
public enum ProxyFallbackReadback: Sendable, Equatable {
    case confirmed(Int)
    case remaining(Int)
}

public enum ProxyFallbackPresentation {
    public static let title = "被改走的账号"
    public static let blockedNote = "先续期并启用这个代理"
    public static let proxyUnavailableNote = "代理信息暂时无法加载，下拉重试"
    public static let emptyTitle = "没有被改走的账号"
    public static let unsupportedTitle = "站点版本较旧，暂不支持此功能"
    public static let revertAction = "恢复"
    public static let cancelAction = "取消"
    public static let failuresTitle = "没有恢复的账号"
    public static let reloadFailed = "暂时无法加载 · 重试"
    public static let running = "正在恢复…"
    public static let retry = "重试"
    public static let originUnavailable = "原代理仍已过期或已停用，请先续期或启用后再恢复"
    public static let maybeReverted = "已不在被改走列表，可能已恢复，请到账号详情核对"

    /// The subtitle and the receipts: the proxy's name, “代理 #4” while it is unknown or unnamed.
    public static func proxyName(_ proxy: AdminProxy?, id: Int) -> String {
        proxy.map(ProxyPresentation.displayName) ?? "代理 #\(id)"
    }
    public static func rowName(_ account: ProxyFallbackAccount) -> String {
        let name = account.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "账号 #\(account.id)" : name
    }
    /// “Kimi · API Key · 现在：备用 hk-02”, “… · 现在：直连”; a backup deleted since has no name: “现在：备用 #1”.
    public static func rowDetail(_ account: ProxyFallbackAccount) -> String {
        let platform = AccountNaming.platformName(account.platform, catalog: nil)
        let type = AccountNaming.typeName(platform: account.platform, type: account.type)
        return "\(platform) · \(type) · 现在：" + currentRoute(account)
    }
    /// As the backend's requireUsableFallbackOrigin: active (a missing status counts) and not expired, `expires_at` after `now`.
    public static func canRevert(_ proxy: AdminProxy, now: Date) -> Bool {
        proxy.isActive && (proxy.expiresAt.map { $0 > now } ?? true)
    }
    public static func revertAllTitle(proxyName: String) -> String { "全部恢复到 \(proxyName)" }
    public static func confirmTitle(_ scope: ProxyFallbackScope, count: Int, accountName: String?, proxyName: String) -> String {
        switch scope {
        case .all: return "把 \(count) 个账号改回走 \(proxyName)？"
        case .account(let id): return "把「\(accountName ?? "账号 #\(id)")」改回走 \(proxyName)？"
        }
    }
    /// The proxy's probed exit IP (`ip_address`), never its host.
    public static func confirmMessage(_ scope: ProxyFallbackScope, exitIP: String?) -> String {
        let subject = scope == .all ? "它们" : "它"
        guard let exit = exitIP?.trimmingCharacters(in: .whitespacesAndNewlines), !exit.isEmpty else { return "\(subject)的出口 IP 会随之改变。" }
        return "\(subject)的出口 IP 会变回 \(exit)。"
    }

    /// “已恢复 2 个账号到 hk-01”, then “1 个已不在回退状态，已跳过” and “1 个没有恢复”; nothing restored but something skipped or
    /// failed leaves out the first part.
    public static func receipt(_ result: ProxyFallbackRevertResult, proxyName: String) -> ProxyFallbackNotice {
        let reverted = result.revertedIDs.count, skipped = result.skipped.count, failed = result.failed.count
        var parts: [String] = []
        if reverted > 0 || (skipped == 0 && failed == 0) { parts.append(revertedText(reverted, proxyName: proxyName)) }
        if skipped > 0 { parts.append("\(skipped) 个已不在回退状态，已跳过") }
        if failed > 0 { parts.append("\(failed) 个没有恢复") }
        let tone: Tone = failed > 0 ? (reverted > 0 ? .caution : .critical) : (reverted > 0 ? .ok : .neutral)
        return ProxyFallbackNotice(text: parts.joined(separator: " · "), tone: tone)
    }
    /// R11: fixed words per code; an unknown well-formed code is named, anything else (the server's unclassified errors come with
    /// an empty code) gets one sentence.
    public static func failureText(code: String?) -> String {
        let code = code ?? ""
        switch code {
        case AccountWriteReason.notFound, "RESOURCE_NOT_FOUND": return "账号不存在或已删除"
        case ProxyReason.fallbackOriginUnavailable: return "原代理已过期或已停用"
        case _ where ProxyFallbackRevertResult.skippedCodes.contains(code): return "已不在回退状态"
        case _ where isWellFormed(code): return "没有恢复（错误码 \(code)）"
        default: return "服务器没能恢复这个账号"
        }
    }
    /// `failed` in order; `stillListed` is the list read after the revert (nil when that read failed).
    public static func failureLines(_ result: ProxyFallbackRevertResult, names: [Int: String], stillListed: Set<Int>?) -> [ProxyFallbackFailureLine] {
        result.failed.map { item in
            let name = names[item.id] ?? "账号 #\(item.id)"
            if let stillListed, !stillListed.contains(item.id) {
                return ProxyFallbackFailureLine(id: item.id, name: name, reason: maybeReverted, tone: .caution)
            }
            return ProxyFallbackFailureLine(id: item.id, name: name, reason: failureText(code: item.code), tone: .critical)
        }
    }
    /// 409 PROXY_FALLBACK_ORIGIN_UNAVAILABLE: the proxy was stopped or expired before the revert reached it.
    public static func isOriginUnavailable(_ error: any Error) -> Bool {
        guard let api = error as? APIError else { return false }
        return api.statusCode == 409 && api.reason == ProxyReason.fallbackOriginUnavailable
    }
    /// `reason` is the error's catalog text.
    public static func rejectedText(_ reason: String) -> String { "恢复没有成功：" + reason }
    public static func readback(targets: [Int], remaining: [ProxyFallbackAccount]) -> ProxyFallbackReadback {
        let listed = Set(remaining.map(\.id))
        let still = Set(targets).intersection(listed).count
        return still == 0 ? .confirmed(Set(targets).count) : .remaining(still)
    }
    public static func readbackReceipt(_ readback: ProxyFallbackReadback, proxyName: String) -> ProxyFallbackNotice {
        switch readback {
        case .confirmed(let count): ProxyFallbackNotice(text: revertedText(count, proxyName: proxyName), tone: .ok)
        case .remaining(let count): ProxyFallbackNotice(text: "恢复结果未确认 · 还有 \(count) 个没有恢复", tone: .caution)
        }
    }

    private static func revertedText(_ count: Int, proxyName: String) -> String { "已恢复 \(count) 个账号到 \(proxyName)" }
    private static func currentRoute(_ account: ProxyFallbackAccount) -> String {
        guard let current = account.currentProxyID else { return "直连" }
        let name = account.currentProxyName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "备用 " + (name.isEmpty ? "#\(current)" : name)
    }
    private static func isWellFormed(_ code: String) -> Bool {
        let scalars = code.unicodeScalars
        return (1...64).contains(scalars.count) && scalars.allSatisfy { ("A"..."Z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
    }
}
