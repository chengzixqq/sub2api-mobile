import Foundation

// 40 §5 模型页 (S4-19): what the page sends for one model and what its blocks say. AnalyticsModelName is S4-15's; this file only
// extends it (S4D2b-11).

extension AnalyticsModelName {
    /// 40 §5.1 the title: “a → b” for a mapping name that splits, else the name as sent.
    public var title: String {
        guard source == .mapping, let upstream else { return raw }
        return requested + " → " + upstream
    }

    /// `usage/stats`, `dashboard/*` and `admin/usage` take the raw name and its source. A site without `usage.model_source` reads
    /// a model alone as requested: it gets no source, and a mapping name its requested half (an upstream name stays as the nearest).
    public func filterValue(supportsModelSource: Bool) -> (model: String, source: ModelSource?) {
        guard supportsModelSource else { return (source == .mapping ? requested : raw, nil) }
        return (raw, source)
    }

    /// Only the model and its source change; the range, the group and the zone stay.
    public func applied(to query: AnalyticsQuery, supportsModelSource: Bool) -> AnalyticsQuery {
        let value = filterValue(supportsModelSource: supportsModelSource)
        var scoped = query
        scoped.model = value.model
        scoped.modelSource = value.source
        return scoped
    }

    /// 40 §5.2 速度. The token stats group by the requested model, so without `ops.dashboard_model_filter` only a requested name has
    /// a row of its own to look for (S4D2b-20).
    public func speedPlan(supportsOpsModelFilter: Bool) -> AnalyticsModelSpeedPlan {
        switch (supportsOpsModelFilter, source) {
        case (true, .mapping):
            upstream.map { AnalyticsModelSpeedPlan.filtered(model: $0, source: .upstream) } ?? .filtered(model: raw, source: .requested)
        case (true, _): .filtered(model: raw, source: source)
        case (false, .requested): .matching(raw)
        case (false, _): .unavailable
        }
    }
}

/// How the model page reads its speed (40 §5.2, S4D2b-20).
public enum AnalyticsModelSpeedPlan: Hashable, Sendable {
    /// With `ops.dashboard_model_filter`: the model as sent (a mapping's b as upstream); every row that comes back is merged.
    case filtered(model: String, source: ModelSource)
    /// Without it, a requested name: the site's rows, and the one of that name.
    case matching(String)
    /// Without it, an upstream or mapping name: no row can be its own, so nothing is read and the cells show “—”.
    case unavailable

    public var topN: Int? {
        switch self {
        case .filtered: 10
        case .matching: 100
        case .unavailable: nil
        }
    }

    public func opsQuery(start: Date, end: Date, groupID: Int?) -> OpsQuery? {
        switch self {
        case .filtered(let model, let source): OpsQuery(start: start, end: end, groupID: groupID, model: model, modelSource: source)
        case .matching: OpsQuery(start: start, end: end, groupID: groupID)
        case .unavailable: nil
        }
    }
}

/// The speed block's value: a 404 OPS_DISABLED is not a failure but hides the block (40 §5.5).
public enum AnalyticsModelSpeed: Equatable, Sendable {
    case opsDisabled
    /// nil: no row for the model.
    case measured(OpsTokenSpeed?, window: OpsTokenStatsWindow)

    public init(_ stats: OpsTokenStats, plan: AnalyticsModelSpeedPlan) {
        switch plan {
        case .filtered: self = .measured(OpsTokenStats.merged(stats.items), window: stats.window)
        case .matching(let name): self = .measured(stats.merged(matching: name), window: stats.window)
        case .unavailable: self = .measured(nil, window: stats.window)
        }
    }

    public var speed: OpsTokenSpeed? {
        guard case .measured(let speed, _) = self else { return nil }
        return speed
    }
    /// The window the server answered for; nil while ops monitoring is off.
    public var window: OpsTokenStatsWindow? {
        guard case .measured(_, let window) = self else { return nil }
        return window
    }
}

/// 40 §5.1 / §5.3 the model page's copy and cells.
public enum AnalyticsModelPresentation {
    public static let trendTitle = "趋势"
    public static let usageTitle = "用量"
    public static let speedTitle = "速度"
    public static let usersTitle = "用得最多的用户"
    public static let trendMeta = "实际 / 标准（点线）"
    public static let usersMeta = "实际扣费"
    public static let usersEmpty = "这个范围内没有用户用量"
    public static let logsTitle = "这个模型的使用记录"
    public static let usersShown = 3

