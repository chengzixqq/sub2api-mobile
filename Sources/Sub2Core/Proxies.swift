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

// MARK: - 阶段 6 · S6-10: probe results, accounts and the rest of the endpoints (60 §12–§14); the write bodies are in ProxyWrites.swift

/// `POST :id/test` (`service.ProxyTestResult`). A failed probe is still 200, with `success: false` and the probe's own error.
public struct ProxyTestResult: Decodable, Sendable, Equatable {
    public let success: Bool
    /// The probe's text; it only becomes `latency_message`, never a receipt.
    public let message: String?
    public let latencyMs: Int?
    public let ipAddress: String?
    public let city: String?
    public let region: String?
    public let country: String?
    public let countryCode: String?
    /// `checked_at` (Unix seconds), on a failure too.
    public let checkedAt: Date?
    public init(success: Bool, message: String? = nil, latencyMs: Int? = nil, ipAddress: String? = nil, city: String? = nil, region: String? = nil,
                country: String? = nil, countryCode: String? = nil, checkedAt: Date? = nil) {
        self.success = success; self.message = message; self.latencyMs = latencyMs; self.ipAddress = ipAddress; self.city = city
        self.region = region; self.country = country; self.countryCode = countryCode; self.checkedAt = checkedAt
    }
    enum CodingKeys: String, CodingKey {
        case success, message, latencyMs = "latency_ms", ipAddress = "ip_address", city, region, country, countryCode = "country_code"
        case checkedAt = "checked_at"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(success: c.lenientValue(.success) ?? false, message: c.lenientValue(.message), latencyMs: c.lenientValue(.latencyMs),
                  ipAddress: c.lenientValue(.ipAddress), city: c.lenientValue(.city), region: c.lenientValue(.region),
                  country: c.lenientValue(.country), countryCode: c.lenientValue(.countryCode),
                  checkedAt: ServerTime.date(unixSeconds: c.lenientValue(.checkedAt)))
    }
}

/// One target of a quality check; `cf_ray` is not read.
public struct ProxyQualityItem: Decodable, Sendable, Equatable {
    public let target: String
    /// pass / warn / fail / challenge.
    public let status: String
    public let httpStatus: Int?
    public let latencyMs: Int?
    public let message: String?
    public init(target: String, status: String, httpStatus: Int? = nil, latencyMs: Int? = nil, message: String? = nil) {
        self.target = target; self.status = status; self.httpStatus = httpStatus; self.latencyMs = latencyMs; self.message = message
    }
    enum CodingKeys: String, CodingKey { case target, status, httpStatus = "http_status", latencyMs = "latency_ms", message }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(target: c.lenientString(.target), status: c.lenientString(.status), httpStatus: c.lenientValue(.httpStatus),
                  latencyMs: c.lenientValue(.latencyMs), message: c.lenientValue(.message))
    }
}

