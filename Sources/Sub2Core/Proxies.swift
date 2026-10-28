import Foundation

// R19 / X12: the App's one proxy file. S2-11 made AdminProxy, ProxyExpiry and allProxies(withCount:); S6-10 adds the rest here
// without changing them.

/// 60 §12.2 (`dto.AdminProxyWithAccountCount`): one proxy of `proxies/all` and of the proxy list. Only `id` is required; a field
/// of an odd type reads as absent. `password` arrives in the clear: it stays in memory, is never encoded, and every description
/// writes <redacted> in its place.
public struct AdminProxy: Decodable, Sendable, Identifiable, Equatable {
    public let id: Int
    public let name: String
    /// JSON `protocol`: http / https / socks5 / socks5h.
    public let scheme: String
    public let host: String
    public let port: Int?
    public let username: String?
    public let password: String?
    /// active / inactive / expired.
    public let status: String?
    public let createdAt: Date?
    public let updatedAt: Date?
    /// nil: never expires.
    public let expiresAt: Date?
    /// none / proxy / direct.
    public let fallbackMode: String?
    public let backupProxyID: Int?
    public let expiryWarnDays: Int?
    public let accountCount: Int?
    /// `account_count` was in the reply (H02: a list read without counts has none).
    public let hasAccountCountKey: Bool
    public let fallbackAccountCount: Int?
    public let latencyMs: Int?
    public let latencyStatus: String?
    public let latencyMessage: String?
    public let latencyCheckedAt: Date?
    public let ipAddress: String?
    public let country: String?
    public let countryCode: String?
    public let region: String?
    public let city: String?
    public let qualityStatus: String?
    public let qualityScore: Int?
    public let qualityGrade: String?
    public let qualitySummary: String?
    public let qualityChecked: Date?

    public init(id: Int, name: String, scheme: String = "", host: String = "", port: Int? = nil, username: String? = nil, password: String? = nil,
                status: String? = nil, createdAt: Date? = nil, updatedAt: Date? = nil, expiresAt: Date? = nil, fallbackMode: String? = nil,
                backupProxyID: Int? = nil, expiryWarnDays: Int? = nil, accountCount: Int? = nil, hasAccountCountKey: Bool = false,
                fallbackAccountCount: Int? = nil, latencyMs: Int? = nil, latencyStatus: String? = nil, latencyMessage: String? = nil,
                latencyCheckedAt: Date? = nil, ipAddress: String? = nil, country: String? = nil, countryCode: String? = nil, region: String? = nil,
                city: String? = nil, qualityStatus: String? = nil, qualityScore: Int? = nil, qualityGrade: String? = nil,
                qualitySummary: String? = nil, qualityChecked: Date? = nil) {
        self.id = id; self.name = name; self.scheme = scheme; self.host = host; self.port = port; self.username = username
        self.password = password; self.status = status; self.createdAt = createdAt; self.updatedAt = updatedAt; self.expiresAt = expiresAt
        self.fallbackMode = fallbackMode; self.backupProxyID = backupProxyID; self.expiryWarnDays = expiryWarnDays
        self.accountCount = accountCount; self.hasAccountCountKey = hasAccountCountKey; self.fallbackAccountCount = fallbackAccountCount
        self.latencyMs = latencyMs; self.latencyStatus = latencyStatus; self.latencyMessage = latencyMessage
        self.latencyCheckedAt = latencyCheckedAt; self.ipAddress = ipAddress; self.country = country; self.countryCode = countryCode
        self.region = region; self.city = city; self.qualityStatus = qualityStatus; self.qualityScore = qualityScore
        self.qualityGrade = qualityGrade; self.qualitySummary = qualitySummary; self.qualityChecked = qualityChecked
    }

