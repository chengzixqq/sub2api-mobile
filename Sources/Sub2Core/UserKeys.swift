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

/// 30 §7.2: one end-user API key, also the group key page's row (50 §6.7). The plaintext `key` is never kept (30 §7.7): it is
/// read into a local only to derive the mask when an older server sends no `key_masked`, then dropped.
public struct AdminAPIKey: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let userID: Int?
    /// "sk-…3f9a"; "" marks a deleted key (tombstone); nil when the reply carried neither `key_masked` nor `key`.
    public let keyMasked: String?
    /// The stored value, HTML-escaped by the server; pages show `displayName`.
    public let name: String
    public let groupID: Int?
    public let status: String
    public let effectiveStatus: String?
    public let ipWhitelist: [String]
    public let ipBlacklist: [String]
    public let lastUsedAt: Date?
    public let lastUsedIP: String?
    /// 0 = unlimited.
    public let quota: Decimal
    public let quotaUsed: Decimal
    public let expiresAt: Date?
    /// Meaningful only with `api_keys.current_concurrency`; the server reports 0 when it cannot read it.
    public let currentConcurrency: Int?
    /// 0 = unlimited.
    public let rateLimit5h: Decimal
    public let rateLimit1d: Decimal
    public let rateLimit7d: Decimal
    public let usage5h: Decimal
    public let usage1d: Decimal
    public let usage7d: Decimal
    /// Left out while a window has not started or has expired.
    public let reset5hAt: Date?
    public let reset1dAt: Date?
    public let reset7dAt: Date?
    public let createdAt: Date?
    public let updatedAt: Date?
    public let user: AdminUserSummary?

    public init(id: Int, userID: Int? = nil, keyMasked: String? = nil, name: String = "", groupID: Int? = nil, status: String = "active",
                effectiveStatus: String? = nil, ipWhitelist: [String] = [], ipBlacklist: [String] = [], lastUsedAt: Date? = nil,
                lastUsedIP: String? = nil, quota: Decimal = 0, quotaUsed: Decimal = 0, expiresAt: Date? = nil, currentConcurrency: Int? = nil,
                rateLimit5h: Decimal = 0, rateLimit1d: Decimal = 0, rateLimit7d: Decimal = 0, usage5h: Decimal = 0, usage1d: Decimal = 0,
                usage7d: Decimal = 0, reset5hAt: Date? = nil, reset1dAt: Date? = nil, reset7dAt: Date? = nil, createdAt: Date? = nil,
                updatedAt: Date? = nil, user: AdminUserSummary? = nil) {
        self.id = id; self.userID = userID; self.keyMasked = keyMasked; self.name = name; self.groupID = groupID; self.status = status
        self.effectiveStatus = effectiveStatus; self.ipWhitelist = ipWhitelist; self.ipBlacklist = ipBlacklist
        self.lastUsedAt = lastUsedAt; self.lastUsedIP = lastUsedIP; self.quota = quota; self.quotaUsed = quotaUsed; self.expiresAt = expiresAt
        self.currentConcurrency = currentConcurrency; self.rateLimit5h = rateLimit5h; self.rateLimit1d = rateLimit1d; self.rateLimit7d = rateLimit7d
        self.usage5h = usage5h; self.usage1d = usage1d; self.usage7d = usage7d; self.reset5hAt = reset5hAt; self.reset1dAt = reset1dAt
        self.reset7dAt = reset7dAt; self.createdAt = createdAt; self.updatedAt = updatedAt; self.user = user
    }

    enum CodingKeys: String, CodingKey {
        case id, key, name, status, quota, user
        case userID = "user_id", keyMasked = "key_masked", groupID = "group_id", effectiveStatus = "effective_status"
        case ipWhitelist = "ip_whitelist", ipBlacklist = "ip_blacklist", lastUsedAt = "last_used_at", lastUsedIP = "last_used_ip"
        case quotaUsed = "quota_used", expiresAt = "expires_at", currentConcurrency = "current_concurrency"
        case rateLimit5h = "rate_limit_5h", rateLimit1d = "rate_limit_1d", rateLimit7d = "rate_limit_7d"
        case usage5h = "usage_5h", usage1d = "usage_1d", usage7d = "usage_7d"
        case reset5hAt = "reset_5h_at", reset1dAt = "reset_1d_at", reset7dAt = "reset_7d_at", createdAt = "created_at", updatedAt = "updated_at"
    }
    /// `id` is required and amounts are strict like a balance (a malformed one fails the reply, a missing one is 0); any other
    /// field that is missing or malformed reads as empty.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func text(_ key: CodingKeys) -> String? { try? c.decodeIfPresent(String.self, forKey: key) }
        func number(_ key: CodingKeys) -> Int? { try? c.decodeIfPresent(Int.self, forKey: key) }
        func amount(_ key: CodingKeys) throws -> Decimal { try c.optionalDecimal(key) ?? 0 }
        func time(_ key: CodingKeys) -> Date? { try? c.optionalTimestamp(key) }
        func list(_ key: CodingKeys) -> [String] { (try? c.decodeIfPresent(LossyList<String>.self, forKey: key))?.items ?? [] }
        self.init(id: try c.decode(Int.self, forKey: .id), userID: number(.userID),
                  keyMasked: text(.keyMasked) ?? text(.key).map(Self.localMask), name: text(.name) ?? "", groupID: number(.groupID),
                  status: text(.status) ?? "", effectiveStatus: text(.effectiveStatus), ipWhitelist: list(.ipWhitelist),
                  ipBlacklist: list(.ipBlacklist), lastUsedAt: time(.lastUsedAt), lastUsedIP: text(.lastUsedIP),
                  quota: try amount(.quota), quotaUsed: try amount(.quotaUsed), expiresAt: time(.expiresAt),
                  currentConcurrency: number(.currentConcurrency), rateLimit5h: try amount(.rateLimit5h),
                  rateLimit1d: try amount(.rateLimit1d), rateLimit7d: try amount(.rateLimit7d), usage5h: try amount(.usage5h),
                  usage1d: try amount(.usage1d), usage7d: try amount(.usage7d), reset5hAt: time(.reset5hAt), reset1dAt: time(.reset1dAt),
                  reset7dAt: time(.reset7dAt), createdAt: time(.createdAt), updatedAt: time(.updatedAt),
                  user: try? c.decodeIfPresent(AdminUserSummary.self, forKey: .user))
    }

    /// List reads drop tombstones; a single read of a deleted key answers 404 API_KEY_NOT_FOUND, so there it is only a guard.
    public var isTombstone: Bool { keyMasked?.isEmpty == true }
    /// S3D1-12: cards, receipts, confirmations and forms show this; `name` stays the server's value for comparing a read-back.
    public var displayName: String { UserKeyName.unescaped(name) }
    /// The run mode does not change the status, only its badge and whether it counts as active (AdminAPIKeyStatus).
    public func status(now: Date) -> AdminAPIKeyStatus {
        AdminAPIKeyStatus.resolve(effectiveStatus: effectiveStatus, status: status, expiresAt: expiresAt, quota: quota, quotaUsed: quotaUsed, now: now)
    }
    /// Backend `dto.MaskAPIKey`: the first 3 and last 4 runes around "…", "…" for 7 runes or fewer, "" for an empty or
    /// `__deleted__` tombstone value.
    static func localMask(_ key: String) -> String {
        guard !key.isEmpty, !key.hasPrefix("__deleted__") else { return "" }
        let runes = Array(key.unicodeScalars)
        guard runes.count > 7 else { return "…" }
        return String(String.UnicodeScalarView(runes.prefix(3))) + "…" + String(String.UnicodeScalarView(runes.suffix(4)))
    }
}