/// `POST :id/quality-check`: always 200 with a score, even when the base probe failed (then `base_connectivity` is fail).
public struct ProxyQualityResult: Decodable, Sendable, Equatable {
    public static let baseConnectivityTarget = "base_connectivity"
    public let proxyID: Int?
    public let score: Int?
    public let grade: String?
    public let summary: String?
    public let exitIP: String?
    public let country: String?
    public let countryCode: String?
    public let baseLatencyMs: Int?
    public let passedCount: Int
    public let warnCount: Int
    public let failedCount: Int
    public let challengeCount: Int
    /// Unix seconds.
    public let checkedAt: Date?
    public let items: [ProxyQualityItem]
    public init(proxyID: Int? = nil, score: Int? = nil, grade: String? = nil, summary: String? = nil, exitIP: String? = nil, country: String? = nil,
                countryCode: String? = nil, baseLatencyMs: Int? = nil, passedCount: Int = 0, warnCount: Int = 0, failedCount: Int = 0,
                challengeCount: Int = 0, checkedAt: Date? = nil, items: [ProxyQualityItem] = []) {
        self.proxyID = proxyID; self.score = score; self.grade = grade; self.summary = summary; self.exitIP = exitIP; self.country = country
        self.countryCode = countryCode; self.baseLatencyMs = baseLatencyMs; self.passedCount = passedCount; self.warnCount = warnCount
        self.failedCount = failedCount; self.challengeCount = challengeCount; self.checkedAt = checkedAt; self.items = items
    }
    enum CodingKeys: String, CodingKey {
        case proxyID = "proxy_id", score, grade, summary, exitIP = "exit_ip", country, countryCode = "country_code", baseLatencyMs = "base_latency_ms"
        case passedCount = "passed_count", warnCount = "warn_count", failedCount = "failed_count", challengeCount = "challenge_count"
        case checkedAt = "checked_at", items
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(proxyID: c.lenientValue(.proxyID), score: c.lenientValue(.score), grade: c.lenientValue(.grade), summary: c.lenientValue(.summary),
                  exitIP: c.lenientValue(.exitIP), country: c.lenientValue(.country), countryCode: c.lenientValue(.countryCode),
                  baseLatencyMs: c.lenientValue(.baseLatencyMs), passedCount: c.lenientValue(.passedCount) ?? 0,
                  warnCount: c.lenientValue(.warnCount) ?? 0, failedCount: c.lenientValue(.failedCount) ?? 0,
                  challengeCount: c.lenientValue(.challengeCount) ?? 0, checkedAt: ServerTime.date(unixSeconds: c.lenientValue(.checkedAt)),
                  items: c.lossyList(ProxyQualityItem.self, .items))
    }
    public var baseConnectivityPassed: Bool { items.contains { $0.target == Self.baseConnectivityTarget && $0.status == "pass" } }
    /// The `quality_status` the server stores (`proxyQualityOverallStatus`): challenge, failed, warn, healthy; nothing passed is failed.
    public var overallStatus: String {
        if challengeCount > 0 { return "challenge" }
        if failedCount > 0 { return "failed" }
        if warnCount > 0 { return "warn" }
        return passedCount > 0 ? "healthy" : "failed"
    }
}

/// An account whose `proxy_id` is this proxy (`GET :id/accounts`). Only `id` is required.
public struct ProxyAccountRef: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let platform: String
    public let type: String
    public let notes: String?
    public init(id: Int, name: String, platform: String, type: String, notes: String? = nil) {
        self.id = id; self.name = name; self.platform = platform; self.type = type; self.notes = notes
    }
    enum CodingKeys: String, CodingKey { case id, name, platform, type, notes }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(Int.self, forKey: .id), name: c.lenientString(.name), platform: c.lenientString(.platform),
                  type: c.lenientString(.type), notes: c.lenientValue(.notes))
    }
}

/// An account the expiry moved off this proxy (`GET :id/fallback-accounts`); a null current proxy means it now connects directly.
public struct ProxyFallbackAccount: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int
    public let name: String
    public let platform: String
    public let type: String
    public let notes: String?
    public let currentProxyID: Int?
    public let currentProxyName: String?
    public var isDirect: Bool { currentProxyID == nil }
    public init(id: Int, name: String, platform: String, type: String, notes: String? = nil, currentProxyID: Int? = nil, currentProxyName: String? = nil) {
        self.id = id; self.name = name; self.platform = platform; self.type = type; self.notes = notes
        self.currentProxyID = currentProxyID; self.currentProxyName = currentProxyName
    }
    enum CodingKeys: String, CodingKey {
        case id, name, platform, type, notes, currentProxyID = "current_proxy_id", currentProxyName = "current_proxy_name"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decode(Int.self, forKey: .id), name: c.lenientString(.name), platform: c.lenientString(.platform),
                  type: c.lenientString(.type), notes: c.lenientValue(.notes), currentProxyID: c.lenientValue(.currentProxyID),
                  currentProxyName: c.lenientValue(.currentProxyName))
    }
}

