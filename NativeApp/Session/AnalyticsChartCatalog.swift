import Foundation

// 40 §2.1 / §3.1 the analytics charts as the pages name and group them (S4-14). S4-17 appends what only 更多图表 needs at the end of
// this file; the names below stay as they are.

extension AnalyticsTopic {
    /// The topic's capsule and header: 计费 / 用量 / 运行.
    var title: String {
        switch self {
        case .billing: "计费"
        case .usage: "用量"
        case .ops: "运行"
        }
    }

    /// The topic's charts in the order 更多图表 lists them.
    var charts: [AnalyticsChartKey] {
        switch self {
        case .billing: [.billing, .profit]
        case .usage: [.tokens, .userTrend, .endpoints, .reqType]
        case .ops: [.perf, .accountSwitch, .latency, .errTrend, .errDist, .tokenSpeed]
        }
    }
}

extension AnalyticsChartKey {
    /// The chart's name: a card's title, the chart page's navigation title.
    var title: String {
        switch self {
        case .billing: "计费明细"
        case .profit: "利润明细"
        case .tokens: "Token 使用趋势"
        case .userTrend: "用户用量趋势"
        case .endpoints: "端点分布"
        case .reqType: "请求类型"
        case .perf: "RPM / TPM 趋势"
        case .accountSwitch: "平均账号切换"
        case .latency: "请求时长分布"
        case .errTrend: "错误趋势"
        case .errDist: "错误分布"
        case .tokenSpeed: "Token 请求统计"
        }
    }

    var topic: AnalyticsTopic {
        switch self {
        case .billing, .profit: .billing
        case .tokens, .userTrend, .endpoints, .reqType: .usage
        case .perf, .accountSwitch, .latency, .errTrend, .errDist, .tokenSpeed: .ops
        }
    }

    /// 40 §3.1: only 计费明细 and 利润明细 open on a page of their own (the cards' feet); the others are seen in 更多图表.
    var hasSinglePage: Bool { topic == .billing }

    /// The chart page's subtitle “<主题> · <窗口>”: “计费 · 今天”.
    func pageSubtitle(rangeName: String) -> String { topic.title + " · " + rangeName }
}