/// Go `html.EscapeString` and its exact inverse for the five characters it replaces (S3D1-12). Key names are stored
/// escaped; a write-back sends the unescaped name and the server escapes it again.
public enum UserKeyName {
    private static let entities: [(entity: String, scalar: Unicode.Scalar)] = [
        ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&#39;", "'"), ("&#34;", "\""),
    ]
    public static func escaped(_ name: String) -> String {
        var result = String.UnicodeScalarView()
        for scalar in name.unicodeScalars {
            if let entity = entities.first(where: { $0.scalar == scalar })?.entity { result.append(contentsOf: entity.unicodeScalars) }
            else { result.append(scalar) }
        }
        return String(result)
    }
    /// Only the five entities above; any other (`&nbsp;`, `&copy;`) stays as stored.
    public static func unescaped(_ stored: String) -> String {
        guard stored.contains("&") else { return stored }
        var rest = Substring(stored).unicodeScalars, result = String.UnicodeScalarView()
        while let first = rest.first {
            if first == "&", let match = entities.first(where: { rest.starts(with: $0.entity.unicodeScalars) }) {
                result.append(match.scalar); rest = rest.dropFirst(match.entity.unicodeScalars.count)
            } else {
                result.append(first); rest = rest.dropFirst()
            }
        }
        return String(result)
    }
}
