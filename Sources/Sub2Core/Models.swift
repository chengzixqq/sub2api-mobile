import Foundation

public enum AuthenticationKind: String, Codable, Sendable { case adminKey, password }

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

public struct TokenPair: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken; self.refreshToken = refreshToken; self.expiresAt = expiresAt
    }
}

public enum Credential: Codable, Sendable, Equatable { case adminKey(String), tokens(TokenPair) }
public protocol CredentialStore: Sendable {
    func load(serverID: UUID) async throws -> Credential?
    func save(_ credential: Credential, serverID: UUID) async throws
    func remove(serverID: UUID) async throws
}

public struct CaptchaProof: Codable, Sendable {
    public var turnstileToken: String?
    public var tencentTicket: String?
    public var tencentRandstr: String?
    public init(turnstileToken: String? = nil, tencentTicket: String? = nil, tencentRandstr: String? = nil) {
        self.turnstileToken = turnstileToken; self.tencentTicket = tencentTicket; self.tencentRandstr = tencentRandstr
    }
    enum CodingKeys: String, CodingKey {
        case turnstileToken = "turnstile_token", tencentTicket = "tencent_captcha_ticket", tencentRandstr = "tencent_captcha_randstr"
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
    public init(user: AdminUser, tokens: TokenPair) { self.user = user; self.tokens = tokens }
}
public enum LoginResult: Sendable { case authenticated(AuthSession), twoFactor(TwoFactorChallenge) }

public struct Page<T: Codable & Sendable>: Codable, Sendable {
    public let items: [T]
    public let total: Int
    public let page: Int
    public let pageSize: Int
    public let pages: Int
    public var hasMore: Bool { page < pages }
    public init(items: [T], total: Int, page: Int, pageSize: Int, pages: Int) {
        self.items = items; self.total = total; self.page = page; self.pageSize = pageSize; self.pages = pages
    }
    enum CodingKeys: String, CodingKey { case items, total, page, pageSize = "page_size", pages }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        items = try c.decode([T].self, forKey: .items); total = try c.decode(Int.self, forKey: .total)
        page = try c.decode(Int.self, forKey: .page); pageSize = try c.decode(Int.self, forKey: .pageSize)
        guard total >= 0, page >= 1, pageSize > 0 else { throw APIError.invalidResponse }
        let calculated = total / pageSize + (total % pageSize == 0 ? 0 : 1)
        pages = try c.decodeIfPresent(Int.self, forKey: .pages) ?? calculated
        guard pages >= 0 else { throw APIError.invalidResponse }
    }
}

public struct AdminUser: Identifiable, Codable, Sendable {
    public let id: Int
    public let email: String
    public var username: String?
    public var balance: Decimal
    public var status: String
    public var role: String?
    public var concurrency: Int?
    public var notes: String?
    public var rpmLimit: Int?
    public var currentConcurrency: Int?
    public var createdAt: String?
    public var updatedAt: String?
    public var lastUsedAt: String?
    public var lastActiveAt: String?
    public init(id: Int, email: String, username: String? = nil, balance: Decimal = 0, status: String = "active", role: String? = nil, concurrency: Int? = nil, notes: String? = nil, rpmLimit: Int? = nil, currentConcurrency: Int? = nil, createdAt: String? = nil, updatedAt: String? = nil, lastUsedAt: String? = nil, lastActiveAt: String? = nil) {
        self.id = id; self.email = email; self.username = username; self.balance = balance; self.status = status; self.role = role; self.concurrency = concurrency
        self.notes = notes; self.rpmLimit = rpmLimit; self.currentConcurrency = currentConcurrency
        self.createdAt = createdAt; self.updatedAt = updatedAt; self.lastUsedAt = lastUsedAt; self.lastActiveAt = lastActiveAt
    }
    enum CodingKeys: String, CodingKey {
        case id, email, username, balance, status, role, concurrency, notes
        case rpmLimit = "rpm_limit", currentConcurrency = "current_concurrency"
        case createdAt = "created_at", updatedAt = "updated_at", lastUsedAt = "last_used_at", lastActiveAt = "last_active_at"
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); email = try c.decode(String.self, forKey: .email)
        username = try c.decodeIfPresent(String.self, forKey: .username); balance = try c.decimal(.balance)
        status = try c.decode(String.self, forKey: .status); role = try c.decodeIfPresent(String.self, forKey: .role)
        concurrency = try c.decodeIfPresent(Int.self, forKey: .concurrency)
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        rpmLimit = try c.decodeIfPresent(Int.self, forKey: .rpmLimit)
        currentConcurrency = try c.decodeIfPresent(Int.self, forKey: .currentConcurrency)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt)
        lastUsedAt = try c.decodeIfPresent(String.self, forKey: .lastUsedAt)
        lastActiveAt = try c.decodeIfPresent(String.self, forKey: .lastActiveAt)
    }
}

