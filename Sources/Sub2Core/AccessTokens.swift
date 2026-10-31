import Foundation

/// One entry of `GET /api/v1/admin/access-tokens` (00 §1.3). Times stay raw strings until they are displayed.
public struct AdminAccessToken: Identifiable, Decodable, Sendable, Equatable {
    public let id: Int
    public let name: String?
    public let prefix: String?
    public let last4: String?
    public let scope: String?
    public let expiresAt: String?
    public let lastUsedAt: String?
    public let lastUsedIP: String?
    public let createdAt: String?
    /// The token that authenticated this request.
    public let current: Bool
    public var isReadOnly: Bool { Self.isReadOnly(scope: scope) }
    /// Backend `ReadOnly()` is anything but "write". An unknown scope counts as writable until the server
    /// answers `ACCESS_TOKEN_READ_ONLY` (00 §1.6).
    public static func isReadOnly(scope: String?) -> Bool { scope.map { $0 != "write" } ?? false }

    enum CodingKeys: String, CodingKey {
        case id, name, prefix, last4, scope, current
        case expiresAt = "expires_at", lastUsedAt = "last_used_at", lastUsedIP = "last_used_ip", createdAt = "created_at"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name); prefix = try c.decodeIfPresent(String.self, forKey: .prefix)
        last4 = try c.decodeIfPresent(String.self, forKey: .last4); scope = try c.decodeIfPresent(String.self, forKey: .scope)
        expiresAt = try c.decodeIfPresent(String.self, forKey: .expiresAt); lastUsedAt = try c.decodeIfPresent(String.self, forKey: .lastUsedAt)
        lastUsedIP = try c.decodeIfPresent(String.self, forKey: .lastUsedIP); createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        current = try c.decodeIfPresent(Bool.self, forKey: .current) ?? false
    }
    public init(id: Int, name: String? = nil, prefix: String? = nil, last4: String? = nil, scope: String? = nil, expiresAt: String? = nil,
                lastUsedAt: String? = nil, lastUsedIP: String? = nil, createdAt: String? = nil, current: Bool = false) {
        self.id = id; self.name = name; self.prefix = prefix; self.last4 = last4; self.scope = scope; self.expiresAt = expiresAt
        self.lastUsedAt = lastUsedAt; self.lastUsedIP = lastUsedIP; self.createdAt = createdAt; self.current = current
    }
}

extension APIClient {
    /// The caller's own tokens; the list is `{items}`, not a paged envelope.
    public func accessTokens() async throws -> [AdminAccessToken] {
        let reply: AccessTokenList = try await request("admin/access-tokens", timeout: RequestTimeout.probe)
        return reply.items ?? []
    }
    /// `true` when the revoked token is the one this App signs in with (60 §6.4); a read-only token may revoke itself.
    @discardableResult
    public func revokeAccessToken(id: Int) async throws -> Bool {
        let reply: RevocationReply = try await request("admin/access-tokens/\(validID(id))", method: "DELETE", timeout: RequestTimeout.probe)
        return reply.current ?? false
    }
}

private struct AccessTokenList: Decodable, Sendable { let items: [AdminAccessToken]? }

// MARK: Presentation (60 §6.3–§6.5)

extension AdminAccessToken {
    public static let intro = "访问令牌以签发它的管理员身份调用管理接口，可只读、会过期、能单独吊销。比 Admin Key 安全：Admin Key 以第一个管理员身份操作，丢了只能到 Web 重新生成。"
    public static let currentBadgeText = "本机"
    /// U02: the App lists and revokes tokens but never issues one.
    public static let emptyTitle = "还没有访问令牌"
    public static let emptyMessage = "首版 App 不签发访问令牌。"
    public static let revokeActionTitle = "吊销"
    public static func revokedReceipt(_ name: String) -> String { "已吊销「\(name)」" }

    public var displayName: String { Self.trimmed(name) ?? "未命名令牌" }
    /// “sat_3f9a…c71e”, shown monospaced; the backend's prefix is `sat_` and the first four hex digits.
    public var maskedText: String { (Self.trimmed(prefix) ?? "sat_") + "…" + (Self.trimmed(last4) ?? "") }
    /// The same rule as `isReadOnly`: an unknown scope reads 只读.
    public var scopeTitle: String { isReadOnly ? "只读" : "读写" }
    public var scopeTone: Tone { isReadOnly ? .neutral : .caution }

    /// “最近使用 3 分钟前 · 203.0.113.24”: `now` is the site's clock, the day boundary the server's zone (00 §6.3). The server
    /// writes the time at most every five minutes.
    public func usageLine(now: Date, timeZone: ServerTimeZone) -> String {
        guard let used = Self.date(lastUsedAt) else { return "从未使用" }
        let line = "最近使用 " + DisplayFormat.relativeTime(used, now: now, timeZone: timeZone.timeZone)
        return Self.trimmed(lastUsedIP).map { line + " · " + $0 } ?? line
    }
    /// Server calendar days from today to the expiry day; nil without a readable expiry.
    public func daysLeft(now: Date, timeZone: ServerTimeZone) -> Int? {
        guard let expires = Self.date(expiresAt) else { return nil }
        let calendar = timeZone.calendar
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: expires)).day
    }
    /// “2027/01/16 到期 · 还剩 87 天”; the expiry day itself is “今天到期”.
    public func expiryLine(now: Date, timeZone: ServerTimeZone) -> String {
        guard let expires = Self.date(expiresAt), let days = daysLeft(now: now, timeZone: timeZone) else { return DisplayFormat.missing }
        return days <= 0 ? "今天到期" : Self.day(expires, timeZone: timeZone) + " 到期 · 还剩 \(days) 天"
    }
    /// Seven days or less draws the expiry in caution (60 §6.3).
    public func isExpiringSoon(now: Date, timeZone: ServerTimeZone) -> Bool { daysLeft(now: now, timeZone: timeZone).map { $0 <= 7 } ?? false }

    public var revokeTitle: String { "吊销「\(displayName)」？" }
    /// 60 §6.4; revoking this App's own token also ends the session here.
    public var revokeMessage: String {
        let message = "用它的设备或脚本会失去访问（其他服务器实例最多 30 秒后生效）。"
        return current ? message + "\n本机会退出这个站点。" : message
    }

    /// Go's zero time would read as a date long gone; it counts as missing.
    private static func date(_ raw: String?) -> Date? {
        guard let date = ServerTime.parseTimestamp(raw), date.timeIntervalSince1970 > 0 else { return nil }
        return date
    }
    private static func trimmed(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
    /// yyyy/MM/dd in the server's zone; S6-26 moves this to the shared date formats (S6D1-16).
    private static func day(_ date: Date, timeZone: ServerTimeZone) -> String {
        let parts = timeZone.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d/%02d/%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
