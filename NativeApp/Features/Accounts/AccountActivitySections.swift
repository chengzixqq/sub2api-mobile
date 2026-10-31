import SwiftUI
import Sub2Core

// 20 §2.3 今日（贰）, 记录（叁） and the status card's “最近上游错误” line (S2-09). S2-21 adds 定时测试 to 记录's end.

/// 实际 · 账号成本 · 标准, then 请求 / Tokens and the footnote. Each figure reads its name, then its value. Failures use S1-08's
/// block views (X37): without figures BlockFailureRow “读取失败 · 重试” under them, with figures BlockStatusAccessory beside the
/// title; both count a 429 wait down with 重试 held back and read again by themselves once it ends.
struct AccountTodaySection: View {
    let load: LoadState<AccountTodayStats>
    let ordinal: String
    /// The page's refresh gate: the 429 wait's resend goes out only while the page could refresh.
    let autoRetry: Bool
    let retry: @MainActor () async -> Void

    var body: some View {
        AccountDetailSectionBox(title: "今日", ordinal: ordinal, id: "account.today.header") {
            figures(AccountDetailPresentation.today(load.value), pending: isPending)
            if showsFailureRow {
                BlockFailureRow(title: AccountDetailPresentation.todayFailureTitle, error: load.lastError, occurredAt: load.lastErrorAt,
                                refresh: load.refresh, id: "account.today", resendsAfterWait: autoRetry, retry: resend)
                    .padding(.vertical, 4)
            }
            Text(AccountTodayFigures.footnote).font(.footnote).foregroundStyle(Palette.ink3).fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 8)
                .accessibilityIdentifier("account.today.footnote")
        } accessory: {
            BlockStatusAccessory(load, id: "account.today", resendsAfterWait: autoRetry, retry: resend)
        }
    }

    /// The first read: skeleton figures, never 0.
    private var isPending: Bool {
        if case .placeholder = load.state.display { true } else { false }
    }
    /// A failure with no figures to keep; with figures the title's accessory speaks instead.
    private var showsFailureRow: Bool {
        if case .failed(_, nil, _) = load.state { true } else { false }
    }
    private func resend() { Task { await retry() } }

    private func figures(_ figures: AccountTodayFigures, pending: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                amount("实际", figures.actual, dot: Palette.legendActual, id: "actual", pending: pending)
                amount("账号成本", figures.accountCost, dot: Palette.legendCost, id: "cost", pending: pending)
                amount("标准", figures.standard, dot: Palette.legendStandard, id: "standard", pending: pending)
            }
            HStack(spacing: 16) {
                count("请求", figures.requests, id: "requests", pending: pending)
                count("Tokens", figures.tokens, id: "tokens", pending: pending)
                Spacer(minLength: 0)
            }
        }
        .padding(.vertical, 8)
        .redacted(reason: pending ? .placeholder : [])
    }
    private func amount(_ label: String, _ value: String, dot: Color, id: String, pending: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(dot).frame(width: 7, height: 7)
                Text(label).font(.caption).foregroundStyle(Palette.ink2).lineLimit(1)
            }
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1).lineLimit(1).minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .figureAccessibility(label, value, id: id, pending: pending)
    }
    private func count(_ label: String, _ value: String, id: String, pending: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(label).font(.subheadline).foregroundStyle(Palette.ink2)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Palette.ink1)
        }
        .figureAccessibility(label, value, id: id, pending: pending)
    }
}

private extension View {
    /// A figure reads its name, then its value; “—” reads 无数据 and a skeleton 正在加载.
    func figureAccessibility(_ label: String, _ value: String, id: String, pending: Bool) -> some View {
        accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(label))
            .accessibilityValue(Text(pending ? "正在加载" : DisplayFormat.spoken(value)))
            .accessibilityIdentifier("account.today.\(id)")
    }
}

/// 上游错误 (“近 24 小时 N 条”, or “运维监控未开启” and still open) and 使用记录, both into the log page filtered by this account;
/// then S2-21's 定时测试 into its small page.
struct AccountRecordsSection: View {
    let account: RouteObject
    let upstream: BlockState<AccountUpstreamErrors>
    let ordinal: String
    var showsScheduledTests = false
    /// nil while the first read is out.
    var scheduledSummary: ScheduledTestSummary?

    var body: some View {
        AccountDetailSectionBox(title: "记录", ordinal: ordinal, id: "account.records.header") {
            row(.upstream, systemImage: "exclamationmark.octagon", title: "上游错误",
                trailing: AccountDetailPresentation.upstreamRecordTrailing(upstream), id: "account.records.upstream")
            Divider().overlay(Palette.hairline)
            row(.usage, systemImage: "list.bullet", title: "使用记录", trailing: nil, id: "account.records.usage")
            if showsScheduledTests {
                Divider().overlay(Palette.hairline)
                AccountScheduledTestsRow(accountID: account.id, summary: scheduledSummary)
            }
        }
    }

    private func row(_ scope: LogScope, systemImage: String, title: String, trailing: String?, id: String) -> some View {
        NavigationLink(value: AppRoute.logs(LogsRoute(scope: scope, account: account))) {
            HStack(spacing: 12) {
                Image(systemName: systemImage).foregroundStyle(Palette.ink3).frame(width: 22)
                Text(title).foregroundStyle(Palette.ink1)
                Spacer(minLength: 8)
                if let trailing { Text(trailing).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink2).lineLimit(1) }
                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Palette.ink3)
            }
            .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(trailing.map(DisplayFormat.spoken) ?? ""))
        .accessibilityIdentifier(id)
    }
}

/// In AccountStatusCard's error footer: “最近上游错误 HH:MM · N 分钟前 · 401 ›” opens that request (40 §7); after OPS_DISABLED,
/// a failed read or a quiet day, the account's `error_at` as a plain “出错于 …” (U22). Recomputed every minute on the site clock.
struct AccountUpstreamErrorLineView: View {
    let account: UpstreamAccount
    let upstream: BlockState<AccountUpstreamErrors>
    @Environment(\.sessionContext) private var session

    var body: some View {
        TimelineView(.everyMinute) { context in
            if let shown = currentLine(at: context.date) { content(shown) }
        }
    }

    @ViewBuilder private func content(_ line: LastUpstreamErrorLine) -> some View {
        switch line {
        case .latest(let requestID, _, _, _):
            NavigationLink(value: AppRoute.request(.error(id: requestID, kind: .upstream))) {
                HStack(spacing: 6) {
                    Text(line.text).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink2)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Palette.ink3)
                }
                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityLabel(Text(line.text))
            .accessibilityIdentifier("account.status.lastUpstreamError")
        case .erroredAt:
            Text(line.text).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink2)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.top, 4)
                .accessibilityIdentifier("account.status.erroredAt")
        }
    }

    private func currentLine(at local: Date) -> LastUpstreamErrorLine? {
        let now = local.addingTimeInterval(session?.client.serverClock.offset ?? 0)
        let input = LastUpstreamErrorInput(account: account, state: AccountDisplayState(account, now: now).state, upstream: upstream)
        return AccountDetailPresentation.lastUpstreamErrorLine(input, now: now, timeZone: session?.site.serverTimeZone.timeZone ?? .current)
    }
}
