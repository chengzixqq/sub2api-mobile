import Foundation
import Testing
@testable import Sub2Core

private let now = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(seconds) }
private func wire(_ date: Date) -> String { ServerTime.utcTimestamp(date) }
private func display(_ input: AccountStateInput, at time: Date = now) -> AccountDisplayState { AccountDisplayState(input, now: time) }
private func active(schedulable: Bool = true, overload: Date? = nil, rateLimit: Date? = nil, temp: Date? = nil) -> AccountStateInput {
    AccountStateInput(status: "active", schedulable: schedulable, overloadUntil: overload, rateLimitResetAt: rateLimit, tempUnschedulableUntil: temp)
}
private func decodedAccount(_ fields: String = "") throws -> UpstreamAccount {
    let base = #"{"id":9,"name":"账号","platform":"anthropic","type":"oauth","status":"active","schedulable":true"#
    return try JSONDecoder().decode(UpstreamAccount.self, from: Data((base + (fields.isEmpty ? "" : "," + fields) + "}").utf8))
}

// MARK: 20 §0.2 table, one row per case

struct D02Row: Sendable, CustomTestStringConvertible {
    let name: String
    let input: AccountStateInput
    let label: String
    let tone: Tone
    let target: Date?
    var testDescription: String { name }
}

private let d02Rows: [D02Row] = [
    D02Row(name: "1 error 先于限时窗口", input: AccountStateInput(status: "error", schedulable: false, overloadUntil: at(60)), label: "错误", tone: .critical, target: nil),
    D02Row(name: "2 inactive", input: AccountStateInput(status: "inactive", schedulable: true, rateLimitResetAt: at(60)), label: "停用", tone: .neutral, target: nil),
    D02Row(name: "2 历史值 disabled", input: AccountStateInput(status: "disabled", schedulable: true, rateLimitResetAt: at(60)), label: "停用", tone: .neutral, target: nil),
    D02Row(name: "2 未知值", input: AccountStateInput(status: "banned", schedulable: true, rateLimitResetAt: at(60)), label: "停用", tone: .neutral, target: nil),
    D02Row(name: "3 过载", input: active(overload: at(72), rateLimit: at(120), temp: at(180)), label: "过载中", tone: .critical, target: at(72)),
    D02Row(name: "4 限流", input: active(rateLimit: at(120), temp: at(180)), label: "限流中", tone: .caution, target: at(120)),
    D02Row(name: "5 临时不可调度", input: active(temp: at(180)), label: "临时不可调度", tone: .caution, target: at(180)),
    D02Row(name: "6 暂停", input: active(schedulable: false, overload: at(-1), rateLimit: at(-60), temp: at(-5)), label: "暂停", tone: .neutral, target: nil),
    D02Row(name: "7 到期自动暂停", input: AccountStateInput(status: "active", schedulable: true, autoPauseOnExpired: true, expiresAt: at(-1)), label: "暂停", tone: .neutral, target: nil),
    D02Row(name: "8 正常", input: AccountStateInput(status: "active", schedulable: true, autoPauseOnExpired: true, expiresAt: at(3_600)), label: "正常", tone: .ok, target: nil)
]

@Test(arguments: d02Rows)
func displayStateFollowsD02Order(row: D02Row) {
    let result = display(row.input)
    #expect(result.label == row.label && result.tone == row.tone)
    #expect(result.countdownTarget == row.target)
    #expect(AccountDisplayState.scheduleState(row.input, now: now) == result.state)
    #expect(result.note == (row.name.hasPrefix("7") ? "已过期" : nil))
    #expect(result.isExpiredPause == row.name.hasPrefix("7"))
    #expect(!result.isStopped)
}

@Test func windowBoundariesMatchGoComparison() {
    // Go `After(now)`: a window ending exactly now is over.
    #expect(display(active(overload: now)).state == .available)
    #expect(display(active(overload: now, rateLimit: at(1))).state == .rateLimited)
    let expiring = AccountStateInput(status: "active", schedulable: true, autoPauseOnExpired: true, expiresAt: now)
    #expect(display(expiring).state == .paused && display(expiring).note == "已过期")
    #expect(display(expiring, at: at(-1)).state == .available)
    #expect(display(AccountStateInput(status: "active", schedulable: true, autoPauseOnExpired: false, expiresAt: at(-60))).state == .available)
    #expect(display(AccountStateInput(status: "active", schedulable: true, autoPauseOnExpired: true)).state == .available)
    let past = display(active(overload: at(-1), rateLimit: at(-1), temp: at(-1)))
    #expect(past.state == .available && past.countdownTarget == nil && past.reason == nil)
    // `status` is compared exactly, like the backend.
    #expect(display(AccountStateInput(status: "Active", schedulable: true)).state == .inactive)
    #expect(display(AccountStateInput(status: "ERROR", schedulable: true)).state == .inactive)
}

