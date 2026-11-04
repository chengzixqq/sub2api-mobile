import SwiftUI
import Sub2Core

/// 40 §0.1 / §1.8: the analytics pages call the shared state their session; it lives in NativeApp/Session so it can be tested.
typealias AnalyticsSession = AnalyticsSessionState

extension EnvironmentValues {
    /// Set by AnalyticsSessionScope for the page and its cards.
    @Entry var analyticsSession: AnalyticsSession? = nil
    /// Set by `analyticsPageRefresh` (S4-13): the page's card reads, for pull to refresh, the foreground and the 60-second tick; a card
    /// outside such a page reads without registering.
    @Entry var analyticsCardLoaders: AnalyticsCardLoaders? = nil
}

extension AnalyticsSessionState {
    /// The connected site's session, with the App's memory and group directory.
    convenience init(model: AppModel, context: SessionContext, entry: AnalyticsEntryRange) {
        let client = context.client, generation = context.generation
        self.init(serverID: context.serverID, generation: generation, client: client, timeZone: context.site.serverTimeZone,
                  supportsModelSource: context.has(.usageModelSource), supportsOpsModelFilter: context.has(.opsDashboardModelFilter),
                  memory: model.analyticsMemory, entry: entry, groups: model.groupDirectory, isUITesting: model.isUITesting,
                  clock: { client.serverClock.now() }, isSessionCurrent: { [weak model] in model?.sessionGeneration == generation })
    }
}

/// The analytics stack's one session (S4D1-01): the first page to appear registers it for its tab, the pages it pushes find the
/// same one, and AppRouter drops it once the stack leaves analytics. `entry` is the route's range, used only before the site
/// remembers one (a page pushed on its own passes `.last7`, the search directory's default).
struct AnalyticsSessionScope<Content: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var context
    private let entry: AnalyticsEntryRange
    private let content: (AnalyticsSession) -> Content
    @State private var tab: MainTab?
    @State private var session: AnalyticsSession?

    init(entry: AnalyticsEntryRange, @ViewBuilder content: @escaping (AnalyticsSession) -> Content) {
        self.entry = entry; self.content = content
    }

    var body: some View {
        Group {
            if let session {
                content(session).environment(\.analyticsSession, session)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear(perform: register)
        .onChange(of: model.sessionGeneration) { _, _ in register() }
        .task(id: session.map { ObjectIdentifier($0) }) { await session?.prepare() }
    }

    private func register() {
        guard let context, let pageStates = model.pageStates else { return }
        if let session, !session.isStale(currentGeneration: context.generation) { return }
        let tab = self.tab ?? router.selectedTab
        self.tab = tab
        let model = model, entry = entry
        session = pageStates.state(PageStateKey.analyticsSession, tab: tab, prunedBy: router) {
            AnalyticsSession(model: model, context: context, entry: entry)
        }
    }
}

// MARK: - 计费数据（S4-13）

/// 40 §1.3: the three billing reads every analytics page shares (S4D2b-01). Their value types are fixed: a key read as another type
/// loses its value.
extension AnalyticsCardKey {
    /// AnalyticsSummary: `usage/stats` over the range and the filter.
    static let billingSummary = AnalyticsCardKey("billing.summary")
    /// AnalyticsSummary: `usage/stats` over the comparison window, with the same filter.
    static let billingComparison = AnalyticsCardKey("billing.comparison")
    /// DashboardTrendReply: `dashboard/trend` over the range and the filter.
    static let billingTrend = AnalyticsCardKey("billing.trend")
}

extension AnalyticsSession {
    func loadBillingSummary(refresh: Bool = false) async {
        await load(.billingSummary, refresh: refresh, fixture: { try await AnalyticsFixtures.billingSummary($0) }) { client, session in
            try await client.usageAnalysis(session.query())
        }
    }
    func loadBillingComparison(refresh: Bool = false) async {
        await load(.billingComparison, refresh: refresh, fixture: { try await AnalyticsFixtures.billingComparison($0) }) { client, session in
            try await client.usageAnalysis(session.comparisonQuery())
        }
    }
    func loadBillingTrend(refresh: Bool = false) async {
        await load(.billingTrend, refresh: refresh, fixture: { try await AnalyticsFixtures.billingTrend($0) }) { client, session in
            try await client.usageAnalysisTrend(session.query())
        }
    }
}

// MARK: - 运维开关（S4-13）

/// The analytics pages' only reading of whether ops monitoring is off, and their only report of an ops read (S4D2b-06); AppModel
/// compiles in the App target only, hence here.
extension AppModel {
    /// LiveOpsStore's verdict (the latest server signal, else the admin/me snapshot); admin/me's without the store.
    var analyticsOpsDisabled: Bool { liveOps?.opsDisabled ?? (siteSession?.me.features.opsMonitoringEnabled == false) }
    /// A new success passes nil, a new failure its error: LiveOpsStore records the signal (it reads only 404 OPS_DISABLED), and the
    /// report that turns ops off reads admin/me again once (40 §1.4, §2.5).
    func recordAnalyticsOpsResponse(_ error: (any Error)?) async {
        let wasDisabled = analyticsOpsDisabled
        await liveOps?.recordOpsResponse(error)
        guard !wasDisabled, analyticsOpsDisabled else { return }
        try? await reloadSiteSession()
    }
}

// MARK: - 运维图表读取（S4-18）

extension AnalyticsSession {
    /// 40 §2.2: the ops charts but RPM / TPM read the page range, its end not rounded.
    var opsRangeQuery: OpsQuery { opsQuery(start: range.start, end: range.end) }

    /// An ops chart's read (S4D2b-06): nothing goes out while ops monitoring is off (00 §0.3); a new answer is reported, a success
    /// as nil and a failure with its error, so a 404 OPS_DISABLED turns ops off (and reads admin/me again).
    func loadOps<Value: Sendable>(_ key: AnalyticsCardKey, refresh: Bool = false, model: AppModel,
                                  fixture: @escaping @MainActor @Sendable (AnalyticsSessionState) async throws -> Value,
                                  operation: @escaping @MainActor @Sendable (APIClient, AnalyticsSessionState) async throws -> Value) async {
        guard !model.analyticsOpsDisabled else { return }
        let before = state(key, as: Value.self)
        let succeededAt = before?.updatedAt, failedAt = before?.lastErrorAt
        await load(key, refresh: refresh, fixture: fixture, operation: operation)
        guard let after = state(key, as: Value.self) else { return }
        if after.lastErrorAt != failedAt, let error = after.lastError {
            await model.recordAnalyticsOpsResponse(error)
        } else if after.updatedAt != succeededAt, after.value != nil, after.lastErrorAt == nil {
            await model.recordAnalyticsOpsResponse(nil)
        }
    }
}
