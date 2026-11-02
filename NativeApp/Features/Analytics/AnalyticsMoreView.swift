import SwiftUI
import Sub2Core

/// 40 §2 更多图表 (`analyticsMore`): the title, “<站点名> · <范围名>” and the filter button; a bar pinned on top with the topics' capsules
/// (the one under its lower edge lit, the last one at the end; a tap scrolls to it) and the range Menu; the range caption and the
/// filter chip, then each topic's header and its chart cards. Cards read when they first show (LazyVStack); the page's loaders
/// read every loaded card again on a pull, a range or filter change and the foreground, and the visible ones every 60 seconds
/// while the range reaches now. `chart` lands on its card and draws its border once; `topic` on its header. With ops monitoring
/// off 运行 is one notice. The range and the filter are the session's (统计分析 keeps a change made here). Identifier
/// analytics.more.list.
struct AnalyticsMoreView: View {
    let chart: AnalyticsChartKey?
    let topic: AnalyticsTopic?

    var body: some View {
        AnalyticsSessionScope(entry: .last7) { session in
            AnalyticsMorePage(chart: chart, topic: topic, session: session)
        }
        .navigationTitle("更多图表")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AnalyticsMorePage: View {
    let chart: AnalyticsChartKey?
    let topic: AnalyticsTopic?
    let session: AnalyticsSession
    @Environment(AppModel.self) private var model
    @State private var sheet: AnalyticsSheet?
    @State private var loaders = AnalyticsCardLoaders()
    /// The rows on screen whose top has reached the bar's lower edge, and that edge in the window.
    @State private var passed: Set<AnalyticsMoreAnchor> = []
    @State private var barBottom: CGFloat = 0
    @State private var isAtBottom = false
    @State private var highlighted: AnalyticsChartKey?
    @State private var hasLanded = false

    /// After the first layout, then again once the cards above the target have grown from their estimate (S4D2b-16 ③).
    private static let landingPauses: [Duration] = [.milliseconds(50), .milliseconds(400)]
    /// A header this close under the bar already counts as the current topic (the design's spy).
    private static let barSlack: CGFloat = 40

    var body: some View {
        let opsEnabled = !model.analyticsOpsDisabled
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    caption
                    ForEach(AnalyticsTopic.allCases, id: \.self) { topic in
                        row(.topic(topic)) { AnalyticsMoreTopicHeader(topic: topic, opsEnabled: opsEnabled) }
                        if topic == .ops, !opsEnabled {
                            AnalyticsOpsOffCard()
                        } else {
                            ForEach(topic.charts, id: \.self) { chart in card(chart) }
                        }
                    }
                }
                .padding(EdgeInsets(top: 4, leading: 16, bottom: 24, trailing: 16))
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("analytics.more.list")
            .onScrollGeometryChange(for: Bool.self, of: { Self.isScrolledToBottom($0) }) { _, atBottom in isAtBottom = atBottom }
            .safeAreaInset(edge: .top, spacing: 0) {
                AnalyticsMoreTopicBar(session: session, active: AnalyticsChartCatalog.activeTopic(passed: passed, isAtBottom: isAtBottom),
                                      opsEnabled: opsEnabled, sheet: $sheet) { topic in
                    withAnimation { proxy.scrollTo(AnalyticsMoreAnchor.topic(topic), anchor: .top) }
                }
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { barBottom = $0 }
            }
            .task { await land(proxy, opsEnabled: opsEnabled) }
        }
        .background(Palette.canvas)
        .navigationSubtitle([model.activeProfile?.name, session.range.name].compactMap { $0 }.joined(separator: " · "))
        .toolbar { ToolbarItem(placement: .topBarTrailing) { AnalyticsFilterButton(session: session, sheet: $sheet) } }
        .analyticsSheets(session, sheet: $sheet)
        .analyticsPageRefresh(session, loaders: loaders)
    }

