import SwiftUI
import Sub2Core

/// 10 §1.3.4 今日（贰）: 每小时实际扣费, 账号成本 / 标准 / 利润, Tokens and 成功率, then 更多统计. The header follows the stats block and
/// the chart's title row the hourly one (10 §1.5); a block without a value gets its own retry row, and the cells under a failed chart
/// stay. 重试 reads home again past the server cache; the next poll retries by itself (S1D1-20). Identifiers home.today.*.
struct HomeTodaySection: View {
    let store: LiveOpsStore
    @Environment(\.sessionContext) private var session

    var body: some View {
        Section {
            hourlyBlock
            figures
            moreStats
        } header: {
            NumberedSectionHeader(title: "今日", ordinal: "贰", meta: meta, id: "home.today.header") {
                BlockStatusAccessory(state: store.home.stats, refresh: store.homeRefresh(for: .stats), id: "home.today",
                                     resendsAfterWait: false, retry: retry)
            }
        }
    }

    private static let chartHeight: CGFloat = 104
    private static let amountKinds: [HomeTodayKind] = [.accountCost, .standardCost, .profit]

    private var timeZone: TimeZone { session?.site.serverTimeZone.timeZone ?? .current }
    /// “00:00 起”, or “统计更新于 HH:MM” while the server's statistics lag (10 §1.3.1).
    private var meta: String { HomePresentation.statsFreshness(store.home.stats.value, timeZone: timeZone) ?? HomePresentation.todaySectionMeta }
    private func retry() { Task { await store.refreshHome(noCache: true) } }

    // MARK: 每小时实际扣费

    private var hourlyBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("每小时实际扣费").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink1)
                BlockStatusAccessory(state: store.home.hourly, refresh: store.homeRefresh(for: .hourly), id: "home.today.hourly",
                                     resendsAfterWait: false, retry: retry)
                Spacer(minLength: 8)
                HomeHourlyLegend(style: .bars)
            }
            hourlyContent
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private var hourlyContent: some View {
        switch store.home.hourly.display {
        case .value(let hourly, _, _, _):
            HomeHourlyChart(series: HomeHourlySeries(hourly, now: store.serverNow(), timeZone: timeZone), height: Self.chartHeight)
        case .placeholder:
            RoundedRectangle(cornerRadius: 6).fill(Palette.sunken).frame(height: Self.chartHeight)
                .accessibilityElement()
                .accessibilityLabel(HomeHourlySeries.accessibilityLabel)
                .accessibilityValue("正在加载")
        case .failed, .disabled:
            BlockFailureRow(title: HomeHourlySeries.failedText, error: store.homeLastError(for: .hourly), refresh: store.homeRefresh(for: .hourly),
                            id: "home.today.hourly", resendsAfterWait: false, retry: retry)
                .homeFailureContainer("home.today.hourly.failed")
        }
    }

    // MARK: 三格、Tokens 与成功率

    private var figures: some View {
        let cells = HomePresentation.todayCells(stats: store.home.stats.value, todaySLA: store.todaySLA)
        let stats = store.home.stats.display.homePhase
        // 今日 SLA is its own read, skipped while ops monitoring is off.
        let slaLoading = !store.opsDisabled && store.todayOps.state.display.homePhase == .placeholder
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(cells.filter { Self.amountKinds.contains($0.kind) }) { amountCell($0, isLoading: stats == .placeholder) }
            }
            .padding(.vertical, 10)
            Palette.hairline.frame(height: 1).accessibilityHidden(true)
            HStack(spacing: 18) {
                ForEach(cells.filter { !Self.amountKinds.contains($0.kind) }) { cell in
                    HomeInlineFigure(label: cell.label, value: cell.value, id: "home.today." + cell.kind.rawValue,
                                     isLoading: cell.kind == .successRate ? slaLoading : stats == .placeholder)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            if stats == .failed {
                BlockFailureRow(state: store.home.stats, error: store.homeLastError(for: .stats), refresh: store.homeRefresh(for: .stats),
                                id: "home.today", resendsAfterWait: false, retry: retry)
                    .homeFailureContainer("home.today.failed")
            }
        }
    }

    /// Amounts in ink: billing figures are never coloured, a loss shows “−$” (10 §0.6).
    private func amountCell(_ cell: HomeValueCell, isLoading: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(cell.label).font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1)
            Text(cell.value).font(.title3.weight(.medium)).monospacedDigit().foregroundStyle(Palette.ink1)
                .lineLimit(1).minimumScaleFactor(0.5)
        }
        .redacted(reason: isLoading ? .placeholder : [])
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cell.label)
        .accessibilityValue(isLoading ? HomeInlineFigure.loadingValue : DisplayFormat.spoken(cell.value))
        .accessibilityIdentifier("home.today." + cell.kind.rawValue)
    }

    // MARK: 更多统计

    private var moreStats: some View {
        NavigationLink(value: AppRoute.analytics()) {
            HStack(spacing: 12) {
                Image(systemName: "chart.bar").foregroundStyle(Palette.ink3).frame(width: 24).accessibilityHidden(true)
                Text("更多统计").foregroundStyle(Palette.ink1)
                Spacer(minLength: 8)
                Text("模型 · 用户 · 分组排行").font(.subheadline).foregroundStyle(Palette.ink3).lineLimit(1)
            }
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier("home.today.more")
    }
}

/// “Tokens 96.4M”: the name in ink2, the figure in ink1 (the design's kv-row). VoiceOver reads `spokenLabel`, then the figure, with
/// “—” as 无数据.
struct HomeInlineFigure: View {
    static let loadingValue = "正在加载"

    let label: String
    var spokenLabel: String?
    let value: String
    let id: String
    var isLoading = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(label).foregroundStyle(Palette.ink2)
            Text(value).fontWeight(.semibold).monospacedDigit().foregroundStyle(Palette.ink1)
        }
        .font(.subheadline)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .redacted(reason: isLoading ? .placeholder : [])
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel ?? label)
        .accessibilityValue(isLoading ? Self.loadingValue : DisplayFormat.spoken(value))
        .accessibilityIdentifier(id)
    }
}

extension View {
    /// A block's failure row under the overview's own identifier (`home.today.failed` …), its buttons still reachable.
    func homeFailureContainer(_ id: String) -> some View {
        accessibilityElement(children: .contain).accessibilityIdentifier(id)
    }
}
