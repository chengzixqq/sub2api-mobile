import Testing
@testable import NativeSessionSupport

// 40 §2.1 / §3.1 the analytics charts' names, topics and single pages (S4-14).

@Test func chartTitlesFollowTheSpecOrder() {
    #expect(AnalyticsChartKey.allCases.map(\.title) == [
        "计费明细", "利润明细", "Token 使用趋势", "用户用量趋势", "端点分布", "请求类型",
        "RPM / TPM 趋势", "平均账号切换", "请求时长分布", "错误趋势", "错误分布", "Token 请求统计",
    ])
    #expect(Set(AnalyticsChartKey.allCases.map(\.title)).count == AnalyticsChartKey.allCases.count)
}

@Test func topicsListTwoFourAndSixCharts() {
    #expect(AnalyticsTopic.allCases.map(\.title) == ["计费", "用量", "运行"])
    #expect(AnalyticsTopic.allCases.map(\.charts.count) == [2, 4, 6])
    #expect(AnalyticsTopic.billing.charts == [.billing, .profit])
    #expect(AnalyticsTopic.usage.charts == [.tokens, .userTrend, .endpoints, .reqType])
    #expect(AnalyticsTopic.ops.charts == [.perf, .accountSwitch, .latency, .errTrend, .errDist, .tokenSpeed])
    for chart in AnalyticsChartKey.allCases {
        #expect(AnalyticsTopic.allCases.filter { $0.charts.contains(chart) } == [chart.topic])
    }
}

@Test func onlyBillingAndProfitHaveASinglePage() {
    #expect(AnalyticsChartKey.allCases.filter(\.hasSinglePage) == [.billing, .profit])
    #expect(AnalyticsChartKey.billing.pageSubtitle(rangeName: "今天") == "计费 · 今天")
    #expect(AnalyticsChartKey.profit.pageSubtitle(rangeName: "近 7 天") == "计费 · 近 7 天")
}

// 40 §1.4 更多图表卡 and §2.1 更多图表's chips, tiles, windows and landing (S4-17).

@Test func opsTopicNoteIsTheOnlyLiteral() {
    #expect(AnalyticsTopic.ops.note == "需开启运维监控")
    #expect(AnalyticsTopic.billing.note == nil && AnalyticsTopic.usage.note == nil)
}

@Test func chipTitlesCardCountAndFooterFollowTheOpsSwitch() {
    #expect(AnalyticsTopic.allCases.map { AnalyticsChartCatalog.chipTitle($0, opsEnabled: true) } == ["计费 2", "用量 4", "运行 6"])
    #expect(AnalyticsTopic.allCases.map { AnalyticsChartCatalog.chipTitle($0, opsEnabled: false) } == ["计费 2", "用量 4", "运行 —"])
    #expect(AnalyticsChartCatalog.chipSpokenLabel(.billing, opsEnabled: true) == "计费，2 张图")
    #expect(AnalyticsChartCatalog.chipSpokenLabel(.ops, opsEnabled: false) == "运行，未开启")
    #expect(AnalyticsChartCatalog.chartCount(opsEnabled: true) == 12 && AnalyticsChartCatalog.chartCount(opsEnabled: false) == 6)
    #expect(AnalyticsChartCatalog.cardMeta(opsEnabled: true) == "12 张" && AnalyticsChartCatalog.cardMeta(opsEnabled: false) == "6 张")
    #expect(AnalyticsChartCatalog.footerMeta(opsEnabled: true) == "计费 2 · 用量 4 · 运行 6")
    #expect(AnalyticsChartCatalog.footerMeta(opsEnabled: false) == "计费 2 · 用量 4 · 运行 未开启")
}

@Test func tilesSwapOpsChartsWhenMonitoringIsOff() {
    #expect(AnalyticsChartCatalog.tileCharts(opsEnabled: true) == [.tokens, .userTrend, .errTrend, .latency])
    #expect(AnalyticsChartCatalog.tileCharts(opsEnabled: false) == [.tokens, .userTrend, .endpoints, .reqType])
}

@Test func landingPrefersTheChartThenTheTopic() {
    #expect(AnalyticsChartCatalog.landing(chart: .tokens, topic: .ops, opsEnabled: true) == .chart(.tokens))
    #expect(AnalyticsChartCatalog.landing(chart: nil, topic: .usage, opsEnabled: true) == .topic(.usage))
    #expect(AnalyticsChartCatalog.landing(chart: nil, topic: nil, opsEnabled: true) == nil)
    #expect(AnalyticsChartCatalog.landing(chart: .errTrend, topic: nil, opsEnabled: true) == .chart(.errTrend))
    // Ops off: the ops charts are one notice, under the 运行 header.
    #expect(AnalyticsChartCatalog.landing(chart: .errTrend, topic: nil, opsEnabled: false) == .topic(.ops))
    #expect(AnalyticsChartCatalog.landing(chart: .endpoints, topic: nil, opsEnabled: false) == .chart(.endpoints))
}

@Test func activeTopicFollowsTheLastRowPastTheBarAndTheBottom() {
    #expect(AnalyticsChartCatalog.activeTopic(passed: [], isAtBottom: false) == .billing)
    #expect(AnalyticsChartCatalog.activeTopic(passed: [.topic(.billing), .chart(.billing)], isAtBottom: false) == .billing)
    // The rows past the bar's edge that still show; the lowest of them decides.
    #expect(AnalyticsChartCatalog.activeTopic(passed: [.chart(.profit), .topic(.usage)], isAtBottom: false) == .usage)
    #expect(AnalyticsChartCatalog.activeTopic(passed: [.chart(.endpoints)], isAtBottom: false) == .usage)
    #expect(AnalyticsChartCatalog.activeTopic(passed: [.chart(.reqType), .topic(.ops)], isAtBottom: false) == .ops)
    #expect(AnalyticsChartCatalog.activeTopic(passed: [.chart(.latency)], isAtBottom: false) == .ops)
    // Scrolled to the end the last topic lights up, even when its header never reaches the bar.
    #expect(AnalyticsChartCatalog.activeTopic(passed: [.chart(.reqType)], isAtBottom: true) == .ops)
    #expect(AnalyticsMoreAnchor.chart(.tokenSpeed).topic == .ops && AnalyticsMoreAnchor.topic(.usage).topic == .usage)
}

@Test func windowLabelAddsTheOpsSuffix() {
    #expect(AnalyticsChartCatalog.windowLabel(of: .tokens, rangeName: "近 7 天") == "近 7 天")
    #expect(AnalyticsChartCatalog.windowLabel(of: .billing, rangeName: "今天") == "今天")
    #expect(AnalyticsChartCatalog.windowLabel(of: .perf, rangeName: "近 7 天") == "截至现在 · 运维监控")
    #expect(AnalyticsChartCatalog.windowLabel(of: .errTrend, rangeName: "近 7 天") == "近 7 天 · 运维监控")
    #expect(AnalyticsChartCatalog.windowLabel(of: .tokenSpeed, rangeName: "近 7 天") == "近 7 天 · 运维监控")
    #expect(AnalyticsChartCatalog.windowLabel(of: .tokenSpeed, rangeName: "近 7 天", tokenStatsWindow: "近 15 天") == "近 15 天 · 运维监控")
    #expect(AnalyticsChartCatalog.windowLabel(of: .errTrend, rangeName: "近 7 天", tokenStatsWindow: "近 15 天") == "近 7 天 · 运维监控")
}