@Test(arguments: [true, false])
func stoppedMarkOnlyForTimedStatesWithSchedulingOff(schedulable: Bool) {
    for input in [active(schedulable: schedulable, overload: at(30)), active(schedulable: schedulable, rateLimit: at(30)), active(schedulable: schedulable, temp: at(30))] {
        #expect(display(input).isStopped == !schedulable)
    }
    #expect(!display(AccountStateInput(status: "error", schedulable: schedulable, overloadUntil: at(30))).isStopped)
    #expect(!display(AccountStateInput(status: "inactive", schedulable: schedulable, rateLimitResetAt: at(30))).isStopped)
    #expect(!display(active(schedulable: schedulable)).isStopped)
    #expect(AccountDisplayState.stoppedMark == "已停止调度")
}

@Test func countdownExpiryRederivesIntoNextTimedState() {
    let input = active(overload: at(10), rateLimit: at(60), temp: at(90))
    let steps: [(TimeInterval, AccountScheduleState, Date?)] = [(0, .overloaded, at(10)), (10, .rateLimited, at(60)), (60, .tempUnschedulable, at(90)), (90, .available, nil)]
    for (offset, state, target) in steps {
        let result = display(input, at: at(offset))
        #expect(result.state == state && result.countdownTarget == target, "t+\(offset)")
    }
}

// MARK: Reason phrases (R12)

@Test func reasonPhrasesNeverEchoRawErrors() {
    let secret = "Authentication failed (401): sk-fixture-secret"
    #expect(display(AccountStateInput(status: "error", schedulable: true, errorSummary: "Authentication failed (401)", errorMessage: secret)).reason == "Authentication failed (401)")
    #expect(display(AccountStateInput(status: "error", schedulable: true, errorSummary: "  Access forbidden (403)\n")).reason == "Access forbidden (403)")
    for blank in [nil, "", "  \n"] as [String?] {
        let reason = display(AccountStateInput(status: "error", schedulable: true, errorSummary: blank, errorMessage: secret)).reason
        #expect(reason == "上游返回异常")
        #expect(!(reason ?? "").contains("sk-fixture") && !(reason ?? "").contains("Authentication"))
    }
    #expect(AccountDisplayState.unknownErrorReason == "上游返回异常")
    #expect(display(active(overload: at(10))).reason == "上游 529")
    #expect(display(active(rateLimit: at(10))).reason == "上游 429")
    for idle in [active(schedulable: false), AccountStateInput(status: "inactive", schedulable: true), active()] {
        #expect(display(idle).reason == nil)
    }
}

