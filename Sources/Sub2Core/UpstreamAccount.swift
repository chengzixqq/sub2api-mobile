import Foundation

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
    // C02 structured error (`accounts.structured_error`); timestamps stay raw strings like `lastUsedAt`.
    public var errorAt: String?
    public var errorStatusCode: Int?
    public var errorKind: String?
    public var errorSummary: String?
    /// C15: false means `current_concurrency` is a 0 placeholder, not an observed value.
    public var concurrencyAvailable: Bool?
    // 20 §0.2 inputs.
    public var rateLimitResetAt: String?
    public var overloadUntil: String?
    public var tempUnschedulableUntil: String?
    /// Raw `TempUnschedState` JSON or upstream text; parsed by AccountDisplayState, never shown.
    public var tempUnschedulableReason: String?
    public var autoPauseOnExpired: Bool?
    /// C10 (`accounts.token_status`).
    public var tokenStatus: AccountTokenStatus?
    // 20 §1.7; timestamps stay raw strings.
    public var updatedAt: String?
    public var proxyID: Int?
    public var proxyFallbackOriginID: Int?
    public var proxyFallbackOriginName: String?
    public var sessionIdleTimeoutMinutes: Int?
    /// Set on a shadow account, whose credentials follow its parent (S2D1-21).
    public var parentAccountID: Int?
    /// Non-sensitive keys only (base_url, model_mapping, account_mode …), redacted on the way in like the backend's
    /// `RedactCredentials`. Never encoded, logged or put in an error.
    public var credentials: JSONValue?
    /// `credentials_status`'s has_<key> flags, plus one for each secret an old server sent in the clear.
    public var credentialsStatus: [String: Bool]?
    /// A non-empty secret arrived in the clear: the server predates credential redaction (0f8e2d093), and a whole-credentials
    /// PUT there would delete the secrets (S2D1-09). Not encoded.
    public let credentialsArrivedUnredacted: Bool
    public struct Group: Identifiable, Codable, Sendable, Equatable {
        public let id: Int
        public let name: String
        public init(id: Int, name: String) { self.id = id; self.name = name }
    }
    private struct GroupBinding: Decodable { let group: Group? }
    public init(id: Int, name: String, platform: String, type: String, status: String = "active", schedulable: Bool = true, errorMessage: String? = nil, concurrency: Int? = nil, priority: Int? = nil, rateMultiplier: Decimal? = nil, notes: String? = nil, lastUsedAt: String? = nil, expiresAt: Int64? = nil, createdAt: String? = nil, baseRPM: Int? = nil, quotaUsed: Decimal? = nil, groupIDs: [Int] = [], groups: [Group] = [], currentConcurrency: Int? = nil, probeConcurrency: Int? = nil, currentRPM: Int? = nil, quotaLimit: Decimal? = nil, quotaDailyLimit: Decimal? = nil, quotaDailyUsed: Decimal? = nil, quotaWeeklyLimit: Decimal? = nil, quotaWeeklyUsed: Decimal? = nil, windowCostLimit: Decimal? = nil, currentWindowCost: Decimal? = nil, activeSessions: Int? = nil, maxSessions: Int? = nil, sessionWindowStart: String? = nil, sessionWindowEnd: String? = nil, sessionWindowStatus: String? = nil, loadFactor: Int? = nil, proxy: AccountProxy? = nil, extra: AccountExtra? = nil, schedulerScore: AccountSchedulerScore? = nil, schedulerScores: [AccountSchedulerScore]? = nil, schedulingRPM: Int? = nil, errorAt: String? = nil, errorStatusCode: Int? = nil, errorKind: String? = nil, errorSummary: String? = nil, concurrencyAvailable: Bool? = nil, rateLimitResetAt: String? = nil, overloadUntil: String? = nil, tempUnschedulableUntil: String? = nil, tempUnschedulableReason: String? = nil, autoPauseOnExpired: Bool? = nil, tokenStatus: AccountTokenStatus? = nil, updatedAt: String? = nil, proxyID: Int? = nil, proxyFallbackOriginID: Int? = nil, proxyFallbackOriginName: String? = nil, credentials: JSONValue? = nil, credentialsStatus: [String: Bool]? = nil, sessionIdleTimeoutMinutes: Int? = nil, parentAccountID: Int? = nil, credentialsArrivedUnredacted: Bool = false) {
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
        self.errorAt = errorAt; self.errorStatusCode = errorStatusCode; self.errorKind = errorKind; self.errorSummary = errorSummary
        self.concurrencyAvailable = concurrencyAvailable; self.rateLimitResetAt = rateLimitResetAt; self.overloadUntil = overloadUntil
        self.tempUnschedulableUntil = tempUnschedulableUntil; self.tempUnschedulableReason = tempUnschedulableReason
        self.autoPauseOnExpired = autoPauseOnExpired; self.tokenStatus = tokenStatus
        self.updatedAt = updatedAt; self.proxyID = proxyID; self.proxyFallbackOriginID = proxyFallbackOriginID
        self.proxyFallbackOriginName = proxyFallbackOriginName; self.sessionIdleTimeoutMinutes = sessionIdleTimeoutMinutes
        self.parentAccountID = parentAccountID
        let redaction = AccountCredentialRedaction(credentials, reported: credentialsStatus)
        self.credentials = redaction.credentials; self.credentialsStatus = redaction.status
        self.credentialsArrivedUnredacted = credentialsArrivedUnredacted || redaction.arrivedUnredacted
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
        case errorAt = "error_at", errorStatusCode = "error_status_code", errorKind = "error_kind", errorSummary = "error_summary"
        case concurrencyAvailable = "concurrency_available", rateLimitResetAt = "rate_limit_reset_at", overloadUntil = "overload_until"
        case tempUnschedulableUntil = "temp_unschedulable_until", tempUnschedulableReason = "temp_unschedulable_reason"
        case autoPauseOnExpired = "auto_pause_on_expired", tokenStatus = "token_status"
        case updatedAt = "updated_at", proxyID = "proxy_id", proxyFallbackOriginID = "proxy_fallback_origin_id"
        case proxyFallbackOriginName = "proxy_fallback_origin_name", sessionIdleTimeoutMinutes = "session_idle_timeout_minutes"
        case parentAccountID = "parent_account_id", credentialsStatus = "credentials_status"
    }
    /// Read but never encoded; a credentials value of an odd shape reads as absent instead of failing the whole list.
    private enum RelationshipKeys: String, CodingKey { case accountGroups = "account_groups", credentials }
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
        errorAt = try c.decodeIfPresent(String.self, forKey: .errorAt); errorStatusCode = try c.decodeIfPresent(Int.self, forKey: .errorStatusCode)
        errorKind = try c.decodeIfPresent(String.self, forKey: .errorKind); errorSummary = try c.decodeIfPresent(String.self, forKey: .errorSummary)
        concurrencyAvailable = try c.decodeIfPresent(Bool.self, forKey: .concurrencyAvailable)
        rateLimitResetAt = try c.decodeIfPresent(String.self, forKey: .rateLimitResetAt)
        overloadUntil = try c.decodeIfPresent(String.self, forKey: .overloadUntil)
        tempUnschedulableUntil = try c.decodeIfPresent(String.self, forKey: .tempUnschedulableUntil)
        tempUnschedulableReason = try c.decodeIfPresent(String.self, forKey: .tempUnschedulableReason)
        autoPauseOnExpired = try c.decodeIfPresent(Bool.self, forKey: .autoPauseOnExpired)
        tokenStatus = try c.decodeIfPresent(AccountTokenStatus.self, forKey: .tokenStatus)
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt); proxyID = try c.decodeIfPresent(Int.self, forKey: .proxyID)
        proxyFallbackOriginID = try c.decodeIfPresent(Int.self, forKey: .proxyFallbackOriginID)
        proxyFallbackOriginName = try c.decodeIfPresent(String.self, forKey: .proxyFallbackOriginName)
        sessionIdleTimeoutMinutes = try c.decodeIfPresent(Int.self, forKey: .sessionIdleTimeoutMinutes)
        parentAccountID = try c.decodeIfPresent(Int.self, forKey: .parentAccountID)
        let relationships = try decoder.container(keyedBy: RelationshipKeys.self)
        groups = try Self.decodeGroups(c, relationships)
        let redaction = AccountCredentialRedaction(try? relationships.decodeIfPresent(JSONValue.self, forKey: .credentials),
                                                   reported: try? c.decodeIfPresent([String: Bool].self, forKey: .credentialsStatus))
        credentials = redaction.credentials; credentialsStatus = redaction.status; credentialsArrivedUnredacted = redaction.arrivedUnredacted
    }
    /// `groups` and `account_groups` merged; the first name seen for an id wins.
    private static func decodeGroups(_ c: KeyedDecodingContainer<CodingKeys>, _ relationships: KeyedDecodingContainer<RelationshipKeys>) throws -> [Group] {
        let direct = try c.decodeIfPresent([Group?].self, forKey: .groups)?.compactMap { $0 } ?? []
        let bindings = try relationships.decodeIfPresent([GroupBinding].self, forKey: .accountGroups) ?? []
        var seen = Set<Int>()
        return (direct + bindings.compactMap(\.group)).filter { seen.insert($0.id).inserted }
    }
}

