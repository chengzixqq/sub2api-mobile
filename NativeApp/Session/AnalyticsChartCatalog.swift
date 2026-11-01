import Foundation
import Sub2Core

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

// MARK: - 更多图表（S4-17）

/// 更多图表's scroll targets: a topic's header or a chart's card.
enum AnalyticsMoreAnchor: Hashable, Sendable {
    case topic(AnalyticsTopic)
    case chart(AnalyticsChartKey)

    var topic: AnalyticsTopic {
        switch self {
        case .topic(let topic): topic
        case .chart(let chart): chart.topic
        }
    }
}

extension AnalyticsTopic {
    /// The small text beside the header: only 运行 has one.
    var note: String? { self == .ops ? "需开启运维监控" : nil }
}

/// 40 §1.4 更多图表卡 and §2.1 更多图表: what the ops switch changes (运行 is one notice while monitoring is off), the chart cards'
/// windows, where a route lands and which topic the bar lights up. vendor's four charts are not built (U01).
enum AnalyticsChartCatalog {
    /// “计费 2”, “运行 6”; 运行 with ops off “运行 —”.
    static func chipTitle(_ topic: AnalyticsTopic, opsEnabled: Bool) -> String {
        topic.title + " " + (isShown(topic, opsEnabled: opsEnabled) ? String(topic.charts.count) : DisplayFormat.missing)
    }
    /// “计费，2 张图”, “运行，未开启”.
    static func chipSpokenLabel(_ topic: AnalyticsTopic, opsEnabled: Bool) -> String {
        topic.title + "，" + (isShown(topic, opsEnabled: opsEnabled) ? "\(topic.charts.count) 张图" : "未开启")
    }
    /// 12, or 6 with ops off.
    static func chartCount(opsEnabled: Bool) -> Int {
        AnalyticsTopic.allCases.filter { isShown($0, opsEnabled: opsEnabled) }.reduce(0) { $0 + $1.charts.count }
    }
    /// The card's header, “12 张”.
    static func cardMeta(opsEnabled: Bool) -> String { "\(chartCount(opsEnabled: opsEnabled)) 张" }
    /// The card's foot after 全部图表: “计费 2 · 用量 4 · 运行 6”, with ops off “… · 运行 未开启”.
    static func footerMeta(opsEnabled: Bool) -> String {
        AnalyticsTopic.allCases.map { topic in
            topic.title + " " + (isShown(topic, opsEnabled: opsEnabled) ? String(topic.charts.count) : "未开启")
        }.joined(separator: " · ")
    }
    /// The card's four tiles: with ops off 端点分布 and 请求类型 take the ops charts' places.
    static func tileCharts(opsEnabled: Bool) -> [AnalyticsChartKey] {
        opsEnabled ? [.tokens, .userTrend, .errTrend, .latency] : [.tokens, .userTrend, .endpoints, .reqType]
    }

    /// A chart card's window: the range's name; RPM / TPM “截至现在”; Token 请求统计 its own window (S4-18b); the ops charts add
    /// “ · 运维监控”.
    static func windowLabel(of chart: AnalyticsChartKey, rangeName: String, tokenStatsWindow: String? = nil) -> String {
        guard chart.topic == .ops else { return rangeName }
        if chart == .perf { return PerfTrendPresentation.cardMeta(opsDisabled: false) }
        return (chart == .tokenSpeed ? tokenStatsWindow ?? rangeName : rangeName) + " · 运维监控"
    }

    /// The chart first, else the topic; neither stays at the top (全部图表). With ops off an ops chart lands on its topic's notice.
    static func landing(chart: AnalyticsChartKey?, topic: AnalyticsTopic?, opsEnabled: Bool) -> AnalyticsMoreAnchor? {
        if let chart { return isShown(chart.topic, opsEnabled: opsEnabled) ? .chart(chart) : .topic(chart.topic) }
        return topic.map { .topic($0) }
    }
    /// The topic under the bar's lower edge: that of the last row, in the list's order, among those on screen whose top has reached
    /// it; none (the top of the list), the first; scrolled to the end, the last.
    static func activeTopic(passed: Set<AnalyticsMoreAnchor>, isAtBottom: Bool) -> AnalyticsTopic {
        let topics = AnalyticsTopic.allCases
        if isAtBottom, let last = topics.last { return last }
        let rows = topics.flatMap { topic in [AnalyticsMoreAnchor.topic(topic)] + topic.charts.map { .chart($0) } }
        return rows.last(where: passed.contains)?.topic ?? topics[0]
    }

    private static func isShown(_ topic: AnalyticsTopic, opsEnabled: Bool) -> Bool { opsEnabled || topic != .ops }
}
