import Foundation

public enum AuthenticationKind: String, Codable, Sendable {
    case adminKey, password, accessToken
    /// An unknown stored value only changes wording, so it never drops the site (an older App reading newer data).
    public init(from decoder: any Decoder) throws {
        self = AuthenticationKind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .password
    }
}

public struct ServerProfile: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    public var baseURL: URL
    public var authentication: AuthenticationKind
    public init(id: UUID = UUID(), name: String, baseURL: URL, authentication: AuthenticationKind) {
        self.id = id; self.name = name; self.baseURL = baseURL; self.authentication = authentication
    }
    public func validatedURL() throws -> URL {
        guard let parts = URLComponents(url: baseURL, resolvingAgainstBaseURL: false),
              parts.scheme?.lowercased() == "https", let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty || parts.path == "/" else { throw APIError.invalidServer }
        return baseURL
    }
}
extension ServerProfile {
    /// A typed site address as 00 §1.1 accepts it: `https://host[:port]`, host lowercased, nothing after it.
    public static func normalizedURL(_ raw: String) throws -> URL {
        let invalid = APIError(kind: .validation, message: "请输入完整 HTTPS 站点地址，例如 https://sub2.example.com；不支持路径、账号或查询参数。")
        guard var components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https", let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil, components.query == nil, components.fragment == nil,
              components.path.isEmpty || components.path == "/" else { throw invalid }
        components.scheme = "https"
        components.host = host.lowercased()
        components.path = ""
        guard let url = components.url else { throw invalid }
        return url
    }
    /// Saved profiles are read one by one: an unreadable entry is skipped instead of emptying the list,
    /// which would then be written back over the good entries.
    public static func storedList(from data: Data) -> [ServerProfile] {
        ((try? JSONDecoder().decode([Lossy<ServerProfile>].self, from: data)) ?? []).compactMap(\.value)
    }
    public static func storedArchive(from data: Data) -> [UUID: ServerProfile] {
        ((try? JSONDecoder().decode([UUID: Lossy<ServerProfile>].self, from: data)) ?? [:]).compactMapValues(\.value)
    }
}
/// One element of a list read element by element: an unreadable one becomes nil instead of failing the list.
struct Lossy<Value: Decodable>: Decodable {
    let value: Value?
    init(from decoder: any Decoder) throws { value = try? Value(from: decoder) }
}
/// A list field read element by element; a value that is not a list reads as empty (00 §5 rule 2).
struct LossyList<Element: Decodable & Sendable>: Decodable, Sendable {
    let items: [Element]
    init(from decoder: any Decoder) throws {
        items = ((try? decoder.singleValueContainer().decode([Lossy<Element>].self)) ?? []).compactMap(\.value)
    }
}

public struct TokenPair: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt
    }
}

public enum Credential: Codable, Sendable, Equatable {
    case adminKey(String), tokens(TokenPair), accessToken(String)

    /// The only `sat_` rule: trimmed, then the backend's case-sensitive prefix check (`IsAdminAccessToken`).
    public static func fromAPIKey(_ raw: String) -> Credential {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.hasPrefix("sat_") ? .accessToken(key) : .adminKey(key)
    }
    public var authenticationKind: AuthenticationKind {
        switch self {
        case .tokens: .password
        case .adminKey: .adminKey
        case .accessToken: .accessToken
        }
    }
    /// Keeps the synthesized Keychain format (`{"adminKey":{"_0":…}}`) byte for byte.
    private enum Stored: Codable { case adminKey(String), tokens(TokenPair), accessToken(String) }
    public init(from decoder: any Decoder) throws {
        switch try Stored(from: decoder) {
        // Tokens saved as Admin Keys before `sat_` support are migrated by prefix (00 §9.4).
        case .adminKey(let key): self = Self.fromAPIKey(key)
        case .tokens(let pair): self = .tokens(pair)
        case .accessToken(let key): self = .accessToken(key)
        }
    }
    public func encode(to encoder: any Encoder) throws {
        let stored: Stored = switch self {
        case .adminKey(let key): .adminKey(key)
        case .tokens(let pair): .tokens(pair)
        case .accessToken(let key): .accessToken(key)
        }
        try stored.encode(to: encoder)
    }
}
public protocol CredentialStore: Sendable {
    func load(serverID: UUID) async throws -> Credential?
    func save(_ credential: Credential, serverID: UUID) async throws
    func remove(serverID: UUID) async throws
}

