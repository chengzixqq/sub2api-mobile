import Foundation

/// The whole `extra` is kept as sent (20 §1.7; the PUT fallback merges onto it); only memory holds it, never a log or a page.
public struct AccountExtra: Codable, Sendable {
    public let raw: JSONValue
    public let upstreamBillingProbe: AccountBillingProbe?
    /// `extra.model_rate_limits` as sent; read it through `modelRateLimits`.
    public let modelRateLimitEntries: [String: ModelRateLimitEntry]?
    /// One model scope; anything but an object reads as an entry without a time.
    public struct ModelRateLimitEntry: Codable, Sendable, Equatable {
        public let rateLimitResetAt: String?
        public init(rateLimitResetAt: String? = nil) { self.rateLimitResetAt = rateLimitResetAt }
        enum CodingKeys: String, CodingKey { case rateLimitResetAt = "rate_limit_reset_at" }
        public init(from decoder: any Decoder) throws {
            rateLimitResetAt = try? decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .rateLimitResetAt)
        }
    }
    /// Entries with a readable reset time, by model name; not filtered by `now` (AccountDisplayState keeps the active ones).
    public var modelRateLimits: [AccountModelRateLimit] {
        let parser = TimestampParser()
        return (modelRateLimitEntries ?? [:]).compactMap { model, entry in
            parser.date(entry.rateLimitResetAt).map { AccountModelRateLimit(model: model, resetAt: $0) }
        }.sorted { $0.model < $1.model }
    }
    public subscript(key: String) -> JSONValue? { raw[key] }
    /// For fixtures: the same derivation as a decoded `extra`.
    public init(raw: JSONValue) throws { self = try raw.decode(AccountExtra.self) }
    public init(upstreamBillingProbe: AccountBillingProbe? = nil, modelRateLimitEntries: [String: ModelRateLimitEntry]? = nil) {
        self.upstreamBillingProbe = upstreamBillingProbe; self.modelRateLimitEntries = modelRateLimitEntries
        var fields = [String: JSONValue]()
        fields[CodingKeys.upstreamBillingProbe.rawValue] = upstreamBillingProbe.flatMap { try? JSONValue(encoding: $0) }
        fields[CodingKeys.modelRateLimitEntries.rawValue] = modelRateLimitEntries.flatMap { try? JSONValue(encoding: $0) }
        raw = .object(fields)
    }
    enum CodingKeys: String, CodingKey { case upstreamBillingProbe = "upstream_billing_probe", modelRateLimitEntries = "model_rate_limits" }
    /// A malformed `model_rate_limits` is dropped on its own, and an `extra` that is not an object derives nothing; neither
    /// fails the whole account list.
    public init(from decoder: any Decoder) throws {
        raw = try JSONValue(from: decoder)
        guard raw.objectValue != nil else { upstreamBillingProbe = nil; modelRateLimitEntries = nil; return }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        upstreamBillingProbe = try c.decodeIfPresent(AccountBillingProbe.self, forKey: .upstreamBillingProbe)
        modelRateLimitEntries = try? c.decodeIfPresent([String: ModelRateLimitEntry].self, forKey: .modelRateLimitEntries)
    }
    public func encode(to encoder: any Encoder) throws { try raw.encode(to: encoder) }
}

/// C10 `token_status`, for OAuth and Setup Token accounts; times stay raw strings until displayed.
public struct AccountTokenStatus: Codable, Sendable, Equatable {
    public let expiresAt: String?
    public let lifetimeSeconds: Int64?
    public let refreshedAt: String?
    public let autoRefresh: Bool?
    public init(expiresAt: String? = nil, lifetimeSeconds: Int64? = nil, refreshedAt: String? = nil, autoRefresh: Bool? = nil) {
        self.expiresAt = expiresAt; self.lifetimeSeconds = lifetimeSeconds; self.refreshedAt = refreshedAt; self.autoRefresh = autoRefresh
    }
    enum CodingKeys: String, CodingKey {
        case expiresAt = "expires_at", lifetimeSeconds = "lifetime_seconds", refreshedAt = "refreshed_at", autoRefresh = "auto_refresh"
    }
}