    /// “模型 · 近 7 天”; the backend has no platform for a model (U36).
    public static func subtitle(rangeName: String) -> String { "模型 · " + rangeName }

    /// “上游模型 b” for a mapping name that splits.
    public static func upstreamLine(_ name: AnalyticsModelName) -> String? {
        guard name.source == .mapping, let upstream = name.upstream else { return nil }
        return "上游模型 " + upstream
    }

    /// “实际扣费 · 占全部 12.3%” (“占高级组 …” under a group filter); “—” without either amount or with a denominator not above 0.
    public static func shareLabel(actual: Decimal?, denominator: Decimal?, groupName: String?) -> String {
        let prefix = "实际扣费 · 占" + (groupName ?? "全部") + " "
        guard let actual, let denominator, denominator > 0 else { return prefix + DisplayFormat.missing }
        return prefix + DisplayFormat.ratioPercent(NSDecimalNumber(decimal: actual / denominator).doubleValue)
    }

    /// The design's line; the spec leaves its end out under a group filter.
    public static func logsSubtitle(hasGroup: Bool) -> String {
        "近 24 小时 · 带上" + (hasGroup ? "模型和分组" : "模型") + "筛选，可以去掉"
    }

    /// 请求 / Tokens / 缓存读占比 / 平均每次 (keys requests / tokens / cacheRead / average). A share or an average over 0 is “—”.
    public static func usage(_ summary: AnalyticsSummary?) -> [AnalyticsFigure] {
        let tokens = summary?.tokens ?? 0, requests = summary?.requests ?? 0
        let cacheRead = summary?.cacheReadTokens.flatMap { tokens > 0 ? Double($0) / Double(tokens) : nil }
        let average = summary?.actualCost.flatMap { requests > 0 ? $0 / Decimal(requests) : nil }
        return [AnalyticsFigure("requests", label: "请求", value: DisplayFormat.grouped(summary?.requests)),
                AnalyticsFigure("tokens", label: "Tokens", value: DisplayFormat.compact(summary?.tokens)),
                AnalyticsFigure("cacheRead", label: "缓存读占比", value: DisplayFormat.wholePercent(cacheRead)),
                AnalyticsFigure("average", label: "平均每次", value: DisplayFormat.money(average, digits: 3))]
    }

    /// 输出 Tokens/秒 / 平均首 Token / 平均时长 (keys tps / firstToken / duration); a value not above 0 is missing (the server
    /// writes 0 for no durations).
    public static func speed(_ speed: OpsTokenSpeed?) -> [AnalyticsFigure] {
        [AnalyticsFigure("tps", label: "输出 Tokens/秒",
                         value: DisplayFormat.decimal(positive(speed?.tokensPerSecond), minFractionDigits: 1, maxFractionDigits: 1)),
         AnalyticsFigure("firstToken", label: "平均首 Token", value: DisplayFormat.duration(positive(speed?.firstTokenMs), style: .percentile)),
         AnalyticsFigure("duration", label: "平均时长", value: DisplayFormat.duration(positive(speed?.durationMs), style: .percentile))]
    }

    /// The rolling window's name, or the range's for a custom window.
    public static func speedMeta(_ window: OpsTokenStatsWindow, rangeName: String) -> String { window.title ?? rangeName }
    /// 2.3's window sentence; the model page lists no models, so the group sentence stays out.
    public static func speedFootnote(_ window: OpsTokenStatsWindow) -> String { window.footnote() }

    /// The blocks' numbers in the order shown: without the speed block the users take its number.
    public struct Outline: Equatable, Sendable {
        public let trend: String
        public let usage: String
        public let speed: String?
        public let users: String

        public init(showsSpeed: Bool) {
            trend = ChineseOrdinal.text(1)
            usage = ChineseOrdinal.text(2)
            speed = showsSpeed ? ChineseOrdinal.text(3) : nil
            users = ChineseOrdinal.text(showsSpeed ? 4 : 3)
        }
    }

    private static func positive(_ value: Double?) -> Double? { value.flatMap { $0 > 0 ? $0 : nil } }
}
