import SwiftUI
import Sub2Core

/// 40 §1 统计分析 (`analytics`): the range bar, then the cards in their final order (计费趋势 → 利润明细 → 排行 → RPM / TPM → 更多图表,
/// X44). The page reads every card at once, and refreshes them through `analyticsPageRefresh`; the range and the filter are the
/// session's, shared with the pages it pushes. Coming from the overview's RPM / TPM cells it scrolls once to that card. Later items
/// fill their own slot files and leave this one alone. Identifier analytics.cards.
struct AnalyticsView: View {
    /// AppRoute.analytics's parameters, with its defaults.
    struct Route: Hashable, Sendable {
        var range: AnalyticsEntryRange
        var focus: AnalyticsFocus?
        var metric: PerfMetric?

        init(range: AnalyticsEntryRange = .today, focus: AnalyticsFocus? = nil, metric: PerfMetric? = nil) {
            self.range = range; self.focus = focus; self.metric = metric
        }
    }

    private let route: Route

    init(route: Route) { self.route = route }

    var body: some View {
        AnalyticsSessionScope(entry: route.range) { session in
            AnalyticsCardFlow(session: session, route: route)
        }
        .navigationTitle("统计分析")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The ScrollViewReader ids of the card slots; every slot has its anchor, filled or not.
enum AnalyticsCardAnchor: String, Hashable, CaseIterable, Sendable {
    case billing, profit, rank, perf, more
}

private struct AnalyticsCardFlow: View {
    let session: AnalyticsSession
    let route: AnalyticsView.Route
    @Environment(AppModel.self) private var model
    @State private var sheet: AnalyticsSheet?
    @State private var loaders = AnalyticsCardLoaders()
    @State private var scrolledToFocus = false

    /// The billing card settling first, then one layout pass, at most this long after appearing (S4D2b-16 ②).
    private static let focusWaitLimit: Duration = .milliseconds(1_500)
    private static let focusPoll: Duration = .milliseconds(100)
    private static let layoutPause: Duration = .milliseconds(300)

    var body: some View {
        TimelineView(.everyMinute) { _ in
            page.navigationSubtitle(subtitle)
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { AnalyticsFilterButton(session: session, sheet: $sheet) } }
        .analyticsSheets(session, sheet: $sheet)
        .analyticsPageRefresh(session, loaders: loaders)
    }

    private var page: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 12) {
                    AnalyticsRangeBar(session: session, sheet: $sheet)
                    slot(.billing) { BillingTrendCard(session: session) }
                    slot(.profit) { ProfitCard(session: session) }
                    slot(.rank) { AnalyticsRankCard() }
                    slot(.perf) { AnalyticsPerfCard(routeMetric: route.metric) }
                    slot(.more) { AnalyticsMoreCard() }
                }
                .padding(EdgeInsets(top: 4, leading: 16, bottom: 24, trailing: 16))
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("analytics.cards")
            .task { await scrollToFocus(proxy) }
        }
        .background(Palette.canvas)
    }

    private func slot<Card: View>(_ anchor: AnalyticsCardAnchor, @ViewBuilder _ card: () -> Card) -> some View {
        VStack(spacing: 0) { card() }.id(anchor)
    }

    /// “<站点名> · 刚刚更新”: the site's name alone until a card has loaded.
    private var subtitle: String {
        [model.activeProfile?.name, session.updateLine(now: Date())].compactMap { $0 }.joined(separator: " · ")
    }

    /// 40 §1.1: from the RPM / TPM cells, once, after the billing card has its first answer, so the cards above have their height.
    private func scrollToFocus(_ proxy: ScrollViewProxy) async {
        guard route.focus == .perf, !scrolledToFocus else { return }
        scrolledToFocus = true
        let deadline = ContinuousClock.now + Self.focusWaitLimit
        while !billingAnswered, ContinuousClock.now < deadline {
            do { try await Task.sleep(for: Self.focusPoll) } catch { return }
        }
        do { try await Task.sleep(for: Self.layoutPause) } catch { return }
        withAnimation { proxy.scrollTo(AnalyticsCardAnchor.perf, anchor: .top) }
    }
    private var billingAnswered: Bool {
        let summary = session.state(.billingSummary, as: AnalyticsSummary.self)
        let trend = session.state(.billingTrend, as: DashboardTrendReply.self)
        return [summary.map { $0.value != nil || $0.error != nil }, trend.map { $0.value != nil || $0.error != nil }].allSatisfy { $0 == true }
    }
}