private let temporaryReasons: [(String?, String)] = [
    (#"{"status_code":503,"matched_keyword":"overloaded","rule_index":0}"#, "上游 503 · 规则 #1"),
    (#"{"status_code":429,"matched_keyword":"","rule_index":2}"#, "上游 429"),
    (#"{"status_code":400,"matched_keyword":"x","rule_index":-1}"#, "上游 400"),
    (#"{"status_code":0,"matched_keyword":"quota","rule_index":1}"#, "临时不可调度 · 规则 #2"),
    (#"{"until_unix":1800000060,"status_code":529,"error_message":"upstream private text"}"#, "上游 529"),
    (#"{"status_code":"503","matched_keyword":7}"#, "临时不可调度"),
    ("OpenAI 403 temporary cooldown (1/3): upstream text", "临时不可调度"),
    (nil, "临时不可调度"), ("", "临时不可调度"), ("[1,2]", "临时不可调度"), ("123", "临时不可调度"), ("{}", "临时不可调度")
]

@Test(arguments: temporaryReasons)
func temporaryReasonParsesTempUnschedState(raw: String?, expected: String) {
    let result = display(AccountStateInput(status: "active", schedulable: true, tempUnschedulableUntil: at(60), tempUnschedulableReason: raw))
    #expect(result.state == .tempUnschedulable)
    #expect(result.reason == expected)
    #expect(!(result.reason ?? "").contains("upstream"))
}

// MARK: Credential errors

struct CredentialCase: Sendable, CustomTestStringConvertible {
    let kind: String?
    let code: Int?
    let message: String?
    let expected: Bool
    var testDescription: String { "\(kind ?? "-") \(code.map(String.init) ?? "-") \(message ?? "-")" }
}

private let credentialCases: [CredentialCase] = [
    .init(kind: "auth", code: nil, message: nil, expected: true), .init(kind: "forbidden", code: nil, message: nil, expected: true),
    .init(kind: "token_refresh", code: nil, message: nil, expected: true), .init(kind: "quota", code: 401, message: nil, expected: true),
    .init(kind: "other", code: 403, message: nil, expected: true), .init(kind: "other", code: 500, message: nil, expected: false),
    // With C02 fields the regex is not used.
    .init(kind: "rate_limit", code: nil, message: "token expired (401)", expected: false),
    .init(kind: nil, code: 500, message: "invalid_api_key", expected: false),
    .init(kind: nil, code: nil, message: "Authentication failed (401): invalid", expected: true),
    .init(kind: nil, code: nil, message: "invalid_api_key", expected: true),
    .init(kind: nil, code: nil, message: "Token refresh failed: x", expected: true),
    .init(kind: "", code: nil, message: "Access forbidden (403)", expected: true),
    .init(kind: nil, code: nil, message: "upstream returned 500", expected: false),
    .init(kind: nil, code: nil, message: "HTTP 4010 response", expected: false),
    .init(kind: nil, code: nil, message: nil, expected: false)
]

@Test(arguments: credentialCases)
func credentialErrorClassification(item: CredentialCase) {
    let failed = AccountStateInput(status: "error", schedulable: true, errorKind: item.kind, errorStatusCode: item.code, errorMessage: item.message)
    #expect(display(failed).isCredentialError == item.expected)
    let healthy = AccountStateInput(status: "active", schedulable: true, errorKind: item.kind, errorStatusCode: item.code, errorMessage: item.message)
    #expect(!display(healthy).isCredentialError)
}

// MARK: Model rate limits and account fields

@Test func modelRateLimitsKeepActiveSortedAndDoNotChangeTone() throws {
    let limits = #""z-model":{"rate_limit_reset_at":"\#(wire(at(600)))","rate_limited_at":"x"},"a-model":{"rate_limit_reset_at":"\#(wire(at(60)))"},"old":{"rate_limit_reset_at":"\#(wire(at(-60)))"},"bad":"x","noreset":{},"badtime":{"rate_limit_reset_at":"garbage"}"#
    let account = try decodedAccount(#""extra":{"model_rate_limits":{\#(limits)},"upstream_billing_probe":{"status":"ok"}}"#)
    let result = AccountDisplayState(account, now: now)
    #expect(result.modelRateLimits == [AccountModelRateLimit(model: "a-model", resetAt: at(60)), AccountModelRateLimit(model: "z-model", resetAt: at(600))])
    #expect(result.state == .available && result.tone == .ok)
    #expect(account.extra?.modelRateLimits.map(\.model) == ["a-model", "old", "z-model"])
    #expect(account.extra?.upstreamBillingProbe?.status == "ok")
    let roundTrip = try JSONDecoder().decode(UpstreamAccount.self, from: JSONEncoder().encode(account))
    #expect(roundTrip.extra?.modelRateLimits == account.extra?.modelRateLimits)
    for shape in ["[1,2]", #""text""#, "null", "7"] {
        let odd = try decodedAccount(#""extra":{"model_rate_limits":\#(shape),"upstream_billing_probe":{"status":"ok"}}"#)
        #expect(odd.extra?.modelRateLimits.isEmpty == true, "\(shape)")
        #expect(odd.extra?.upstreamBillingProbe?.status == "ok")
    }
}

@Test func upstreamAccountDecodesStructuredErrorRuntimeAndTokenFields() throws {
    let json = #"{"id":3,"name":"凭据","platform":"openai","type":"oauth","status":"error","schedulable":false,"error_message":"Authentication failed (401): x","error_at":"2026-10-22T09:58:00Z","error_status_code":401,"error_kind":"auth","error_summary":"Authentication failed (401)","concurrency_available":false,"rate_limit_reset_at":"2026-10-22T10:00:00Z","overload_until":null,"temp_unschedulable_until":"2026-10-22T18:05:00+08:00","temp_unschedulable_reason":"{\"status_code\":503}","auto_pause_on_expired":true,"token_status":{"expires_at":"2026-10-22T18:00:00Z","lifetime_seconds":28800,"refreshed_at":"2026-10-22T10:00:00Z","auto_refresh":true},"credentials":{"base_url":"https://fixture-credential.example.invalid"}}"#
    let account = try JSONDecoder().decode(UpstreamAccount.self, from: Data(json.utf8))
    #expect(account.errorAt == "2026-10-22T09:58:00Z" && account.errorStatusCode == 401)
    #expect(account.errorKind == "auth" && account.errorSummary == "Authentication failed (401)")
    #expect(account.concurrencyAvailable == false)
    #expect(account.rateLimitResetAt == "2026-10-22T10:00:00Z" && account.overloadUntil == nil)
    #expect(account.tempUnschedulableUntil == "2026-10-22T18:05:00+08:00" && account.tempUnschedulableReason == #"{"status_code":503}"#)
    #expect(account.autoPauseOnExpired == true)
    #expect(account.tokenStatus == AccountTokenStatus(expiresAt: "2026-10-22T18:00:00Z", lifetimeSeconds: 28_800, refreshedAt: "2026-10-22T10:00:00Z", autoRefresh: true))
    let encoded = try JSONEncoder().encode(account)
    #expect(!String(decoding: encoded, as: UTF8.self).contains("fixture-credential"))
    let roundTrip = try JSONDecoder().decode(UpstreamAccount.self, from: encoded)
    #expect(roundTrip.errorAt == account.errorAt && roundTrip.errorStatusCode == 401 && roundTrip.errorKind == "auth")
    #expect(roundTrip.errorSummary == account.errorSummary && roundTrip.concurrencyAvailable == false)
    #expect(roundTrip.rateLimitResetAt == account.rateLimitResetAt && roundTrip.tempUnschedulableUntil == account.tempUnschedulableUntil)
    #expect(roundTrip.tempUnschedulableReason == account.tempUnschedulableReason && roundTrip.autoPauseOnExpired == true)
    #expect(roundTrip.tokenStatus == account.tokenStatus)
    let old = try decodedAccount()
    #expect(old.errorAt == nil && old.errorStatusCode == nil && old.errorKind == nil && old.errorSummary == nil)
    #expect(old.concurrencyAvailable == nil && old.rateLimitResetAt == nil && old.overloadUntil == nil)
    #expect(old.tempUnschedulableUntil == nil && old.tempUnschedulableReason == nil && old.autoPauseOnExpired == nil && old.tokenStatus == nil)
    #expect(try decodedAccount(#""token_status":null"#).tokenStatus == nil)
}

@Test func accountTimestampOffsetsAndNanosecondsDriveCountdown() throws {
    let clock = try #require(ServerTime.parseTimestamp("2026-10-22T09:59:00Z"))
    let account = try decodedAccount(#""rate_limit_reset_at":"2026-10-22T18:00:00.123456789+08:00","temp_unschedulable_until":null"#)
    let limited = AccountDisplayState(account, now: clock)
    #expect(limited.state == .rateLimited)
    let target = try #require(limited.countdownTarget)
    #expect(abs(target.timeIntervalSince1970 - 1_792_663_200.123) <= 0.001)
    let expired = try decodedAccount(#""expires_at":\#(Int64(clock.timeIntervalSince1970) - 1),"auto_pause_on_expired":true"#)
    let paused = AccountDisplayState(expired, now: clock)
    #expect(paused.state == .paused && paused.note == "已过期")
    #expect(AccountDisplayState(try decodedAccount(#""expires_at":0,"auto_pause_on_expired":true"#), now: clock).state == .available)
}

// MARK: status-summary items (10 §1.3.3: interchangeable with the server's state)

private let serverItems: [AccountStatusItem] = [
    AccountStatusItem(id: 1, state: .error, status: "error", schedulable: false, overloadUntil: at(30)),
    AccountStatusItem(id: 2, state: .inactive, status: "inactive"),
    AccountStatusItem(id: 3, state: .overloaded, stopped: true, schedulable: false, rateLimitResetAt: at(60), overloadUntil: at(30)),
    AccountStatusItem(id: 4, state: .rateLimited, rateLimitResetAt: at(60), tempUnschedulableUntil: at(90)),
    AccountStatusItem(id: 5, state: .tempUnschedulable, stopped: true, schedulable: false, tempUnschedulableUntil: at(90)),
    AccountStatusItem(id: 6, state: .paused, schedulable: false),
    AccountStatusItem(id: 7, state: .paused, expiresAt: at(-60)),
    AccountStatusItem(id: 8, state: .available, expiresAt: at(-60)),
    AccountStatusItem(id: 9, state: .available)
]

@Test(arguments: serverItems)
func summaryItemMatchesServerState(item: AccountStatusItem) {
    let result = AccountDisplayState(item, now: now)
    #expect(result.state == item.state)
    #expect(result.isStopped == item.stopped)
}

@Test func summaryItemExpiredPauseUsesReportedStateWhenFlagMissing() {
    #expect(AccountDisplayState(AccountStatusItem(id: 7, state: .paused, expiresAt: at(-60)), now: now).note == "已过期")
    let available = AccountDisplayState(AccountStatusItem(id: 8, state: .available, expiresAt: at(-60)), now: now)
    #expect(available.state == .available && available.note == nil)
    let switchedOff = AccountDisplayState(AccountStatusItem(id: 6, state: .paused, schedulable: false), now: now)
    #expect(switchedOff.state == .paused && switchedOff.note == nil)
    // An unknown server state gives no evidence of auto-pause.
    #expect(AccountDisplayState(AccountStatusItem(id: 10, state: nil, expiresAt: at(-60)), now: now).state == .available)
    #expect(AccountDisplayState(AccountStatusItem(id: 11, state: .error, status: "error"), now: now).state == .error)
    // A window that has ended since collection moves on to the next row.
    #expect(AccountDisplayState(AccountStatusItem(id: 4, state: .rateLimited, rateLimitResetAt: at(60)), now: at(61)).state == .available)
}

@Test func summaryItemTakesStructuredErrorFromMatchingAccount() {
    let item = AccountStatusItem(id: 3, state: .error, status: "error")
    let account = UpstreamAccount(id: 3, name: "x", platform: "openai", type: "apikey", status: "error",
                                  errorKind: "forbidden", errorSummary: "Access forbidden (403)")
    let matched = AccountDisplayState(item, structuredError: account, now: now)
    #expect(matched.reason == "Access forbidden (403)" && matched.isCredentialError)
    let other = UpstreamAccount(id: 4, name: "y", platform: "openai", type: "apikey", status: "error",
                                errorKind: "forbidden", errorSummary: "Access forbidden (403)")
    let ignored = AccountDisplayState(item, structuredError: other, now: now)
    #expect(ignored.reason == "上游返回异常" && !ignored.isCredentialError)
    let alone = AccountDisplayState(item, now: now)
    #expect(alone.reason == "上游返回异常" && !alone.isCredentialError)
}

@Test func attentionGroupingsAndTokenAccounts() {
    let attention: Set<AccountScheduleState> = [.error, .overloaded, .rateLimited, .tempUnschedulable]
    let limited: Set<AccountScheduleState> = [.overloaded, .rateLimited, .tempUnschedulable]
    for state in AccountScheduleState.allCases {
        #expect(state.needsAttention == attention.contains(state), "\(state)")
        #expect(state.isLimited == limited.contains(state), "\(state)")
    }
    for (type, isToken) in [("oauth", true), ("setup-token", true), ("apikey", false), ("upstream", false), ("bedrock", false), ("service_account", false)] {
        #expect(UpstreamAccount(id: 1, name: "a", platform: "anthropic", type: type).isTokenAccount == isToken, "\(type)")
    }
}

// MARK: Current list field (visible change of this item)

private let statusFieldCases: [(UpstreamAccount, String)] = [
    (UpstreamAccount(id: 1, name: "a", platform: "openai", type: "apikey"), "正常"),
    (UpstreamAccount(id: 2, name: "a", platform: "openai", type: "apikey", status: "inactive"), "停用"),
    (UpstreamAccount(id: 3, name: "a", platform: "openai", type: "apikey", status: "disabled"), "停用"),
    (UpstreamAccount(id: 4, name: "a", platform: "openai", type: "apikey", status: "error", errorMessage: "sk-fixture-secret"), "错误"),
    (UpstreamAccount(id: 5, name: "a", platform: "openai", type: "apikey", schedulable: false), "暂停"),
    (UpstreamAccount(id: 6, name: "a", platform: "openai", type: "apikey", expiresAt: Int64(now.timeIntervalSince1970) - 1, autoPauseOnExpired: true), "暂停 · 已过期"),
    (UpstreamAccount(id: 7, name: "a", platform: "openai", type: "apikey", rateLimitResetAt: wire(at(60))), "限流中"),
    (UpstreamAccount(id: 8, name: "a", platform: "openai", type: "apikey", overloadUntil: wire(at(60))), "过载中")
]

@Test(arguments: statusFieldCases)
func fieldPresentationStatusUsesDisplayState(account: UpstreamAccount, expected: String) {
    #expect(AccountFieldPresentation.value(.status, account: account, now: now) == expected)
    #expect(AccountFieldPresentation.value(.schedulable, account: account, now: now) == (account.schedulable ? "参与调度" : "暂停调度"))
}
