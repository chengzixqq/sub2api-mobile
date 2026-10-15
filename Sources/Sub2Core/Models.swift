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
    public init(id: Int, email: String, username: String? = nil, balance: Decimal = 0, status: String = "active", role: String? = nil, concurrency: Int? = nil) {
        self.id = id; self.email = email; self.username = username; self.balance = balance; self.status = status; self.role = role; self.concurrency = concurrency
    }
    enum CodingKeys: String, CodingKey { case id, email, username, balance, status, role, concurrency }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id); email = try c.decode(String.self, forKey: .email)
        username = try c.decodeIfPresent(String.self, forKey: .username); balance = try c.decimal(.balance)
        status = try c.decode(String.self, forKey: .status); role = try c.decodeIfPresent(String.self, forKey: .role)
        concurrency = try c.decodeIfPresent(Int.self, forKey: .concurrency)
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
    public var concurrency: Int?
    public init(id: Int, name: String, platform: String, type: String, status: String = "active", schedulable: Bool = true, errorMessage: String? = nil, concurrency: Int? = nil) {
        self.id = id; self.name = name; self.platform = platform; self.type = type; self.status = status
        self.schedulable = schedulable; self.errorMessage = errorMessage; self.concurrency = concurrency
    }
    enum CodingKeys: String, CodingKey { case id, name, platform, type, status, schedulable, errorMessage = "error_message", concurrency }
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
    public let tpm: Double
    public init(todayRequests: Int, todayTokens: Int, todayCost: Decimal, totalUsers: Int, totalAccounts: Int, errorAccounts: Int, rpm: Double, tpm: Double) {
        self.todayRequests = todayRequests; self.todayTokens = todayTokens; self.todayCost = todayCost; self.totalUsers = totalUsers
        self.totalAccounts = totalAccounts; self.errorAccounts = errorAccounts; self.rpm = rpm; self.tpm = tpm
    }
    enum CodingKeys: String, CodingKey {
        case todayRequests = "today_requests", todayTokens = "today_tokens", todayCost = "today_cost", totalUsers = "total_users"
        case totalAccounts = "total_accounts", errorAccounts = "error_accounts", rpm, tpm
    }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        todayRequests = try c.decode(Int.self, forKey: .todayRequests); todayTokens = try c.decode(Int.self, forKey: .todayTokens)
        todayCost = try c.decimal(.todayCost); totalUsers = try c.decode(Int.self, forKey: .totalUsers)
        totalAccounts = try c.decode(Int.self, forKey: .totalAccounts); errorAccounts = try c.decode(Int.self, forKey: .errorAccounts)
        rpm = try c.decode(Double.self, forKey: .rpm); tpm = try c.decode(Double.self, forKey: .tpm)
    }
}
public struct TrendPoint: Identifiable, Codable, Sendable {
    public var id: String { date }
    public let date: String
    public let requests: Int
    public let totalTokens: Int
    public let cost: Decimal
    public init(date: String, requests: Int, totalTokens: Int, cost: Decimal) { self.date = date; self.requests = requests; self.totalTokens = totalTokens; self.cost = cost }
    enum CodingKeys: String, CodingKey { case date, requests, totalTokens = "total_tokens", cost }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date); requests = try c.decode(Int.self, forKey: .requests)
        totalTokens = try c.decode(Int.self, forKey: .totalTokens); cost = try c.decimal(.cost)
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
    public let cost: Decimal
    public init(requests: Int, tokens: Int, cost: Decimal) { self.requests = requests; self.tokens = tokens; self.cost = cost }
    enum CodingKeys: String, CodingKey { case requests, tokens, cost }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        requests = try c.decode(Int.self, forKey: .requests); tokens = try c.decode(Int.self, forKey: .tokens); cost = try c.decimal(.cost)
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
