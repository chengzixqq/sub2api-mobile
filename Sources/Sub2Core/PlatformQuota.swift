import Foundation

// 30 §8.2 / §8.4 / §8.7 (S3-14, E07): a user's per-platform spending limits. `*_limit_usd` null is 不限 and 0 is 禁止 — the two
// are never mixed up, on the way in or out. Writes go out once without an Idempotency-Key (the server takes none).

public enum PlatformQuotaWindowKind: String, Sendable, CaseIterable, Identifiable {
    case daily, weekly, monthly
    public var id: String { rawValue }
    public var title: String {
        switch self { case .daily: "日"; case .weekly: "周"; case .monthly: "月" }
    }
}

public struct PlatformQuotaWindow: Sendable, Equatable {
    /// Already 0 when the window ran out (the server zeroes it lazily).
    public let usage: Decimal
    /// nil 不限, 0 禁止.
    public let limit: Decimal?
    /// nil while the window has not started or has run out.
    public let resetsAt: Date?
    public let windowStart: Date?
    public init(usage: Decimal = 0, limit: Decimal? = nil, resetsAt: Date? = nil, windowStart: Date? = nil) {
        self.usage = usage; self.limit = limit; self.resetsAt = resetsAt; self.windowStart = windowStart
    }
}

/// One row of `GET …/platform-quotas`. A limit that is neither missing, null, a number nor a numeric string leaves the row
/// on the list with `limitsReadable == false` (S3D1-17): its cells read “—” and the whole-table fallback refuses to write.
public struct UserPlatformQuota: Decodable, Sendable, Equatable, Identifiable {
    public let platform: String
    public let daily: PlatformQuotaWindow
    public let weekly: PlatformQuotaWindow
    public let monthly: PlatformQuotaWindow
    public let limitsReadable: Bool
    public var id: String { platform }

    public init(platform: String, daily: PlatformQuotaWindow, weekly: PlatformQuotaWindow, monthly: PlatformQuotaWindow, limitsReadable: Bool = true) {
        self.platform = platform; self.daily = daily; self.weekly = weekly; self.monthly = monthly; self.limitsReadable = limitsReadable
    }
    public func window(_ kind: PlatformQuotaWindowKind) -> PlatformQuotaWindow {
        switch kind { case .daily: daily; case .weekly: weekly; case .monthly: monthly }
    }
    public var limits: PlatformQuotaLimits { PlatformQuotaLimits(daily: daily.limit, weekly: weekly.limit, monthly: monthly.limit) }
    /// 30 §8.3 “已禁止使用”: any window at 0.
    public var isBanned: Bool { PlatformQuotaWindowKind.allCases.contains { window($0).limit == 0 } }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: QuotaKey.self)
        platform = try c.decode(String.self, forKey: QuotaKey("platform"))
        var readable = true
        func window(_ kind: PlatformQuotaWindowKind) -> PlatformQuotaWindow {
            let limit = Self.limit(c, QuotaKey(kind.rawValue + "_limit_usd"))
            readable = readable && limit.readable
            return PlatformQuotaWindow(usage: (try? c.optionalDecimal(QuotaKey(kind.rawValue + "_usage_usd"))) ?? 0, limit: limit.value,
                                       resetsAt: Self.date(c, QuotaKey(kind.rawValue + "_window_resets_at")),
                                       windowStart: Self.date(c, QuotaKey(kind.rawValue + "_window_start")))
        }
        daily = window(.daily); weekly = window(.weekly); monthly = window(.monthly)
        limitsReadable = readable
    }
    /// Missing or null → 不限; a non-negative number or ASCII decimal string → the limit; anything else is unreadable.
    private static func limit(_ c: KeyedDecodingContainer<QuotaKey>, _ key: QuotaKey) -> (value: Decimal?, readable: Bool) {
        guard c.contains(key), (try? c.decodeNil(forKey: key)) == false else { return (nil, true) }
        if let number = try? c.decode(Decimal.self, forKey: key) { return number.isNaN || number < 0 ? (nil, false) : (number, true) }
        if let text = try? c.decode(String.self, forKey: key), let value = PlatformQuotaLimits.parse(text) { return (value, true) }
        return (nil, false)
    }
    private static func date(_ c: KeyedDecodingContainer<QuotaKey>, _ key: QuotaKey) -> Date? {
        ServerTime.parseTimestamp(try? c.decodeIfPresent(String.self, forKey: key))
    }
}

