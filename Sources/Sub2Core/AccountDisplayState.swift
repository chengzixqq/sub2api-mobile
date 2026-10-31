import Foundation

/// A model scope whose own rate limit has not reset yet (20 §0.2; backend `activeModelRateLimits`). It never changes the account's tone.
public struct AccountModelRateLimit: Sendable, Equatable, Hashable {
    public let model: String
    public let resetAt: Date
    public init(model: String, resetAt: Date) { self.model = model; self.resetAt = resetAt }
}

/// The fields the D02 order reads, already parsed. Build it when the data changes; a ticking countdown only passes a new `now`
/// to `AccountDisplayState`, so a list of 2,000 rows does not re-parse its timestamps every second.
public struct AccountStateInput: Sendable, Equatable {
    public let status: String
    public let schedulable: Bool
    public let overloadUntil: Date?
    public let rateLimitResetAt: Date?
    public let tempUnschedulableUntil: Date?
    /// `TempUnschedState` JSON or plain upstream text: parsed for the reason phrase, never shown.
    public let tempUnschedulableReason: String?
    /// nil when the source has no such field (status-summary items): row 7 then follows the server's `state`.
    public let autoPauseOnExpired: Bool?
    public let expiresAt: Date?
    public let reportedState: AccountScheduleState?
    public let errorSummary: String?
    public let errorKind: String?
    public let errorStatusCode: Int?
    /// Only for the credential-error guess when C02 fields are missing; never displayed (R12).
    public let errorMessage: String?
    public let modelRateLimits: [AccountModelRateLimit]

    public init(status: String, schedulable: Bool, overloadUntil: Date? = nil, rateLimitResetAt: Date? = nil, tempUnschedulableUntil: Date? = nil,
                tempUnschedulableReason: String? = nil, autoPauseOnExpired: Bool? = nil, expiresAt: Date? = nil, reportedState: AccountScheduleState? = nil,
                errorSummary: String? = nil, errorKind: String? = nil, errorStatusCode: Int? = nil, errorMessage: String? = nil,
                modelRateLimits: [AccountModelRateLimit] = []) {
        self.status = status; self.schedulable = schedulable
        self.overloadUntil = overloadUntil; self.rateLimitResetAt = rateLimitResetAt; self.tempUnschedulableUntil = tempUnschedulableUntil
        self.tempUnschedulableReason = tempUnschedulableReason; self.autoPauseOnExpired = autoPauseOnExpired; self.expiresAt = expiresAt
        self.reportedState = reportedState; self.errorSummary = errorSummary; self.errorKind = errorKind; self.errorStatusCode = errorStatusCode
        self.errorMessage = errorMessage; self.modelRateLimits = modelRateLimits
    }
    /// Account DTO: RFC3339 windows, Unix-second `expires_at` (00 §6.4).
    public init(_ account: UpstreamAccount) {
        let parser = TimestampParser()
        self.init(status: account.status, schedulable: account.schedulable, overloadUntil: parser.date(account.overloadUntil),
                  rateLimitResetAt: parser.date(account.rateLimitResetAt), tempUnschedulableUntil: parser.date(account.tempUnschedulableUntil),
                  tempUnschedulableReason: account.tempUnschedulableReason, autoPauseOnExpired: account.autoPauseOnExpired ?? false,
                  expiresAt: ServerTime.date(unixSeconds: account.expiresAt), errorSummary: account.errorSummary, errorKind: account.errorKind,
                  errorStatusCode: account.errorStatusCode, errorMessage: account.errorMessage, modelRateLimits: account.extra?.modelRateLimits ?? [])
    }
    /// A status-summary item has no C02 fields; the same account from `accounts?status=error` supplies them (10 §1.2).
    /// An account with another id is ignored.
    public init(_ item: AccountStatusItem, structuredError account: UpstreamAccount? = nil) {
        let error = account?.id == item.id ? account : nil
        self.init(status: item.status, schedulable: item.schedulable, overloadUntil: item.overloadUntil, rateLimitResetAt: item.rateLimitResetAt,
                  tempUnschedulableUntil: item.tempUnschedulableUntil, tempUnschedulableReason: item.tempUnschedulableReason,
                  expiresAt: item.expiresAt, reportedState: item.state, errorSummary: error?.errorSummary, errorKind: error?.errorKind,
                  errorStatusCode: error?.errorStatusCode, errorMessage: error?.errorMessage, modelRateLimits: item.modelRateLimits)
    }
}

/// 20 §0.2: the only place the App derives an account's status word, tone, countdown, “已停止调度” and reason phrase.
/// `now` is always the site's ServerClock time (20 §0.6). When a countdown reaches zero, derive again with the new `now`.
public struct AccountDisplayState: Sendable, Equatable {
    public static let stoppedMark = "已停止调度"
    public static let expiredNote = "已过期"
    public static let unknownErrorReason = "上游返回异常"
    public let state: AccountScheduleState
    /// End of the window for 过载中 / 限流中 / 临时不可调度.
    public let countdownTarget: Date?
    /// A timed state with scheduling switched off (D02 `stopped`).
    public let isStopped: Bool
    /// Row 7: paused because the account expired with auto-pause on.
    public let isExpiredPause: Bool
    public let reason: String?
    /// Decides between “更换 API Key…” and “重新授权…”; only for 错误.
    public let isCredentialError: Bool
    public let modelRateLimits: [AccountModelRateLimit]
    public var label: String { state.label }
    public var tone: Tone { state.tone }
    public var note: String? { isExpiredPause ? Self.expiredNote : nil }

