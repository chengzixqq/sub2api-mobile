import SwiftUI
import Sub2Core

/// 40 §1.4 排行卡's slot in the card flow (X44): the session comes from `\.analyticsSession`, the segment from the App's memory.
struct AnalyticsRankCard: View {
    @Environment(\.analyticsSession) private var session
    @Environment(AppModel.self) private var model

    var body: some View {
        if let session {
            RankCard(session: session, dimension: model.analyticsMemory.rankCardDimension(serverID: session.serverID))
        }
    }
}

/// 40 §1.4 排行: 模型 · 用户 · 分组 (remembered on this phone), the first five by actual cost with their shares, and the way to the
/// full ranking. It reads only the segment it shows (40 §1.3), and nothing while that segment is the filter's own dimension.
/// Identifiers analytics.rankCard.*.
struct RankCard: View {
    let session: AnalyticsSession
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var context
    @State private var dimension: AnalyticsRankDimension

    /// Close to the loaded card's height (S4D2b-16).
    static let placeholderHeight: CGFloat = 260
    static let emptyHeight: CGFloat = 88

    init(session: AnalyticsSession, dimension: AnalyticsRankDimension) {
        self.session = session
        _dimension = State(initialValue: dimension)
    }

    var body: some View {
        AnalyticsCard(title: AnalyticsRanking.cardTitle, id: "analytics.rankCard") {
            Text(AnalyticsRanking.cardTrailing).font(.caption).foregroundStyle(Palette.ink3).lineLimit(1)
        } content: {
            segments
            if dimension == .user, let group = keyGroupName {
                Text(AnalyticsRanking.keyGroupNote(group)).font(.footnote).foregroundStyle(Palette.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("analytics.rankCard.keyGroupNote")
            }
            if let filter = session.filter, dimension.isNarrowed(by: filter) {
                RankNarrowedRow(kind: filter.kind, name: session.filterName ?? "", id: "analytics.rankCard.narrowed") { session.setFilter(nil) }
                    .padding(.bottom, 8)
            } else {
                ranking
            }
        }
        .analyticsCardLoading("rank", session: session, trigger: dimension) { [session, dimension, supportsSort] refresh in
            await AnalyticsRankCardPlan.read(session, showing: dimension, refresh: refresh) {
                await AnalyticsRankRequests.load(session, dimension: dimension, supportsSort: supportsSort, refresh: refresh)
            }
        }
    }

    private var segments: some View {
        Picker("排行维度", selection: Binding(get: { dimension }, set: choose)) {
            ForEach(AnalyticsRankDimension.allCases, id: \.self) { item in
                Text(item.segmentTitle).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("analytics.rankCard.segment")
    }

    @ViewBuilder private var ranking: some View {
        switch dimension {
        case .model:
            segmentBody(session.state(.rankModels(.requested), as: [AnalyticsBreakdown].self)) { rows in
                let list = AnalyticsRanking.models(rows, source: .requested, metric: .actualCost)
                return RankCardContent(list: list, footer: AnalyticsRanking.cardFooter(.model, rows: list.items.count, totalUsers: nil))
            }
        case .user:
            segmentBody(session.state(.rankCardUsers, as: AnalyticsUserRanking.self)) { ranking in
                let list = AnalyticsRanking.users(ranking, metric: .actualCost)
                return RankCardContent(list: list, footer: AnalyticsRanking.cardFooter(.user, rows: list.items.count,
                                                                                       totalUsers: ranking.ranking.totalUsers))
            }
        case .group:
            segmentBody(session.state(.rankGroups, as: [AnalyticsBreakdown].self)) { [groups = session.groups] rows in
                let list = AnalyticsRanking.groups(rows, metric: .actualCost) { groups?.name(for: $0) }
                return RankCardContent(list: list, footer: AnalyticsRanking.cardFooter(.group, rows: list.items.count, totalUsers: nil))
            }
        }
    }

    private func segmentBody<Value: Sendable>(_ load: LoadState<Value>?, shown: @escaping (Value) -> RankCardContent) -> some View {
        AnalyticsCardBody(load, id: "analytics.rankCard", minHeight: Self.placeholderHeight, timeZone: session.timeZone.timeZone,
                          retry: retry) { value in
            rows(shown(value))
        }
    }

    @ViewBuilder private func rows(_ content: RankCardContent) -> some View {
        if content.list.items.isEmpty {
            Text(dimension.emptyText).font(.subheadline).foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, minHeight: Self.emptyHeight)
                .accessibilityIdentifier("analytics.rankCard.empty")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(content.list.items.prefix(AnalyticsRanking.cardRows).enumerated()), id: \.element.id) { index, item in
                    RankRow(item, rank: index + 1, style: .line, id: "analytics.rankCard.row.\(index + 1)")
                }
            }
        }
        if let footer = content.footer {
            AnalyticsCardFoot(title: footer.title, meta: footer.meta ?? "", id: "analytics.rankCard.foot") {
                router.push(.analyticsRank(dimension))
            }
        } else {
            Color.clear.frame(height: 8).accessibilityHidden(true)
        }
    }

