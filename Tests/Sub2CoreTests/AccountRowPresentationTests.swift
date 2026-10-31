import Foundation
import Testing
@testable import Sub2Core

private let now = Date(timeIntervalSince1970: 1_792_028_400)   // 2026-10-15T01:40:00Z
private let shanghai = TimeZone(identifier: "Asia/Shanghai")!
private let newYork = TimeZone(identifier: "America/New_York")!
private let directory: [Int: String] = [1: "高级组", 5: "Claude Code 组"]

private func stamp(_ seconds: TimeInterval) -> String { ServerTime.utcTimestamp(now.addingTimeInterval(seconds)) }

private func row(_ id: Int = 1, platform: String = "anthropic", type: String = "oauth", status: String = "active", schedulable: Bool = true,
                 groups: [Int] = [1, 5], embedded: [[String: Any]] = [], fields: [String: Any] = [:]) throws -> UpstreamAccount {
    var json: [String: Any] = ["id": id, "name": "账号-\(id)", "platform": platform, "type": type, "status": status,
                               "schedulable": schedulable, "group_ids": groups, "groups": embedded]
    json.merge(fields) { _, new in new }
    return try JSONDecoder().decode(UpstreamAccount.self, from: JSONSerialization.data(withJSONObject: json))
}

private func second(_ account: UpstreamAccount, _ omit: AccountRowOmit, home: String? = nil,
                    directory names: [Int: String] = directory) -> String {
    AccountRowPresentation.secondLine(account, omit: omit, home: home, catalog: .builtin, directory: { names[$0] })
}

private func third(_ account: UpstreamAccount, today: AccountTodayCell = .value(0), at time: Date = now,
                   timeZone: TimeZone = shanghai) -> AccountRowThirdLine {
    AccountRowPresentation.thirdLine(account, display: AccountDisplayState(account, now: time), today: today, timeZone: timeZone)
}

// MARK: - Second line (20 §1.3, 50 §2.3, 60 §2.3)

@Test func secondLineInsidePlatformSectionListsGroupsThenType() throws {
    #expect(second(try row(), .platform) == "高级组、Claude Code 组 · OAuth")
}

@Test func secondLineWithoutOmitLeadsWithCatalogPlatformName() throws {
    #expect(second(try row(), .none) == "Anthropic · 高级组、Claude Code 组 · OAuth")
    #expect(second(try row(platform: "zhipu", type: "apikey", groups: [1]), .none) == "智谱 GLM · 高级组 · API Key")
    #expect(second(try row(platform: "future_vendor", type: "apikey", groups: []), .none) == "future_vendor · 未分组 · API Key")
}

@Test func secondLineOmitGroupWritesOtherGroupsOrPlatformOnly() throws {
    #expect(second(try row(), .group, home: "高级组") == "Anthropic · 另属 Claude Code 组 · OAuth")
    #expect(second(try row(groups: [1]), .group, home: "高级组") == "Anthropic · OAuth")
}

@Test func secondLineUngroupedUnknownAndEmbeddedNames() throws {
    #expect(second(try row(type: "apikey", groups: []), .platform) == "未分组 · API Key")
    #expect(second(try row(type: "apikey", groups: [1, 99]), .platform) == "高级组、#99 · API Key")
    let embedded = try row(type: "apikey", groups: [10], embedded: [["id": 10, "name": "标准分组"]])
    #expect(second(embedded, .platform, directory: [:]) == "标准分组 · API Key")
    #expect(AccountRowPresentation.groupNames(embedded, directory: { _ in "目录名" }) == ["目录名"])
}

