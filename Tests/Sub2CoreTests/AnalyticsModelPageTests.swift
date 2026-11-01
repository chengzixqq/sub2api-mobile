import Foundation
import Testing
@testable import Sub2Core

// 40 §5 模型页 (S4-19): the title, what every read sends, the speed plan and its merge, and what each block says. The split of
// “a -> b” itself is S4-15's (AnalyticsModelNameTests).

private let shanghai = ServerTimeZone(identifier: "Asia/Shanghai", utcOffset: "+08:00")!
private func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }
private let weekStart = utc("2026-10-09T16:00:00Z")
private let morning = utc("2026-10-16T01:41:00Z")
private let opus = "claude-opus-4"
private let opusUpstream = "claude-opus-4-20250514"
private let mapping = AnalyticsModelName("claude-opus-4 -> claude-opus-4-20250514", source: .mapping)

private func items(_ query: AnalyticsQuery) throws -> [String: String] {
    Dictionary(try query.queryItems().map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
}
private func items(_ query: OpsQuery?, supportsModelFilter: Bool = true) -> [String: String]? {
    query.map { Dictionary($0.queryItems(supportsModelFilter: supportsModelFilter).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first }) }
}
private func summary(_ json: String) throws -> AnalyticsSummary { try JSONDecoder().decode(AnalyticsSummary.self, from: Data(json.utf8)) }
private func values(_ figures: [AnalyticsFigure]) -> [String: String] { Dictionary(uniqueKeysWithValues: figures.map { ($0.key, $0.value) }) }
private func tokenRow(_ model: String, _ requests: Int, speed: Double?, firstToken: Double?, withFirstToken: Int, duration: Double?) -> OpsTokenStats.Item {
    OpsTokenStats.Item(model: model, requestCount: requests, tokensPerSecond: speed, firstTokenMs: firstToken, durationMs: duration,
                       requestsWithFirstToken: withFirstToken)
}

@Test func modelPageTitleShowsTheMappingArrow() {
    #expect(mapping.title == "claude-opus-4 → claude-opus-4-20250514")
    for source in [ModelSource.requested, .upstream] {
        #expect(AnalyticsModelName("a -> b", source: source).title == "a -> b", "\(source)")
    }
    #expect(AnalyticsModelName("gpt-5", source: .mapping).title == "gpt-5")
    #expect(AnalyticsModelName(" -> b", source: .mapping).title == " -> b")
    #expect(AnalyticsModelPresentation.upstreamLine(mapping) == "上游模型 claude-opus-4-20250514")
    #expect(AnalyticsModelPresentation.upstreamLine(AnalyticsModelName(opus, source: .requested)) == nil)
    #expect(AnalyticsModelPresentation.upstreamLine(AnalyticsModelName(opusUpstream, source: .upstream)) == nil)
}

@Test func modelPageQuerySendsModelSourceRangeAndGroup() throws {
    let base = AnalyticsQuery(start: weekStart, end: morning, granularity: .day, timeZone: shanghai, groupID: 1)
    let cases: [(AnalyticsModelName, String)] = [(AnalyticsModelName(opus, source: .requested), "requested"),
                                                 (AnalyticsModelName(opusUpstream, source: .upstream), "upstream"), (mapping, "mapping")]
    for (name, source) in cases {
        let sent = try items(name.applied(to: base, supportsModelSource: true))
        #expect(sent["model"] == name.raw && sent["model_source"] == source, "\(source)")
        #expect(sent["group_id"] == "1" && sent["timezone"] == "Asia/Shanghai")
        #expect(sent["start_time"] == "2026-10-09T16:00:00Z" && sent["end_time"] == "2026-10-16T01:41:00Z")
    }
    #expect(mapping.applied(to: base, supportsModelSource: true).granularity == .day)
}