    /// A different segment is shown and remembered; it reads when it has no value yet.
    private func choose(_ next: AnalyticsRankDimension) {
        guard next != dimension else { return }
        dimension = next
        model.analyticsMemory.setRankCardDimension(next, serverID: session.serverID)
    }
    private func retry() {
        let session = session, dimension = dimension, supportsSort = supportsSort
        Task { await AnalyticsRankRequests.load(session, dimension: dimension, supportsSort: supportsSort, refresh: true) }
    }
    private var supportsSort: Bool { context?.has(.dashboardUsersRankingSort) == true }
    /// users-ranking under a group filter counts the requests made with that group's keys.
    private var keyGroupName: String? { session.filter?.kind == .group ? session.filterName : nil }
}

private struct RankCardContent {
    let list: AnalyticsRankList
    let footer: AnalyticsRankFooter?
}

// MARK: - 排行行（S4-19 复用）

/// 40 §1.4 / §4.3 one rank row: 名次 (1–3 bold), the name (models monospaced, cut in the middle), the share bar and the value;
/// `.full` puts the value beside the name and adds the percent and the detail line. A row with a route pushes it (X39) and shows a
/// chevron in `.full`; the others look the same and do nothing. Read as one element: “第 1 名，claude-opus-4”, then the value, the
/// share and, in `.full`, the detail. S4-19's model page reuses `.full`.
struct RankRow: View {
    enum Style: Sendable { case line, full }

    private let item: AnalyticsRankItem
    private let rank: Int
    private let style: Style
    private let id: String

    /// The card's share bar.
    private static let lineTrackWidth: CGFloat = 48
    /// The card's amounts up to $999.99, so the bars line up.
    private static let lineValueWidth: CGFloat = 64

    init(_ item: AnalyticsRankItem, rank: Int, style: Style, id: String) {
        self.item = item; self.rank = rank; self.style = style; self.id = id
    }

    var body: some View {
        if let route = item.route {
            NavigationLink(value: route) { content(tappable: true) }
                .buttonStyle(.plain)
                .accessibilityLabel(spokenLabel)
                .accessibilityValue(spokenValue)
                .accessibilityIdentifier(id)
        } else {
            content(tappable: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenLabel)
                .accessibilityValue(spokenValue)
                .accessibilityIdentifier(id)
        }
    }

    @ViewBuilder private func content(tappable: Bool) -> some View {
        switch style {
        case .line: line
        case .full: full(chevron: tappable)
        }
    }

    private var line: some View {
        HStack(spacing: 10) {
            number
            name.frame(maxWidth: .infinity, alignment: .leading)
            RankShareTrack(share: item.share).frame(width: Self.lineTrackWidth)
            Text(item.value).font(.subheadline.weight(.medium)).monospacedDigit().foregroundStyle(Palette.ink1).lineLimit(1)
                .fixedSize().frame(minWidth: Self.lineValueWidth, alignment: .trailing)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func full(chevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            number
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    name
                    Spacer(minLength: 8)
                    Text(item.value).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1).lineLimit(1)
                        .fixedSize()
                }
                HStack(spacing: 8) {
                    RankShareTrack(share: item.share)
                    Text(item.shareText).font(.caption).monospacedDigit().foregroundStyle(Palette.ink2).frame(minWidth: 44, alignment: .trailing)
                }
                if let detail = item.detail {
                    Text(detail).font(.caption).monospacedDigit().foregroundStyle(Palette.ink3).fixedSize(horizontal: false, vertical: true)
                }
            }
            if chevron {
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink3).padding(.top, 3)
            }
        }
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private var number: some View {
        Text("\(rank)").font(.callout.weight(rank <= 3 ? .bold : .regular)).monospacedDigit()
            .foregroundStyle(rank <= 3 ? Palette.ink1 : Palette.ink3)
            .frame(minWidth: 22)
    }
    private var name: some View {
        Text(item.name).font(item.isMonospaced ? .subheadline.monospaced() : .subheadline).foregroundStyle(Palette.ink1)
            .lineLimit(1).truncationMode(.middle)
    }

    private var spokenLabel: String { "第 \(rank) 名，\(item.name)" }
    private var spokenValue: String {
        let shown = [DisplayFormat.spoken(item.value), "占 \(item.shareText)"]
        return (style == .full ? shown + [item.detail].compactMap { $0 } : shown).joined(separator: "，")
    }
}

