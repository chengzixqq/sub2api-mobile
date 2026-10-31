import Foundation

/// One finished test, from any of three sources: test_result (C07), a stored run (C08), or an old server's before/after snapshots.
public struct AccountTestOutcome: Sendable, Equatable {
    public let passed: Bool
    public let timing: AccountTestTiming?
    public let upstreamStatus: Int?
    public let usage: AccountTestResult.Usage?
    /// The account after the test; nil when unknown.
    public let account: AccountTestResult.AccountState?
    public let recovery: AccountTestResult.Recovery?
    /// nil when the change the test made is unknown.
    public let marked: AccountTestResult.Marked?
    public let errorKind: String?
    /// Redacted.
    public let errorText: String?
    public init(passed: Bool, timing: AccountTestTiming? = nil, upstreamStatus: Int? = nil, usage: AccountTestResult.Usage? = nil,
                account: AccountTestResult.AccountState? = nil, recovery: AccountTestResult.Recovery? = nil,
                marked: AccountTestResult.Marked? = nil, errorKind: String? = nil, errorText: String? = nil) {
        self.passed = passed; self.timing = timing; self.upstreamStatus = upstreamStatus; self.usage = usage; self.account = account
        self.recovery = recovery; self.marked = marked; self.errorKind = errorKind; self.errorText = errorText
    }
    /// C07: `data.success` decides; the server's trace is the timing.
    public init(result: AccountTestResult, errorText: String?) {
        self.init(passed: result.success,
                  timing: result.totalMs.map { AccountTestTiming(firstTokenMs: result.firstTokenMs, totalMs: $0, isLocal: false) },
                  upstreamStatus: result.upstreamStatus, usage: result.usage, account: result.account, recovery: result.recovery,
                  marked: result.marked, errorKind: result.account?.errorKind, errorText: errorText)
    }
    /// C08: only a success or failed run has an outcome; `latency_ms` is the total.
    public init?(run: AccountTestRun, after account: AccountTestResult.AccountState? = nil) {
        guard run.status == .success || run.status == .failed else { return nil }
        self.init(passed: run.status == .success,
                  timing: run.latencyMs.map { AccountTestTiming(firstTokenMs: run.firstTokenMs, totalMs: $0, isLocal: false) },
                  upstreamStatus: run.upstreamStatusCode, account: account, recovery: run.recovery, errorKind: run.errorKind,
                  errorText: run.sanitizedErrorText)
    }
    /// C07 fallback: the snapshot taken before the test against `GET :id` after EOF, by the backend's computeAccountTestMarked.
    /// Without the after snapshot nothing about the account is known.
    public static func legacy(passed: Bool, timing: AccountTestTiming?, before: AccountTestResult.AccountState,
                              after: AccountTestResult.AccountState?, now: Date, errorText: String?) -> AccountTestOutcome {
        guard let after else { return AccountTestOutcome(passed: passed, timing: timing, errorText: errorText) }
        let marked = AccountTestResult.Marked(
            error: after.status == "error" && (before.status != "error" || before.errorSummary != after.errorSummary || before.errorKind != after.errorKind),
            rateLimited: advanced(before.rateLimitResetAt, after.rateLimitResetAt),
            tempUnschedulable: advanced(before.tempUnschedulableUntil, after.tempUnschedulableUntil))
        let recovery = passed ? AccountTestResult.Recovery(clearedError: before.status == "error" && after.status != "error",
                                                           clearedRateLimit: isLimited(before, now: now) && !isLimited(after, now: now)) : nil
        return AccountTestOutcome(passed: passed, timing: timing, account: after, recovery: recovery, marked: marked,
                                  errorKind: after.errorKind, errorText: errorText)
    }
    private static func advanced(_ before: Date?, _ after: Date?) -> Bool {
        guard let after else { return false }
        return before.map { after > $0 } ?? true
    }
    private static func isLimited(_ state: AccountTestResult.AccountState, now: Date) -> Bool {
        [state.rateLimitResetAt, state.tempUnschedulableUntil].contains { until in until.map { $0 > now } ?? false }
    }
}

/// “已自动清除…” under a passed result; `offersEnableScheduling` puts “启用调度” beside it.
public struct AccountTestRecoveryNote: Sendable, Equatable {
    public let text: String
    public let offersEnableScheduling: Bool
    public init(text: String, offersEnableScheduling: Bool) { self.text = text; self.offersEnableScheduling = offersEnableScheduling }
}