@Test func typeNameFollowsAccountNamingIncludingAntigravityUpstream() throws {
    let expected = ["apikey": "API Key", "setup-token": "Setup Token", "upstream": "对接上游", "bedrock": "AWS Bedrock", "service_account": "Vertex"]
    for (type, name) in expected { #expect(second(try row(type: type, groups: []), .platform) == "未分组 · \(name)") }
    #expect(second(try row(platform: "antigravity", type: "apikey", groups: []), .platform) == "未分组 · 对接上游")
}

// MARK: - Third line

@Test func errorLineUsesSummaryAndNeverErrorMessage() throws {
    let secret = "Bearer sk-secret-fixture invalid"
    let summarized = try row(status: "error", schedulable: false, fields: ["error_summary": " 401 凭据已失效（invalid_api_key） ", "error_message": secret])
    #expect(third(summarized) == .error(summary: "401 凭据已失效（invalid_api_key）"))
    for blank in [nil, "   "] as [String?] {
        var fields: [String: Any] = ["error_message": secret]
        if let blank { fields["error_summary"] = blank }
        let account = try row(status: "error", fields: fields)
        let line = third(account)
        #expect(line == .error(summary: "上游返回异常"))
        let spoken = AccountRowPresentation.accessibilityLabel(name: account.name, display: AccountDisplayState(account, now: now), now: now,
                                                               second: second(account, .platform), third: line)
        #expect(!spoken.contains("Bearer") && !spoken.contains("sk-secret") && spoken.contains("上游返回异常"))
    }
}

@Test func limitedLineUsesReasonAndServerTimeZoneClock() throws {
    let account = try row(fields: ["rate_limit_reset_at": stamp(300)])
    #expect(third(account) == .limited(stoppedMark: nil, reason: "上游 429", resume: "09:45 恢复", modelLimits: nil))
    #expect(third(account, timeZone: newYork) == .limited(stoppedMark: nil, reason: "上游 429", resume: "21:45 恢复", modelLimits: nil))
}

@Test func stoppedLimitedLineLeadsWithMarkAndEndsWithModelLimits() throws {
    let limits: [String: Any] = ["model_rate_limits": ["claude-opus-4": ["rate_limit_reset_at": stamp(720)],
                                                       "claude-sonnet-4-5": ["rate_limit_reset_at": stamp(400)]]]
    let account = try row(schedulable: false, fields: ["rate_limit_reset_at": stamp(300), "extra": limits])
    #expect(third(account) == .limited(stoppedMark: "已停止调度", reason: "上游 429", resume: "09:45 恢复", modelLimits: "模型限流 2"))
    let later = now.addingTimeInterval(200)
    guard case .limited(_, _, _, let one) = third(account, at: later) else { Issue.record("not limited"); return }
    #expect(one == "模型限流 2")
    let partlyExpired = try row(schedulable: false, fields: ["rate_limit_reset_at": stamp(900), "extra": limits])
    guard case .limited(_, _, _, let tail) = third(partlyExpired, at: now.addingTimeInterval(500)) else { Issue.record("not limited"); return }
    #expect(tail == "模型限流 1")
    guard case .limited(_, _, _, let none) = third(partlyExpired, at: now.addingTimeInterval(800)) else { Issue.record("not limited"); return }
    #expect(none == nil)
}

@Test func tempUnschedulableAndOverloadedReasons() throws {
    let reason = #"{"status_code":529,"matched_keyword":"overloaded","rule_index":0}"#
    let temporary = try row(fields: ["temp_unschedulable_until": stamp(600), "temp_unschedulable_reason": reason])
    guard case .limited(_, let temporaryReason, let resume, _) = third(temporary) else { Issue.record("not limited"); return }
    #expect(temporaryReason == "上游 529 · 规则 #1" && resume == "09:50 恢复")
    let overloaded = try row(fields: ["overload_until": stamp(60)])
    #expect(AccountDisplayState(overloaded, now: now).label == "过载中")
    guard case .limited(_, let overloadReason, _, _) = third(overloaded) else { Issue.record("not limited"); return }
    #expect(overloadReason == "上游 529")
}

@Test func usageLineShowsConcurrencyAndToday() throws {
    let account = try row(fields: ["concurrency": 4, "current_concurrency": 2, "concurrency_available": true])
    guard case .usage(let concurrency, let today) = third(account, today: .value(Decimal(string: "409.38")!)) else { Issue.record("not usage"); return }
    #expect(concurrency.text == "2/4 并发" && concurrency.spoken == "并发 2/4" && today == "$409.38")
    #expect(third(account, today: .value(0)) == .usage(concurrency: concurrency, today: "$0.00"))
    #expect(third(account, today: .failed) == .usage(concurrency: concurrency, today: "—"))
    #expect(third(account, today: .hidden) == .usage(concurrency: concurrency, today: nil))
    let idle = [try row(schedulable: false, fields: ["concurrency": 4, "current_concurrency": 0]),
                try row(status: "inactive", fields: ["concurrency": 4, "current_concurrency": 0]),
                try row(fields: ["concurrency": 4, "current_concurrency": 0, "auto_pause_on_expired": true,
                                 "expires_at": Int(now.timeIntervalSince1970) - 60])]
    for account in idle {
        guard case .usage = third(account) else { Issue.record("\(account.id) not usage"); continue }
    }
}

@Test func concurrencyMissingCases() throws {
    let missing = [try row(fields: ["concurrency": 4, "current_concurrency": 2, "concurrency_available": false]),
                   try row(fields: ["concurrency": 0, "current_concurrency": 0]),
                   try row(fields: ["current_concurrency": 1]),
                   try row(fields: ["concurrency": 4])]
    for account in missing {
        let concurrency = AccountRowConcurrency(account)
        #expect(concurrency.isMissing && concurrency.text == "— 并发" && concurrency.spoken == "并发 无数据")
        #expect(concurrency.fraction == nil && concurrency.tone == nil)
    }
}

@Test func concurrencyToneThresholds() throws {
    func concurrency(_ used: Int, _ limit: Int) throws -> AccountRowConcurrency {
        AccountRowConcurrency(try row(fields: ["concurrency": limit, "current_concurrency": used]))
    }
    #expect(try concurrency(3, 4).tone == .caution)
    #expect(try concurrency(2, 4).tone == nil)
    #expect(try concurrency(9, 10).tone == .critical)
    let over = try concurrency(5, 4)
    #expect(over.fraction == 1 && over.tone == .critical && over.text == "5/4 并发")
}

@Test func todayCellFromListState() {
    let stats = AccountTodayStats(requests: 1, tokens: 2, cost: 3, userCost: Decimal(string: "12.34"))
    #expect(AccountTodayCell(stats: stats, unavailable: false) == .value(Decimal(string: "12.34")!))
    #expect(AccountTodayCell(stats: stats, unavailable: true) == .failed)
    #expect(AccountTodayCell(stats: nil, unavailable: false) == .failed)
    #expect(AccountTodayCell(stats: AccountTodayStats(requests: 1, tokens: 2, cost: 3), unavailable: false) == .failed)
    #expect(AccountTodayCell.value(0).text == "$0.00" && AccountTodayCell.failed.text == "—" && AccountTodayCell.hidden.text == nil)
}

// MARK: - Glyph, badge and VoiceOver

@Test func stateIconsAndIdleStates() {
    let icons = AccountScheduleState.allCases.map { AccountRowPresentation.systemImage(for: $0) }
    #expect(Set(icons).count == AccountScheduleState.allCases.count)
    #expect(AccountRowPresentation.systemImage(for: .available) == "circle.fill")
    #expect(AccountRowPresentation.systemImage(for: .rateLimited) == "hourglass")
    #expect(AccountRowPresentation.systemImage(for: .overloaded) == "flame")
    #expect(AccountRowPresentation.systemImage(for: .tempUnschedulable) == "clock.badge.exclamationmark")
    #expect(AccountRowPresentation.systemImage(for: .error) == "exclamationmark.octagon")
    #expect(AccountRowPresentation.systemImage(for: .paused) == "pause")
    #expect(AccountRowPresentation.systemImage(for: .inactive) == "minus")
    #expect(AccountScheduleState.allCases.filter(AccountRowPresentation.isIdle) == [.paused, .inactive])
}

@Test func badgeTextHiddenForNormalAndCountsDownForTimedStates() throws {
    func badge(_ account: UpstreamAccount) -> String? { AccountRowPresentation.badgeText(AccountDisplayState(account, now: now), now: now) }
    #expect(badge(try row()) == nil)
    #expect(badge(try row(fields: ["rate_limit_reset_at": stamp(277)])) == "限流中 4:37")
    #expect(badge(try row(fields: ["rate_limit_reset_at": stamp(3_725)])) == "限流中 1:02:05")
    #expect(badge(try row(status: "error")) == "错误")
    #expect(badge(try row(fields: ["auto_pause_on_expired": true, "expires_at": Int(now.timeIntervalSince1970) - 60])) == "暂停 · 已过期")
}

@Test func countdownExpiryFallsToNextState() throws {
    let account = try row(fields: ["overload_until": stamp(1_200), "rate_limit_reset_at": stamp(1_500), "concurrency": 4, "current_concurrency": 1])
    #expect(AccountDisplayState(account, now: now.addingTimeInterval(1_140)).label == "过载中")
    let next = now.addingTimeInterval(1_201)
    #expect(AccountDisplayState(account, now: next).label == "限流中")
    guard case .limited(_, _, let resume, _) = third(account, at: next) else { Issue.record("not limited"); return }
    #expect(resume == "10:05 恢复")
    let after = now.addingTimeInterval(1_560)
    #expect(AccountDisplayState(account, now: after).label == "正常")
    guard case .usage = third(account, at: after) else { Issue.record("not usage"); return }
}

@Test func accessibilityLabelReadsMissingValuesAsNoData() throws {
    let plain = try row(fields: ["concurrency_available": false])
    let usage = third(plain, today: .failed)
    let spoken = AccountRowPresentation.accessibilityLabel(name: "账号-1", display: AccountDisplayState(plain, now: now), now: now,
                                                           second: second(plain, .platform), third: usage)
    #expect(spoken == "账号-1，正常，高级组、Claude Code 组 · OAuth，并发 无数据，今日 无数据")
    #expect(!spoken.contains("—"))
    let limited = try row(fields: ["rate_limit_reset_at": stamp(277)])
    let limitedSpoken = AccountRowPresentation.accessibilityLabel(name: "账号-1", display: AccountDisplayState(limited, now: now), now: now,
                                                                  second: second(limited, .platform), third: third(limited))
    #expect(limitedSpoken == "账号-1，限流中，剩余 4:37，高级组、Claude Code 组 · OAuth，上游 429，09:44 恢复")
    let hidden = AccountRowPresentation.accessibilityLabel(name: "账号-1", display: AccountDisplayState(plain, now: now), now: now,
                                                           second: "x", third: third(plain, today: .hidden))
    #expect(hidden.hasSuffix("并发 无数据"))
}