/// The 4pt share bar: the sunken track and the share in ink2, a sliver at least so a small share still shows.
struct RankShareTrack: View {
    let share: Double
    private static let minimumFill = 0.006

    var body: some View {
        Capsule().fill(Palette.sunken)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule().fill(Palette.ink2).frame(width: proxy.size.width * max(Self.minimumFill, min(1, share)))
                }
            }
            .frame(height: 4)
            .accessibilityHidden(true)
    }
}

/// 40 §1.4 / §4.3 in place of a ranking of the filter's own dimension: “已筛选分组：高级组　清除筛选” (a model name monospaced).
/// Identifiers `<id>` (the text) and `<id>.clear`.
struct RankNarrowedRow: View {
    let kind: AnalyticsFilter.Kind
    let name: String
    let id: String
    let clear: @MainActor () -> Void

    var body: some View {
        let shownName = Text(name).font(kind == .model ? .subheadline.monospaced() : .subheadline).fontWeight(.semibold)
            .foregroundStyle(Palette.ink1)
        HStack(spacing: 10) {
            Text("已筛选\(kind.title)：\(shownName)")
                .font(.subheadline).foregroundStyle(Palette.ink2).lineLimit(1).truncationMode(.middle)
                .accessibilityLabel(AnalyticsRanking.narrowedText(kind, name: name))
                .accessibilityIdentifier(id)
            Spacer(minLength: 8)
            Button("清除筛选", action: clear)
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("\(id).clear")
        }
        .frame(minHeight: 52)
    }
}

// MARK: - 读取

/// The rank reads the card and the full ranking share (40 §1.3, §4.2), one way in per key.
@MainActor enum AnalyticsRankRequests {
    /// The card's segment: the requested models, five users (by actual cost where the site sorts), the groups.
    static func load(_ session: AnalyticsSession, dimension: AnalyticsRankDimension, supportsSort: Bool, refresh: Bool) async {
        switch dimension {
        case .model:
            await loadModels(session, source: .requested, refresh: refresh)
        case .user:
            let sortBy = AnalyticsRanking.userSortParameter(.actualCost, supportsSort: supportsSort)
            await loadUsers(session, key: .rankCardUsers, sortBy: sortBy, limit: AnalyticsRanking.cardRows, refresh: refresh)
        case .group:
            await loadGroups(session, refresh: refresh)
        }
    }
    /// The full ranking: the models by the chosen source, fifty users by the chosen sort where the site sorts (else one list the
    /// page re-sorts), the groups.
    static func loadPage(_ session: AnalyticsSession, dimension: AnalyticsRankDimension, choice: AnalyticsRankChoice, supportsSort: Bool,
                         refresh: Bool) async {
        switch dimension {
        case .model:
            await loadModels(session, source: choice.source, refresh: refresh)
        case .user:
            let sortBy = AnalyticsRanking.userSortParameter(choice.metric, supportsSort: supportsSort)
            await loadUsers(session, key: .rankUsers(sortBy: sortBy), sortBy: sortBy, limit: AnalyticsRanking.pageUsers, refresh: refresh)
        case .group:
            await loadGroups(session, refresh: refresh)
        }
    }

    static func loadModels(_ session: AnalyticsSession, source: ModelSource, refresh: Bool) async {
        await session.load(.rankModels(source), refresh: refresh,
                           fixture: { try AnalyticsFixtures.rankModels($0, source: source) }) { client, session in
            try await client.usageAnalysisModels(session.query(), source: source)
        }
    }
    static func loadGroups(_ session: AnalyticsSession, refresh: Bool) async {
        await session.load(.rankGroups, refresh: refresh, fixture: { try AnalyticsFixtures.rankGroups($0) }) { client, session in
            try await client.usageAnalysisGroups(session.query())
        }
    }
    static func loadUsers(_ session: AnalyticsSession, key: AnalyticsCardKey, sortBy: AnalyticsRankMetric?, limit: Int, refresh: Bool) async {
        await session.load(key, refresh: refresh,
                           fixture: { try AnalyticsFixtures.rankUsers($0, sortBy: sortBy, limit: limit) }) { client, session in
            try await AnalyticsRankLoader.users(session.query(), sortBy: sortBy, limit: limit) { query, sort, count in
                try await client.usageAnalysisUsersRanking(query, sortBy: sort, limit: count)
            }
        }
    }
}
