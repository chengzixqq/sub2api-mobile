import SwiftUI
import Sub2Core

/// 40 §5 模型页 (`analyticsModel`), from the rank card's and the full ranking's model rows. The title is the model (“a → b” for a
/// mapping), the subtitle “模型 · 近 7 天”; no filter button, yet the session's group filter counts (a model filter does not). The
/// range bar, the head with the share of the whole (or the group), 壹 趋势, 贰 用量, 叁 速度 (gone while ops monitoring is off, the
/// users taking its number), 肆 用得最多的用户 and the way to its usage records. Every read carries the model, its source, the range
/// and the group; each block loads and fails on its own, and the page refreshes them through `analyticsPageRefresh`. Identifier
/// analytics.model.
struct AnalyticsModelView: View {
    let model: String
    let source: ModelSource

    var body: some View {
        let name = AnalyticsModelName(model, source: source)
        AnalyticsSessionScope(entry: .last7) { session in
            AnalyticsModelPage(name: name, session: session)
        }
        .navigationTitle(name.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AnalyticsModelPage: View {
    let name: AnalyticsModelName
    let session: AnalyticsSession
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var context
    @State private var sheet: AnalyticsSheet?
    @State private var loaders = AnalyticsCardLoaders()

    var body: some View {
        let options = self.options, outline = AnalyticsModelPresentation.Outline(showsSpeed: showsSpeed)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                AnalyticsRangeBar(session: session, sheet: $sheet)
                header
                trendSection(outline.trend)
                AnalyticsModelUsageSection(ordinal: outline.usage, rangeName: session.range.name, summary: summary)
                if let ordinal = outline.speed { speedSection(ordinal, options: options) }
                usersSection(outline.users, options: options)
            }
            .padding(EdgeInsets(top: 4, leading: 16, bottom: 24, trailing: 16))
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("analytics.model")
        .background(Palette.canvas)
        .navigationSubtitle(AnalyticsModelPresentation.subtitle(rangeName: session.range.name))
        .analyticsSheets(session, sheet: $sheet)
        // Ops monitoring turned back on reads the speed block, which shows again.
        .analyticsCardLoading("model.page", session: session, trigger: model.analyticsOpsDisabled) { [session, name, model, options] refresh in
            await AnalyticsModelLoads.loadAll(session, name: name, model: model, options: options, refresh: refresh)
        }
        .analyticsPageRefresh(session, loaders: loaders)
    }

    private var header: some View {
        let actual = summary?.value?.actualCost
        let denominator = session.state(session.modelPageDenominatorKey, as: AnalyticsSummary.self)?.value?.actualCost
        return AnalyticsModelHeader(name: name, summary: summary,
                                    shareLabel: AnalyticsModelPresentation.shareLabel(actual: actual, denominator: denominator,
                                                                                      groupName: session.modelPageGroupLabel),
                                    changeLine: changeLine, timeZone: zone, retry: retry { session, name, refresh in
                                        await AnalyticsModelLoads.loadSummary(session, name: name, refresh: refresh)
                                    })
    }

    private func trendSection(_ ordinal: String) -> some View {
        AnalyticsModelTrendSection(ordinal: ordinal, range: session.range, trend: state(.trend), summary: summary?.value, timeZone: zone,
                                   retry: retry { session, name, refresh in
                                       await AnalyticsModelLoads.loadTrend(session, name: name, refresh: refresh)
                                   })
    }

    private func speedSection(_ ordinal: String, options: AnalyticsModelLoads.Options) -> some View {
        AnalyticsModelSpeedSection(ordinal: ordinal, speed: state(.speed), isReadable: session.modelPageSpeedPlan(name) != .unavailable,
                                   localWindow: localWindow, rangeName: session.range.name, timeZone: zone,
                                   retry: retry { [model] session, name, refresh in
                                       await AnalyticsModelLoads.loadSpeed(session, name: name, model: model, options: options, refresh: refresh)
                                   })
    }

    private func usersSection(_ ordinal: String, options: AnalyticsModelLoads.Options) -> some View {
        AnalyticsModelUsersSection(ordinal: ordinal, users: state(.users),
                                   logsSubtitle: AnalyticsModelPresentation.logsSubtitle(hasGroup: session.modelPageGroupID != nil),
                                   logsRoute: .logs(session.modelPageLogsRoute(name)), timeZone: zone,
                                   retry: retry { session, name, refresh in
                                       await AnalyticsModelLoads.loadUsers(session, name: name, options: options, refresh: refresh)
                                   })
    }

    /// Hidden while the comparison is pending or either read last failed, as on 计费趋势 (40 §1.3).
    private var changeLine: String? {
        let window = state(.comparison, as: AnalyticsSummary.self)
        let comparison = AnalyticsBillingCard.Comparison(window?.state, lastReadFailed: window?.lastErrorAt != nil,
                                                         totalsLastReadFailed: summary?.lastErrorAt != nil)
        guard let current = summary?.value, case .loaded(let previous) = comparison else { return nil }
        return DisplayFormat.changeLine(DisplayFormat.ratioChange(current: current.actualCost, previous: previous.actualCost),
                                        label: session.range.comparison.label)
    }

    /// 40 §5.5: off by the App's ops verdict, or by the speed read's own 404 OPS_DISABLED.
    private var showsSpeed: Bool { !model.analyticsOpsDisabled && state(.speed, as: AnalyticsModelSpeed.self)?.value != .opsDisabled }
    /// The window a read would use, for the meta and the footnote before (or without) one.
    private var localWindow: OpsTokenStatsWindow {
        OpsTokenStatsWindow.select(start: session.range.start, end: session.range.end, now: session.now, zone: session.timeZone,
                                   supportsCustomRange: options.customRange)
    }
    private var options: AnalyticsModelLoads.Options {
        AnalyticsModelLoads.Options(customRange: context?.has(.opsTokenStatsCustomRange) == true,
                                    usersSort: context?.has(.dashboardUsersRankingSort) == true)
    }
    private var summary: LoadState<AnalyticsSummary>? { state(.summary) }
    private var zone: TimeZone { session.timeZone.timeZone }

    private func state<Value: Sendable>(_ part: AnalyticsModelPart, as type: Value.Type = Value.self) -> LoadState<Value>? {
        session.state(.modelPage(part, name), as: type)
    }
    /// 重试本项: that block's reads again.
    private func retry(_ load: @escaping @MainActor @Sendable (AnalyticsSession, AnalyticsModelName, Bool) async -> Void) -> @MainActor () -> Void {
        let session = session, name = name
        return { Task { await load(session, name, true) } }
    }
}

extension AnalyticsSession {
    /// The share's denominator: 统计分析's billing total, unless the session filters by a model (S4D2b-01).
    var modelPageDenominatorKey: AnalyticsCardKey { modelPageSharesBillingTotal ? .billingSummary : .modelPageDenominator }
}

// MARK: - 读取

/// The model page's reads (S4D2b-02 ①): they capture the session and values only, and check by themselves whether a block reads.
@MainActor enum AnalyticsModelLoads {
    /// The site's capabilities the reads depend on besides the session's own.
    struct Options: Hashable, Sendable {
        let customRange: Bool
        let usersSort: Bool
    }

    static func loadAll(_ session: AnalyticsSession, name: AnalyticsModelName, model: AppModel, options: Options, refresh: Bool) async {
        async let summary: Void = loadSummary(session, name: name, refresh: refresh)
        async let trend: Void = loadTrend(session, name: name, refresh: refresh)
        async let speed: Void = loadSpeed(session, name: name, model: model, options: options, refresh: refresh)
        async let users: Void = loadUsers(session, name: name, options: options, refresh: refresh)
        _ = await (summary, trend, speed, users)
    }

    /// The head: the model's totals, the comparison window and the share's denominator.
    static func loadSummary(_ session: AnalyticsSession, name: AnalyticsModelName, refresh: Bool) async {
        async let totals: Void = session.load(.modelPage(.summary, name), refresh: refresh,
                                              fixture: { try AnalyticsFixtures.modelSummary(name, session: $0) }) { client, session in
            try await client.usageAnalysis(session.modelPageQuery(name))
        }
        async let comparison: Void = session.load(.modelPage(.comparison, name), refresh: refresh,
                                                  fixture: { try AnalyticsFixtures.modelSummary(name, session: $0, comparison: true) }) { client, session in
            try await client.usageAnalysis(session.modelPageComparisonQuery(name))
        }
        async let denominator: Void = loadDenominator(session, refresh: refresh)
        _ = await (totals, comparison, denominator)
    }

    static func loadTrend(_ session: AnalyticsSession, name: AnalyticsModelName, refresh: Bool) async {
        await session.load(.modelPage(.trend, name), refresh: refresh, fixture: { try AnalyticsFixtures.modelTrend(name, session: $0) }) { client, session in
            try await client.usageAnalysisTrend(session.modelPageQuery(name))
        }
    }

    /// Nothing while ops monitoring is off, nor for a name no row can be (S4D2b-06, S4D2b-20). A 404 OPS_DISABLED is reported and
    /// hides the block until a later read (`loadModelPageSpeed`); another failure is the block's.
    static func loadSpeed(_ session: AnalyticsSession, name: AnalyticsModelName, model: AppModel, options: Options, refresh: Bool) async {
        guard !model.analyticsOpsDisabled else { return }
        let plan = session.modelPageSpeedPlan(name)
        guard let query = session.modelPageOpsQuery(plan), let topN = plan.topN else { return }
        let customRange = options.customRange
        await session.loadModelPageSpeed(name, refresh: refresh,
                                         fixture: { AnalyticsFixtures.modelSpeed(plan, session: $0, supportsCustomRange: customRange) }) { client, session in
            do {
                let stats = try await client.opsTokenStats(query, topN: topN, supportsCustomRange: customRange,
                                                           supportsModelFilter: session.supportsOpsModelFilter)
                await model.recordAnalyticsOpsResponse(nil)
                return AnalyticsModelSpeed(stats, plan: plan)
            } catch let error where AccountUpstreamErrors.isOpsDisabled(error) {
                await model.recordAnalyticsOpsResponse(error)
                return .opsDisabled
            }
        }
    }

    /// Three users by actual charge where the site sorts; a refused `sort_by` is asked once more without it (AnalyticsRankLoader).
    static func loadUsers(_ session: AnalyticsSession, name: AnalyticsModelName, options: Options, refresh: Bool) async {
        let sortBy = AnalyticsRanking.userSortParameter(.actualCost, supportsSort: options.usersSort)
        let limit = AnalyticsModelPresentation.usersShown
        await session.load(.modelPage(.users, name), refresh: refresh,
                           fixture: { try AnalyticsFixtures.modelUsers(name, session: $0, sortBy: sortBy) }) { client, session in
            try await AnalyticsRankLoader.users(session.modelPageQuery(name), sortBy: sortBy, limit: limit) { query, sort, count in
                try await client.usageAnalysisUsersRanking(query, sortBy: sort, limit: count)
            }
        }
    }

    /// 统计分析's billing total where it is the denominator, refreshed with the page; else the range and group without a model.
    private static func loadDenominator(_ session: AnalyticsSession, refresh: Bool) async {
        guard !session.modelPageSharesBillingTotal else { return await session.loadBillingSummary(refresh: refresh) }
        await session.load(.modelPageDenominator, refresh: refresh, fixture: { try await AnalyticsFixtures.modelDenominator($0) }) { client, session in
            try await client.usageAnalysis(session.modelPageScope())
        }
    }
}
