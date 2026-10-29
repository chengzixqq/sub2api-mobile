import SwiftUI
import Sub2Core

/// 10 §2 the overview's calm layout, while nothing needs a person (HomePresentation.isCalm): the status flag, HomeView's R18 banner,
/// six cells and ops notice (the regular layout's own views), 自动恢复中 while accounts recover by themselves, 每小时实际扣费 as a
/// line over yesterday, 按账号 and 渠道; no 待处理, 运行 or health score. The ranking is read only while this shows (10 §2.7) and a
/// failed read hides only its section (§2.6). Identifiers home.calm, home.calm.flag, home.calm.recovering, home.calm.hourly,
/// home.calm.ranking (the title), home.calm.ranking.<account id> and home.calm.channels.
struct HomeCalmView<Banner: View, Figures: View>: View {
    let store: LiveOpsStore
    private let banner: Banner
    private let figures: Figures
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session

    init(store: LiveOpsStore, @ViewBuilder banner: () -> Banner, @ViewBuilder figures: () -> Figures) {
        self.store = store; self.banner = banner(); self.figures = figures()
    }

    var body: some View {
        let summary = store.availability
        let recovering = summary.flatMap { HomePresentation.limitedItem($0, now: store.serverNow()) }
        let ranking = HomePresentation.calmRanking(store.ranking.state, refresh: store.ranking.refresh)
        let outline = HomePresentation.calmOutline(hasRanking: !ranking.isEmpty)
        List {
            banner
            if let summary { flagSection(HomePresentation.calmFlag(totals: summary.totals, hasLimited: recovering != nil)) }
            figures
            if let summary, let recovering { recoveringSection(recovering, summary: summary) }
            hourlySection(outline)
            if !ranking.isEmpty { rankingSection(ranking, outline: outline) }
            channelsSection(outline)
        }
        .homeListChrome()
        .accessibilityIdentifier("home.calm")
        .onAppear { store.setCalmVisible(true) }
        .onDisappear { store.setCalmVisible(false) }
    }

    private var timeZone: TimeZone { session?.site.serverTimeZone.timeZone ?? .current }
    private func refresh() { Task { await store.refreshHome(noCache: true) } }
    private func open(_ destination: HomeDestination) { router.open(HomeDestinationAction(destination)) { refresh() } }

    private func flagSection(_ flag: HomeCalmFlag) -> some View {
        Section { CalmStatusFlag(flag: flag) }
            .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 6, trailing: 0))
            .listRowBackground(Color.clear)
    }

    /// 10 §2.4: the 受限 row of the regular queue, on its own (00 §8.1 single capsule); it switches to the 账号 tab's 受限.
    private func recoveringSection(_ item: AttentionItem, summary: AccountStatusSummary) -> some View {
        Section {
            LimitedAttentionRow(item: item, railPosition: item.tone.drawsRail ? .single : nil, now: store.serverNow,
                                identifier: "home.calm.recovering", onOpen: { open(item.destination) },
                                onCountdownElapsed: { Task { await store.countdownElapsed() } })
        } header: {
            NumberedSectionHeader(title: HomePresentation.calmRecoveringTitle, meta: HomePresentation.calmRecoveringMeta(summary),
                                  id: "home.calm.recovering.header")
        }
    }

    /// The header follows the stats block like the regular 今日 (its meta, 统计更新于 while stale); the chart's row keeps its own.
    private func hourlySection(_ outline: HomeCalmOutline) -> some View {
        Section {
            HomeHourlyBlock(store: store, style: .line, showsTitle: false)
            HomeTodayFigures(store: store)
            if !outline.moreStatsFollowsRanking { HomeMoreStatsRow() }
        } header: {
            let meta = HomePresentation.statsFreshness(store.home.stats.value, timeZone: timeZone) ?? HomePresentation.todaySectionMeta
            NumberedSectionHeader(title: "每小时实际扣费", ordinal: outline.hourlyOrdinal, meta: meta, id: "home.calm.hourly") {
                BlockStatusAccessory(state: store.home.stats, refresh: store.homeRefresh(for: .stats), id: "home.today",
                                     resendsAfterWait: false, retry: refresh)
            }
        }
    }

    private func rankingSection(_ rows: [HomeRankingRow], outline: HomeCalmOutline) -> some View {
        Section {
            ForEach(rows) { row in CalmRankingRow(row: row) { open(row.destination) } }
            HomeMoreStatsRow()
        } header: {
            NumberedSectionHeader(title: "按账号", ordinal: outline.rankingOrdinal, meta: HomePresentation.calmRankingMeta, id: "home.calm.ranking")
        }
    }

    private func channelsSection(_ outline: HomeCalmOutline) -> some View {
        Section {
            CalmChannelsRow(store: store, retry: refresh) { router.select(.monitor(segment: .channels)) }
        } header: {
            NumberedSectionHeader(title: "渠道", ordinal: outline.channelsOrdinal, id: "home.calm.channels.header")
        }
    }
}

