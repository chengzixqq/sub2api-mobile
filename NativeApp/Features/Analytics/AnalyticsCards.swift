import SwiftUI
import Sub2Core

// 40 §1.4 / §1.6 / §1.7 the analytics cards (S4-13, C-31): the shell and its parts, the reads of a card and of a page, then
// 计费趋势 and the 利润明细 slot S4-13b fills.

// MARK: - 卡片外壳

/// An analytics card: the title (a header) with its trailing accessory, then the content, on a rounded surface. Identifier `<id>`.
struct AnalyticsCard<Trailing: View, Content: View>: View {
    private let title: String
    private let id: String
    private let trailing: Trailing
    private let content: Content

    init(title: String, id: String, @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content) {
        self.title = title; self.id = id; self.trailing = trailing(); self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.headline).foregroundStyle(Palette.ink1).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                trailing
            }
            content
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 4, trailing: 16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(id)
    }
}

extension AnalyticsCard where Trailing == EmptyView {
    init(title: String, id: String, @ViewBuilder content: () -> Content) {
        self.init(title: title, id: id, trailing: { EmptyView() }, content: content)
    }
}

/// The card's way on, “全部 10 小时 · 计费明细 ›”: the whole row is the button (at least 44pt), read as one line. Identifier `<id>`.
struct AnalyticsCardFoot: View {
    private let title: String
    private let meta: String
    private let id: String
    private let action: @MainActor () -> Void

    init(title: String, meta: String, id: String, action: @escaping @MainActor () -> Void) {
        self.title = title; self.meta = meta; self.id = id; self.action = action
    }

    var body: some View {
        VStack(spacing: 0) {
            Palette.hairline.frame(height: 1).accessibilityHidden(true)
            Button(action: action) {
                HStack(spacing: 8) {
                    Image(systemName: "list.bullet").font(.subheadline).foregroundStyle(Palette.ink3).accessibilityHidden(true)
                    Text(title).foregroundStyle(Palette.ink1).monospacedDigit()
                    Spacer(minLength: 8)
                    Text(meta).foregroundStyle(Palette.ink3)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
                }
                .font(.subheadline)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(title) · \(meta)")
            .accessibilityAddTraits(.isButton)
            .accessibilityIdentifier(id)
        }
    }
}

/// 40 §1.6 首次加载: a spinner holding the card's height. Identifier `<id>.loading`, read as 正在加载.
struct AnalyticsCardPlaceholder: View {
    private let height: CGFloat
    private let id: String

    init(height: CGFloat, id: String) { self.height = height; self.id = id }

    var body: some View {
        ZStack { ProgressView() }
            .frame(maxWidth: .infinity, minHeight: height)
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(HomeInlineFigure.loadingValue)
            .accessibilityIdentifier("\(id).loading")
    }
}

/// 40 §1.6 a card's failure line. Without a value: 加载失败 / 统计较慢，加载超时 with 重试本项 (BlockFailureRow: the 429 countdown,
/// 完成合规确认 and 详情 come with it), or 请求参数无效 / 当前身份无权查看 alone; with a value whose last refresh failed: “更新失败 · 显示的是
/// 09:40 的数据” and 重试本项 (`<id>.stale`). Nothing while reading or after a success.
struct AnalyticsCardStatusRow<Value: Sendable>: View {
    private let load: LoadState<Value>?
    private let id: String
    private let timeZone: TimeZone
    private let resendsAfterWait: Bool
    private let retry: @MainActor () -> Void

    init(_ load: LoadState<Value>?, id: String, timeZone: TimeZone, resendsAfterWait: Bool = true, retry: @escaping @MainActor () -> Void) {
        self.load = load; self.id = id; self.timeZone = timeZone; self.resendsAfterWait = resendsAfterWait; self.retry = retry
    }