/// `POST :id/fallback-accounts/revert`, account by account.
public struct ProxyFallbackRevertResult: Decodable, Sendable, Equatable {
    /// A skipped or failed account. The server's `message` is its own error text and is not read (R11): pages word it by `code`.
    public struct Item: Decodable, Sendable, Equatable {
        public let id: Int
        public let code: String
        public init(id: Int, code: String) { self.id = id; self.code = code }
        enum CodingKeys: String, CodingKey { case id, code }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.init(id: try c.decode(Int.self, forKey: .id), code: c.lenientString(.code))
        }
    }
    public static let maxAccountsPerRequest = 500
    /// The codes of an account that is no longer moved off this proxy.
    public static let skippedCodes: Set<String> = ["ACCOUNT_NOT_IN_FALLBACK", "ACCOUNT_NOT_FALLBACK_OF_PROXY"]
    public let revertedIDs: [Int]
    public let skipped: [Item]
    public let failed: [Item]
    public init(revertedIDs: [Int] = [], skipped: [Item] = [], failed: [Item] = []) {
        self.revertedIDs = revertedIDs; self.skipped = skipped; self.failed = failed
    }
    enum CodingKeys: String, CodingKey { case revertedIDs = "reverted_ids", skipped, failed }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(revertedIDs: c.lossyList(Int.self, .revertedIDs), skipped: c.lossyList(Item.self, .skipped), failed: c.lossyList(Item.self, .failed))
    }
}

/// `GET admin/proxies` (60 §12.2). The list pages through everything with the defaults; global search asks for a few by name.
public struct ProxyListQuery: Sendable, Equatable {
    public enum Sort: String, Sendable, Equatable {
        case id, name, scheme = "protocol", status, createdAt = "created_at", expiry, accountCount = "account_count"
    }
    public static let catalogPageSize = 200
    /// The server cuts `search` to 100 bytes and may split a character; the App cuts first, at a character boundary.
    public static let searchByteLimit = 100
    public var search: String
    public var pageSize: Int
    public var sort: Sort
    public var ascending: Bool
    public init(search: String = "", pageSize: Int = ProxyListQuery.catalogPageSize, sort: Sort = .id, ascending: Bool = false) {
        self.search = search; self.pageSize = pageSize; self.sort = sort; self.ascending = ascending
    }
    /// Paging and sort always go out; `search` (trimmed, 100 UTF-8 bytes) only when not empty.
    public func queryItems(page: Int) throws -> [URLQueryItem] {
        guard page >= 1, (1...PageSize.maximum).contains(pageSize) else { throw APIError(kind: .validation, message: "代理的查询条件无效。") }
        let term = AccountWebLink.truncatedUTF8(search.trimmingCharacters(in: .whitespacesAndNewlines), maxBytes: Self.searchByteLimit)
        let items = [URLQueryItem(name: "page", value: String(page)), URLQueryItem(name: "page_size", value: String(pageSize)),
                     URLQueryItem(name: "sort_by", value: sort.rawValue), URLQueryItem(name: "sort_order", value: ascending ? "asc" : "desc")]
        return term.isEmpty ? items : items + [URLQueryItem(name: "search", value: term)]
    }
}

/// The reasons the proxy pages word themselves (60 §13.4, §14.4); the rest go through 00 §3.3.
public enum ProxyReason {
    public static let notFound = "PROXY_NOT_FOUND"
    public static let inUse = "PROXY_IN_USE"
    public static let backupRequired = "PROXY_BACKUP_REQUIRED"
    public static let backupSelf = "PROXY_BACKUP_SELF"
    public static let fallbackOriginUnavailable = AccountWriteReason.fallbackOriginUnavailable
    public static let tooManyAccounts = "TOO_MANY_ACCOUNTS"
    /// 409 PROXY_IN_USE because accounts were moved off it: `metadata.fallback_account_count` above 0; nil otherwise.
    public static func fallbackAccountCount(in error: APIError) -> Int? {
        guard error.statusCode == 409, error.reason == inUse, let count = error.metadata["fallback_account_count"].flatMap({ Int($0) }),
              count > 0 else { return nil }
        return count
    }
}

/// 00 §2.3 has no row for it: the base probe (up to 20 seconds) and four targets of 15 seconds each, plus room.
public enum ProxyRequestTimeout {
    public static let qualityCheck: TimeInterval = 95
}