@Test func modelPageQueryWithoutModelSourceSendsTheNearestName() throws {
    let base = AnalyticsQuery(start: weekStart, end: morning, granularity: .day, timeZone: shanghai)
    let mapped = try items(mapping.applied(to: base, supportsModelSource: false))
    #expect(mapped["model"] == opus && mapped["model_source"] == nil)
    let upstream = AnalyticsModelName(opusUpstream, source: .upstream)
    #expect(try items(upstream.applied(to: base, supportsModelSource: false))["model"] == opusUpstream)
    #expect(mapping.filterValue(supportsModelSource: false) == (opus, nil))
    #expect(mapping.filterValue(supportsModelSource: true) == (mapping.raw, .mapping))
    #expect(upstream.filterValue(supportsModelSource: true) == (opusUpstream, .upstream))
}

@Test(arguments: [true, false])
func modelPageSpeedPlanFollowsOpsModelFilter(supports: Bool) {
    let requested = AnalyticsModelName(opus, source: .requested), upstream = AnalyticsModelName(opusUpstream, source: .upstream)
    let unsplit = AnalyticsModelName("gpt-5", source: .mapping)
    let plans = [requested, upstream, mapping, unsplit].map { $0.speedPlan(supportsOpsModelFilter: supports) }
    if supports {
        #expect(plans == [.filtered(model: opus, source: .requested), .filtered(model: opusUpstream, source: .upstream),
                          .filtered(model: opusUpstream, source: .upstream), .filtered(model: "gpt-5", source: .requested)])
        #expect(plans.map(\.topN) == [10, 10, 10, 10])
    } else {
        #expect(plans == [.matching(opus), .unavailable, .unavailable, .unavailable])
        #expect(plans.map(\.topN) == [100, nil, nil, nil])
    }
}

@Test func modelPageSpeedPlanBuildsTheOpsQuery() {
    let filtered = mapping.speedPlan(supportsOpsModelFilter: true).opsQuery(start: weekStart, end: morning, groupID: 2)
    #expect(items(filtered) == ["start_time": "2026-10-09T16:00:00Z", "end_time": "2026-10-16T01:41:00Z", "group_id": "2",
                                "model": opusUpstream, "model_source": "upstream"])
    let matching = AnalyticsModelSpeedPlan.matching(opus).opsQuery(start: weekStart, end: morning, groupID: nil)
    #expect(items(matching, supportsModelFilter: false) == ["start_time": "2026-10-09T16:00:00Z", "end_time": "2026-10-16T01:41:00Z"])
    #expect(AnalyticsModelSpeedPlan.unavailable.opsQuery(start: weekStart, end: morning, groupID: 2) == nil)
}

@Test func modelPageFilteredSpeedMergesEveryRowByWeights() throws {
    let stats = OpsTokenStats(items: [tokenRow("claude-opus-4", 100, speed: 50, firstToken: 800, withFirstToken: 80, duration: 9_000),
                                      tokenRow("claude-opus-4-latest", 300, speed: 30, firstToken: 1_200, withFirstToken: 300, duration: 5_000)],
                              window: .custom)
    guard case .measured(let speed?, let window) = AnalyticsModelSpeed(stats, plan: .filtered(model: opusUpstream, source: .upstream)) else {
        Issue.record("expected a merged speed"); return
    }
    #expect(window == .custom && speed.requestCount == 400)
    #expect(abs((speed.tokensPerSecond ?? 0) - 35) < 0.0001)
    #expect(abs((speed.firstTokenMs ?? 0) - (800.0 * 80 + 1_200.0 * 300) / 380) < 0.0001)
    #expect(abs((speed.durationMs ?? 0) - 6_000) < 0.0001)
}