public struct CaptchaProof: Codable, Sendable {
    public var provider: String?
    public var turnstileToken: String?
    public var tencentTicket: String?
    public var tencentRandstr: String?
    public var aliyunParam: String?
    public init(provider: String? = nil, turnstileToken: String? = nil, tencentTicket: String? = nil, tencentRandstr: String? = nil, aliyunParam: String? = nil) {
        self.provider = provider; self.turnstileToken = turnstileToken; self.tencentTicket = tencentTicket
        self.tencentRandstr = tencentRandstr; self.aliyunParam = aliyunParam
    }
    enum CodingKeys: String, CodingKey {
        case provider = "captcha_provider", turnstileToken = "turnstile_token", tencentTicket = "tencent_captcha_ticket"
        case tencentRandstr = "tencent_captcha_randstr", aliyunParam = "aliyun_captcha_param"
    }
}
public struct TwoFactorChallenge: Sendable {
    public let tempToken: String
    public let maskedEmail: String?
    public init(tempToken: String, maskedEmail: String? = nil) { self.tempToken = tempToken; self.maskedEmail = maskedEmail }
}
public struct AuthSession: Sendable {
    public let user: AdminUser
    public let tokens: TokenPair
    /// The server issued no refresh token: sign in again once the access expires (00 §1.4 step 5).
    public let refreshTokenUnavailable: Bool
    public init(user: AdminUser, tokens: TokenPair, refreshTokenUnavailable: Bool = false) {
        self.user = user; self.tokens = tokens; self.refreshTokenUnavailable = refreshTokenUnavailable
    }
}
public enum LoginResult: Sendable { case authenticated(AuthSession), twoFactor(TwoFactorChallenge) }

public struct Page<T: Decodable & Sendable>: Decodable, Sendable {
    public let items: [T]
    /// nil in deferred-count envelopes: show no total and page by `hasMore` (00 §4.1).
    public let total: Int?
    public let page: Int
    public let pageSize: Int
    public let pages: Int?
    /// Raw `has_more`; incremental envelopes also carry `since_id` / `latest_id`.
    public let reportedHasMore: Bool?
    public let sinceID: Int?
    public let latestID: Int?
    public var hasMore: Bool {
        if let reportedHasMore { return reportedHasMore }
        if let pages { return page < pages }
        if let total, pageSize > 0 { return page <= Int.max / pageSize && page * pageSize < total }
        return false
    }
    public init(items: [T], total: Int?, page: Int, pageSize: Int, pages: Int?, hasMore: Bool? = nil, sinceID: Int? = nil, latestID: Int? = nil) {
        self.items = items; self.total = total; self.page = page; self.pageSize = pageSize; self.pages = pages
        reportedHasMore = hasMore; self.sinceID = sinceID; self.latestID = latestID
    }
    enum CodingKeys: String, CodingKey {
        case items, total, page, pageSize = "page_size", pages, hasMore = "has_more", sinceID = "since_id", latestID = "latest_id"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([T].self, forKey: .items); total = try c.decodeIfPresent(Int.self, forKey: .total)
        page = try c.decode(Int.self, forKey: .page); pageSize = try c.decode(Int.self, forKey: .pageSize)
        guard total.map({ $0 >= 0 }) ?? true, page >= 1, pageSize > 0 else { throw APIError.invalidResponse }
        let size = pageSize
        pages = try c.decodeIfPresent(Int.self, forKey: .pages) ?? total.map { $0 / size + ($0 % size == 0 ? 0 : 1) }
        guard pages.map({ $0 >= 0 }) ?? true else { throw APIError.invalidResponse }
        reportedHasMore = try c.decodeIfPresent(Bool.self, forKey: .hasMore)
        sinceID = try c.decodeIfPresent(Int.self, forKey: .sinceID); latestID = try c.decodeIfPresent(Int.self, forKey: .latestID)
    }
    public func mapItems<U: Decodable & Sendable>(_ transform: (T) throws -> U) rethrows -> Page<U> {
        Page<U>(items: try items.map(transform), total: total, page: page, pageSize: pageSize, pages: pages,
                hasMore: reportedHasMore, sinceID: sinceID, latestID: latestID)
    }
}