    public init(_ input: AccountStateInput, now: Date) {
        let derived = Self.derive(input, now: now)
        state = derived.state; countdownTarget = derived.target; isExpiredPause = derived.expiredPause
        isStopped = derived.state.isLimited && !input.schedulable
        reason = Self.reasonPhrase(derived.state, input)
        isCredentialError = derived.state == .error && Self.looksLikeCredentialError(input)
        modelRateLimits = Self.activeModelRateLimits(input.modelRateLimits, now: now)
    }
    public init(_ account: UpstreamAccount, now: Date) { self.init(AccountStateInput(account), now: now) }
    public init(_ item: AccountStatusItem, structuredError account: UpstreamAccount? = nil, now: Date) {
        self.init(AccountStateInput(item, structuredError: account), now: now)
    }

    /// Backend `service.AccountScheduleState` (account_status_summary.go:63-82), compared the way Go does.
    public static func scheduleState(_ input: AccountStateInput, now: Date) -> AccountScheduleState { derive(input, now: now).state }

    private static func derive(_ input: AccountStateInput, now: Date) -> (state: AccountScheduleState, target: Date?, expiredPause: Bool) {
        if input.status == "error" { return (.error, nil, false) }
        if input.status != "active" { return (.inactive, nil, false) }
        let windows: [(AccountScheduleState, Date?)] = [
            (.overloaded, input.overloadUntil), (.rateLimited, input.rateLimitResetAt), (.tempUnschedulable, input.tempUnschedulableUntil)
        ]
        for (state, end) in windows { if let end, end > now { return (state, end, false) } }
        if !input.schedulable { return (.paused, nil, false) }
        // Expiry only moves forward, so a summary item the server judged paused (schedulable, no window) is still an expired pause.
        let autoPause = input.autoPauseOnExpired ?? (input.reportedState == .paused)
        if autoPause, let expiresAt = input.expiresAt, expiresAt <= now { return (.paused, nil, true) }
        return (.available, nil, false)
    }

    private static func reasonPhrase(_ state: AccountScheduleState, _ input: AccountStateInput) -> String? {
        switch state {
        case .error: nonEmpty(input.errorSummary) ?? unknownErrorReason
        case .overloaded: "上游 529" // Only `handle529` sets overload_until.
        case .rateLimited: "上游 429"
        case .tempUnschedulable: temporaryReason(input.tempUnschedulableReason)
        case .paused, .inactive, .available: nil
        }
    }

    /// `TempUnschedState`: “上游 {status_code}” when the code is positive, plus “ · 规则 #n” like Web; anything else “临时不可调度”.
    static func temporaryReason(_ raw: String?) -> String {
        let fallback = "临时不可调度"
        guard let data = raw?.data(using: .utf8), let parsed = try? JSONDecoder().decode(TempUnschedReason.self, from: data) else { return fallback }
        let code = parsed.statusCode ?? 0
        let head = code > 0 ? "上游 \(code)" : fallback
        guard nonEmpty(parsed.matchedKeyword) != nil, let rule = parsed.ruleIndex, rule >= 0 else { return head }
        return "\(head) · 规则 #\(rule + 1)"
    }

    /// C02 first (`error_kind`, `error_status_code`); the case-insensitive regex only runs when both are missing.
    static func looksLikeCredentialError(_ input: AccountStateInput) -> Bool {
        let kind = nonEmpty(input.errorKind)
        if kind != nil || input.errorStatusCode != nil {
            return kind.map { ["auth", "forbidden", "token_refresh"].contains($0) } == true || [401, 403].contains(input.errorStatusCode ?? 0)
        }
        guard let message = input.errorMessage else { return false }
        return message.range(of: #"\b40[13]\b|invalid_api_key|token"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func activeModelRateLimits(_ limits: [AccountModelRateLimit], now: Date) -> [AccountModelRateLimit] {
        limits.filter { $0.resetAt > now }.sorted { $0.model < $1.model }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

/// Each field is read on its own: a mistyped one is treated as missing.
private struct TempUnschedReason: Decodable {
    let statusCode: Int?
    let matchedKeyword: String?
    let ruleIndex: Int?
    enum CodingKeys: String, CodingKey { case statusCode = "status_code", matchedKeyword = "matched_keyword", ruleIndex = "rule_index" }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        statusCode = try? c.decodeIfPresent(Int.self, forKey: .statusCode)
        matchedKeyword = try? c.decodeIfPresent(String.self, forKey: .matchedKeyword)
        ruleIndex = try? c.decodeIfPresent(Int.self, forKey: .ruleIndex)
    }
}

extension AccountScheduleState {
    /// 20 §0.2 受限: the timed states.
    public var isLimited: Bool { self == .overloaded || self == .rateLimited || self == .tempUnschedulable }
    /// 20 §0.2 需处理.
    public var needsAttention: Bool { self == .error || isLimited }
}

extension UpstreamAccount {
    /// Backend `Account.IsOAuth`: OAuth and Setup Token accounts hold an access token; the rest are key accounts.
    public var isTokenAccount: Bool { type == "oauth" || type == "setup-token" }
}