public struct AccountSchedulerScore: Codable, Sendable {
    public let groupID: Int?
    public let groupName: String?
    public let groupPriority: Int?
    public let baseScore: Double
    public let stickyScore: Double
    public let stickyScoreInfinity: Bool
    public let stickyWeightedEnabled: Bool
    public init(groupID: Int? = nil, groupName: String? = nil, groupPriority: Int? = nil, baseScore: Double, stickyScore: Double, stickyScoreInfinity: Bool, stickyWeightedEnabled: Bool) {
        self.groupID = groupID; self.groupName = groupName; self.groupPriority = groupPriority
        self.baseScore = baseScore; self.stickyScore = stickyScore
        self.stickyScoreInfinity = stickyScoreInfinity; self.stickyWeightedEnabled = stickyWeightedEnabled
    }
    enum CodingKeys: String, CodingKey {
        case groupID = "group_id", groupName = "group_name", groupPriority = "group_priority"
        case baseScore = "base_score", stickyScore = "sticky_score"
        case stickyScoreInfinity = "sticky_score_infinity", stickyWeightedEnabled = "sticky_weighted_enabled"
    }
}

public struct AccountBillingProbe: Codable, Sendable {
    public let status: String
    public let data: Snapshot?
    public let freshUntil: String?
    public struct Snapshot: Codable, Sendable {
        public let effectiveRateMultiplier: Decimal?
        public let observedAt: String?
        enum CodingKeys: String, CodingKey { case effectiveRateMultiplier = "effective_rate_multiplier", observedAt = "observed_at" }
        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            effectiveRateMultiplier = try c.optionalDecimal(.effectiveRateMultiplier)
            observedAt = try c.decodeIfPresent(String.self, forKey: .observedAt)
        }
    }
    enum CodingKeys: String, CodingKey { case status, data; case freshUntil = "fresh_until" }
    /// A cached declaration is historical evidence, not a locally recomputed live peak-rate claim.
    public func historicalMultiplier(at now: Date = Date()) -> Decimal? {
        guard status == "ok", let freshUntil, let expiry = ServerTime.parseTimestamp(freshUntil), expiry > now,
              let data, let observedAt = data.observedAt, let observed = ServerTime.parseTimestamp(observedAt), observed <= now else { return nil }
        return data.effectiveRateMultiplier
    }
}