    /// 说明行 and the filter chip scroll with the list; only the capsules and the Menu stay on top.
    private var caption: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { AnalyticsRangeCaption(session: session, sheet: $sheet); AnalyticsFilterChip(session: session) }
            VStack(alignment: .leading, spacing: 4) { AnalyticsRangeCaption(session: session, sheet: $sheet); AnalyticsFilterChip(session: session) }
        }
    }

    private func card(_ chart: AnalyticsChartKey) -> some View {
        row(.chart(chart)) {
            AnalyticsMoreChartCard(chart: chart, session: session, isHighlighted: highlighted == chart) { highlighted = nil }
        }
    }

    /// A scroll target that reports whether its top has reached the bar while it shows (LazyVStack drops what scrolled away). The id
    /// stays outermost: ScrollViewReader finds a row not yet built by it.
    private func row<Content: View>(_ anchor: AnalyticsMoreAnchor, @ViewBuilder _ content: () -> Content) -> some View {
        let line = barBottom + Self.barSlack
        return content()
            .onGeometryChange(for: Bool.self) { $0.frame(in: .global).minY <= line } action: { isPast in
                if isPast { passed.insert(anchor) } else { passed.remove(anchor) }
            }
            .onDisappear { passed.remove(anchor) }
            .id(anchor)
    }

    /// Once per page: the route's chart (highlighted) or topic; none stays at the top.
    private func land(_ proxy: ScrollViewProxy, opsEnabled: Bool) async {
        guard !hasLanded else { return }
        hasLanded = true
        guard let anchor = AnalyticsChartCatalog.landing(chart: chart, topic: topic, opsEnabled: opsEnabled) else { return }
        if case .chart(let chart) = anchor { highlighted = chart }
        for pause in Self.landingPauses {
            do { try await Task.sleep(for: pause) } catch { return }
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    /// The end of a list taller than the screen, give or take a few points. `visibleRect` spans the bars' insets, `containerSize`
    /// does not (measured on iOS 26: 874 against 631 under the navigation bar, the pinned bar and the tab bar).
    nonisolated private static func isScrolledToBottom(_ geometry: ScrollGeometry) -> Bool {
        geometry.contentSize.height > geometry.containerSize.height
            && geometry.visibleRect.maxY >= geometry.contentSize.height + geometry.contentInsets.bottom - 4
    }
}

/// The pinned bar: 计费 2 · 用量 4 · 运行 6 (运行 — with ops off, still a way to its notice), the lit one read as selected, and the
/// range Menu on the right. Identifiers analytics.more.topicBar, analytics.more.topic.<topic>.
private struct AnalyticsMoreTopicBar: View {
    let session: AnalyticsSession
    let active: AnalyticsTopic
    let opsEnabled: Bool
    @Binding var sheet: AnalyticsSheet?
    let select: @MainActor (AnalyticsTopic) -> Void

    var body: some View {
        // Three capsules and the Menu fit one line; a horizontal scroll view this close under the navigation bar is hidden by its
        // edge effect.
        HStack(spacing: 8) {
            ForEach(AnalyticsTopic.allCases, id: \.self) { topic in chip(topic) }
            Spacer(minLength: 0)
            AnalyticsRangeMenu(session: session, sheet: $sheet).fixedSize()
        }
        .padding(.horizontal, 16)
        .background(Palette.canvas)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("analytics.more.topicBar")
    }

    private func chip(_ topic: AnalyticsTopic) -> some View {
        let isOn = topic == active
        return Button { select(topic) } label: {
            AnalyticsCapsuleLabel(isOn: isOn) { Text(AnalyticsChartCatalog.chipTitle(topic, opsEnabled: opsEnabled)).monospacedDigit() }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AnalyticsChartCatalog.chipSpokenLabel(topic, opsEnabled: opsEnabled))
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .accessibilityIdentifier("analytics.more.topic.\(topic.rawValue)")
    }
}

/// A topic's header; 运行 adds “需开启运维监控” while its charts show. Identifier analytics.more.topicHeader.<topic>.
private struct AnalyticsMoreTopicHeader: View {
    let topic: AnalyticsTopic
    let opsEnabled: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(topic.title).font(.title3.weight(.semibold)).foregroundStyle(Palette.ink1)
            if opsEnabled, let note = topic.note {
                Text(note).font(.caption).foregroundStyle(Palette.ink3)
            }
            Spacer(minLength: 0)
        }
        .padding(EdgeInsets(top: 12, leading: 4, bottom: 0, trailing: 4))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("analytics.more.topicHeader.\(topic.rawValue)")
    }
}

/// A chart's card: its name and window over its body (Token 请求统计 its own window). Landed on, its border is drawn once for
/// `highlightDuration` from when it shows, and it reads 已定位 meanwhile. Identifier analytics.more.chart.<chart>.
private struct AnalyticsMoreChartCard: View {
    let chart: AnalyticsChartKey
    let session: AnalyticsSession
    let isHighlighted: Bool
    let endHighlight: @MainActor () -> Void
    @Environment(\.sessionContext) private var context

    static let highlightDuration: Duration = .seconds(2)

    var body: some View {
        AnalyticsCard(title: chart.title, id: "analytics.more.chart.\(chart.rawValue)") {
            Text(AnalyticsChartCatalog.windowLabel(of: chart, rangeName: session.range.name, tokenStatsWindow: tokenStatsWindow))
                .font(.caption).monospacedDigit().foregroundStyle(Palette.ink3).lineLimit(1)
        } content: {
            chartBody.padding(.bottom, 12)
        }
        .background {
            if isHighlighted { RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Palette.accentWash).padding(-4) }
        }
        .overlay {
            if isHighlighted { RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.accent, lineWidth: 2) }
        }
        .animation(.easeOut(duration: 0.3), value: isHighlighted)
        .accessibilityValue(isHighlighted ? "已定位" : "")
        .task(id: isHighlighted) {
            guard isHighlighted else { return }
            do { try await Task.sleep(for: Self.highlightDuration) } catch { return }
            endHighlight()
        }
    }

    private var tokenStatsWindow: String? {
        guard chart == .tokenSpeed else { return nil }
        return OpsTokenStatsBody.windowTitle(session, supportsCustomRange: context?.has(.opsTokenStatsCustomRange) ?? false)
    }

    @ViewBuilder private var chartBody: some View {
        switch chart {
        case .billing: AnalyticsBillingBody(size: .card)
        case .profit: AnalyticsProfitBody(size: .card)
        case .tokens: TokenTrendBody(size: .card)
        case .userTrend: UserTrendBody(size: .card)
        case .endpoints: EndpointShareBody(size: .card)
        case .reqType: RequestTypeBody(size: .card)
        case .perf: OpsPerfBody(size: .card)
        case .accountSwitch: OpsSwitchBody(size: .card)
        case .latency: OpsLatencyBody(size: .card)
        case .errTrend: OpsErrorTrendBody(size: .card)
        case .errDist: OpsErrorDistributionBody(size: .card)
        case .tokenSpeed: OpsTokenStatsBody(size: .card)
        }
    }
}

/// 40 §2.5 运行 while ops monitoring is off (admin/me, or a 404 OPS_DISABLED an ops chart reported): one card with OpsDisabledNotice.
/// Identifier analytics.more.ops.off.
struct AnalyticsOpsOffCard: View {
    var body: some View {
        VStack(spacing: 0) { OpsDisabledNotice(style: .emptyState) }
            .padding(16)
            .frame(maxWidth: .infinity)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("analytics.more.ops.off")
    }
}