    var body: some View {
        if let load, load.error != nil {
            let failure = AnalyticsCardFailure(error: load.lastError)
            if load.value != nil {
                failureRow(load, title: AnalyticsCardText.staleLine(shownAt: load.updatedAt, timeZone: timeZone), id: "\(id).stale")
            } else if failure.allowsRetry {
                failureRow(load, title: failure.title, id: id)
            } else {
                refusal(load, title: failure.title)
            }
        }
    }

    private func failureRow(_ load: LoadState<Value>, title: String, id: String) -> some View {
        BlockFailureRow(title: title, error: load.lastError, occurredAt: load.lastErrorAt, refresh: load.refresh, id: id,
                        resendsAfterWait: resendsAfterWait, retryTitle: AnalyticsCardText.retry, retry: retry)
    }
    /// 400 and 403: no retry, only the details.
    private func refusal(_ load: LoadState<Value>, title: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline).foregroundStyle(Palette.ink2).frame(minHeight: 44, alignment: .leading)
            if let error = load.lastError, let details = ErrorDetails(error, occurredAt: load.lastErrorAt ?? Date()) {
                ErrorDetailsDisclosure(details: details)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(id).failure")
    }
}

/// A card's content over one read: the placeholder until its first answer (`minHeight`, close to the loaded height), then the
/// failure line, or the content with the stale line above it (`showsStaleLine` false where a big number already carries the
/// card's status row).
struct AnalyticsCardBody<Value: Sendable, Content: View>: View {
    private let load: LoadState<Value>?
    private let id: String
    private let minHeight: CGFloat
    private let timeZone: TimeZone
    private let resendsAfterWait: Bool
    private let showsStaleLine: Bool
    private let retry: @MainActor () -> Void
    private let content: (Value) -> Content

    init(_ load: LoadState<Value>?, id: String, minHeight: CGFloat, timeZone: TimeZone, resendsAfterWait: Bool = true,
         showsStaleLine: Bool = true, retry: @escaping @MainActor () -> Void, @ViewBuilder content: @escaping (Value) -> Content) {
        self.load = load; self.id = id; self.minHeight = minHeight; self.timeZone = timeZone; self.resendsAfterWait = resendsAfterWait
        self.showsStaleLine = showsStaleLine; self.retry = retry; self.content = content
    }

    var body: some View {
        if let load, let value = load.value {
            VStack(alignment: .leading, spacing: 8) {
                if showsStaleLine { statusRow(load) }
                content(value)
            }
        } else if let load, load.error != nil {
            statusRow(load)
        } else {
            AnalyticsCardPlaceholder(height: minHeight, id: id)
        }
    }

    private func statusRow(_ load: LoadState<Value>) -> some View {
        AnalyticsCardStatusRow(load, id: id, timeZone: timeZone, resendsAfterWait: resendsAfterWait, retry: retry)
    }
}

/// Equal cells of a small label over a figure (账号成本 / 标准 / 利润): billing figures are never coloured, a loss reads −$. Each cell
/// is one element, its value read with 无数据 for “—”. Identifiers `<id>.<figure.key>`.
struct AnalyticsFigureRow: View {
    private let figures: [AnalyticsFigure]
    private let id: String

    init(_ figures: [AnalyticsFigure], id: String) { self.figures = figures; self.id = id }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(figures) { figure in
                VStack(alignment: .leading, spacing: 3) {
                    Text(figure.label).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1)
                    Text(figure.value).font(.title3.weight(.medium)).monospacedDigit().foregroundStyle(Palette.ink1)
                        .lineLimit(1).minimumScaleFactor(0.5)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(figure.label)
                .spokenValue(figure.value)
                .accessibilityIdentifier("\(id).\(figure.key)")
            }
        }
    }
}

// MARK: - 读取与刷新

