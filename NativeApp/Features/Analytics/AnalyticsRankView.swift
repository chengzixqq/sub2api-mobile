import SwiftUI
import Sub2Core

/// 40 §4 全部排行 (`analyticsRank`): 模型分布 / 用户排行 / 分组使用分布 over the session's range and filter. The range bar, the
/// composition strip, the list header with its sort (and, for models, source) menu, every row, and the users' footnote; a dimension
/// that is the filter's shows only “已筛选…清除筛选”. Models and groups sort here; another source reads `dashboard/models` again,
/// another user sort `users-ranking` where the site sorts (else the fifty are re-sorted here). The sort and the source are
/// remembered (40 §4.4). Identifiers analytics.rank.*.
struct AnalyticsRankView: View {
    let dimension: AnalyticsRankDimension
    @Environment(AppModel.self) private var model

    var body: some View {
        AnalyticsSessionScope(entry: .last7) { session in
            AnalyticsRankPage(dimension: dimension, session: session,
                              choice: .remembered(model.analyticsMemory, dimension: dimension, serverID: session.serverID))
        }
        .navigationTitle(dimension.pageTitle)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AnalyticsRankPage: View {
    let dimension: AnalyticsRankDimension
    let session: AnalyticsSession
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var context
    @State private var choice: AnalyticsRankChoice
    @State private var sheet: AnalyticsSheet?
    @State private var loaders = AnalyticsCardLoaders()

    private static let loadingHeight: CGFloat = 240

    init(dimension: AnalyticsRankDimension, session: AnalyticsSession, choice: AnalyticsRankChoice) {
        self.dimension = dimension; self.session = session
        _choice = State(initialValue: choice)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                AnalyticsRangeBar(session: session, sheet: $sheet)
                content
            }
            .padding(EdgeInsets(top: 4, leading: 16, bottom: 24, trailing: 16))
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("analytics.rank.list")
        .background(Palette.canvas)
        .navigationSubtitle(subtitle)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { AnalyticsFilterButton(session: session, sheet: $sheet) } }
        .analyticsSheets(session, sheet: $sheet)
        .analyticsCardLoading("rank.page", session: session, trigger: choice) { [session, dimension, choice, supportsSort] refresh in
            guard !dimension.isNarrowed(by: session.filter) else { return }
            await AnalyticsRankRequests.loadPage(session, dimension: dimension, choice: choice, supportsSort: supportsSort, refresh: refresh)
        }
        .analyticsPageRefresh(session, loaders: loaders)
    }

    @ViewBuilder private var content: some View {
        if let filter = session.filter, dimension.isNarrowed(by: filter) {
            RankNarrowedRow(kind: filter.kind, name: session.filterName ?? "", id: "analytics.rank.narrowed") { session.setFilter(nil) }
                .padding(.horizontal, 16)
                .rankSurface()
        } else {
            switch dimension {
            case .model: modelRanking
            case .user: userRanking
            case .group: groupRanking
            }
        }
    }

    private var modelRanking: some View {
        let source = choice.source, metric = choice.metric
        return ranking(session.state(.rankModels(source), as: [AnalyticsBreakdown].self)) { rows in
            let list = AnalyticsRanking.models(rows, source: source, metric: metric)
            return RankPageContent(list: list, header: AnalyticsRanking.listHeader(.model, rows: list.items.count, source: source, totalUsers: nil))
        }
    }
    private var groupRanking: some View {
        let metric = choice.metric, groups = session.groups
        return ranking(session.state(.rankGroups, as: [AnalyticsBreakdown].self)) { rows in
            let list = AnalyticsRanking.groups(rows, metric: metric) { groups?.name(for: $0) }
            return RankPageContent(list: list, header: AnalyticsRanking.listHeader(.group, rows: list.items.count, source: .requested, totalUsers: nil))
        }
    }
    private var userRanking: some View {
        let metric = choice.metric, keyGroup = keyGroupName
        let key = AnalyticsCardKey.rankUsers(sortBy: AnalyticsRanking.userSortParameter(metric, supportsSort: supportsSort))
        return ranking(session.state(key, as: AnalyticsUserRanking.self)) { ranking in
            let list = AnalyticsRanking.users(ranking, metric: metric)
            return RankPageContent(list: list,
                                   header: AnalyticsRanking.listHeader(.user, rows: list.items.count, source: .requested,
                                                                       totalUsers: ranking.ranking.totalUsers),
                                   footnote: AnalyticsRanking.userFootnote(metric: metric, ranking: ranking, keyGroup: keyGroup))
        }
    }

