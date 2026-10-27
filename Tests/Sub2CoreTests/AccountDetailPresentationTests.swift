import Foundation
import Testing
@testable import Sub2Core

private let now = Date(timeIntervalSince1970: 1_792_028_400)   // 2026-10-15T01:40:00Z
private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private let utc = TimeZone(identifier: "UTC")!

private func stamp(_ seconds: TimeInterval) -> String { ServerTime.utcTimestamp(now.addingTimeInterval(seconds)) }

private func account(_ id: Int = 1, platform: String = "anthropic", type: String = "oauth", status: String = "active", schedulable: Bool = true,
                     fields: [String: Any] = [:]) throws -> UpstreamAccount {
    var json: [String: Any] = ["id": id, "name": "账号-\(id)", "platform": platform, "type": type, "status": status, "schedulable": schedulable]
    json.merge(fields) { _, new in new }
    return try JSONDecoder().decode(UpstreamAccount.self, from: JSONSerialization.data(withJSONObject: json))
}

private func card(_ account: UpstreamAccount, timeZone: TimeZone = shanghai) -> AccountStatusCardContent {
    AccountDetailPresentation.statusCard(account, now: now, timeZone: timeZone)
}

private func buttons(_ account: UpstreamAccount, keyReplaced: Bool = false) -> [AccountDetailAction] {
    AccountDetailPresentation.actionRow(account, now: now, keyReplaced: keyReplaced).actions
}

private func expired() -> [String: Any] { ["auto_pause_on_expired": true, "expires_at": Int(now.timeIntervalSince1970) - 60] }

// MARK: - Status card (20 §2.3)

@Test func statusCardQuietVariants() throws {
    let cases: [(UpstreamAccount, String, Tone)] = [
        (try account(), "正常 · 参与调度", .ok),
        (try account(schedulable: false), "暂停 · 不参与调度", .neutral),
        (try account(fields: expired()), "暂停 · 已过期，自动暂停调度", .neutral),
        (try account(status: "inactive"), "停用 · 不参与调度", .neutral),
        (try account(status: "disabled"), "停用 · 不参与调度", .neutral)
    ]
    for (account, title, tone) in cases {
        let content = card(account)
        #expect(content.style == .quiet)
        #expect(content.title == title)
        #expect(content.tone == tone)
        #expect(content.cause == nil && content.countdown == nil && content.countdownTarget == nil && content.resumeNote == nil)
        #expect(content.errorBody == nil && content.scheduleNote == nil)
    }
}

@Test func statusCardTimedVariants() throws {
    let limited = card(try account(fields: ["rate_limit_reset_at": stamp(277)]))
    #expect(limited.style == .alert)
    #expect(limited.title == "限流中" && limited.tone == .caution)
    #expect(limited.cause == "上游 429")
    #expect(limited.countdownTarget == now.addingTimeInterval(277))
    #expect(limited.countdown == "4:37")
    #expect(limited.resumeNote == "后自动恢复 · 预计 09:44")
    #expect(limited.scheduleNote == nil && limited.errorBody == nil)

    let overloaded = card(try account(fields: ["overload_until": stamp(3_725)]))
    #expect(overloaded.title == "过载中" && overloaded.tone == .critical)
    #expect(overloaded.cause == "上游 529")
    #expect(overloaded.countdown == "1:02:05")

    let reason = #"{"status_code":529,"matched_keyword":"x","rule_index":0}"#
    let temporary = card(try account(fields: ["temp_unschedulable_until": stamp(60), "temp_unschedulable_reason": reason]))
    #expect(temporary.title == "临时不可调度" && temporary.cause == "上游 529 · 规则 #1")

    let stopped = card(try account(schedulable: false, fields: ["rate_limit_reset_at": stamp(277)]))
    #expect(stopped.scheduleNote == AccountStatusCardContent.ScheduleNote(emphasis: "已停止调度", detail: "到时恢复后也不参与调度"))
}

@Test func statusCardResumeTimeFollowsServerTimeZone() throws {
    let limited = try account(fields: ["rate_limit_reset_at": stamp(277)])
    #expect(card(limited, timeZone: shanghai).resumeNote == "后自动恢复 · 预计 09:44")
    #expect(card(limited, timeZone: utc).resumeNote == "后自动恢复 · 预计 01:44")
}

@Test func statusCardErrorVariants() throws {
    let fields: [String: Any] = ["error_summary": "401 凭据已失效", "error_message": "raw upstream text sk-secret", "error_status_code": 401, "error_kind": "auth"]
    let paused = card(try account(status: "error", schedulable: false, fields: fields))
    #expect(paused.style == .alert)
    #expect(paused.title == "错误" && paused.tone == .critical)
    #expect(paused.cause == "上游 401")
    #expect(paused.errorBody == "401 凭据已失效")
    #expect(paused.scheduleNote == AccountStatusCardContent.ScheduleNote(emphasis: "出错时已自动停止调度", detail: "恢复时可一并启用"))
    #expect(paused.countdown == nil && paused.resumeNote == nil && paused.countdownTarget == nil)
    let shown = [paused.title, paused.cause, paused.errorBody, paused.scheduleNote?.emphasis, paused.scheduleNote?.detail].compactMap { $0 }
    #expect(!shown.contains { $0.contains("raw upstream") })

    let bare = card(try account(status: "error", fields: ["error_message": "boom"]))
    #expect(bare.errorBody == "上游返回异常")
    #expect(bare.cause == nil)
    #expect(bare.scheduleNote == nil)
    #expect(card(try account(status: "error", fields: ["error_summary": "  "])).errorBody == "上游返回异常")
}