extension View {
    /// 40 §1.7 one card's (tile's, chart body's) read: when it first shows and whenever the session's range or filter or `trigger`
    /// changes, it registers `load` with the page's AnalyticsCardLoaders and reads (a value already in the session is not read again,
    /// so coming back from a pushed page reads nothing). Appearing and disappearing set its visibility for the 60-second tick. Without
    /// loaders in the environment it only reads.
    func analyticsCardLoading<Trigger: Hashable & Sendable>(_ id: String, session: AnalyticsSession, trigger: Trigger,
                                                           followsLiveTick: Bool = true, load: @escaping AnalyticsCardLoaders.Load) -> some View {
        modifier(AnalyticsCardLoading(id: id, key: AnalyticsCardLoadingKey(scope: session.scope, trigger: trigger),
                                      followsLiveTick: followsLiveTick, load: load))
    }
    func analyticsCardLoading(_ id: String, session: AnalyticsSession, followsLiveTick: Bool = true,
                              load: @escaping AnalyticsCardLoaders.Load) -> some View {
        analyticsCardLoading(id, session: session, trigger: 0, followsLiveTick: followsLiveTick, load: load)
    }

    /// One analytics page's refreshes over its cards (each of the five pages uses it once): pull to refresh reads every card again;
    /// back in the foreground a live range reads them again and a past one fills in what is missing (D18: a read the background
    /// cancelled); a range or filter change reads every card; while the page shows, the App is active and the range reaches now,
    /// every 60 seconds “now” moves on and the visible cards that follow it read again.
    func analyticsPageRefresh(_ session: AnalyticsSession, loaders: AnalyticsCardLoaders) -> some View {
        modifier(AnalyticsPageRefresh(session: session, loaders: loaders))
    }
}

private struct AnalyticsCardLoadingKey<Trigger: Hashable & Sendable>: Hashable, Sendable {
    let scope: AnalyticsScope
    let trigger: Trigger
}

private struct AnalyticsCardLoading<Key: Hashable & Sendable>: ViewModifier {
    @Environment(\.analyticsCardLoaders) private var loaders
    let id: String
    let key: Key
    let followsLiveTick: Bool
    let load: AnalyticsCardLoaders.Load

    func body(content: Content) -> some View {
        content
            .task(id: key) {
                loaders?.register(id, followsLiveTick: followsLiveTick, load: load)
                await load(false)
            }
            .onAppear { loaders?.setVisible(id, true) }
            .onDisappear { loaders?.setVisible(id, false) }
    }
}

private struct AnalyticsPageRefresh: ViewModifier {
    static let liveInterval: Duration = .seconds(60)

    let session: AnalyticsSession
    let loaders: AnalyticsCardLoaders
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false

    func body(content: Content) -> some View {
        let ticks = visible && scenePhase == .active && session.isLive
        content
            .environment(\.analyticsCardLoaders, loaders)
            .refreshable {
                session.advanceNow()
                await loaders.reloadAll(refresh: true)
            }
            .onChange(of: model.foregroundRevision) { _, _ in
                Task {
                    session.advanceNow()
                    await loaders.reloadAll(refresh: session.isLive)
                }
            }
            .onChange(of: session.scope) { _, _ in Task { await loaders.reloadAll(refresh: false) } }
            .onAppear { visible = true }
            .onDisappear { visible = false }
            .task(id: ticks) {
                guard ticks else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: Self.liveInterval) } catch { return }
                    session.advanceNow()
                    await loaders.tick()
                }
            }
    }
}

// MARK: - 计费趋势（40 §1.4）

/// 40 §1.4 计费趋势: the actual charge over the range (or the selected bar's), its change against the comparison window, the bars
/// with the standard as a dotted line, 账号成本 / 标准 / 利润, 请求 · Tokens · 平均耗时, and the way to 计费明细. The totals, the
/// comparison and the trend are read together; each shows its own state. Identifiers analytics.billing.*.
struct BillingTrendCard: View {
    let session: AnalyticsSession
    @Environment(AppRouter.self) private var router
    @State private var selection = AnalyticsChartSelection()

    /// Close to the loaded card's height, so the cards below barely move (S4D2b-16).
    static let placeholderHeight: CGFloat = 300
    static let chartHeight: CGFloat = 118