/// “✓ 全部正常 · 15 个账号可调度” on the ok wash; VoiceOver reads it without the tick.
private struct CalmStatusFlag: View {
    let flag: HomeCalmFlag

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Tone.ok.base).accessibilityHidden(true)
            Text(flag.title).fontWeight(.semibold).foregroundStyle(Tone.ok.ink)
            Text("· " + flag.detail).fontWeight(.medium).foregroundStyle(Palette.ink2)
        }
        .font(.subheadline)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.vertical, 5)
        .padding(.leading, 9)
        .padding(.trailing, 11)
        .frame(minHeight: 28)
        .background(Tone.ok.wash, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(flag.title + "，" + flag.detail)
        .accessibilityIdentifier("home.calm.flag")
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// One account of 按账号: the name and today's actual cost in ink (amounts are never coloured, 10 §0.6), a bar against the first
/// row, then “平台 · N 次请求”. It opens the account on 概览's stack.
private struct CalmRankingRow: View {
    let row: HomeRankingRow
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(row.name).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 8)
                        Text(row.amount).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1).lineLimit(1)
                            .layoutPriority(1)
                    }
                    bar
                    Text(row.detail).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2).lineLimit(1)
                }
                AttentionChevron()
            }
            .padding(.vertical, 5)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.calm.ranking.\(row.accountID)")
    }

    private var bar: some View {
        RoundedRectangle(cornerRadius: 1).fill(Palette.sunken).frame(height: 5)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    RoundedRectangle(cornerRadius: 1).fill(Palette.ink2).frame(width: proxy.size.width * row.ratio)
                }
            }
            .accessibilityHidden(true)
    }
}

/// 10 §2.4 渠道: “N 个渠道” over the regular row's counts; it opens 监控 · 渠道 when there is something to see there. Monitoring off
/// reads 渠道监控未开启 and a failure without earlier counts 渠道状态加载失败 · 重试, neither opening anything (as 10 §1.3.5).
private struct CalmChannelsRow: View {
    let store: LiveOpsStore
    let retry: @MainActor () -> Void
    let open: () -> Void

    var body: some View {
        let channels = HomeRunPresentation.channels(store.home.channels.display)
        switch channels {
        case .failed:
            BlockFailureRow(title: HomePresentation.channelsFailedText, error: store.homeLastError(for: .channels),
                            refresh: store.homeRefresh(for: .channels), id: "home.calm.channels", resendsAfterWait: false, retry: retry)
                .homeFailureContainer("home.calm.channels.failed")
        case .disabled:
            label(channels, showsChevron: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(HomePresentation.channelsDisabledText)
                .accessibilityIdentifier("home.calm.channels")
        case .loading, .summary, .empty:
            Button(action: open) { label(channels, showsChevron: channels.isTappable) }
                .buttonStyle(.plain)
                .disabled(!channels.isTappable)
                .accessibilityLabel(title(channels))
                .accessibilityValue(channels == .empty ? "" : channels.text)
                .accessibilityIdentifier("home.calm.channels")
        }
    }

    private static let iconWidth: CGFloat = 24

    private func title(_ channels: HomeRunPresentation.Channels) -> String {
        if channels == .disabled { return HomePresentation.channelsDisabledText }
        return store.home.channels.value.map(HomePresentation.channelCountTitle) ?? "渠道"
    }

    private func label(_ channels: HomeRunPresentation.Channels, showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right").foregroundStyle(Palette.ink3).frame(width: Self.iconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title(channels)).foregroundStyle(channels == .disabled ? Palette.ink2 : Palette.ink1)
                if case .summary = channels {
                    Text(HomeRunSection.summary(channels)).font(.subheadline).foregroundStyle(Palette.ink2)
                }
            }
            .redacted(reason: channels == .loading ? .placeholder : [])
            Spacer(minLength: 8)
            if case .summary(_, true) = channels {
                Text(BlockStatusPresentation.updateFailed).font(.footnote).foregroundStyle(Palette.ink3)
            }
            if showsChevron { AttentionChevron() }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