@Test func statusCardModelLimitBlock() throws {
    let limits: [String: Any] = ["model_rate_limits": [
        "zeta": ["rate_limit_reset_at": stamp(300)], "alpha": ["rate_limit_reset_at": stamp(3_900)],
        "mid": ["rate_limit_reset_at": stamp(3_600)], "gone": ["rate_limit_reset_at": stamp(-10)]
    ]]
    let content = card(try account(fields: ["rate_limit_reset_at": stamp(277), "extra": limits]))
    #expect(content.modelLimitsTitle == "模型限流 3")
    #expect(content.modelLimits == [
        .init(model: "alpha", remaining: "1 小时 5 分钟后"), .init(model: "mid", remaining: "1 小时后"), .init(model: "zeta", remaining: "5 分钟后")
    ])
    // A model limit is not an account state: the quiet card keeps its title and still lists it.
    let quiet = card(try account(fields: ["extra": limits]))
    #expect(quiet.style == .quiet && quiet.title == "正常 · 参与调度")
    #expect(quiet.modelLimitsTitle == "模型限流 3")
    let none = card(try account())
    #expect(none.modelLimitsTitle == nil && none.modelLimits.isEmpty)
}

@Test func statusCardRecomputesAfterWindowEnds() throws {
    #expect(card(try account(fields: ["rate_limit_reset_at": stamp(-1)])).title == "正常 · 参与调度")
    let next = card(try account(fields: ["overload_until": stamp(-1), "rate_limit_reset_at": stamp(90)]))
    #expect(next.title == "限流中" && next.countdown == "1:30")
}

// MARK: - Button row (20 §2.3, U17, S2D1-20)

@Test func actionRowTable() throws {
    let credential: [String: Any] = ["error_kind": "auth", "error_status_code": 401]
    let cases: [(UpstreamAccount, Bool, [AccountDetailAction])] = [
        (try account(), false, [.test, .stopScheduling]),
        (try account(status: "inactive"), false, [.enableAccount, .test]),
        (try account(schedulable: false), false, [.resumeScheduling, .test]),
        (try account(fields: expired()), false, [.editExpiry, .test]),
        (try account(schedulable: false, fields: expired()), false, [.editExpiry, .test]),
        (try account(type: "apikey", status: "error", fields: credential), false, [.replaceKey, .recover, .test]),
        (try account(type: "oauth", status: "error", fields: credential), false, [.reauthorize, .recover, .test]),
        (try account(type: "setup-token", status: "error", fields: ["error_status_code": 403]), false, [.reauthorize, .recover, .test]),
        (try account(type: "bedrock", status: "error", fields: credential), false, [.webCredential, .recover, .test]),
        (try account(type: "service_account", status: "error", fields: ["error_kind": "forbidden"]), false, [.webCredential, .recover, .test]),
        (try account(type: "apikey", status: "error", fields: ["error_kind": "token_refresh"]), true, [.test, .recover]),
        (try account(type: "apikey", status: "error", fields: ["error_kind": "quota", "error_status_code": 429]), false, [.recover, .test]),
        (try account(fields: ["rate_limit_reset_at": stamp(60)]), false, [.recover, .test, .stopScheduling]),
        (try account(fields: ["overload_until": stamp(60)]), false, [.recover, .test, .stopScheduling]),
        (try account(fields: ["temp_unschedulable_until": stamp(60)]), false, [.recover, .test, .stopScheduling]),
        (try account(schedulable: false, fields: ["rate_limit_reset_at": stamp(60)]), false, [.recover, .test, .resumeScheduling])
    ]
    for (account, replaced, expected) in cases {
        #expect(buttons(account, keyReplaced: replaced) == expected, "\(account.type) \(account.status) \(account.schedulable)")
    }
}

@Test func actionRowGuessesCredentialErrorWithoutStructuredFields() throws {
    #expect(buttons(try account(type: "apikey", status: "error", fields: ["error_message": "Error: invalid_api_key"])) == [.replaceKey, .recover, .test])
    #expect(buttons(try account(type: "apikey", status: "error", fields: ["error_message": "upstream 500"])) == [.recover, .test])
}

@Test func actionRowLeadsWithPrimary() throws {
    let row = AccountDetailPresentation.actionRow(try account(fields: ["rate_limit_reset_at": stamp(60)]), now: now)
    #expect(row.primary == .recover)
    #expect(row.secondary == [.test, .stopScheduling])
    #expect(row.actions.first == row.primary)
}

