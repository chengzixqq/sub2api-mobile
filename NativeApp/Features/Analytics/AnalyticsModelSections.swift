import SwiftUI
import Sub2Core

// 40 §5.3 the model page's head and its numbered blocks (S4-19). They show the states they are given and read nothing;
// AnalyticsModelView.swift reads. Identifiers analytics.model.* (C-31).

/// 头部: “实际扣费 · 占全部 12.3%”, the big number with its status row, the change against the comparison window (hidden while that
/// is pending or failed, as on 计费趋势) and, for a mapping name, “上游模型 b”.
struct AnalyticsModelHeader: View {
    let name: AnalyticsModelName
    let summary: LoadState<AnalyticsSummary>?
    let shareLabel: String
    let changeLine: String?
    let timeZone: TimeZone
    let retry: @MainActor () -> Void

    static let placeholderHeight: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if summary?.value == nil, summary?.error == nil {
                AnalyticsCardPlaceholder(height: Self.placeholderHeight, id: "analytics.model.summary")
            } else {
                figures
            }
            if let upstream = name.upstream, let line = AnalyticsModelPresentation.upstreamLine(name) {
                Text("上游模型 \(Text(upstream).monospaced())")
                    .font(.footnote).foregroundStyle(Palette.ink2).lineLimit(1).truncationMode(.middle)
                    .accessibilityLabel(line)
                    .accessibilityIdentifier("analytics.model.upstream")
            }
        }
        .padding(16)
        .modelSurface()
    }

    @ViewBuilder private var figures: some View {
        let amount = DisplayFormat.money(summary?.value?.actualCost)
        Text(shareLabel).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2).lineLimit(1)
            .accessibilityIdentifier("analytics.model.share")
        Text(amount).font(.largeTitle.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1)
            .lineLimit(1).minimumScaleFactor(0.5)
            .accessibilityLabel(DisplayFormat.spoken(amount))
            .accessibilityIdentifier("analytics.model.actual")
        AnalyticsCardStatusRow(summary, id: "analytics.model.summary", timeZone: timeZone, retry: retry)
        if let changeLine {
            Text(changeLine).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink2)
                .accessibilityIdentifier("analytics.model.change")
        }
    }
}

/// A numbered block: its header (identifier `<id>.header`) over a surface.
struct AnalyticsModelSection<Content: View>: View {
    private let title: String
    private let ordinal: String
    private let meta: String
    private let id: String
    private let content: Content

    init(title: String, ordinal: String, meta: String, id: String, @ViewBuilder content: () -> Content) {
        self.title = title; self.ordinal = ordinal; self.meta = meta; self.id = id; self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NumberedSectionHeader(title: title, ordinal: ordinal, meta: meta, id: "\(id).header").padding(.horizontal, 16)
            VStack(alignment: .leading, spacing: 12) { content }
                .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                .modelSurface()
        }
    }
}

/// 壹 趋势: the model's actual charge per bucket with the standard dotted, 100pt high, no selection (S4D2b-04 ⑧); then 账号成本 / 标准
/// / 利润 of its totals.
struct AnalyticsModelTrendSection: View {
    let ordinal: String
    let range: AnalyticsRange
    let trend: LoadState<DashboardTrendReply>?
    let summary: AnalyticsSummary?
    let timeZone: TimeZone
    let retry: @MainActor () -> Void

    static let chartHeight: CGFloat = 100

    var body: some View {
        AnalyticsModelSection(title: AnalyticsModelPresentation.trendTitle, ordinal: ordinal, meta: AnalyticsModelPresentation.trendMeta,
                              id: "analytics.model.trend") {
            AnalyticsCardBody(trend, id: "analytics.model.trend", minHeight: Self.chartHeight, timeZone: timeZone, retry: retry) { reply in
                AnalyticsBarChart(series: .billing(range: range, points: reply.points), selection: nil, id: "analytics.model.trend.chart",
                                  chartTitle: AnalyticsModelPresentation.trendTitle, height: Self.chartHeight)
            }
            AnalyticsFigureRow(AnalyticsBillingCard.figures(summary), id: "analytics.model.trend")
        }
    }
}

/// 贰 用量: 请求 · Tokens over 缓存读占比 · 平均每次, from the totals the head shows (their failure is the head's).
struct AnalyticsModelUsageSection: View {
    let ordinal: String
    let rangeName: String
    let summary: LoadState<AnalyticsSummary>?

    static let placeholderHeight: CGFloat = 96