public struct DashboardSummary: Sendable {
    public let stats: DashboardStats
    public let trend: [TrendPoint]
    public let monitoring: OpsSnapshot?
    public init(stats: DashboardStats, trend: [TrendPoint], monitoring: OpsSnapshot? = nil) { self.stats = stats; self.trend = trend; self.monitoring = monitoring }
}
public struct DashboardStats: Codable, Sendable {
    public let todayRequests: Int
    public let todayTokens: Int
    public let todayCost: Decimal
    public let totalUsers: Int
    public let totalAccounts: Int
    public let errorAccounts: Int
    public let rpm: Double
    /// nil is a legacy server; false is unavailable, never a measured zero.
    public let rpmAvailable: Bool?
    public let tpm: Double
    public let todayActualCost: Decimal?
    public let todayAccountCost: Decimal?
    public let totalActualCost: Decimal?
    public let totalAccountCost: Decimal?
    public let totalTokens: Int?
    public let totalRequests: Int?
    public let averageDurationMs: Double?
    /// `stats_updated_at` as sent (RFC3339 UTC), so the fixture's JSON round trip keeps it; HomeFallback parses it (S1-07).
    public let statsUpdatedAt: String?
    /// nil on a server before the stats aggregation.
    public let statsStale: Bool?
    public init(todayRequests: Int, todayTokens: Int, todayCost: Decimal, totalUsers: Int, totalAccounts: Int, errorAccounts: Int, rpm: Double, tpm: Double, todayActualCost: Decimal? = nil, todayAccountCost: Decimal? = nil, totalActualCost: Decimal? = nil, totalAccountCost: Decimal? = nil, totalTokens: Int? = nil, averageDurationMs: Double? = nil, totalRequests: Int? = nil, rpmAvailable: Bool? = nil, statsUpdatedAt: String? = nil, statsStale: Bool? = nil) {
        self.todayRequests = todayRequests; self.todayTokens = todayTokens; self.todayCost = todayCost; self.totalUsers = totalUsers
        self.totalAccounts = totalAccounts; self.errorAccounts = errorAccounts; self.rpm = rpm; self.tpm = tpm
        self.rpmAvailable = rpmAvailable
        self.todayActualCost = todayActualCost; self.todayAccountCost = todayAccountCost
        self.totalActualCost = totalActualCost; self.totalAccountCost = totalAccountCost
        self.totalTokens = totalTokens; self.totalRequests = totalRequests; self.averageDurationMs = averageDurationMs
        self.statsUpdatedAt = statsUpdatedAt; self.statsStale = statsStale
    }
    enum CodingKeys: String, CodingKey {
        case todayRequests = "today_requests", todayTokens = "today_tokens", todayCost = "today_cost", totalUsers = "total_users"
        case totalAccounts = "total_accounts", errorAccounts = "error_accounts", rpm, tpm
        case rpmAvailable = "rpm_available"
        case todayActualCost = "today_actual_cost", todayAccountCost = "today_account_cost"
        case totalActualCost = "total_actual_cost", totalAccountCost = "total_account_cost"
        case totalTokens = "total_tokens", totalRequests = "total_requests", averageDurationMs = "average_duration_ms"
        case statsUpdatedAt = "stats_updated_at", statsStale = "stats_stale"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        todayRequests = try c.decode(Int.self, forKey: .todayRequests); todayTokens = try c.decode(Int.self, forKey: .todayTokens)
        todayCost = try c.decimal(.todayCost); totalUsers = try c.decode(Int.self, forKey: .totalUsers)
        totalAccounts = try c.decode(Int.self, forKey: .totalAccounts); errorAccounts = try c.decode(Int.self, forKey: .errorAccounts)
        rpm = try c.decode(Double.self, forKey: .rpm); tpm = try c.decode(Double.self, forKey: .tpm)
        rpmAvailable = try c.decodeIfPresent(Bool.self, forKey: .rpmAvailable)
        todayActualCost = try c.optionalDecimal(.todayActualCost); todayAccountCost = try c.optionalDecimal(.todayAccountCost)
        totalActualCost = try c.optionalDecimal(.totalActualCost); totalAccountCost = try c.optionalDecimal(.totalAccountCost)
        totalTokens = try c.decodeIfPresent(Int.self, forKey: .totalTokens)
        totalRequests = try c.decodeIfPresent(Int.self, forKey: .totalRequests)
        averageDurationMs = try c.decodeIfPresent(Double.self, forKey: .averageDurationMs)
        statsUpdatedAt = try? c.decodeIfPresent(String.self, forKey: .statsUpdatedAt)
        statsStale = try? c.decodeIfPresent(Bool.self, forKey: .statsStale)
    }
}
public struct TrendPoint: Identifiable, Codable, Sendable {
    public var id: String { date }
    public let date: String
    public let requests: Int
    public let totalTokens: Int
    public let cost: Decimal
    public let actualCost: Decimal?
    public init(date: String, requests: Int, totalTokens: Int, cost: Decimal, actualCost: Decimal? = nil) {
        self.date = date; self.requests = requests; self.totalTokens = totalTokens; self.cost = cost; self.actualCost = actualCost
    }
    enum CodingKeys: String, CodingKey { case date, requests, totalTokens = "total_tokens", cost, actualCost = "actual_cost" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date); requests = try c.decode(Int.self, forKey: .requests)
        totalTokens = try c.decode(Int.self, forKey: .totalTokens); cost = try c.decimal(.cost)
        actualCost = try c.optionalDecimal(.actualCost)
    }
}
public struct OpsSnapshot: Codable, Sendable {
    public let errorRate: Double?
    public let qps: Double?
    public let activeRequests: Int?
    public init(errorRate: Double? = nil, qps: Double? = nil, activeRequests: Int? = nil) { self.errorRate = errorRate; self.qps = qps; self.activeRequests = activeRequests }
    enum CodingKeys: String, CodingKey { case errorRate = "error_rate", qps, activeRequests = "active_requests" }
}
public struct AccountTodayStats: Codable, Sendable {
    public let requests: Int
    public let tokens: Int
    /// Provider/account cost. This is not the user's actual charge.
    public let cost: Decimal
    /// Aggregated usage_logs.actual_cost, exposed by today-stats as user_cost.
    public let userCost: Decimal?
    public let standardCost: Decimal?
    public init(requests: Int, tokens: Int, cost: Decimal, userCost: Decimal? = nil, standardCost: Decimal? = nil) {
        self.requests = requests; self.tokens = tokens; self.cost = cost
        self.userCost = userCost; self.standardCost = standardCost
    }
    enum CodingKeys: String, CodingKey { case requests, tokens, cost; case userCost = "user_cost", standardCost = "standard_cost" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requests = try c.decode(Int.self, forKey: .requests); tokens = try c.decode(Int.self, forKey: .tokens); cost = try c.decimal(.cost)
        userCost = try c.optionalDecimal(.userCost); standardCost = try c.optionalDecimal(.standardCost)
    }
}
public struct LoginAgreementDocument: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let contentMarkdown: String
    public init(id: String, title: String, contentMarkdown: String) { self.id = id; self.title = title; self.contentMarkdown = contentMarkdown }
    enum CodingKeys: String, CodingKey { case id, title, contentMarkdown = "content_md" }
}
/// Raw `settings/public` fields (00 §9.4). A captcha conflict is reported to the login page, never thrown while decoding.
public struct PublicSettings: Decodable, Sendable {
    /// nil when the key is absent (servers before `auth.captcha_provider`); "" means no captcha.
    public let rawCaptchaProvider: String?
    public let turnstileEnabled: Bool?
    public let tencentCaptchaEnabled: Bool?
    public let aliyunCaptchaEnabled: Bool?
    /// "" (front end deployed separately) and a missing key mean different things (00 §1.5).
    public let mobileVerifyPath: String?
    public let siteName: String?
    public let siteLogo: String?
    public let version: String?
    public let serverTimezone: String?
    public let serverUTCOffset: String?
    public let backendModeEnabled: Bool?
    public let totpEnabled: Bool?
    public let loginAgreementEnabled: Bool?
    public let loginAgreementMode: String?
    public let loginAgreementRevision: String?
    public let loginAgreementUpdatedAt: String?
    /// Read before every sign-in, so one malformed document is dropped instead of failing the whole reply.
    private let agreementDocuments: LossyList<LoginAgreementDocument>?
    public let channelMonitorEnabled: Bool?
    public let channelMonitorMode: String?
    public let paymentEnabled: Bool?
    public let subscriptionEnabled: Bool?
    /// The global low-balance reminder (30 §1.3); read leniently so a malformed value cannot fail the sign-in page.
    private let lowBalanceNotify: LenientValue<Bool>?
    private let lowBalanceThreshold: LenientValue<Decimal>?