@Test func actionTitlesFollowSpecWords() {
    #expect(AccountDetailAction.allCases.map(\.title) == [
        "测试连接", "停止调度", "启用调度", "启用账号", "恢复状态", "更换 API Key…", "重新授权…", "在 Web 中更换凭据", "修改过期时间…"
    ])
    #expect(AccountDetailAction.stopScheduling.rawValue == "stop" && AccountDetailAction.resumeScheduling.rawValue == "resume")
    #expect(AccountDetailAction.editExpiry.id == "editExpiry")
}

// MARK: - Page state (20 §2.5), removal, light refresh (20 §2.6), subtitle

@Test func pageStateResolveFollows25Table() {
    typealias State = AccountDetailPageState
    #expect(State.resolve(hasAccount: false, loadedFromServer: false, failure: nil, removed: false) == .skeleton)
    #expect(State.resolve(hasAccount: false, loadedFromServer: false, failure: "站点暂时不可用", removed: false) == .failure(message: "站点暂时不可用"))
    #expect(State.resolve(hasAccount: true, loadedFromServer: false, failure: "站点暂时不可用", removed: false)
        == .content(banner: "读取最新数据失败，显示的是列表里的快照"))
    #expect(State.resolve(hasAccount: true, loadedFromServer: false, failure: nil, removed: false) == .content(banner: nil))
    #expect(State.resolve(hasAccount: true, loadedFromServer: true, failure: nil, removed: false) == .content(banner: nil))
    #expect(State.resolve(hasAccount: true, loadedFromServer: true, failure: "站点暂时不可用", removed: false) == .content(banner: nil))
    #expect(State.resolve(hasAccount: true, loadedFromServer: true, failure: nil, removed: true) == .removed)
    #expect(State.resolve(hasAccount: false, loadedFromServer: false, failure: "x", removed: true) == .removed)
}

@Test func removedOnlyForAccountNotFound() {
    #expect(AccountDetailPresentation.isRemoved(APIError.server(status: 404, reason: "ACCOUNT_NOT_FOUND")))
    #expect(!AccountDetailPresentation.isRemoved(APIError.server(status: 404, reason: "RESOURCE_NOT_FOUND")))
    #expect(!AccountDetailPresentation.isRemoved(APIError.server(status: 404, envelope: nil)))
    #expect(!AccountDetailPresentation.isRemoved(APIError.server(status: 500, reason: nil)))
    #expect(!AccountDetailPresentation.isRemoved(APIError(kind: .transport, message: "offline")))
    #expect(!AccountDetailPresentation.isRemoved(CancellationError()))
}

@Test func lightRefreshDecision() throws {
    let current = try account(fields: ["current_concurrency": 1, "concurrency": 4, "concurrency_available": true, "group_ids": [3],
                                       "extra": ["model_rate_limits": ["m": ["rate_limit_reset_at": stamp(60)]]]])
    let live = AccountRuntime(status: "active", schedulable: true, currentConcurrency: nil, concurrencyAvailable: false,
                              rateLimitResetAt: now.addingTimeInterval(120), overloadUntil: nil, tempUnschedulableUntil: now.addingTimeInterval(30))
    guard case .merged(let merged) = AccountDetailRefresh.apply([1: live], to: current) else {
        Issue.record("expected a merge"); return
    }
    #expect(merged.currentConcurrency == nil && merged.concurrencyAvailable == false)
    #expect(merged.rateLimitResetAt == stamp(120) && merged.tempUnschedulableUntil == stamp(30) && merged.overloadUntil == nil)
    #expect(merged.name == current.name && merged.groupIDs == [3] && merged.extra?.modelRateLimits.count == 1)

    let reloads: [[Int: AccountRuntime]] = [
        [:], [2: live],
        [1: AccountRuntime(status: "error", schedulable: true)],
        [1: AccountRuntime(status: "active", schedulable: false)]
    ]
    for runtime in reloads {
        guard case .reload = AccountDetailRefresh.apply(runtime, to: current) else { Issue.record("expected a reload: \(runtime)"); continue }
    }
}

@Test func refreshDelayClamps() {
    #expect(AccountDetailRefresh.interval == 60)
    #expect(AccountDetailRefresh.delay(sinceLastRefresh: nil) == 0)
    #expect(AccountDetailRefresh.delay(sinceLastRefresh: 20) == 40)
    #expect(AccountDetailRefresh.delay(sinceLastRefresh: 75) == 0)
    #expect(AccountDetailRefresh.delay(sinceLastRefresh: -5) == 60)
}

@Test func subtitleUsesCatalogAndTypeNames() throws {
    #expect(AccountDetailPresentation.subtitle(try account(), catalog: .builtin) == "Anthropic · OAuth")
    #expect(AccountDetailPresentation.subtitle(try account(platform: "antigravity", type: "apikey"), catalog: .builtin) == "Antigravity · 对接上游")
    #expect(AccountDetailPresentation.subtitle(try account(platform: "openai", type: "bedrock"), catalog: .builtin) == "OpenAI · AWS Bedrock")
    #expect(AccountDetailPresentation.subtitle(try account(platform: "future_vendor", type: "apikey"), catalog: .builtin) == "future_vendor · API Key")
}