    var body: some View {
        AnalyticsModelSection(title: AnalyticsModelPresentation.usageTitle, ordinal: ordinal, meta: rangeName, id: "analytics.model.usage") {
            if summary?.value == nil, summary?.error == nil {
                AnalyticsCardPlaceholder(height: Self.placeholderHeight, id: "analytics.model.usage")
            } else {
                let figures = AnalyticsModelPresentation.usage(summary?.value)
                AnalyticsFigureRow(Array(figures.prefix(2)), id: "analytics.model.usage")
                AnalyticsFigureRow(Array(figures.dropFirst(2)), id: "analytics.model.usage")
            }
        }
    }
}

/// 叁 速度: 输出 Tokens/秒 · 平均首 Token · 平均时长 and the window's footnote. Without a row of its own to read (S4D2b-20) the cells
/// show “—” under the window the page would ask for.
struct AnalyticsModelSpeedSection: View {
    let ordinal: String
    let speed: LoadState<AnalyticsModelSpeed>?
    let isReadable: Bool
    let localWindow: OpsTokenStatsWindow
    let rangeName: String
    let timeZone: TimeZone
    let retry: @MainActor () -> Void

    static let placeholderHeight: CGFloat = 52

    var body: some View {
        let window = speed?.value?.window ?? localWindow
        AnalyticsModelSection(title: AnalyticsModelPresentation.speedTitle, ordinal: ordinal,
                              meta: AnalyticsModelPresentation.speedMeta(window, rangeName: rangeName), id: "analytics.model.speed") {
            if isReadable {
                AnalyticsCardBody(speed, id: "analytics.model.speed", minHeight: Self.placeholderHeight, timeZone: timeZone, retry: retry) { value in
                    AnalyticsFigureRow(AnalyticsModelPresentation.speed(value.speed), id: "analytics.model.speed")
                }
            } else {
                AnalyticsFigureRow(AnalyticsModelPresentation.speed(nil), id: "analytics.model.speed")
            }
            Text(AnalyticsModelPresentation.speedFootnote(window)).font(.footnote).foregroundStyle(Palette.ink3)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("analytics.model.speed.note")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("analytics.model.speed")
    }
}

/// 肆 用得最多的用户: three rows as on the full ranking (the value is the actual charge, each opens the user), then the way to the
/// model's usage records.
struct AnalyticsModelUsersSection: View {
    let ordinal: String
    let users: LoadState<AnalyticsUserRanking>?
    let logsSubtitle: String
    let logsRoute: AppRoute
    let timeZone: TimeZone
    let retry: @MainActor () -> Void

    static let placeholderHeight: CGFloat = 132
    static let emptyHeight: CGFloat = 64

    var body: some View {
        AnalyticsModelSection(title: AnalyticsModelPresentation.usersTitle, ordinal: ordinal, meta: AnalyticsModelPresentation.usersMeta,
                              id: "analytics.model.users") {
            AnalyticsCardBody(users, id: "analytics.model.users", minHeight: Self.placeholderHeight, timeZone: timeZone, retry: retry) { ranking in
                rows(AnalyticsRanking.users(ranking, metric: .actualCost).items)
            }
            VStack(spacing: 0) {
                Palette.hairline.frame(height: 1).accessibilityHidden(true)
                AnalyticsModelLogsRow(subtitle: logsSubtitle, route: logsRoute).padding(.top, 8)
            }
        }
    }

    @ViewBuilder private func rows(_ items: [AnalyticsRankItem]) -> some View {
        if items.isEmpty {
            Text(AnalyticsModelPresentation.usersEmpty).font(.subheadline).foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, minHeight: Self.emptyHeight)
                .accessibilityIdentifier("analytics.model.users.empty")
        } else {
            VStack(spacing: 0) {
                ForEach(Array(items.prefix(AnalyticsModelPresentation.usersShown).enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Palette.hairline.frame(height: 1).padding(.leading, 32).accessibilityHidden(true) }
                    // “user:1” → analytics.model.user.1
                    RankRow(item, rank: index + 1, style: .full, id: "analytics.model." + item.id.replacingOccurrences(of: ":", with: "."))
                }
            }
        }
    }
}

/// “这个模型的使用记录” with “近 24 小时 · 带上模型筛选，可以去掉”: pushes 使用记录 with the model and the group (X39).
private struct AnalyticsModelLogsRow: View {
    let subtitle: String
    let route: AppRoute

    var body: some View {
        NavigationLink(value: route) {
            HStack(spacing: 10) {
                Image(systemName: "list.bullet").font(.subheadline).foregroundStyle(Palette.ink3).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AnalyticsModelPresentation.logsTitle).font(.subheadline).foregroundStyle(Palette.ink1)
                    Text(subtitle).font(.footnote).foregroundStyle(Palette.ink2).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink3).accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AnalyticsModelPresentation.logsTitle + "，" + subtitle)
        .accessibilityIdentifier("analytics.model.logs")
    }
}

private extension View {
    func modelSurface() -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