@Test func modelPageSiteWideSpeedTakesOnlyTheSameNamedRows() {
    let window = OpsTokenStatsWindow.rolling(.fifteenDays, coversRange: true)
    let stats = OpsTokenStats(items: [tokenRow("gpt-5", 200, speed: 80, firstToken: 600, withFirstToken: 200, duration: 3_000),
                                      tokenRow("gpt-5-mini", 900, speed: 120, firstToken: 300, withFirstToken: 900, duration: 1_000)],
                              window: window)
    #expect(AnalyticsModelSpeed(stats, plan: .matching("gpt-5")) == .measured(stats.merged(matching: "gpt-5"), window: window))
    #expect(AnalyticsModelSpeed(stats, plan: .matching("deepseek-v3")) == .measured(nil, window: window))
    #expect(AnalyticsModelSpeed(stats, plan: .unavailable) == .measured(nil, window: window))
    #expect(AnalyticsModelSpeed(stats, plan: .matching("gpt-5")).speed?.requestCount == 200)
    #expect(AnalyticsModelSpeed(stats, plan: .matching("gpt-5")).window == window)
    #expect(AnalyticsModelSpeed.opsDisabled.speed == nil && AnalyticsModelSpeed.opsDisabled.window == nil)
    #expect(values(AnalyticsModelPresentation.speed(nil)) == ["tps": "—", "firstToken": "—", "duration": "—"])
}

@Test func modelPageSpeedCellsFormat() {
    func cells(_ speed: Double?, _ firstToken: Double?, _ duration: Double?) -> [String: String] {
        values(AnalyticsModelPresentation.speed(OpsTokenSpeed(requestCount: 10, tokensPerSecond: speed, firstTokenMs: firstToken, durationMs: duration)))
    }
    #expect(cells(48.25, 820, 9_400) == ["tps": "48.3", "firstToken": "820ms", "duration": "9.4s"])
    #expect(cells(86, 2_400, 42_000) == ["tps": "86.0", "firstToken": "2.4s", "duration": "42s"])
    #expect(cells(nil, nil, 0) == ["tps": "—", "firstToken": "—", "duration": "—"])
    #expect(AnalyticsModelPresentation.speed(nil).map(\.label) == ["输出 Tokens/秒", "平均首 Token", "平均时长"])
}

@Test func modelPageSpeedMetaAndFootnoteFollowTheWindow() {
    #expect(AnalyticsModelPresentation.speedMeta(.custom, rangeName: "近 7 天") == "近 7 天")
    #expect(AnalyticsModelPresentation.speedFootnote(.custom) == "统计窗口与所选范围一致。")
    let covering = OpsTokenStatsWindow.rolling(.fifteenDays, coversRange: true)
    #expect(AnalyticsModelPresentation.speedMeta(covering, rangeName: "近 7 天") == "近 15 天")
    #expect(AnalyticsModelPresentation.speedFootnote(covering).contains("取能盖住所选范围的最小一个"))
    let short = OpsTokenStatsWindow.rolling(.thirtyDays, coversRange: false)
    #expect(AnalyticsModelPresentation.speedFootnote(short).contains("盖不住所选范围"))
    for window in [OpsTokenStatsWindow.custom, covering, short] {
        #expect(!AnalyticsModelPresentation.speedFootnote(window).contains("只列「"))
    }
}

@Test func modelPageShareLabelUsesTheGroupNameAndGuardsTheDenominator() {
    let share = AnalyticsModelPresentation.shareLabel
    #expect(share(Decimal(string: "180.20"), Decimal(string: "1464.70"), nil) == "实际扣费 · 占全部 12.3%")
    #expect(share(Decimal(string: "180.20"), Decimal(string: "1464.70"), "高级组") == "实际扣费 · 占高级组 12.3%")
    #expect(share(Decimal(string: "180.20"), 0, nil) == "实际扣费 · 占全部 —")
    #expect(share(Decimal(string: "180.20"), nil, nil) == "实际扣费 · 占全部 —")
    #expect(share(nil, Decimal(string: "1464.70"), "高级组") == "实际扣费 · 占高级组 —")
}