    var body: some View {
        let summary = session.state(.billingSummary, as: AnalyticsSummary.self)
        let trend = session.state(.billingTrend, as: DashboardTrendReply.self)
        let card = AnalyticsBillingCard(range: session.range, summary: summary?.value, comparison: comparison,
                                        points: trend?.value?.points ?? [], selected: selection.selected)
        AnalyticsCard(title: "计费趋势", id: "analytics.billing") {
            AnalyticsChartLegend()
        } content: {
            if summary?.value == nil, summary?.error == nil {
                AnalyticsCardPlaceholder(height: Self.placeholderHeight, id: "analytics.billing")
            } else {
                headline(card, summary: summary)
                AnalyticsCardBody(trend, id: "analytics.billing.trend", minHeight: Self.chartHeight, timeZone: zone, showsStaleLine: false,
                                  retry: retry) { _ in
                    AnalyticsBarChart(series: card.bars, selection: $selection, id: "analytics.billing.chart", chartTitle: "计费趋势",
                                      height: Self.chartHeight)
                }
                AnalyticsFigureRow(AnalyticsBillingCard.figures(summary?.value), id: "analytics.billing")
                usage(card)
                AnalyticsCardFoot(title: card.footTitle, meta: "计费明细", id: "analytics.billing.foot") { router.push(.analyticsChart(.billing)) }
            }
        }
        .analyticsCardLoading("billing", session: session) { [session] refresh in await BillingTrendCard.load(session, refresh: refresh) }
        .onChange(of: session.scope) { _, _ in selection = AnalyticsChartSelection() }
    }

    /// The three reads at once; 重试本项 reads them all again.
    static func load(_ session: AnalyticsSession, refresh: Bool) async {
        async let summary: Void = session.loadBillingSummary(refresh: refresh)
        async let comparison: Void = session.loadBillingComparison(refresh: refresh)
        async let trend: Void = session.loadBillingTrend(refresh: refresh)
        _ = await (summary, comparison, trend)
    }

    private var zone: TimeZone { session.timeZone.timeZone }
    /// LoadState keeps `lastErrorAt` until a read succeeds, through a retry and a cancelled one.
    private var comparison: AnalyticsBillingCard.Comparison {
        let state = session.state(.billingComparison, as: AnalyticsSummary.self)
        let totals = session.state(.billingSummary, as: AnalyticsSummary.self)
        return AnalyticsBillingCard.Comparison(state?.state, lastReadFailed: state?.lastErrorAt != nil,
                                               totalsLastReadFailed: totals?.lastErrorAt != nil)
    }
    private func retry() {
        let session = session
        Task { await BillingTrendCard.load(session, refresh: true) }
    }

    /// The big number with its label (one element), the status row under it, then the change or the selected bar's line.
    @ViewBuilder private func headline(_ card: AnalyticsBillingCard, summary: LoadState<AnalyticsSummary>?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(card.headline).font(.footnote).foregroundStyle(Palette.ink2).monospacedDigit().lineLimit(1)
            Text(card.amount).font(.largeTitle.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(card.headline)
        .spokenValue(card.amount)
        .accessibilityIdentifier("analytics.billing.amount")
        AnalyticsCardStatusRow(summary, id: "analytics.billing", timeZone: zone, retry: retry)
        if let line = card.selectionLine {
            Text(line).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2).accessibilityIdentifier("analytics.billing.selection")
        } else if let line = card.changeLine {
            Text(line).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2).accessibilityIdentifier("analytics.billing.change")
        }
    }

    private func usage(_ card: AnalyticsBillingCard) -> some View {
        HStack(spacing: 18) {
            HomeInlineFigure(label: "请求", value: card.requests, id: "analytics.billing.requests")
            HomeInlineFigure(label: "Tokens", value: card.tokens, id: "analytics.billing.tokens")
            HomeInlineFigure(label: "平均耗时", value: card.averageDuration, id: "analytics.billing.duration")
            Spacer(minLength: 0)
        }
    }
}

/// 40 §1.4 利润明细: S4-13b fills it in this file; AnalyticsView already has it at the profit anchor.
struct ProfitCard: View {
    let session: AnalyticsSession
    var body: some View { EmptyView() }
}