    public var loginAgreementDocuments: [LoginAgreementDocument] { agreementDocuments?.items ?? [] }
    public var balanceLowNotifyEnabled: Bool? { lowBalanceNotify?.value }
    public var balanceLowNotifyThreshold: Decimal? { lowBalanceThreshold?.value }
    public var hasCaptchaProviderKey: Bool { rawCaptchaProvider != nil }
    /// nil, turnstile, tencent, aliyun, conflict, or an unknown value from a newer server. Without the
    /// provider key the three legacy switches decide, and more than one enabled is a conflict.
    public var captchaProvider: String? {
        if let rawCaptchaProvider { return rawCaptchaProvider.isEmpty ? nil : rawCaptchaProvider }
        let enabled = [("turnstile", turnstileEnabled), ("tencent", tencentCaptchaEnabled), ("aliyun", aliyunCaptchaEnabled)].filter { $0.1 == true }
        return enabled.count > 1 ? "conflict" : enabled.first?.0
    }
    public var captchaEnabled: Bool { captchaProvider != nil }
    public var isCaptchaConflict: Bool { captchaProvider == "conflict" }

    enum CodingKeys: String, CodingKey {
        case rawCaptchaProvider = "captcha_provider", turnstileEnabled = "turnstile_enabled"
        case tencentCaptchaEnabled = "tencent_captcha_enabled", aliyunCaptchaEnabled = "aliyun_captcha_enabled"
        case mobileVerifyPath = "mobile_verify_path", siteName = "site_name", siteLogo = "site_logo", version
        case serverTimezone = "server_timezone", serverUTCOffset = "server_utc_offset"
        case backendModeEnabled = "backend_mode_enabled", totpEnabled = "totp_enabled"
        case loginAgreementEnabled = "login_agreement_enabled", loginAgreementMode = "login_agreement_mode"
        case loginAgreementRevision = "login_agreement_revision", loginAgreementUpdatedAt = "login_agreement_updated_at"
        case agreementDocuments = "login_agreement_documents"
        case channelMonitorEnabled = "channel_monitor_enabled", channelMonitorMode = "channel_monitor_mode"
        case paymentEnabled = "payment_enabled", subscriptionEnabled = "subscription_enabled"
        case lowBalanceNotify = "balance_low_notify_enabled", lowBalanceThreshold = "balance_low_notify_threshold"
    }
}

