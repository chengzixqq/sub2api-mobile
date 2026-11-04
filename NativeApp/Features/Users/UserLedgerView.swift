import SwiftUI
import Sub2Core

/// 30 §4: every record of one user, 20 a page. Entering reads page 1 together with the user, who gives the subtitle and the
/// 404 USER_NOT_FOUND (balance-history answers a missing user with an empty page). The end of the list reads the next page,
/// deduplicated by id; a pull reads page 1 again and drops the later pages, and when it fails the rows stay (00 §4.6). No
/// polling, no ETag (30 §4.6).
struct UserLedgerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sessionContext) private var session
    @Environment(\.dismiss) private var dismiss
    let userID: Int

    @State private var feed: BalanceHistoryFeed?
    /// Page 1 failed with no rows shown: the whole-page error.
    @State private var loadFailure: String?
    /// A pull failed: the rows stay under “刷新失败 · 重试”.
    @State private var refreshFailed = false
    @State private var loadedAt: Date?
    @State private var userGone = false
    @State private var displayName: String?
    @State private var loadingMore = false
    @State private var moreFailed = false
    /// Bumped to read the next page again: its retry, or a read the background stopped.
    @State private var moreAttempt = 0
    /// Changes with every page-1 read, so replies for an earlier one are dropped.
    @State private var ticket = UUID()

    private var timeZone: ServerTimeZone { session?.site.serverTimeZone ?? .device }
    private var serverNow: Date { session?.client.serverClock.now() ?? Date() }
    private var ledgerAvailable: Bool { session?.has(.usersBalanceLedger) == true }

    var body: some View {
        content
            .navigationTitle("充值与调整记录")
            .navigationBarTitleDisplayMode(.inline)
            .navigationSubtitle(displayName ?? "")
            .task { if feed == nil { await loadFirstPage() } }
            // A read the background stopped is read again (D18); loaded rows wait for a pull, the page does not poll.
            .onChange(of: model.foregroundRevision) { _, _ in
                if feed == nil, loadFailure == nil, !userGone { Task { await loadFirstPage() } } else { moreAttempt += 1 }
            }
    }

    @ViewBuilder private var content: some View {
        if userGone {
            notFound
        } else if let feed {
            records(feed).refreshable { await loadFirstPage() }
        } else if let loadFailure {
            failure(loadFailure)
        } else {
            List { ForEach(0..<5, id: \.self) { _ in UserLedgerRowSkeleton() } }
        }
    }

    private func records(_ feed: BalanceHistoryFeed) -> some View {
        let zone = timeZone, now = serverNow, ledger = ledgerAvailable
        return List {
            if refreshFailed { refreshRetry }
            if feed.items.isEmpty {
                Section {
                    Text("暂无记录").foregroundStyle(Palette.ink2).frame(minHeight: 44).accessibilityIdentifier("user.ledger.empty")
                }
            } else {
                Section {
                    ForEach(feed.items) { item in
                        UserLedgerRow(item: item, timeZone: zone, now: now, adjustmentLine: UserLedger.thirdLine(for: item, ledgerAvailable: ledger))
                    }
                    if feed.hasMore { nextPageFooter(feed) }
                } header: {
                    header(feed, ledger: ledger)
                }
            }
        }
    }

    /// 30 §4.3 页面头: “N 条”, “总充值”, and with `users.balance_ledger` the sources in small print.
    private func header(_ feed: BalanceHistoryFeed, ledger: Bool) -> some View {
        let lines = UserLedger.breakdownLines(feed.breakdown, ledgerAvailable: ledger)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(UserLedger.countText(feed.total)).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.ink2)
                    .accessibilityIdentifier("user.ledger.count")
                Spacer(minLength: 8)
                Text(UserLedger.rechargedText(feed.totalRecharged)).font(.subheadline).monospacedDigit().foregroundStyle(Palette.ink3)
                    .accessibilityIdentifier("user.ledger.recharged")
            }
            if !lines.isEmpty {
                VStack(alignment: .leading, spacing: 2) { ForEach(lines, id: \.self) { Text($0) } }
                    .font(.footnote).monospacedDigit().foregroundStyle(Palette.ink3)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("user.ledger.breakdown")
            }
        }
        .textCase(nil)
    }

    @ViewBuilder private func nextPageFooter(_ feed: BalanceHistoryFeed) -> some View {
        if moreFailed {
            Button("加载更多失败 · 重试") { moreFailed = false; moreAttempt += 1 }
                .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("user.ledger.more.retry")
        } else {
            ProgressView().frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("user.ledger.more.loading")
                .task(id: NextPageRequest(page: feed.page, attempt: moreAttempt)) { await loadNextPage() }
        }
    }

    private var refreshRetry: some View {
        Section {
            Button { Task { await loadFirstPage() } } label: {
                HStack(alignment: .firstTextBaseline) {
                    Text("刷新失败 · 重试").foregroundStyle(Palette.accent)
                    Spacer(minLength: 8)
                    Text(UserLedger.updatedText(loadedAt, timeZone: timeZone)).font(.footnote).monospacedDigit().foregroundStyle(Palette.ink3)
                }
            }
            .frame(minHeight: 44)
            .accessibilityIdentifier("user.ledger.refresh.retry")
        }
    }

    private func failure(_ message: String) -> some View {
        ContentUnavailableView {
            Label("加载记录失败", systemImage: "exclamationmark.triangle").accessibilityIdentifier("user.ledger.error")
        } description: { Text(message) } actions: {
            Button("重试") { loadFailure = nil; Task { await loadFirstPage() } }
                .buttonStyle(.borderedProminent).frame(minHeight: 44).accessibilityIdentifier("user.ledger.error.retry")
        }
    }

    private var notFound: some View {
        ContentUnavailableView {
            Label("这个用户不存在或已删除", systemImage: "person.crop.circle.badge.xmark").accessibilityIdentifier("user.ledger.not-found")
        } actions: {
            Button("返回") { dismiss() }.frame(minHeight: 44).accessibilityIdentifier("user.ledger.back")
        }
    }

    // MARK: - Reads

    private func loadFirstPage() async {
        guard let session, session.generation == model.sessionGeneration else { return }
        let current = UUID()
        ticket = current; loadingMore = false; moreFailed = false
        async let rows: Void = loadRecords(session, current)
        async let profile: Void = loadProfile(session, current)
        _ = await (rows, profile)
    }
    private func loadRecords(_ session: SessionContext, _ current: UUID) async {
        do {
            let first = try await model.balanceHistory(userID: userID, page: 1)
            guard isCurrent(session, current) else { return }
            feed = BalanceHistoryFeed(firstPage: first); loadedAt = serverNow; loadFailure = nil; refreshFailed = false
        } catch {
            guard isCurrent(session, current), !(error is CancellationError) else { return }
            if feed == nil { loadFailure = error.localizedDescription } else { refreshFailed = true }
        }
    }
    /// Only the subtitle and the missing user; any other failure leaves the subtitle out.
    private func loadProfile(_ session: SessionContext, _ current: UUID) async {
        do {
            let user = try await model.user(id: userID)
            guard isCurrent(session, current) else { return }
            displayName = user.displayName
        } catch {
            guard isCurrent(session, current), (error as? APIError)?.isUserNotFound == true else { return }
            userGone = true
        }
    }
    private func loadNextPage() async {
        guard let session, session.generation == model.sessionGeneration, let shown = feed, shown.hasMore, !loadingMore, !moreFailed else { return }
        let token = ticket
        loadingMore = true
        let result: Result<BalanceHistoryPage, any Error>
        do { result = .success(try await model.balanceHistory(userID: userID, page: shown.nextPage)) } catch { result = .failure(error) }
        guard ticket == token, session.generation == model.sessionGeneration else { return }
        loadingMore = false
        switch result {
        case .success(let next): feed = feed?.appending(next)
        // A cancelled read (the footer scrolled away, the background) runs again when the footer shows or the App returns.
        case .failure(let error): moreFailed = !(error is CancellationError)
        }
    }
    private func isCurrent(_ session: SessionContext, _ current: UUID) -> Bool {
        session.generation == model.sessionGeneration && ticket == current && !Task.isCancelled
    }
}

private struct NextPageRequest: Hashable {
    let page: Int
    let attempt: Int
}