extension AdminProxy {
    /// 12.4: a success writes the latency, exit IP and place; a failure keeps only the probe's text and drops the exit, as the
    /// server's failed snapshot does. `latency_checked_at` becomes the result's `checked_at`; nothing else changes.
    public func applying(_ result: ProxyTestResult) -> AdminProxy {
        let probe = result.success
            ? ProxyProbe(latencyMs: result.latencyMs, status: "success", message: result.message, checkedAt: result.checkedAt,
                         ipAddress: result.ipAddress, country: result.country, countryCode: result.countryCode, region: result.region, city: result.city)
            : ProxyProbe(status: "failed", message: result.message, checkedAt: result.checkedAt)
        return rebuilt(configuration: self, probe: probe, quality: quality)
    }
    /// 13.4: only the quality score, grade, summary, status and time.
    public func applying(_ quality: ProxyQualityResult) -> AdminProxy {
        rebuilt(configuration: self, probe: probe, quality: ProxyQualitySnapshot(status: quality.overallStatus, score: quality.score, grade: quality.grade,
                                                                                 summary: quality.summary, checked: quality.checkedAt))
    }
    /// A PUT answers the plain `dto.AdminProxy`: its configuration, with this row's counts, latency and quality. A changed scheme,
    /// host, port, username or password drops the latency and exit, which the server cleared to probe again (H04).
    public func mergingConfiguration(from updated: AdminProxy) -> AdminProxy {
        let moved = updated.scheme != scheme || updated.host != host || updated.port != port
            || (updated.username ?? "") != (username ?? "") || (updated.password ?? "") != (password ?? "")
        return rebuilt(configuration: updated, probe: moved ? ProxyProbe() : probe, quality: quality)
    }

    private var probe: ProxyProbe {
        ProxyProbe(latencyMs: latencyMs, status: latencyStatus, message: latencyMessage, checkedAt: latencyCheckedAt, ipAddress: ipAddress,
                   country: country, countryCode: countryCode, region: region, city: city)
    }
    private var quality: ProxyQualitySnapshot {
        ProxyQualitySnapshot(status: qualityStatus, score: qualityScore, grade: qualityGrade, summary: qualitySummary, checked: qualityChecked)
    }
    /// The id, counts and `hasAccountCountKey` stay this row's.
    private func rebuilt(configuration c: AdminProxy, probe p: ProxyProbe, quality q: ProxyQualitySnapshot) -> AdminProxy {
        AdminProxy(id: id, name: c.name, scheme: c.scheme, host: c.host, port: c.port, username: c.username, password: c.password, status: c.status,
                   createdAt: c.createdAt ?? createdAt, updatedAt: c.updatedAt ?? updatedAt, expiresAt: c.expiresAt, fallbackMode: c.fallbackMode,
                   backupProxyID: c.backupProxyID, expiryWarnDays: c.expiryWarnDays, accountCount: accountCount, hasAccountCountKey: hasAccountCountKey,
                   fallbackAccountCount: fallbackAccountCount, latencyMs: p.latencyMs, latencyStatus: p.status, latencyMessage: p.message,
                   latencyCheckedAt: p.checkedAt, ipAddress: p.ipAddress, country: p.country, countryCode: p.countryCode, region: p.region, city: p.city,
                   qualityStatus: q.status, qualityScore: q.score, qualityGrade: q.grade, qualitySummary: q.summary, qualityChecked: q.checked)
    }
}

/// The latency snapshot of one probe.
private struct ProxyProbe {
    var latencyMs: Int?
    var status: String?
    var message: String?
    var checkedAt: Date?
    var ipAddress: String?
    var country: String?
    var countryCode: String?
    var region: String?
    var city: String?
}

private struct ProxyQualitySnapshot {
    let status: String?
    let score: Int?
    let grade: String?
    let summary: String?
    let checked: Date?
}

/// `{}` reverts every account moved off the proxy.
private struct ProxyRevertBody: Encodable {
    let accountIDs: [Int]?
    enum CodingKeys: String, CodingKey { case accountIDs = "account_ids" }
}