@Test func modelPageUsageCellsFormatAndEmptyRequests() throws {
    let full = try summary(#"{"total_requests":1210,"total_tokens":35800000,"total_cache_read_tokens":19332000,"total_actual_cost":"180.20"}"#)
    #expect(values(AnalyticsModelPresentation.usage(full)) == ["requests": "1,210", "tokens": "35.8M", "cacheRead": "54%", "average": "$0.149"])
    let idle = try summary(#"{"total_requests":0,"total_tokens":0,"total_cache_read_tokens":0,"total_actual_cost":"0"}"#)
    #expect(values(AnalyticsModelPresentation.usage(idle)) == ["requests": "0", "tokens": "0", "cacheRead": "—", "average": "—"])
    let noCacheKey = try summary(#"{"total_requests":5,"total_tokens":900,"total_actual_cost":"1.00"}"#)
    #expect(values(AnalyticsModelPresentation.usage(noCacheKey))["cacheRead"] == "—")
    #expect(values(AnalyticsModelPresentation.usage(nil)) == ["requests": "—", "tokens": "—", "cacheRead": "—", "average": "—"])
    #expect(AnalyticsModelPresentation.usage(nil).map(\.label) == ["请求", "Tokens", "缓存读占比", "平均每次"])
}

@Test func modelPageSubtitleLogsRowAndSectionCopy() {
    #expect(AnalyticsModelPresentation.subtitle(rangeName: "近 7 天") == "模型 · 近 7 天")
    #expect(AnalyticsModelPresentation.logsSubtitle(hasGroup: false) == "近 24 小时 · 带上模型筛选，可以去掉")
    #expect(AnalyticsModelPresentation.logsSubtitle(hasGroup: true) == "近 24 小时 · 带上模型和分组筛选，可以去掉")
    #expect(AnalyticsModelPresentation.logsTitle == "这个模型的使用记录")
    #expect(AnalyticsModelPresentation.usersEmpty == "这个范围内没有用户用量")
    #expect(AnalyticsModelPresentation.trendMeta == "实际 / 标准（点线）")
    #expect(AnalyticsModelPresentation.usersMeta == "实际扣费")
}

/// 40 §5.5: with ops monitoring off the speed block goes and the users take its number.
@Test func modelPageSectionsNumberInTheOrderShown() {
    let all = AnalyticsModelPresentation.Outline(showsSpeed: true)
    #expect([all.trend, all.usage, all.speed, all.users] == ["壹", "贰", "叁", "肆"])
    let opsOff = AnalyticsModelPresentation.Outline(showsSpeed: false)
    #expect([opsOff.trend, opsOff.usage, opsOff.users] == ["壹", "贰", "叁"])
    #expect(opsOff.speed == nil)
}

/// 40 §5.2: the filtered plan's query goes out once with b, upstream and ten rows; the site-wide one without a model.
@Test func modelPageTokenStatsRequests() async throws {
    let transport = ScriptedTransport { _ in okReply(#"{"time_range":"custom","items":[]}"#) }
    let client = APIClient(server: stubServer(), credential: .adminKey("fixture"), transport: transport, requestClock: .immediate,
                           serverTimeZone: shanghai, serverClock: ServerClock(localNow: { morning }))
    let filtered = mapping.speedPlan(supportsOpsModelFilter: true)
    let matching = AnalyticsModelName(opus, source: .requested).speedPlan(supportsOpsModelFilter: false)
    for (plan, supports) in [(filtered, true), (matching, false)] {
        let query = try #require(plan.opsQuery(start: weekStart, end: morning, groupID: 3))
        let topN = try #require(plan.topN)
        _ = try await client.opsTokenStats(query, topN: topN, supportsCustomRange: true, supportsModelFilter: supports)
    }
    let sent = await transport.requests
    try #require(sent.count == 2)
    #expect(sent.allSatisfy { $0.url?.path == "/api/v1/admin/ops/dashboard/openai-token-stats" })
    let queries = sent.map { request in
        Dictionary((request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []).map { ($0.name, $0.value ?? "") },
                   uniquingKeysWith: { first, _ in first })
    }
    let range = ["start_time": "2026-10-09T16:00:00Z", "end_time": "2026-10-16T01:41:00Z", "group_id": "3"]
    #expect(queries[0] == range.merging(["model": opusUpstream, "model_source": "upstream", "top_n": "10"]) { $1 })
    #expect(queries[1] == range.merging(["top_n": "100"]) { $1 })
}