/// The three limits of one platform. Encoded as exactly `daily_limit_usd`, `weekly_limit_usd` and `monthly_limit_usd`, nil as
/// JSON null: the single-platform PUT decodes strictly, and a misspelt key would turn into “all empty” and delete the quota.
public struct PlatformQuotaLimits: Encodable, Sendable, Equatable {
    public let daily: Decimal?
    public let weekly: Decimal?
    public let monthly: Decimal?
    public init(daily: Decimal? = nil, weekly: Decimal? = nil, monthly: Decimal? = nil) { self.daily = daily; self.weekly = weekly; self.monthly = monthly }

    /// All three empty: the platform has no quota (a PUT like this deletes it).
    public var isEmpty: Bool { daily == nil && weekly == nil && monthly == nil }
    public func limit(_ kind: PlatformQuotaWindowKind) -> Decimal? {
        switch kind { case .daily: daily; case .weekly: weekly; case .monthly: monthly }
    }
    /// The handler's rule (validateQuotaLimitFields: ≥ 0, finite, < 1e10) plus the App's 8 decimals for every amount (00 §6.1).
    public func validate() throws {
        for value in [daily, weekly, monthly].compactMap({ $0 }) {
            guard !value.isNaN, value >= 0, value < Self.ceiling, value.hasAtMostFractionDigits(8) else {
                throw APIError(kind: .validation, message: PlatformQuotaFailure.invalidLimit.message)
            }
        }
    }
    static let ceiling = Decimal(string: "10000000000", locale: Locale(identifier: "en_US_POSIX"))!
    /// ASCII digits with an optional fraction; nothing else.
    static func parse(_ text: String) -> Decimal? {
        guard text.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }

    enum CodingKeys: String, CodingKey { case daily = "daily_limit_usd", weekly = "weekly_limit_usd", monthly = "monthly_limit_usd" }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        for (key, value) in [(CodingKeys.daily, daily), (.weekly, weekly), (.monthly, monthly)] {
            if let value { try c.encode(value, forKey: key) } else { try c.encodeNil(forKey: key) }
        }
    }
}

/// One platform of the whole-table PUT: `{"platform", the three *_limit_usd}`.
public struct PlatformQuotaEntry: Encodable, Sendable, Equatable {
    public let platform: String
    public let limits: PlatformQuotaLimits
    public init(platform: String, limits: PlatformQuotaLimits) { self.platform = platform; self.limits = limits }
    private enum CodingKeys: String, CodingKey { case platform, daily = "daily_limit_usd", weekly = "weekly_limit_usd", monthly = "monthly_limit_usd" }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(platform, forKey: .platform)
        for (key, value) in [(CodingKeys.daily, limits.daily), (.weekly, limits.weekly), (.monthly, limits.monthly)] {
            if let value { try c.encode(value, forKey: key) } else { try c.encodeNil(forKey: key) }
        }
    }
}

/// `PUT …/:platform` → `{platform_quota, previous}`; a null `platform_quota` means the PUT removed the quota.
public struct PlatformQuotaUpsertResult: Decodable, Sendable {
    public let platformQuota: UserPlatformQuota?
    public let previous: PlatformQuotaLimits?
    /// false: `previous` came back unreadable, so no undo is offered.
    public let previousReadable: Bool
    public init(platformQuota: UserPlatformQuota?, previous: PlatformQuotaLimits?, previousReadable: Bool = true) {
        self.platformQuota = platformQuota; self.previous = previous; self.previousReadable = previousReadable
    }
    private enum CodingKeys: String, CodingKey { case platformQuota = "platform_quota", previous }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let previous = try c.decodeIfPresent(UserPlatformQuota.self, forKey: .previous)
        self.init(platformQuota: try c.decodeIfPresent(UserPlatformQuota.self, forKey: .platformQuota), previous: previous?.limits,
                  previousReadable: previous?.limitsReadable ?? true)
    }
}