extension UpstreamAccount {
    /// The backend's `SensitiveCredentialKeys` (service/account_credentials_redact.go), word for word. The App's only copy.
    public static let sensitiveCredentialKeys: Set<String> = [
        "access_token", "refresh_token", "id_token", "agent_private_key",
        "api_key", "session_key", "cookie",
        "password", "sso_token", "sso", "sso-rw", "clearTextPassword",
        "aws_secret_access_key", "aws_session_token",
        "service_account_json", "service_account", "private_key"
    ]
}

/// Mirrors the backend's `dto.RedactCredentials`, so an old server's secrets never stay in memory: sensitive keys are dropped and
/// a present value (not null, "" or false) becomes has_<key> = true; flags the server sent win.
struct AccountCredentialRedaction {
    let credentials: JSONValue?
    let status: [String: Bool]?
    let arrivedUnredacted: Bool
    init(_ raw: JSONValue?, reported: [String: Bool]?) {
        guard let fields = raw?.objectValue else {
            credentials = nil; status = reported; arrivedUnredacted = false; return
        }
        var kept = [String: JSONValue](), found = [String: Bool]()
        for (key, value) in fields {
            guard UpstreamAccount.sensitiveCredentialKeys.contains(key) else { kept[key] = value; continue }
            if Self.isPresent(value) { found["has_" + key] = true }
        }
        credentials = .object(kept)
        status = found.isEmpty ? reported : (reported ?? [:]).merging(found) { server, _ in server }
        arrivedUnredacted = !found.isEmpty
    }
    private static func isPresent(_ value: JSONValue) -> Bool {
        switch value {
        case .null: false
        case .string(let text): !text.isEmpty
        case .bool(let flag): flag
        default: true
        }
    }
}

/// The login (username / password) is never decoded; the address is shown on the detail page (20 §3.3).
public struct AccountProxy: Codable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let status: String?
    public let expiresAt: String?
    /// JSON `protocol` (socks5, http …).
    public let scheme: String?
    public let host: String?
    public let port: Int?
    public let expiryWarnDays: Int?
    public init(id: Int, name: String, status: String? = nil, expiresAt: String? = nil, scheme: String? = nil, host: String? = nil, port: Int? = nil, expiryWarnDays: Int? = nil) {
        self.id = id; self.name = name; self.status = status; self.expiresAt = expiresAt
        self.scheme = scheme; self.host = host; self.port = port; self.expiryWarnDays = expiryWarnDays
    }
    enum CodingKeys: String, CodingKey {
        case id, name, status, host, port
        case expiresAt = "expires_at", scheme = "protocol", expiryWarnDays = "expiry_warn_days"
    }
}