public struct UpstreamAccount: Identifiable, Codable, Sendable {
    public let id: Int
    public var name: String
    public var platform: String
    public var type: String
    public var status: String
    public var schedulable: Bool
    public var errorMessage: String?
    /// Configured request concurrency capacity; never substitute it for current use.
    public var concurrency: Int?
    public var currentConcurrency: Int?
    public var probeConcurrency: Int?
    public var currentRPM: Int?
    /// Separate natural-minute counter used for provider scheduling limits.
    public var schedulingRPM: Int?
    public var priority: Int?
    public var rateMultiplier: Decimal?
    public var notes: String?
    public var lastUsedAt: String?
    public var expiresAt: Int64?
    public var createdAt: String?
    public var baseRPM: Int?
    public var quotaUsed: Decimal?
    public var quotaLimit: Decimal?
    public var quotaDailyLimit: Decimal?
    public var quotaDailyUsed: Decimal?
    public var quotaWeeklyLimit: Decimal?
    public var quotaWeeklyUsed: Decimal?
    public var windowCostLimit: Decimal?
    public var currentWindowCost: Decimal?
    public var activeSessions: Int?
    public var maxSessions: Int?
    public var sessionWindowStart: String?
    public var sessionWindowEnd: String?
    public var sessionWindowStatus: String?
    public var loadFactor: Int?
    public var proxy: AccountProxy?
    public var extra: AccountExtra?
    public var schedulerScore: AccountSchedulerScore?
    public var schedulerScores: [AccountSchedulerScore]?
    public var groupIDs: [Int]
    public var groups: [Group]
    public struct Group: Identifiable, Codable, Sendable, Equatable {
        public let id: Int
        public let name: String
        public init(id: Int, name: String) { self.id = id; self.name = name }
    }
    private struct GroupBinding: Decodable { let group: Group? }
    public init(id: Int, name: String, platform: String, type: String, status: String = "active", schedulable: Bool = true, errorMessage: String? = nil, concurrency: Int? = nil, priority: Int? = nil, rateMultiplier: Decimal? = nil, notes: String? = nil, lastUsedAt: String? = nil, expiresAt: Int64? = nil, createdAt: String? = nil, baseRPM: Int? = nil, quotaUsed: Decimal? = nil, groupIDs: [Int] = [], groups: [Group] = [], currentConcurrency: Int? = nil, probeConcurrency: Int? = nil, currentRPM: Int? = nil, quotaLimit: Decimal? = nil, quotaDailyLimit: Decimal? = nil, quotaDailyUsed: Decimal? = nil, quotaWeeklyLimit: Decimal? = nil, quotaWeeklyUsed: Decimal? = nil, windowCostLimit: Decimal? = nil, currentWindowCost: Decimal? = nil, activeSessions: Int? = nil, maxSessions: Int? = nil, sessionWindowStart: String? = nil, sessionWindowEnd: String? = nil, sessionWindowStatus: String? = nil, loadFactor: Int? = nil, proxy: AccountProxy? = nil, extra: AccountExtra? = nil, schedulerScore: AccountSchedulerScore? = nil, schedulerScores: [AccountSchedulerScore]? = nil, schedulingRPM: Int? = nil) {
        self.id = id; self.name = name; self.platform = platform; self.type = type; self.status = status
        self.schedulable = schedulable; self.errorMessage = errorMessage; self.concurrency = concurrency
        self.priority = priority; self.rateMultiplier = rateMultiplier; self.notes = notes; self.lastUsedAt = lastUsedAt
        self.expiresAt = expiresAt; self.createdAt = createdAt; self.baseRPM = baseRPM; self.quotaUsed = quotaUsed
        self.groupIDs = groupIDs; self.groups = groups
        self.currentConcurrency = currentConcurrency; self.probeConcurrency = probeConcurrency; self.currentRPM = currentRPM
        self.schedulingRPM = schedulingRPM
        self.quotaLimit = quotaLimit; self.quotaDailyLimit = quotaDailyLimit; self.quotaDailyUsed = quotaDailyUsed
        self.quotaWeeklyLimit = quotaWeeklyLimit; self.quotaWeeklyUsed = quotaWeeklyUsed
        self.windowCostLimit = windowCostLimit; self.currentWindowCost = currentWindowCost
        self.activeSessions = activeSessions; self.maxSessions = maxSessions
        self.sessionWindowStart = sessionWindowStart; self.sessionWindowEnd = sessionWindowEnd; self.sessionWindowStatus = sessionWindowStatus
        self.loadFactor = loadFactor; self.proxy = proxy; self.extra = extra
        self.schedulerScore = schedulerScore; self.schedulerScores = schedulerScores
    }
    enum CodingKeys: String, CodingKey {
        case id, name, platform, type, status, schedulable, concurrency, priority, notes, groups
        case errorMessage = "error_message", rateMultiplier = "rate_multiplier", lastUsedAt = "last_used_at"
        case expiresAt = "expires_at", createdAt = "created_at", baseRPM = "base_rpm", quotaUsed = "quota_used"
        case groupIDs = "group_ids"
        case currentConcurrency = "current_concurrency", probeConcurrency = "probe_concurrency", currentRPM = "current_rpm"
        case schedulingRPM = "scheduling_rpm"
        case quotaLimit = "quota_limit", quotaDailyLimit = "quota_daily_limit", quotaDailyUsed = "quota_daily_used"
        case quotaWeeklyLimit = "quota_weekly_limit", quotaWeeklyUsed = "quota_weekly_used"
        case windowCostLimit = "window_cost_limit", currentWindowCost = "current_window_cost"
        case activeSessions = "active_sessions", maxSessions = "max_sessions"
        case sessionWindowStart = "session_window_start", sessionWindowEnd = "session_window_end", sessionWindowStatus = "session_window_status"
        case loadFactor = "load_factor", proxy, extra
        case schedulerScore = "scheduler_score", schedulerScores = "scheduler_scores"
    }
    private enum RelationshipKeys: String, CodingKey { case accountGroups = "account_groups" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        platform = try c.decode(String.self, forKey: .platform); type = try c.decode(String.self, forKey: .type)
        status = try c.decode(String.self, forKey: .status); schedulable = try c.decode(Bool.self, forKey: .schedulable)
        errorMessage = try c.decodeIfPresent(String.self, forKey: .errorMessage)
        concurrency = try c.decodeIfPresent(Int.self, forKey: .concurrency); priority = try c.decodeIfPresent(Int.self, forKey: .priority)
        currentConcurrency = try c.decodeIfPresent(Int.self, forKey: .currentConcurrency)
        probeConcurrency = try c.decodeIfPresent(Int.self, forKey: .probeConcurrency)
        currentRPM = try c.decodeIfPresent(Int.self, forKey: .currentRPM)
        schedulingRPM = try c.decodeIfPresent(Int.self, forKey: .schedulingRPM)
        quotaLimit = try c.optionalDecimal(.quotaLimit); quotaDailyLimit = try c.optionalDecimal(.quotaDailyLimit)
        quotaDailyUsed = try c.optionalDecimal(.quotaDailyUsed); quotaWeeklyLimit = try c.optionalDecimal(.quotaWeeklyLimit)
        quotaWeeklyUsed = try c.optionalDecimal(.quotaWeeklyUsed); windowCostLimit = try c.optionalDecimal(.windowCostLimit)
        currentWindowCost = try c.optionalDecimal(.currentWindowCost)
        activeSessions = try c.decodeIfPresent(Int.self, forKey: .activeSessions); maxSessions = try c.decodeIfPresent(Int.self, forKey: .maxSessions)
        sessionWindowStart = try c.decodeIfPresent(String.self, forKey: .sessionWindowStart)
        sessionWindowEnd = try c.decodeIfPresent(String.self, forKey: .sessionWindowEnd)
        sessionWindowStatus = try c.decodeIfPresent(String.self, forKey: .sessionWindowStatus)
        loadFactor = try c.decodeIfPresent(Int.self, forKey: .loadFactor)
        proxy = try c.decodeIfPresent(AccountProxy.self, forKey: .proxy); extra = try c.decodeIfPresent(AccountExtra.self, forKey: .extra)
        schedulerScore = try c.decodeIfPresent(AccountSchedulerScore.self, forKey: .schedulerScore)
        schedulerScores = try c.decodeIfPresent([AccountSchedulerScore].self, forKey: .schedulerScores)
        rateMultiplier = try c.optionalDecimal(.rateMultiplier); quotaUsed = try c.optionalDecimal(.quotaUsed)
        notes = try c.decodeIfPresent(String.self, forKey: .notes); lastUsedAt = try c.decodeIfPresent(String.self, forKey: .lastUsedAt)
        expiresAt = try c.decodeIfPresent(Int64.self, forKey: .expiresAt); createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt)
        baseRPM = try c.decodeIfPresent(Int.self, forKey: .baseRPM)
        groupIDs = try c.decodeIfPresent([Int].self, forKey: .groupIDs) ?? []
        let direct = try c.decodeIfPresent([Group?].self, forKey: .groups)?.compactMap { $0 } ?? []
        let relationships = try decoder.container(keyedBy: RelationshipKeys.self)
        let bindings = try relationships.decodeIfPresent([GroupBinding].self, forKey: .accountGroups) ?? []
        var seen = Set<Int>()
        groups = (direct + bindings.compactMap(\.group)).filter { seen.insert($0.id).inserted }
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
    public init(todayRequests: Int, todayTokens: Int, todayCost: Decimal, totalUsers: Int, totalAccounts: Int, errorAccounts: Int, rpm: Double, tpm: Double, todayActualCost: Decimal? = nil, todayAccountCost: Decimal? = nil, totalActualCost: Decimal? = nil, totalAccountCost: Decimal? = nil, totalTokens: Int? = nil, averageDurationMs: Double? = nil, totalRequests: Int? = nil, rpmAvailable: Bool? = nil) {
        self.todayRequests = todayRequests; self.todayTokens = todayTokens; self.todayCost = todayCost; self.totalUsers = totalUsers
        self.totalAccounts = totalAccounts; self.errorAccounts = errorAccounts; self.rpm = rpm; self.tpm = tpm
        self.rpmAvailable = rpmAvailable
        self.todayActualCost = todayActualCost; self.todayAccountCost = todayAccountCost
        self.totalActualCost = totalActualCost; self.totalAccountCost = totalAccountCost
        self.totalTokens = totalTokens; self.totalRequests = totalRequests; self.averageDurationMs = averageDurationMs
    }
    enum CodingKeys: String, CodingKey {
        case todayRequests = "today_requests", todayTokens = "today_tokens", todayCost = "today_cost", totalUsers = "total_users"
        case totalAccounts = "total_accounts", errorAccounts = "error_accounts", rpm, tpm
        case rpmAvailable = "rpm_available"
        case todayActualCost = "today_actual_cost", todayAccountCost = "today_account_cost"
        case totalActualCost = "total_actual_cost", totalAccountCost = "total_account_cost"
        case totalTokens = "total_tokens", totalRequests = "total_requests", averageDurationMs = "average_duration_ms"
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
public struct UserUsageSummary: Codable, Sendable {
    public let totalRequests: Int
    public let totalTokens: Int
    public let totalCost: Decimal
    public init(totalRequests: Int, totalTokens: Int, totalCost: Decimal) { self.totalRequests = totalRequests; self.totalTokens = totalTokens; self.totalCost = totalCost }
    enum CodingKeys: String, CodingKey { case totalRequests = "total_requests", totalTokens = "total_tokens", totalCost = "total_cost" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        totalRequests = try c.decode(Int.self, forKey: .totalRequests); totalTokens = try c.decode(Int.self, forKey: .totalTokens); totalCost = try c.decimal(.totalCost)
    }
}
public struct UserAPIKey: Identifiable, Codable, Sendable {
    public let id: Int
    public let name: String
    public let key: String?
    public let status: String
    public let quota: Decimal
    public let quotaUsed: Decimal
    public init(id: Int, name: String, key: String? = nil, status: String, quota: Decimal, quotaUsed: Decimal) {
        self.id = id; self.name = name; self.key = key; self.status = status; self.quota = quota; self.quotaUsed = quotaUsed
    }
    enum CodingKeys: String, CodingKey { case id, name, key, status, quota, quotaUsed = "quota_used" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); name = try c.decode(String.self, forKey: .name)
        key = try c.decodeIfPresent(String.self, forKey: .key); status = try c.decode(String.self, forKey: .status)
        quota = try c.decimal(.quota); quotaUsed = try c.decimal(.quotaUsed)
    }
}
public struct PublicSettings: Decodable, Sendable {
    public let captchaProvider: String?
    public let captchaEnabled: Bool
    public init(captchaProvider: String? = nil, captchaEnabled: Bool = false) { self.captchaProvider = captchaProvider; self.captchaEnabled = captchaEnabled }
    enum CodingKeys: String, CodingKey { case turnstile = "turnstile_enabled", tencent = "tencent_captcha_enabled", aliyun = "aliyun_captcha_enabled" }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let tencent = try c.decodeIfPresent(Bool.self, forKey: .tencent) == true
        let aliyun = try c.decodeIfPresent(Bool.self, forKey: .aliyun) == true
        let turnstile = try c.decodeIfPresent(Bool.self, forKey: .turnstile) == true
        guard [tencent, aliyun, turnstile].filter({ $0 }).count <= 1 else {
            throw APIError(kind: .captcha, reason: "CAPTCHA_PROVIDER_CONFLICT", message: "站点启用了多个验证码服务，请先在 Web 后台修正配置。")
        }
        if tencent { captchaProvider = "tencent" }
        else if aliyun { captchaProvider = "aliyun" }
        else if turnstile { captchaProvider = "turnstile" }
        else { captchaProvider = nil }
        captchaEnabled = captchaProvider != nil
    }
}