/// `DELETE …/:platform` → `{removed, previous}`.
public struct PlatformQuotaDeleteResult: Decodable, Sendable {
    public let removed: Bool
    public let previous: PlatformQuotaLimits?
    public let previousReadable: Bool
    public init(removed: Bool, previous: PlatformQuotaLimits?, previousReadable: Bool = true) {
        self.removed = removed; self.previous = previous; self.previousReadable = previousReadable
    }
    private enum CodingKeys: String, CodingKey { case removed, previous }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let previous = try c.decodeIfPresent(UserPlatformQuota.self, forKey: .previous)
        self.init(removed: try c.decodeIfPresent(Bool.self, forKey: .removed) ?? false, previous: previous?.limits,
                  previousReadable: previous?.limitsReadable ?? true)
    }
}

/// `POST …/:platform/restore` → `{platform_quota, restored}`: limits, use and window starts as they were.
public struct PlatformQuotaRestoreResult: Decodable, Sendable {
    public let platformQuota: UserPlatformQuota?
    public let restored: Bool
    public init(platformQuota: UserPlatformQuota?, restored: Bool) { self.platformQuota = platformQuota; self.restored = restored }
    private enum CodingKeys: String, CodingKey { case platformQuota = "platform_quota", restored }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(platformQuota: try c.decodeIfPresent(UserPlatformQuota.self, forKey: .platformQuota),
                  restored: try c.decodeIfPresent(Bool.self, forKey: .restored) ?? false)
    }
}

/// 30 §8.4 撤销 of a single-platform write: none before → DELETE; some → some: PUT the previous three limits (use untouched);
/// some → none: restore the soft-deleted row (use included).
public enum PlatformQuotaUndo: Sendable, Equatable {
    case delete, put(PlatformQuotaLimits), restore

    public static func plan(previous: PlatformQuotaLimits?, current: PlatformQuotaLimits?) -> PlatformQuotaUndo? {
        switch (previous.flatMap { $0.isEmpty ? nil : $0 }, current.flatMap { $0.isEmpty ? nil : $0 }) {
        case (nil, nil): nil
        case (nil, _?): .delete
        case (let before?, _?): .put(before)
        case (_?, nil): .restore
        }
    }
}

/// 30 §8.4 without `users.platform_quota_item`: the whole-table PUT soft-deletes every platform it does not list, so the body is
/// always a fresh GET copied row by row with only the target changed (S3D1-17, security). An unreadable row stops it.
public enum PlatformQuotaFallback {
    public enum Failure: Error, Equatable { case unreadable }

    /// Order kept; empty or nil limits leave the platform out (the server then removes it); unknown platforms are copied as is.
    public static func entries(latest: [UserPlatformQuota], setting platform: String, to limits: PlatformQuotaLimits?) throws -> [PlatformQuotaEntry] {
        guard latest.allSatisfy(\.limitsReadable) else { throw Failure.unreadable }
        let target = limits.flatMap { $0.isEmpty ? nil : $0 }
        let kept = latest.compactMap { row -> PlatformQuotaEntry? in
            guard row.platform == platform else { return PlatformQuotaEntry(platform: row.platform, limits: row.limits) }
            return target.map { PlatformQuotaEntry(platform: platform, limits: $0) }
        }
        let isNew = !latest.contains { $0.platform == platform }
        return kept + (isNew ? target.map { [PlatformQuotaEntry(platform: platform, limits: $0)] } ?? [] : [])
    }
    /// 撤销: GET again and put the target back to what it was before the write.
    public static func undoEntries(latest: [UserPlatformQuota], platform: String, before: PlatformQuotaLimits?) throws -> [PlatformQuotaEntry] {
        try entries(latest: latest, setting: platform, to: before)
    }
    /// The undo inserts the platform's row again, so its use starts from 0 (UpsertForUser keeps use only on rows it updates).
    public static func undoResetsUsage(before: PlatformQuotaLimits?, after: PlatformQuotaLimits?) -> Bool {
        !(before?.isEmpty ?? true) && (after?.isEmpty ?? true)
    }
}

