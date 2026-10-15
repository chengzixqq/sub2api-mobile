import Foundation

/// Only display metadata is retained. Proxy credentials, addresses and backend errors are not decoded.
public struct AccountProxy: Codable, Sendable, Equatable {
    public let id: Int
    public let name: String
    public let status: String?
    public let expiresAt: String?
    public init(id: Int, name: String, status: String? = nil, expiresAt: String? = nil) {
        self.id = id; self.name = name; self.status = status; self.expiresAt = expiresAt
    }
    enum CodingKeys: String, CodingKey { case id, name, status; case expiresAt = "expires_at" }
}

public struct AccountExtra: Codable, Sendable {
    public let upstreamBillingProbe: AccountBillingProbe?
    public init(upstreamBillingProbe: AccountBillingProbe? = nil) { self.upstreamBillingProbe = upstreamBillingProbe }
    enum CodingKeys: String, CodingKey { case upstreamBillingProbe = "upstream_billing_probe" }
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
        guard status == "ok", let freshUntil, let expiry = Self.date(freshUntil), expiry > now,
              let data, let observedAt = data.observedAt, let observed = Self.date(observedAt), observed <= now else { return nil }
        return data.effectiveRateMultiplier
    }
    private static func date(_ raw: String) -> Date? {
        let parser = ISO8601DateFormatter()
        if let date = parser.date(from: raw) { return date }
        parser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return parser.date(from: raw)
    }
}

public enum AccountFieldPresentation {
    public static func value(_ field: AccountListField, account: UpstreamAccount, today: AccountTodayStats? = nil) -> String {
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
        case .rateMultiplier: account.rateMultiplier.map { decimal($0) + "×" } ?? "不可用"
        case .status:
            switch account.status { case "active": "正常"; case "inactive": "已禁用"; case "error": "异常"; default: account.status }
        case .schedulable: account.schedulable ? "参与调度" : "暂停调度"
        case .expiresAt: ListFieldPresentation.timestamp(seconds: account.expiresAt)
        case .lastUsedAt: ListFieldPresentation.timestamp(account.lastUsedAt)
        case .createdAt: ListFieldPresentation.timestamp(account.createdAt)
        case .notes: account.notes.flatMap { $0.isEmpty ? nil : $0 } ?? "无"
        case .usage: account.quotaUsed.map(decimal) ?? "不可用"
        case .accountID: String(account.id)
        case .todayStats:
            if let today { "请求 \(today.requests.formatted()) · Tokens \(DashboardPresentation.compactNumber(today.tokens)) · 扣费 \(DashboardPresentation.money(today.userCost)) · 成本 \(DashboardPresentation.money(today.cost))" }
            else { "不可用" }
        case .window:
            if account.sessionWindowStart != nil || account.sessionWindowEnd != nil {
                "会话窗口 \(ListFieldPresentation.timestamp(account.sessionWindowStart)) – \(ListFieldPresentation.timestamp(account.sessionWindowEnd))"
            } else { "不可用" }
        case .proxy: account.proxy.map { "\($0.name)（#\($0.id)）" } ?? "不可用"
        case .loadFactor: number(account.loadFactor)
        case .schedulerScore:
            if let scores = account.schedulerScores, !scores.isEmpty { scores.map { schedulerScore($0, grouped: true) }.joined(separator: " · ") }
            else if let score = account.schedulerScore { schedulerScore(score, grouped: false) }
            else { "不可用" }
        case .upstreamBilling:
            if let probe = account.extra?.upstreamBillingProbe, let multiplier = probe.historicalMultiplier() {
                "上次探测 \(decimal(multiplier))×（\(ListFieldPresentation.timestamp(probe.data?.observedAt))）"
            } else { "不可用" }
        }
    }

    public static func capacity(_ account: UpstreamAccount) -> String {
        // A zero configured limit is shown as received; its meaning is not assumed to be unlimited.
        var values = ["并发 \(number(account.currentConcurrency)) / \(number(account.concurrency))"]
        if let probe = account.probeConcurrency { values.append("探测并发 \(probe)") }
        if let limit = account.windowCostLimit, limit > 0 {
            values.append("窗口标准费用 \(DashboardPresentation.money(account.currentWindowCost)) / \(DashboardPresentation.money(limit))")
        }
        if let limit = account.maxSessions, limit > 0 { values.append("会话 \(number(account.activeSessions)) / \(limit)") }
        if let limit = account.baseRPM, limit > 0 { values.append("调度 RPM \(number(account.schedulingRPM)) / \(limit)（自然分钟）") }
        for (title, used, limit) in [("日配额", account.quotaDailyUsed, account.quotaDailyLimit), ("周配额", account.quotaWeeklyUsed, account.quotaWeeklyLimit), ("总配额", account.quotaUsed, account.quotaLimit)] {
            if let limit, limit > 0 { values.append("\(title) \(DashboardPresentation.money(used)) / \(DashboardPresentation.money(limit))") }
        }
        return values.joined(separator: " · ")
    }

    private static func number(_ value: Int?) -> String { value.map(String.init) ?? "不可用" }
    private static func decimal(_ value: Decimal) -> String { NSDecimalNumber(decimal: value).stringValue }
    private static func schedulerScore(_ score: AccountSchedulerScore, grouped: Bool) -> String {
        let group = grouped ? (score.groupName ?? score.groupID.map { "#\($0)" } ?? "未分组") + "：" : ""
        let sticky = score.stickyScoreInfinity ? "∞" : score.stickyWeightedEnabled ? DashboardPresentation.compactNumber(score.stickyScore) : "未启用"
        return "\(group)基础分 \(DashboardPresentation.compactNumber(score.baseScore)) / 粘性分 \(sticky)"
    }
}
