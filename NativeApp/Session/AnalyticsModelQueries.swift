import Foundation
import Sub2Core

// 40 §5 模型页 over the analytics session (S4-19): the page has no filter button, yet the session's group filter counts (a model
// filter is ignored); every read carries the page's model, its source, the range and that group. AnalyticsModelView.swift reads
// through these.

/// The model page's blocks, each a card of its own.
enum AnalyticsModelPart: String, CaseIterable, Sendable {
    /// AnalyticsSummary: the range's `usage/stats`.
    case summary
    /// AnalyticsSummary: the comparison window's.
    case comparison
    /// DashboardTrendReply.
    case trend
    /// AnalyticsModelSpeed.
    case speed
    /// AnalyticsUserRanking.
    case users
}

extension AnalyticsCardKey {
    /// One per model and source, so two model pages on the stack keep their own; 统计分析's refreshes never reach them, so they do
    /// not count toward its “N 分钟前更新” (S4D2b-14).
    static func modelPage(_ part: AnalyticsModelPart, _ name: AnalyticsModelName) -> AnalyticsCardKey {
        AnalyticsCardKey("model.\(part.rawValue)|\(name.source.rawValue)|\(name.raw)", showsInUpdateLine: false)
    }
    /// AnalyticsSummary: the share's denominator while the session filters by a model, which the page leaves out.
    static let modelPageDenominator = AnalyticsCardKey("model.denominator", showsInUpdateLine: false)
}

extension AnalyticsSessionState {
    /// The group filter's id; a model filter does not count here.
    var modelPageGroupID: Int? {
        guard case .group(let id)? = filter else { return nil }
        return id
    }
    /// The share label's “占高级组”: the group's name, “#id” while unknown.
    var modelPageGroupLabel: String? { modelPageGroupID == nil ? nil : filterName }

    /// The range and the group without a model: the share's denominator.
    func modelPageScope() -> AnalyticsQuery {
        var scoped = query(filtered: false)
        scoped.groupID = modelPageGroupID
        return scoped
    }
    func modelPageQuery(_ name: AnalyticsModelName) -> AnalyticsQuery {
        name.applied(to: modelPageScope(), supportsModelSource: supportsModelSource)
    }
    func modelPageComparisonQuery(_ name: AnalyticsModelName) -> AnalyticsQuery {
        var query = modelPageQuery(name)
        query.start = range.comparison.start; query.end = range.comparison.end
        return query
    }
    func modelPageSpeedPlan(_ name: AnalyticsModelName) -> AnalyticsModelSpeedPlan {
        name.speedPlan(supportsOpsModelFilter: supportsOpsModelFilter)
    }
    func modelPageOpsQuery(_ plan: AnalyticsModelSpeedPlan) -> OpsQuery? {
        plan.opsQuery(start: range.start, end: range.end, groupID: modelPageGroupID)
    }
    /// 40 §5.5 the speed block, read only while ops monitoring counts as on: a kept 404 OPS_DISABLED is read again without a refresh
    /// (ops back on, or other instances catching up within 30 seconds), so the block comes back by itself.
    func loadModelPageSpeed(_ name: AnalyticsModelName, refresh: Bool,
                            fixture: @escaping @MainActor @Sendable (AnalyticsSessionState) async throws -> AnalyticsModelSpeed,
                            operation: @escaping @MainActor @Sendable (APIClient, AnalyticsSessionState) async throws -> AnalyticsModelSpeed) async {
        let key = AnalyticsCardKey.modelPage(.speed, name)
        let hidden = state(key, as: AnalyticsModelSpeed.self)?.value == .opsDisabled
        await load(key, refresh: refresh || hidden, fixture: fixture, operation: operation)
    }

    /// Without a filter or with a group one, 统计分析's billing total is the denominator (S4D2b-01); under a model filter the page
    /// reads its own (`modelPageDenominator`).
    var modelPageSharesBillingTotal: Bool { filter?.kind != .model }

    /// 40 §5.1 “这个模型的使用记录”: the model with its source and the session's group, as the page reads them.
    func modelPageLogsRoute(_ name: AnalyticsModelName) -> LogsRoute {
        let value = name.filterValue(supportsModelSource: supportsModelSource)
        let group = modelPageGroupID.map { RouteObject(id: $0, name: groups?.name(for: $0)) }
        return LogsRoute(scope: .usage, group: group, model: value.model, modelSource: value.source ?? .requested)
    }
}