    /// 40 §4.5: the whole page loads, then fails with “加载失败 · 重试”; a failed refresh keeps the rows and says so in the header.
    @ViewBuilder private func ranking<Value: Sendable>(_ load: LoadState<Value>?, shown: (Value) -> RankPageContent) -> some View {
        if let load, let value = load.value {
            let content = shown(value)
            if let strip = content.list.strip { RankCompositionStrip(strip: strip).rankSurface() }
            list(content, load: load)
            if let footnote = content.footnote {
                Text(footnote).font(.footnote).foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("analytics.rank.footnote")
            }
        } else if let load, load.error != nil {
            BlockFailureRow(load, id: "analytics.rank", retry: retry).padding(.horizontal, 16).rankSurface()
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: Self.loadingHeight)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(HomeInlineFigure.loadingValue)
                .accessibilityIdentifier("analytics.rank.loading")
        }
    }

    private func list<Value: Sendable>(_ content: RankPageContent, load: LoadState<Value>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(content.header).font(.footnote.weight(.medium)).monospacedDigit().foregroundStyle(Palette.ink2)
                    .accessibilityIdentifier("analytics.rank.header")
                Spacer(minLength: 8)
                BlockStatusAccessory(load, id: "analytics.rank", retry: retry)
                RankSortMenu(dimension: dimension, choice: choice, choose: choose)
            }
            .padding(.leading, 16).padding(.trailing, 8)
            if content.list.items.isEmpty {
                Palette.hairline.frame(height: 1).accessibilityHidden(true)
                Text(dimension.emptyText).font(.subheadline).foregroundStyle(Palette.ink2)
                    .frame(maxWidth: .infinity, minHeight: RankCard.emptyHeight)
                    .accessibilityIdentifier("analytics.rank.empty")
            } else {
                ForEach(Array(content.list.items.enumerated()), id: \.element.id) { index, item in
                    Palette.hairline.frame(height: 1).padding(.leading, 16).accessibilityHidden(true)
                    RankRow(item, rank: index + 1, style: .full, id: "analytics.rank.row.\(index + 1)").padding(.horizontal, 16)
                }
            }
        }
        .rankSurface()
    }

    /// Another sort or source is remembered for this dimension (40 §4.4).
    private func choose(_ next: AnalyticsRankChoice) {
        guard next != choice else { return }
        let memory = model.analyticsMemory
        if next.metric != choice.metric { memory.setRankSort(next.metric, for: dimension, serverID: session.serverID) }
        if next.source != choice.source { memory.setRankModelSource(next.source, serverID: session.serverID) }
        choice = next
    }
    private func retry() {
        let session = session, dimension = dimension, choice = choice, supportsSort = supportsSort
        Task { await AnalyticsRankRequests.loadPage(session, dimension: dimension, choice: choice, supportsSort: supportsSort, refresh: true) }
    }
    private var supportsSort: Bool { context?.has(.dashboardUsersRankingSort) == true }
    private var keyGroupName: String? { session.filter?.kind == .group ? session.filterName : nil }
    /// “<站点名> · <范围名>”.
    private var subtitle: String { [model.activeProfile?.name, session.range.name].compactMap { $0 }.joined(separator: " · ") }
}

private struct RankPageContent {
    let list: AnalyticsRankList
    let header: String
    var footnote: String?
}

private extension View {
    func rankSurface() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - 构成条与排序菜单

/// 40 §4.3 构成条: “前 3 占 62.4%” and “合计 …” over a 12pt bar of the first three and the rest, then their legend in two
/// columns. Read as one element. Identifier analytics.rank.strip.
private struct RankCompositionStrip: View {
    let strip: AnalyticsRankStrip

