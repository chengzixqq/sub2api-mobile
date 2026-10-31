import Foundation

// 60 §12.3, §13.3 and §13.4: what the proxy list and detail show. `now` is the site clock and `timeZone` the server's (R20); the
// expiry word itself is ProxyExpiry (S2-11).

/// The list's capsules; the raw value is the `.proxies(filter:)` route value.
public enum ProxyFilter: String, Sendable, CaseIterable {
    case all, expired, soon, failed, inactive
    public var title: String {
        switch self {
        case .all: "全部"
        case .expired: "已过期"
        case .soon: "即将到期"
        case .failed: "链接失败"
        case .inactive: "停用"
        }
    }
    /// nil or an unknown value is 全部.
    public init(routeValue: String?) { self = routeValue.flatMap(Self.init(rawValue:)) ?? .all }
}

public struct ProxyFilterChip: Sendable, Equatable, Identifiable {
    public let filter: ProxyFilter
    public let title: String
    public let count: Int
    /// Only 已过期, while an expired proxy still carries accounts.
    public let showsDot: Bool
    public var id: ProxyFilter { filter }
}

public struct ProxyBadge: Sendable, Equatable {
    public let text: String
    public let tone: Tone
    public init(text: String, tone: Tone) { self.text = text; self.tone = tone }
}

/// The expiry banner above the capsules (only under 全部); “查看” switches to `target`.
public struct ProxyBanner: Sendable, Equatable {
    public static let actionTitle = "查看"
    public let title: String
    public let detail: String
    public let tone: Tone
    public let target: ProxyFilter
    public let proxyIDs: [Int]
    public init(title: String, detail: String, tone: Tone, target: ProxyFilter, proxyIDs: [Int]) {
        self.title = title; self.detail = detail; self.tone = tone; self.target = target; self.proxyIDs = proxyIDs
    }
}

/// The row's leading glyph: normal, error, grey (stopped, or expired with nothing on it) and the neutral dot of “未测试”.
public enum ProxyGlyph: Sendable, Equatable { case normal, error, idle, untested }
/// The row's right side: “测试中”, the status badge of a proxy that is not active, “182ms”, the critical “链接失败” badge, or the
/// grey “未测试”.
public enum ProxyRowTrailing: Sendable, Equatable { case testing, status(ProxyBadge), latency(String), linkFailed, untested }

public struct ProxyRowContent: Sendable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    /// Monospaced “SOCKS5 · 203.0.113.24:1080”.
    public let address: String
    /// The status capsule; nil draws none.
    public let tone: Tone?
    public let glyph: ProxyGlyph
    public let trailing: ProxyRowTrailing
    public let footnote: String
    /// The caution expiry word of a proxy about to expire.
    public let expiryBadge: ProxyBadge?
    /// Expired, still in use and its last probe failed.
    public let showsLinkFailedBadge: Bool
    public let isDimmed: Bool
}

/// The detail's latency block (13.3).
public enum ProxyLatencyReading: Sendable, Equatable {
    case testing
    /// “182” “ms”, or “2.0” “s” from a second; `needle` is the 0–500ms scale position in 0…1; `lastTested` “上次测试 10/16 09:12”.
    case success(value: String, unit: String, needle: Double, lastTested: String?)
    /// “链接失败” and `latency_message`: a probe result, shown monospaced (not an error envelope's message).
    case failed(message: String?)
    /// “— 还没测试过”.
    case untested
}

public struct ProxyStatusCard: Sendable, Equatable {
    public let badge: ProxyBadge
    public let cause: String?
    /// A critical card: the link failed while the proxy is active or carries accounts.
    public let isCritical: Bool
    public init(badge: ProxyBadge, cause: String?, isCritical: Bool) { self.badge = badge; self.cause = cause; self.isCritical = isCritical }
}

/// The three fact cells: exit IP, region and quality, with the quality's MM/DD beside its label.
public struct ProxyFacts: Sendable, Equatable {
    public let exitIP: String
    public let exitIPIsMonospaced: Bool
    public let region: String
    public let quality: String
    public let qualityDate: String?
    public init(exitIP: String, exitIPIsMonospaced: Bool, region: String, quality: String, qualityDate: String?) {
        self.exitIP = exitIP; self.exitIPIsMonospaced = exitIPIsMonospaced; self.region = region; self.quality = quality; self.qualityDate = qualityDate
    }
}