public enum AccountFieldPresentation {
    /// `now` is the site's ServerClock time (20 §0.6).
    public static func value(_ field: AccountListField, account: UpstreamAccount, today: AccountTodayStats? = nil, now: Date) -> String {
        switch field {
        case .platform: account.platform
        case .authenticationType: account.type
        case .groups:
            if !account.groups.isEmpty { account.groups.map(\.name).joined(separator: "、") }
            else if !account.groupIDs.isEmpty { account.groupIDs.map { "#\($0)" }.joined(separator: "、") }
            else { "未分组" }
        case .concurrency: number(account.currentConcurrency)
        case .capacity: capacity(account)
        case .rpm: number(account.currentRPM)
        case .baseRPM: number(account.baseRPM)
        case .priority: number(account.priority)
        case .rateMultiplier: account.rateMultiplier.map { decimal($0) + "×" } ?? DisplayFormat.missing
        case .status: status(account, now: now)
        case .schedulable: account.schedulable ? "参与调度" : "暂停调度"
        case .expiresAt: ListFieldPresentation.timestamp(seconds: account.expiresAt)
        case .lastUsedAt: ListFieldPresentation.timestamp(account.lastUsedAt)
        case .createdAt: ListFieldPresentation.timestamp(account.createdAt)
        case .notes: account.notes.flatMap { $0.isEmpty ? nil : $0 } ?? "无"
        case .usage: DisplayFormat.money(account.quotaUsed)
        case .accountID: String(account.id)
        case .todayStats:
            if let today {
                "请求 \(DisplayFormat.grouped(today.requests)) · Tokens \(DisplayFormat.compact(today.tokens)) · 扣费 \(DisplayFormat.money(today.userCost)) · 成本 \(DisplayFormat.money(today.cost))"
            } else { DisplayFormat.missing }
        case .window:
            if account.sessionWindowStart != nil || account.sessionWindowEnd != nil {
                "会话窗口 \(ListFieldPresentation.timestamp(account.sessionWindowStart)) – \(ListFieldPresentation.timestamp(account.sessionWindowEnd))"
            } else { DisplayFormat.missing }
        case .proxy: account.proxy.map { "\($0.name)（#\($0.id)）" } ?? DisplayFormat.missing
        case .loadFactor: number(account.loadFactor)
        case .schedulerScore:
            if let scores = account.schedulerScores, !scores.isEmpty { scores.map { schedulerScore($0, grouped: true) }.joined(separator: " · ") }
            else if let score = account.schedulerScore { schedulerScore(score, grouped: false) }
            else { DisplayFormat.missing }
        case .upstreamBilling:
            if let probe = account.extra?.upstreamBillingProbe, let multiplier = probe.historicalMultiplier(at: now) {
                "上次探测 \(decimal(multiplier))×（\(ListFieldPresentation.timestamp(probe.data?.observedAt))）"
            } else { DisplayFormat.missing }
        }
    }

    /// 20 §0.2 status word; an expired auto-pause reads “暂停 · 已过期”.
    public static func status(_ account: UpstreamAccount, now: Date) -> String {
        let display = AccountDisplayState(account, now: now)
        return display.note.map { "\(display.label) · \($0)" } ?? display.label
    }

    public static func capacity(_ account: UpstreamAccount) -> String {
        // A zero configured limit is shown as received; its meaning is not assumed to be unlimited.
        var values = ["并发 \(number(account.currentConcurrency)) / \(number(account.concurrency))"]
        if let probe = account.probeConcurrency { values.append("探测并发 \(number(probe))") }
        if let limit = account.windowCostLimit, limit > 0 {
            values.append("窗口标准费用 \(DisplayFormat.money(account.currentWindowCost)) / \(DisplayFormat.money(limit))")
        }
        if let limit = account.maxSessions, limit > 0 { values.append("会话 \(number(account.activeSessions)) / \(number(limit))") }
        if let limit = account.baseRPM, limit > 0 { values.append("调度 RPM \(number(account.schedulingRPM)) / \(number(limit))（自然分钟）") }
        for (title, used, limit) in [("日配额", account.quotaDailyUsed, account.quotaDailyLimit), ("周配额", account.quotaWeeklyUsed, account.quotaWeeklyLimit), ("总配额", account.quotaUsed, account.quotaLimit)] {
            if let limit, limit > 0 { values.append("\(title) \(DisplayFormat.money(used)) / \(DisplayFormat.money(limit))") }
        }
        return values.joined(separator: " · ")
    }

    private static func number(_ value: Int?) -> String { DisplayFormat.grouped(value) }
    /// Multipliers keep every digit the server sent.
    private static func decimal(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
    private static func schedulerScore(_ score: AccountSchedulerScore, grouped: Bool) -> String {
        let group = grouped ? (score.groupName ?? score.groupID.map { "#\($0)" } ?? "未分组") + "：" : ""
        // Weighted scores are small fractions; compact numbers would round them to whole numbers.
        let sticky = score.stickyScoreInfinity ? "∞" : score.stickyWeightedEnabled ? DisplayFormat.decimal(score.stickyScore, maxFractionDigits: 2) : "未启用"
        return "\(group)基础分 \(DisplayFormat.decimal(score.baseScore, maxFractionDigits: 2)) / 粘性分 \(sticky)"
    }
}