/// 20 §4.4: what a stream that ended before test_result left behind.
public enum AccountTestInterruptionCheck: Sendable, Equatable {
    /// The latest run started with this attempt and finished.
    case settled(AccountTestOutcome)
    /// Interrupted, still running, unknown, missing, or an older run.
    case interrupted
}

/// 20 §4.3 result wording, §7.3 failure reasons and the default model; shared by the test sheet and the new-account test.
public enum AccountTestPresentation {
    public enum CredentialKind: Sendable, Equatable {
        /// OAuth and Setup Token.
        case token
        case apiKey
        /// Vertex Service Account.
        case vertex
        case bedrock
        public init(accountType: String) {
            switch accountType {
            case "oauth", "setup-token": self = .token
            case "service_account": self = .vertex
            case "bedrock": self = .bedrock
            default: self = .apiKey
            }
        }
    }
    public static let defaultModelLabel = "默认模型"
    public static let interruptedText = "测试被中断，不能判定是否成功"
    public static let alreadyRunningText = "这个账号已有测试在运行"
    public static let noRunText = "还没有测试记录"
    /// A start this long before the attempt's server time still counts as the attempt (S2D1-01).
    public static let interruptionTolerance: TimeInterval = 2

    /// Like Web: the first id containing “sonnet”, else the first. nil (no models, or the list failed) sends a blank model_id and
    /// the server picks the platform default.
    public static func defaultModel(among ids: [String]) -> String? { ids.first { $0.contains("sonnet") } ?? ids.first }
    public static func headerLines(platformName: String, accountName: String, model: String?) -> [String] {
        ["→ 测试 \(platformName) · \(accountName)", "→ 模型 " + (AccountTestOutput.nonBlank(model) ?? defaultModelLabel)]
    }
    /// “首字 1.2s · 总耗时 3.4s[ · 本机计时]” (R10: DisplayFormat's list durations).
    public static func timingText(_ timing: AccountTestTiming) -> String {
        let first = timing.firstTokenMs.map { ["首字 " + DisplayFormat.duration($0, style: .list)] } ?? []
        let local = timing.isLocal ? ["本机计时"] : []
        return (first + ["总耗时 " + DisplayFormat.duration(timing.totalMs, style: .list)] + local).joined(separator: " · ")
    }
    /// “测试通过 · {timing}” / “测试未通过 · {upstream_status}”.
    public static func headline(_ outcome: AccountTestOutcome) -> String {
        if outcome.passed { return outcome.timing.map { "测试通过 · " + timingText($0) } ?? "测试通过" }
        return outcome.upstreamStatus.map { "测试未通过 · \($0)" } ?? "测试未通过"
    }
    /// The new-account sheet's title (20 §7.3).
    public static func failureReasonHeadline(_ outcome: AccountTestOutcome, credential: CredentialKind) -> String {
        "测试未通过 · " + failureReason(errorKind: outcome.errorKind, upstreamStatus: outcome.upstreamStatus, credential: credential)
    }
    public static func recoveryNote(_ outcome: AccountTestOutcome) -> AccountTestRecoveryNote? {
        guard outcome.passed, let recovery = outcome.recovery else { return nil }
        let cleared = [recovery.clearedError ? "错误" : nil, recovery.clearedRateLimit ? "限流" : nil].compactMap { $0 }
        guard !cleared.isEmpty else { return nil }
        let text = "已自动清除" + cleared.joined(separator: "和")
        guard let account = outcome.account else { return AccountTestRecoveryNote(text: text, offersEnableScheduling: false) }
        return account.schedulable ? AccountTestRecoveryNote(text: text + "，账号恢复调度", offersEnableScheduling: false)
            : AccountTestRecoveryNote(text: text + "，仍暂停调度", offersEnableScheduling: true)
    }
    /// The line under a failed result; nil when the account's state after the test is unknown.
    public static func failureNote(_ outcome: AccountTestOutcome, credential: CredentialKind) -> String? {
        guard !outcome.passed, outcome.account != nil || outcome.marked != nil else { return nil }
        let marked = outcome.marked
        let inError = marked?.error == true || outcome.account?.status == "error"
        if inError, isCredentialFailure(errorKind: outcome.errorKind, upstreamStatus: outcome.upstreamStatus) {
            switch credential {
            case .token: return "令牌无效，账号保持错误。重新授权后再测试连接"
            case .apiKey: return "凭据无效，账号保持错误。更换 API Key 后再测试连接"
            case .vertex, .bedrock: return "凭据无效，账号保持错误。在 Web 中更换凭据后再测试连接"
            }
        }
        if marked?.error == true { return "后端已把账号标为“错误”，并停止调度，不会接收请求" }
        if marked?.rateLimited == true { return "测试触发了上游限流，账号进入限流中" }
        if marked?.tempUnschedulable == true { return "测试触发了临时不可调度" }
        return "账号状态没有改变，可以稍后重试"
    }
    /// “输入 1,234 · 输出 56 tokens” under a passed result.
    public static func usageText(_ outcome: AccountTestOutcome) -> String? {
        guard outcome.passed, let usage = outcome.usage else { return nil }
        return "输入 \(DisplayFormat.grouped(usage.inputTokens)) · 输出 \(DisplayFormat.grouped(usage.outputTokens)) tokens"
    }
    /// The monospaced raw line of a failure: “上游返回 {code} · {error}”.
    public static func failureDetailLine(_ outcome: AccountTestOutcome) -> String? {
        guard !outcome.passed else { return nil }
        let parts = [outcome.upstreamStatus.map { "上游返回 \($0)" }, AccountTestOutput.nonBlank(outcome.errorText).map(AccountTestOutput.sanitize)]
        let present = parts.compactMap { $0 }
        return present.isEmpty ? nil : present.joined(separator: " · ")
    }
    /// 20 §7.3: `error_kind` first; the upstream status only when the kind says nothing more.
    public static func failureReason(errorKind: String?, upstreamStatus: Int?, credential: CredentialKind) -> String {
        switch errorKind {
        case "auth", "token_refresh": return authReason(credential)
        case "forbidden": return forbiddenReason(credential, upstreamStatus: upstreamStatus)
        case "quota": return "上游额度不足"
        case "rate_limit": return "上游限流"
        default: break
        }
        switch upstreamStatus {
        case 401?: return authReason(credential)
        case 403?: return forbiddenReason(credential, upstreamStatus: 403)
        case 429?: return "上游限流"
        case let status?: return "上游返回 \(status)"
        case nil: return "上游拒绝了这次测试请求"
        }
    }
    public static func isCredentialFailure(errorKind: String?, upstreamStatus: Int?) -> Bool {
        ["auth", "forbidden", "token_refresh"].contains(errorKind ?? "") || upstreamStatus == 401 || upstreamStatus == 403
    }
    /// 20 §4.4: the latest run counts when it started no earlier than this attempt (server time, less the tolerance) and finished.
    public static func interruptionCheck(latest: AccountTestRun?, attemptStartedAt: Date,
                                         after account: AccountTestResult.AccountState? = nil) -> AccountTestInterruptionCheck {
        guard let latest, let started = latest.startedAt, started >= attemptStartedAt.addingTimeInterval(-interruptionTolerance),
              let outcome = AccountTestOutcome(run: latest, after: account) else { return .interrupted }
        return .settled(outcome)
    }

    private static func authReason(_ credential: CredentialKind) -> String {
        credential == .token ? "令牌无效或已撤销" : "API Key 无效或已撤销"
    }
    private static func forbiddenReason(_ credential: CredentialKind, upstreamStatus: Int?) -> String {
        switch credential {
        case .token: return "授权的账号没有可用额度或权限"
        case .vertex: return "Service Account 没有 Vertex AI 权限"
        case .bedrock: return "AWS 凭据无效或没有 Bedrock 权限"
        case .apiKey: return upstreamStatus.map { "上游返回 \($0)" } ?? "上游拒绝了这次测试请求"
        }
    }
}

extension AccountTestResult.AccountState {
    /// The before-test snapshot of the C07 fallback.
    public init(account: UpstreamAccount) {
        self.init(status: account.status, schedulable: account.schedulable,
                  rateLimitResetAt: ServerTime.parseTimestamp(account.rateLimitResetAt),
                  tempUnschedulableUntil: ServerTime.parseTimestamp(account.tempUnschedulableUntil),
                  errorSummary: account.errorSummary, errorKind: account.errorKind)
    }
}
