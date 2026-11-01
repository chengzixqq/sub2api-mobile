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