    enum CodingKeys: String, CodingKey {
        case id, name, scheme = "protocol", host, port, username, password, status, createdAt = "created_at", updatedAt = "updated_at"
        case expiresAt = "expires_at", fallbackMode = "fallback_mode", backupProxyID = "backup_proxy_id", expiryWarnDays = "expiry_warn_days"
        case accountCount = "account_count", fallbackAccountCount = "fallback_account_count", latencyMs = "latency_ms"
        case latencyStatus = "latency_status", latencyMessage = "latency_message", latencyCheckedAt = "latency_checked_at"
        case ipAddress = "ip_address", country, countryCode = "country_code", region, city, qualityStatus = "quality_status"
        case qualityScore = "quality_score", qualityGrade = "quality_grade", qualitySummary = "quality_summary", qualityChecked = "quality_checked"
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys) -> T? { (try? c.decodeIfPresent(T.self, forKey: key)) ?? nil }
        func timestamp(_ key: CodingKeys) -> Date? { ServerTime.parseTimestamp(value(key)) }
        func unix(_ key: CodingKeys) -> Date? { ServerTime.date(unixSeconds: value(key)) }
        self.init(id: try c.decode(Int.self, forKey: .id), name: value(.name) ?? "", scheme: value(.scheme) ?? "", host: value(.host) ?? "",
                  port: value(.port), username: value(.username), password: value(.password), status: value(.status),
                  createdAt: timestamp(.createdAt), updatedAt: timestamp(.updatedAt), expiresAt: timestamp(.expiresAt),
                  fallbackMode: value(.fallbackMode), backupProxyID: value(.backupProxyID), expiryWarnDays: value(.expiryWarnDays),
                  accountCount: value(.accountCount), hasAccountCountKey: c.contains(.accountCount),
                  fallbackAccountCount: value(.fallbackAccountCount), latencyMs: value(.latencyMs), latencyStatus: value(.latencyStatus),
                  latencyMessage: value(.latencyMessage), latencyCheckedAt: unix(.latencyCheckedAt), ipAddress: value(.ipAddress),
                  country: value(.country), countryCode: value(.countryCode), region: value(.region), city: value(.city),
                  qualityStatus: value(.qualityStatus), qualityScore: value(.qualityScore), qualityGrade: value(.qualityGrade),
                  qualitySummary: value(.qualitySummary), qualityChecked: unix(.qualityChecked))
    }

    /// A missing status counts as active.
    public var isActive: Bool { (status ?? "active") == "active" }
    /// “socks5://203.0.113.24:1080”; without a port just scheme://host.
    public var address: String { port.map { "\(scheme)://\(host):\($0)" } ?? "\(scheme)://\(host)" }
    /// 60 §12.3: the country's Chinese name, then “ · city”; nil when neither is known.
    public var regionText: String? {
        let code = countryCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let place = city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let country = code.isEmpty ? "" : Locale(identifier: "zh_CN").localizedString(forRegionCode: code) ?? code
        let parts = [country, place].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

extension AdminProxy: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private var maskedPassword: String { password == nil ? "nil" : "<redacted>" }
    public var description: String { "AdminProxy(id: \(id), name: \(name), address: \(address), status: \(status ?? "nil"), password: \(maskedPassword))" }
    public var debugDescription: String { description }
    public var customMirror: Mirror {
        Mirror(self, children: ["id": id, "name": name, "address": address, "status": status as Any, "password": maskedPassword], displayStyle: .struct)
    }
}

/// 60 §12.3 `proxyExpiry`: the word and its tone; `kind` is the design's key.
public struct ProxyExpiryWord: Sendable, Equatable {
    public enum Kind: String, Sendable { case lapsed, never, idle, soon, ok }
    public let kind: Kind
    public let text: String
    /// lapsed critical, soon caution, otherwise none.
    public let tone: Tone?
    public var isSoon: Bool { kind == .soon }
    public init(kind: Kind, text: String, tone: Tone?) { self.kind = kind; self.text = text; self.tone = tone }
}

/// 60 §12.3: by whole days on the server's calendar. expired → “MM/DD 已过期”; no expiry → “永不过期”; not active → “MM/DD 到期”;
/// past due but not yet swept → “已到期 · 等待处理”; within the warning days → “今天到期” / “N 天后到期”; else “剩余 N 天”.
public enum ProxyExpiry {
    public static func describe(_ proxy: AdminProxy, now: Date, timeZone: ServerTimeZone) -> ProxyExpiryWord {
        describe(status: proxy.status, expiresAt: proxy.expiresAt, warnDays: proxy.expiryWarnDays, now: now, timeZone: timeZone)
    }
    /// The account DTO's proxy, whose `expires_at` is still the raw string.
    public static func describe(_ proxy: AccountProxy, now: Date, timeZone: ServerTimeZone) -> ProxyExpiryWord {
        describe(status: proxy.status, expiresAt: ServerTime.parseTimestamp(proxy.expiresAt), warnDays: proxy.expiryWarnDays, now: now, timeZone: timeZone)
    }
    public static func describe(status: String?, expiresAt: Date?, warnDays: Int?, now: Date, timeZone: ServerTimeZone) -> ProxyExpiryWord {
        if status == "expired" {
            return ProxyExpiryWord(kind: .lapsed, text: expiresAt.map { monthDay($0, timeZone: timeZone) + " 已过期" } ?? "已过期", tone: .critical)
        }
        guard let expiresAt else { return ProxyExpiryWord(kind: .never, text: "永不过期", tone: nil) }
        guard (status ?? "active") == "active" else {
            return ProxyExpiryWord(kind: .idle, text: monthDay(expiresAt, timeZone: timeZone) + " 到期", tone: nil)
        }
        let days = days(until: expiresAt, now: now, timeZone: timeZone)
        if days < 0 { return ProxyExpiryWord(kind: .soon, text: "已到期 · 等待处理", tone: .caution) }
        if days <= max(0, warnDays ?? 0) { return ProxyExpiryWord(kind: .soon, text: days == 0 ? "今天到期" : "\(days) 天后到期", tone: .caution) }
        return ProxyExpiryWord(kind: .ok, text: "剩余 \(days) 天", tone: nil)
    }
    /// Server days from today to the expiry's day.
    public static func days(until expiresAt: Date, now: Date, timeZone: ServerTimeZone) -> Int {
        let calendar = timeZone.calendar
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: expiresAt)).day ?? 0
    }
    /// “10/13” on the server's calendar.
    static func monthDay(_ date: Date, timeZone: ServerTimeZone) -> String {
        let parts = timeZone.calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d/%02d", parts.month ?? 0, parts.day ?? 0)
    }
}

extension APIClient {
    /// `GET admin/proxies/all[?with_count=true]`: only the active proxies, newest first. A read (retried on its own); it has no
    /// ETag and is not conditional.
    public func allProxies(withCount: Bool) async throws -> [AdminProxy] {
        try await request("admin/proxies/all", query: withCount ? [URLQueryItem(name: "with_count", value: "true")] : [])
    }
}