/// 壹 有效期's sentence; without one the section shows 剩余 and 到期回退.
public struct ProxyExpiryNote: Sendable, Equatable {
    public let tone: Tone
    public let text: String
    public init(tone: Tone, text: String) { self.tone = tone; self.text = text }
}

/// 13.4 删除: accounts on it come first, then accounts moved off it that could not be restored after the delete.
public enum ProxyDeleteRestriction: Sendable, Equatable { case allowed, hasAccounts(Int), hasFallbackAccounts(Int) }

public enum ProxyPresentation {
    public static let latencyScaleMaxMs = 500
    public static let testingText = "测试中"
    public static let linkFailedText = "链接失败"
    public static let untestedText = "未测试"

    /// “SOCKS5 · 203.0.113.24:1080”, also the detail's subtitle and the ··· menu's line; an IPv6 host is bracketed.
    public static func addressLine(_ proxy: AdminProxy) -> String {
        [AccountProxyPresentation.protocolLabel(proxy.scheme), hostPort(proxy)].filter { !$0.isEmpty }.joined(separator: " · ")
    }
    /// 正常 ok, 停用 neutral, 已过期 critical while accounts still use it (neutral otherwise); another status as it came, neutral.
    public static func statusBadge(_ proxy: AdminProxy) -> ProxyBadge {
        switch currentStatus(proxy) {
        case "active": ProxyBadge(text: "正常", tone: .ok)
        case "inactive": ProxyBadge(text: "停用", tone: .neutral)
        case "expired": ProxyBadge(text: "已过期", tone: accountTotal(proxy) > 0 ? .critical : .neutral)
        case let other: ProxyBadge(text: other, tone: .neutral)
        }
    }
    /// “182ms”, “1.2s”.
    public static func latencyText(_ milliseconds: Int?) -> String? { milliseconds.map { DisplayFormat.duration($0, style: .millis) } }
    /// 链接失败: not stopped, the last probe failed, and active or still carrying accounts.
    public static func isLinkFailed(_ proxy: AdminProxy) -> Bool {
        let status = currentStatus(proxy)
        return status != "inactive" && proxy.latencyStatus == "failed" && (status == "active" || accountTotal(proxy) > 0)
    }
    /// The banner's rule: accounts still use it, and it expired or is active and about to.
    public static func needsCare(_ proxy: AdminProxy, now: Date, timeZone: ServerTimeZone) -> Bool {
        accountTotal(proxy) > 0 && (currentStatus(proxy) == "expired" || ProxyExpiry.describe(proxy, now: now, timeZone: timeZone).isSoon)
    }
    public static func matches(_ proxy: AdminProxy, filter: ProxyFilter, now: Date, timeZone: ServerTimeZone) -> Bool {
        switch filter {
        case .all: true
        case .expired: currentStatus(proxy) == "expired"
        case .soon: accountTotal(proxy) > 0 && ProxyExpiry.describe(proxy, now: now, timeZone: timeZone).isSoon
        case .failed: isLinkFailed(proxy)
        case .inactive: currentStatus(proxy) == "inactive"
        }
    }
    /// The five capsules in order, each with its count.
    public static func chips(_ proxies: [AdminProxy], now: Date, timeZone: ServerTimeZone) -> [ProxyFilterChip] {
        let stuck = proxies.contains { currentStatus($0) == "expired" && accountTotal($0) > 0 }
        return ProxyFilter.allCases.map { filter in
            ProxyFilterChip(filter: filter, title: filter.title, count: proxies.filter { matches($0, filter: filter, now: now, timeZone: timeZone) }.count,
                            showsDot: filter == .expired && stuck)
        }
    }
    /// Expired first, then by the days left; one proxy gets its own two lines, several a count and their short lines. Critical
    /// (and “查看” → 已过期) when one of them expired, otherwise caution (→ 即将到期).
    public static func banner(_ proxies: [AdminProxy], now: Date, timeZone: ServerTimeZone) -> ProxyBanner? {
        let hits = bannerOrder(proxies.filter { needsCare($0, now: now, timeZone: timeZone) }, now: now, timeZone: timeZone)
        guard let first = hits.first else { return nil }
        let lapsed = hits.contains { currentStatus($0) == "expired" }
        func word(_ proxy: AdminProxy) -> String { ProxyExpiry.describe(proxy, now: now, timeZone: timeZone).text }
        let title: String, detail: String
        if hits.count == 1 {
            let count = accountTotal(first)
            title = currentStatus(first) == "expired" ? "\(displayName(first)) 已过期，仍有 \(count) 个账号在用" : "\(displayName(first)) \(word(first))，\(count) 个账号在用"
            detail = currentStatus(first) == "expired" ? "续期，或给这些账号换代理" : "到期前续期，或设置到期回退"
        } else {
            title = "\(hits.count) 个代理需要处理"
            detail = hits.map { currentStatus($0) == "expired" ? "\(displayName($0)) 已过期仍在用" : "\(displayName($0)) \(word($0))" }.joined(separator: " · ")
        }
        return ProxyBanner(title: title, detail: detail, tone: lapsed ? .critical : .caution, target: lapsed ? .expired : .soon, proxyIDs: hits.map(\.id))
    }
    public static func row(_ proxy: AdminProxy, now: Date, timeZone: ServerTimeZone, isTesting: Bool = false) -> ProxyRowContent {
        let word = ProxyExpiry.describe(proxy, now: now, timeZone: timeZone)
        let status = currentStatus(proxy), count = accountTotal(proxy)
        return ProxyRowContent(id: proxy.id, title: displayName(proxy), address: addressLine(proxy), tone: rowTone(proxy, word: word),
                               glyph: glyph(proxy), trailing: trailing(proxy, isTesting: isTesting), footnote: footnote(proxy, timeZone: timeZone),
                               expiryBadge: word.isSoon ? ProxyBadge(text: word.text, tone: .caution) : nil,
                               showsLinkFailedBadge: status == "expired" && count > 0 && proxy.latencyStatus == "failed",
                               isDimmed: status == "inactive" || (status == "expired" && count == 0))
    }
    /// Over 500ms the needle stays at the right end; ink only, latency has no status colour.
    public static func latency(_ proxy: AdminProxy, isTesting: Bool, now: Date, timeZone: ServerTimeZone) -> ProxyLatencyReading {
        if isTesting { return .testing }
        switch proxy.latencyStatus ?? "" {
        case "success":
            guard let milliseconds = proxy.latencyMs, milliseconds >= 0, let text = latencyText(milliseconds) else { return .untested }
            let unit = text.hasSuffix("ms") ? "ms" : "s"
            let needle = Double(min(milliseconds, latencyScaleMaxMs)) / Double(latencyScaleMaxMs)
            let tested = proxy.latencyCheckedAt.map { "上次测试 " + DisplayFormat.monthDayClock($0, timeZone: timeZone, now: now) }
            return .success(value: String(text.dropLast(unit.count)), unit: unit, needle: needle, lastTested: tested)
        case "failed": return .failed(message: nonEmpty(proxy.latencyMessage))
        default: return .untested
        }
    }
    /// `justTestedAt` is this session's test result `checked_at` (“刚刚测试 09:41”).
    public static func statusCard(_ proxy: AdminProxy, isTesting: Bool, justTestedAt: Date?, timeZone: ServerTimeZone) -> ProxyStatusCard {
        let cause: String?
        if isTesting { cause = "正在测试连通性" }
        else if let justTestedAt { cause = "刚刚测试 " + DisplayFormat.clock(justTestedAt, timeZone: timeZone.timeZone) }
        else if currentStatus(proxy) == "inactive" { cause = accountTotal(proxy) > 0 ? "在用的账号不受影响" : "账号编辑里选不到它" }
        else { cause = nil }
        return ProxyStatusCard(badge: statusBadge(proxy), cause: cause, isCritical: isLinkFailed(proxy))
    }
    /// Exit IP (monospaced), region (as the row), quality “A · 92” with `quality_checked`'s MM/DD; “检测中…” while checking.
    public static func facts(_ proxy: AdminProxy, isCheckingQuality: Bool, timeZone: ServerTimeZone) -> ProxyFacts {
        let exitIP = nonEmpty(proxy.ipAddress)
        let quality = [nonEmpty(proxy.qualityGrade), proxy.qualityScore.map(String.init)].compactMap { $0 }.joined(separator: " · ")
        let date = quality.isEmpty || isCheckingQuality ? nil : proxy.qualityChecked.map { ProxyExpiry.monthDay($0, timeZone: timeZone) }
        return ProxyFacts(exitIP: exitIP ?? DisplayFormat.missing, exitIPIsMonospaced: exitIP != nil, region: proxy.regionText ?? DisplayFormat.missing,
                          quality: isCheckingQuality ? "检测中…" : quality.isEmpty ? DisplayFormat.missing : quality, qualityDate: date)
    }
    /// 13.3's sentence table, first match wins. `backupName` is the backup's name from the list cache; `supportsFallbackAccounts`
    /// is `proxies.fallback_accounts`. nil: the section shows 剩余 and 到期回退 instead.
    public static func expiryNote(_ proxy: AdminProxy, backupName: String?, supportsFallbackAccounts: Bool, now: Date,
                                  timeZone: ServerTimeZone) -> ProxyExpiryNote? {
        let mode = ProxyFallbackMode(rawValue: proxy.fallbackMode ?? "") ?? ProxyFallbackMode.none
        let target = fallbackTarget(mode, backupName: backupName)
        switch currentStatus(proxy) {
        case "expired": return expiredNote(proxy, mode: mode, target: target, supportsFallbackAccounts: supportsFallbackAccounts)
        case "active": return activeNote(proxy, mode: mode, target: target, now: now, timeZone: timeZone)
        default: return nil
        }
    }
    /// `protocol://[user[:pass]@]host:port`, as the Web copies it: username and password percent-encoded to RFC 3986 unreserved
    /// characters, “:pass@” with only a password. It carries the password: SensitivePasteboard only, never a log or a receipt.
    /// nil without a scheme or host.
    public static func copyURL(_ proxy: AdminProxy) -> String? {
        let scheme = proxy.scheme.trimmingCharacters(in: .whitespacesAndNewlines), target = hostPort(proxy)
        guard !scheme.isEmpty, !target.isEmpty else { return nil }
        let user = AccountWebLink.queryValue(proxy.username ?? ""), pass = AccountWebLink.queryValue(proxy.password ?? "")
        let auth = pass.isEmpty ? (user.isEmpty ? "" : user + "@") : user + ":" + pass + "@"
        return "\(scheme)://\(auth)\(target)"
    }
    public static func deleteRestriction(_ proxy: AdminProxy) -> ProxyDeleteRestriction {
        let count = accountTotal(proxy)
        if count > 0 { return .hasAccounts(count) }
        if let moved = proxy.fallbackAccountCount, moved > 0 { return .hasFallbackAccounts(moved) }
        return .allowed
    }