struct PlatformQuotaList: Decodable, Sendable {
    let platformQuotas: [UserPlatformQuota]
    private enum CodingKeys: String, CodingKey { case platformQuotas = "platform_quotas" }
}

/// A key spelled at run time (`daily_limit_usd`, `weekly_window_start` …).
struct QuotaKey: CodingKey {
    let stringValue: String
    init(_ name: String) { stringValue = name }
    init?(stringValue: String) { self.stringValue = stringValue }
    var intValue: Int? { nil }
    init?(intValue: Int) { nil }
}

extension APIClient {
    /// `GET admin/users/:id/platform-quotas` (a site without the service answers an empty list).
    public func platformQuotas(userID: Int) async throws -> [UserPlatformQuota] {
        let reply: PlatformQuotaList = try await request(quotaPath(userID))
        return reply.platformQuotas
    }
    /// `PUT …/:platform`; nil limits go out as null, all three empty deletes the quota.
    public func upsertPlatformQuota(userID: Int, platform: String, limits: PlatformQuotaLimits) async throws -> PlatformQuotaUpsertResult {
        try limits.validate()
        return try await request(quotaPath(userID, platform), method: "PUT", body: encode(limits), requestClass: .unkeyedWrite)
    }
    /// `DELETE …/:platform`; 404 USER_PLATFORM_QUOTA_NOT_FOUND without an active quota.
    public func deletePlatformQuota(userID: Int, platform: String) async throws -> PlatformQuotaDeleteResult {
        try await request(quotaPath(userID, platform), method: "DELETE", requestClass: .unkeyedWrite)
    }
    /// `POST …/:platform/restore`; 409 USER_PLATFORM_QUOTA_ACTIVE_EXISTS, 404 USER_PLATFORM_QUOTA_NOT_FOUND.
    public func restorePlatformQuota(userID: Int, platform: String) async throws -> PlatformQuotaRestoreResult {
        try await request(quotaPath(userID, platform) + "/restore", method: "POST", requestClass: .unkeyedWrite)
    }
    /// `POST …/reset {"platform","window"}` → the whole list again.
    public func resetPlatformQuotaWindow(userID: Int, platform: String, window: PlatformQuotaWindowKind) async throws -> [UserPlatformQuota] {
        let body = try encode(["platform": try Self.quotaPlatform(platform), "window": window.rawValue])
        let reply: PlatformQuotaList = try await request(quotaPath(userID) + "/reset", method: "POST", body: body, requestClass: .unkeyedWrite)
        return reply.platformQuotas
    }
    /// `PUT …/platform-quotas {"quotas":[…]}` (the fallback): platforms left out are soft-deleted.
    public func replaceUserPlatformQuotas(userID: Int, quotas: [PlatformQuotaEntry]) async throws -> [UserPlatformQuota] {
        for entry in quotas {
            _ = try Self.quotaPlatform(entry.platform)
            try entry.limits.validate()
        }
        let reply: PlatformQuotaList = try await request(quotaPath(userID), method: "PUT", body: encode(["quotas": quotas]), requestClass: .unkeyedWrite)
        return reply.platformQuotas
    }

    private func quotaPath(_ userID: Int, _ platform: String? = nil) throws -> String {
        let base = "admin/users/\(try validID(userID))/platform-quotas"
        return try platform.map { base + "/" + (try Self.quotaPlatform($0)) } ?? base
    }
    /// Platform ids are lower-case words (domain.ConcretePlatformIDs); anything else never reaches the path.
    private static func quotaPlatform(_ platform: String) throws -> String {
        guard platform.range(of: #"^[a-z0-9_]{1,64}$"#, options: .regularExpression) != nil else {
            throw APIError(kind: .validation, message: "无效的平台。")
        }
        return platform
    }
}