    private static let gap: CGFloat = 2
    /// A rest this small is not drawn.
    private static let minimumRest = 0.002
    private static let restSwatch = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(strip.caption)
                Spacer(minLength: 8)
                Text(strip.total)
            }
            .font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
            bar
            legend
        }
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("analytics.rank.strip")
    }

    private var segments: [(swatch: Int, share: Double)] {
        let parts = strip.parts.enumerated().map { (swatch: $0.offset, share: $0.element.share) }
        return strip.rest > Self.minimumRest ? parts + [(swatch: Self.restSwatch, share: strip.rest)] : parts
    }

    private var bar: some View {
        GeometryReader { proxy in
            let shown = segments
            let width = max(0, proxy.size.width - CGFloat(max(0, shown.count - 1)) * Self.gap)
            HStack(spacing: Self.gap) {
                ForEach(shown.indices, id: \.self) { index in
                    RankStripSwatch(kind: shown[index].swatch).frame(width: width * shown[index].share)
                }
            }
        }
        .frame(height: 12)
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private var legend: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 14, alignment: .leading), GridItem(.flexible(), alignment: .leading)],
                  alignment: .leading, spacing: 6) {
            ForEach(strip.parts.indices, id: \.self) { index in
                legendItem(swatch: index, text: strip.parts[index].name, isMonospaced: strip.parts[index].isMonospaced)
            }
            if let rest = strip.restLegend { legendItem(swatch: Self.restSwatch, text: rest, isMonospaced: false) }
        }
    }

    private func legendItem(swatch: Int, text: String, isMonospaced: Bool) -> some View {
        HStack(spacing: 6) {
            RankStripSwatch(kind: swatch).frame(width: 10, height: 10).clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
            Text(text).font(isMonospaced ? .caption.monospaced() : .caption).foregroundStyle(Palette.ink2).lineLimit(1).truncationMode(.middle)
        }
    }

    private var spoken: String {
        ([strip.caption, strip.total] + strip.parts.map { "\($0.name) \(DisplayFormat.ratioPercent($0.share))" } + [strip.restLegend].compactMap { $0 })
            .joined(separator: "，")
    }
}

/// The strip's fills (v-analytics.css ax-k1…ax-k4): ink, the chart grey, ink stripes, then the rest as an outlined surface.
private struct RankStripSwatch: View {
    let kind: Int

    var body: some View {
        switch kind {
        case 0: Rectangle().fill(Palette.ink1)
        case 1: Rectangle().fill(Palette.chartBar)
        case 2: RankStripes().overlay { Rectangle().strokeBorder(Palette.ink2, lineWidth: 1) }
        default: Rectangle().fill(Palette.surface).overlay { Rectangle().strokeBorder(Palette.ink2, lineWidth: 1.5) }
        }
    }
}

private struct RankStripes: View {
    private static let pitch: CGFloat = 3
    private static let line: CGFloat = 1.4

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Palette.surface))
            for y in stride(from: 0, to: size.height, by: Self.pitch) {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: Self.line)), with: .color(Palette.ink2))
            }
        }
    }
}

/// 40 §4.3 the list header's Menu: 排序 按实际扣费 / 按请求 / 按 Tokens, and for models 模型口径 请求模型 / 上游模型 / 映射.
/// Identifier analytics.rank.sort, its value the current choice.
private struct RankSortMenu: View {
    let dimension: AnalyticsRankDimension
    let choice: AnalyticsRankChoice
    let choose: @MainActor (AnalyticsRankChoice) -> Void

    var body: some View {
        Menu {
            Section("排序") {
                ForEach(AnalyticsRankMetric.allCases, id: \.self) { metric in
                    Toggle(metric.sortTitle, isOn: picked(choice.metric == metric, AnalyticsRankChoice(metric: metric, source: choice.source)))
                }
            }
            if dimension == .model {
                Section("模型口径") {
                    ForEach(ModelSource.allCases, id: \.self) { source in
                        Toggle(source.rankSourceTitle, isOn: picked(choice.source == source, AnalyticsRankChoice(metric: choice.metric, source: source)))
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(choice.metric.sortTitle)
                Image(systemName: "chevron.down").font(.caption2.weight(.semibold))
            }
            .font(.footnote.weight(.medium))
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("排序与口径")
        .accessibilityValue(dimension == .model ? "\(choice.metric.sortTitle)，\(choice.source.rankSourceTitle)" : choice.metric.sortTitle)
        .accessibilityIdentifier("analytics.rank.sort")
    }

    private func picked(_ isOn: Bool, _ next: AnalyticsRankChoice) -> Binding<Bool> {
        let choose = choose
        return Binding(get: { isOn }, set: { if $0 { choose(next) } })
    }
}