public enum BalanceOperation: String, Codable, CaseIterable, Sendable { case set, add, subtract }
/// A balance write kept on disk until its result is known (00 §2.5.5, 30 §3.7). Records saved before S0-06 decode without the
/// fields after `notes`; the file is not migrated.
public struct PendingBalanceOperation: PendingMoneyWrite, Equatable {
    public let id: UUID
    public let serverID: UUID
    public let userID: Int
    public let amount: Decimal
    public let operation: BalanceOperation
    public let notes: String
    /// `id` lowercased, sent as X-Request-ID; nil marks a legacy record (sent without it, no createdAt or email).
    public let requestID: String?
    public let actorUserID: Int?
    public let createdAt: Date?
    public let userDisplayName: String?
    public let userEmail: String?
    /// X-Admin-Adjustment-Action-ID from any reply, saved before the result is known (30 §3.4 step 4).
    public private(set) var actionID: UUID?
    public let idempotencyExpiresAt: Date?
    /// When “用同一编号重试” last sent it; the execution grace starts here too (BACKLOG “余额重试后的执行宽限”). nil until a retry.
    public private(set) var lastSentAt: Date?
    public init(id: UUID = UUID(), serverID: UUID, userID: Int, amount: Decimal, operation: BalanceOperation, notes: String = "",
                actorUserID: Int? = nil, createdAt: Date = Date(), userDisplayName: String? = nil, userEmail: String? = nil) {
        self.id = id; self.serverID = serverID; self.userID = userID; self.amount = amount; self.operation = operation; self.notes = notes
        requestID = id.uuidString.lowercased(); self.actorUserID = actorUserID; self.createdAt = createdAt
        self.userDisplayName = userDisplayName; self.userEmail = userEmail; actionID = nil; idempotencyExpiresAt = nil; lastSentAt = nil
    }
    enum CodingKeys: String, CodingKey {
        case id, serverID, userID, amount, operation, notes, requestID, actorUserID, createdAt, userDisplayName, userEmail, actionID, idempotencyExpiresAt
        case lastSentAt
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id); serverID = try c.decode(UUID.self, forKey: .serverID)
        userID = try c.decode(Int.self, forKey: .userID); amount = try c.decimal(.amount)
        operation = try c.decode(BalanceOperation.self, forKey: .operation); notes = try c.decode(String.self, forKey: .notes)
        requestID = try c.decodeIfPresent(String.self, forKey: .requestID); actorUserID = try c.decodeIfPresent(Int.self, forKey: .actorUserID)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        userDisplayName = try c.decodeIfPresent(String.self, forKey: .userDisplayName); userEmail = try c.decodeIfPresent(String.self, forKey: .userEmail)
        actionID = try c.decodeIfPresent(UUID.self, forKey: .actionID)
        idempotencyExpiresAt = try c.decodeIfPresent(Date.self, forKey: .idempotencyExpiresAt)
        lastSentAt = try c.decodeIfPresent(Date.self, forKey: .lastSentAt)
    }
    public var isLegacy: Bool { requestID == nil }
    public func with(actionID: UUID?) -> PendingBalanceOperation {
        var copy = self
        copy.actionID = actionID
        return copy
    }
    public func with(lastSentAt: Date?) -> PendingBalanceOperation {
        var copy = self
        copy.lastSentAt = lastSentAt
        return copy
    }
    /// This record over the saved copy of the same id: the action id and the last send only ever move forward, so a copy taken
    /// before a reply cannot erase what was saved since.
    public func merging(stored: PendingBalanceOperation) -> PendingBalanceOperation {
        var copy = self
        copy.actionID = actionID ?? stored.actionID
        copy.lastSentAt = [lastSentAt, stored.lastSentAt].compactMap { $0 }.max()
        return copy
    }
    public var summary: PendingMoneyWriteSummary {
        PendingMoneyWriteSummary(subject: .balance(operation, amount: amount), createdAt: createdAt, userID: userID,
                                 userDisplayName: userDisplayName, userEmail: userEmail)
    }
    /// 0 ≤ amount ≤ 999999999999.99999999 with at most 8 decimals (00 §6.1).
    public static func validateAmount(_ amount: Decimal) throws {
        let maximum = Decimal(string: "999999999999.99999999", locale: Locale(identifier: "en_US_POSIX"))!
        guard !amount.isNaN, amount >= 0, amount <= maximum, amount.hasAtMostFractionDigits(8) else { throw APIError.invalidAmount }
    }
    public func validate() throws {
        try Self.validateAmount(amount)
        guard userID > 0, operation == .set || amount > 0 else { throw APIError.invalidAmount }
    }
    /// Exact bytes are deterministic across retries; never use Double for a balance operation.
    public func requestBody() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(BalanceBody(balance: NSDecimalNumber(decimal: amount).stringValue, operation: operation, notes: notes))
    }
    private struct BalanceBody: Encodable { let balance: String; let operation: BalanceOperation; let notes: String }
}

extension Decimal {
    /// True when rounding to `digits` decimals would not change the value.
    func hasAtMostFractionDigits(_ digits: Int) -> Bool {
        var original = self, rounded = Decimal()
        NSDecimalRound(&rounded, &original, digits, .plain)
        return rounded == self
    }
}

extension KeyedDecodingContainer {
    func optionalDecimal(_ key: Key) throws -> Decimal? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        return try decimal(key)
    }
    func decimal(_ key: Key) throws -> Decimal {
        if let raw = try? decode(String.self, forKey: key) {
            guard let result = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")), !result.isNaN else { throw APIError.invalidResponse }
            return result
        }
        let result = try decode(Decimal.self, forKey: key)
        guard !result.isNaN else { throw APIError.invalidResponse }
        return result
    }
}