public enum BalanceOperation: String, Codable, CaseIterable, Sendable { case set, add, subtract }
public struct PendingBalanceOperation: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let serverID: UUID
    public let userID: Int
    public let amount: Decimal
    public let operation: BalanceOperation
    public let notes: String
    public init(id: UUID = UUID(), serverID: UUID, userID: Int, amount: Decimal, operation: BalanceOperation, notes: String = "") {
        self.id = id; self.serverID = serverID; self.userID = userID; self.amount = amount; self.operation = operation; self.notes = notes
    }
    public func validate() throws {
        let maximum = Decimal(string: "999999999999.99999999", locale: Locale(identifier: "en_US_POSIX"))!
        guard !amount.isNaN, amount >= 0, amount <= maximum, userID > 0,
              operation == .set || amount > 0 else { throw APIError.invalidAmount }
        var original = amount
        var rounded = Decimal()
        NSDecimalRound(&rounded, &original, 8, .plain)
        guard rounded == amount else { throw APIError.invalidAmount }
    }
    /// Exact bytes are deterministic across retries; never use Double for a balance operation.
    public func requestBody() throws -> Data {
        try validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(BalanceBody(balance: NSDecimalNumber(decimal: amount).stringValue, operation: operation, notes: notes))
    }
    private struct BalanceBody: Encodable { let balance: String; let operation: BalanceOperation; let notes: String }
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