    // MARK: - Pieces

    /// A missing status counts as active, as AdminProxy.isActive.
    private static func currentStatus(_ proxy: AdminProxy) -> String { proxy.status ?? "active" }
    private static func accountTotal(_ proxy: AdminProxy) -> Int { max(0, proxy.accountCount ?? 0) }
    /// The name, or “代理 #id” without one (also the detail's title and its receipts, S6-12).
    public static func displayName(_ proxy: AdminProxy) -> String {
        let name = proxy.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "代理 #\(proxy.id)" : name
    }
    private static func nonEmpty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
    /// “203.0.113.24:1080”, “[2001:db8::1]:1080”; empty without a host.
    private static func hostPort(_ proxy: AdminProxy) -> String {
        let host = proxy.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return "" }
        let shown = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
        return proxy.port.map { "\(shown):\($0)" } ?? shown
    }
    /// Expired first, then fewer days left (no expiry last); ties keep the list's order.
    private static func bannerOrder(_ proxies: [AdminProxy], now: Date, timeZone: ServerTimeZone) -> [AdminProxy] {
        func rank(_ proxy: AdminProxy) -> (Int, Int) {
            (currentStatus(proxy) == "expired" ? 0 : 1, proxy.expiresAt.map { ProxyExpiry.days(until: $0, now: now, timeZone: timeZone) } ?? .max)
        }
        return proxies.enumerated().sorted { lhs, rhs in
            let left = rank(lhs.element), right = rank(rhs.element)
            return left != right ? left < right : lhs.offset < rhs.offset
        }.map(\.element)
    }
    private static func rowTone(_ proxy: AdminProxy, word: ProxyExpiryWord) -> Tone? {
        switch currentStatus(proxy) {
        case "inactive": nil
        case "expired": accountTotal(proxy) > 0 ? .critical : nil
        default: isLinkFailed(proxy) ? .critical : word.isSoon ? .caution : nil
        }
    }
    private static func glyph(_ proxy: AdminProxy) -> ProxyGlyph {
        switch currentStatus(proxy) {
        case "inactive": return .idle
        case "expired": return accountTotal(proxy) > 0 ? .error : .idle
        default:
            switch proxy.latencyStatus ?? "" {
            case "failed": return .error
            case "success": return .normal
            default: return .untested
            }
        }
    }
    private static func trailing(_ proxy: AdminProxy, isTesting: Bool) -> ProxyRowTrailing {
        if isTesting { return .testing }
        guard currentStatus(proxy) == "active" else { return .status(statusBadge(proxy)) }
        switch proxy.latencyStatus ?? "" {
        case "success": return latencyText(proxy.latencyMs).map(ProxyRowTrailing.latency) ?? .untested
        case "failed": return .linkFailed
        default: return .untested
        }
    }
    /// “3 个账号在用 · 中国香港”; expired “1 个账号仍在用 · 10/13 到期”; a stopped proxy without the place.
    private static func footnote(_ proxy: AdminProxy, timeZone: ServerTimeZone) -> String {
        let count = accountTotal(proxy)
        let usage = count > 0 ? "\(count) 个账号在用" : "没有账号在用"
        switch currentStatus(proxy) {
        case "expired":
            let due = proxy.expiresAt.map { ProxyExpiry.monthDay($0, timeZone: timeZone) + " 到期" }
            return [count > 0 ? "\(count) 个账号仍在用" : usage, due].compactMap { $0 }.joined(separator: " · ")
        case "inactive": return usage
        default: return [usage, proxy.regionText].compactMap { $0 }.joined(separator: " · ")
        }
    }
    /// “直连”, “备用 sg‑01” (a non-breaking hyphen, so the name never wraps there) or “备用代理”.
    private static func fallbackTarget(_ mode: ProxyFallbackMode, backupName: String?) -> String {
        if mode == .direct { return "直连" }
        guard let name = nonEmpty(backupName) else { return "备用代理" }
        return "备用 " + name.replacingOccurrences(of: "-", with: "\u{2011}")
    }
    private static let manualRestore = "要改回来，在账号详情里点“恢复原代理”。"
    /// Rows 1–4. Without `fallback_account_count` (before H03) an expired proxy with nothing on it whose fallback moves accounts says
    /// so without a number.
    private static func expiredNote(_ proxy: AdminProxy, mode: ProxyFallbackMode, target: String, supportsFallbackAccounts: Bool) -> ProxyExpiryNote {
        let count = accountTotal(proxy)
        if count > 0 {
            let tail = mode == ProxyFallbackMode.none ? "到期回退设的是“不回退”，所以账号没被改走；续期，或到账号编辑页换代理。" : "续期，或到账号编辑页换代理。"
            return ProxyExpiryNote(tone: .critical, text: "已过期，\(count) 个账号仍在用这个代理。" + tail)
        }
        if let moved = proxy.fallbackAccountCount, moved > 0 {
            let restore = supportsFallbackAccounts ? "续期并启用后，可以在“被改走的账号”里一键恢复。" : manualRestore
            return ProxyExpiryNote(tone: .neutral, text: "到期后已把 \(moved) 个账号改为\(target)。" + restore)
        }
        if proxy.fallbackAccountCount == nil, mode != ProxyFallbackMode.none {
            return ProxyExpiryNote(tone: .neutral, text: "到期后已把在用的账号改为\(target)。" + manualRestore)
        }
        return ProxyExpiryNote(tone: .neutral, text: "已过期，没有账号在用。")
    }
    /// Rows 5–7: accounts moved off it and not restored yet, then the expiry soon.
    private static func activeNote(_ proxy: AdminProxy, mode: ProxyFallbackMode, target: String, now: Date, timeZone: ServerTimeZone) -> ProxyExpiryNote? {
        if let moved = proxy.fallbackAccountCount, moved > 0 {
            return ProxyExpiryNote(tone: .caution, text: "\(moved) 个账号在本代理到期时被改走，还没恢复。")
        }
        let word = ProxyExpiry.describe(proxy, now: now, timeZone: timeZone)
        guard word.isSoon else { return nil }
        guard mode == ProxyFallbackMode.none else { return ProxyExpiryNote(tone: .caution, text: "\(word.text)。到期后把在用的账号改为\(target)。") }
        let count = accountTotal(proxy)
        let tail = count > 0 ? "，在用的 \(count) 个账号会继续挂在这个过期代理上" : ""
        return ProxyExpiryNote(tone: .caution, text: "\(word.text)。到期后不回退\(tail)。")
    }
}