extension APIClient {
    /// `GET admin/proxies`: a read (retried on its own) without ETag, so not conditional (60 §0.2). The list pages through it with the
    /// default query; global search sends `ProxyListQuery(search:pageSize: 5)`.
    public func proxies(page: Int, query: ProxyListQuery) async throws -> Page<AdminProxy> {
        try await request("admin/proxies", query: query.queryItems(page: page))
    }
    /// `GET admin/proxies/:id`. A server before H02 answers without `account_count`: the list is then searched by the name (100 a
    /// page) for the same id, and the first answer stands when it is not there or that read fails (60 §13.2).
    public func proxy(id: Int) async throws -> AdminProxy {
        let id = try validID(id), snapshot = currentGeneration()
        let detail: AdminProxy = try await request("admin/proxies/\(id)")
        let name = detail.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !detail.hasAccountCountKey, !name.isEmpty else { return detail }
        try check(snapshot)
        do {
            let page = try await proxies(page: 1, query: ProxyListQuery(search: name, pageSize: 100))
            return page.items.first { $0.id == id } ?? detail
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try check(snapshot)
            return detail
        }
    }
    /// `POST admin/proxies` always carries the key the caller made when the user tapped “添加” (R05; optional on the server,
    /// 00 §2.5.1): transport failures go again under the same key and bytes, and an unanswered write ends as KeyedWriteFailure.
    public func createProxy(_ create: ProxyCreateRequest, idempotencyKey: UUID, onEvent: KeyedWriteEventHandler? = nil) async throws -> WriteOutcome<AdminProxy> {
        try await performKeyedWrite(KeyedWriteRequest(path: "admin/proxies", method: "POST", body: create.requestBody(), key: idempotencyKey), onEvent: onEvent)
    }
    /// `PUT admin/proxies/:id`: absolute values, no key, sent once (R06); an unknown result is read back with `matches`.
    public func updateProxy(id: Int, _ update: ProxyUpdateRequest) async throws -> AdminProxy {
        let id = try validID(id)
        return try await request("admin/proxies/\(id)", method: "PUT", body: update.requestBody(proxyID: id))
    }
    /// `DELETE admin/proxies/:id`, sent once. 404 PROXY_NOT_FOUND reads as already deleted; 409 PROXY_IN_USE (see
    /// `ProxyReason.fallbackAccountCount`) and a non-JSON 404 are thrown.
    public func deleteProxy(id: Int) async throws -> DeleteResult {
        let id = try validID(id)
        do {
            let _: EmptyReply = try await request("admin/proxies/\(id)", method: "DELETE")
            return .deleted
        } catch let error as APIError where error.statusCode == 404 && error.reason == ProxyReason.notFound {
            return .alreadyGone
        }
    }
    /// `POST :id/test`, no body: not a read, so never retried on its own. A failed probe is a 200 with `success: false`.
    public func testProxy(id: Int) async throws -> ProxyTestResult {
        try await request("admin/proxies/\(validID(id))/test", method: "POST")
    }
    /// `POST :id/quality-check`, no body, sent once; it can take about 80 seconds, hence its own timeout.
    public func checkProxyQuality(id: Int) async throws -> ProxyQualityResult {
        try await request("admin/proxies/\(validID(id))/quality-check", method: "POST", timeout: ProxyRequestTimeout.qualityCheck)
    }
    /// `GET :id/accounts`; an entry without an id is skipped.
    public func proxyAccounts(id: Int) async throws -> [ProxyAccountRef] {
        let list: LossyList<ProxyAccountRef> = try await request("admin/proxies/\(validID(id))/accounts")
        return list.items
    }
    /// `GET :id/fallback-accounts` (`proxies.fallback_accounts`); an entry without an id is skipped.
    public func proxyFallbackAccounts(id: Int) async throws -> [ProxyFallbackAccount] {
        let list: LossyList<ProxyFallbackAccount> = try await request("admin/proxies/\(validID(id))/fallback-accounts")
        return list.items
    }
    /// `POST :id/fallback-accounts/revert`, no key and sent once (repeating it is safe, H03). No ids: `{}`, every account moved off
    /// this proxy; otherwise each id once in its order, at most 500.
    public func revertProxyFallback(id: Int, accountIDs: [Int]) async throws -> ProxyFallbackRevertResult {
        let id = try validID(id)
        var seen = Set<Int>()
        let ids = try accountIDs.map { try validID($0) }.filter { seen.insert($0).inserted }
        guard ids.count <= ProxyFallbackRevertResult.maxAccountsPerRequest else {
            throw APIError(kind: .validation, message: "一次最多恢复 \(ProxyFallbackRevertResult.maxAccountsPerRequest) 个账号。")
        }
        let body = try ProxyWriteCheck.encode(ProxyRevertBody(accountIDs: ids.isEmpty ? nil : ids))
        return try await request("admin/proxies/\(id)/fallback-accounts/revert", method: "POST", body: body)
    }
}
