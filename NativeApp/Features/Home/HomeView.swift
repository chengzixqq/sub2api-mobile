import SwiftUI
import Sub2Core

/// 10 §1 the overview's regular layout: the R18 banner, the six cells and the ops notice, then the queue (S1-10) and the today and
/// run sections (S1-09b); 10 §2 the calm layout (HomeCalmView, S1-11) in its place while nothing needs a person. The title is the
/// site menu (MainTabs' `siteTitleMenu()`), the subtitle the server's date and freshness.
/// The session's LiveOpsStore polls while this tab shows and the App is active; coming back to the foreground restarts it, which
/// reads at once (D18: no scene-phase handler here), and passing compliance reads again. Identifiers home.*.
struct HomeView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if let store = model.liveOps { HomeScreen(store: store) } else { ProgressView() }
        }
        .navigationTitle(model.activeProfile?.name ?? MainTab.today.title)
    }
}

private struct HomeScreen: View {
    let store: LiveOpsStore
    @Environment(AppModel.self) private var model
    @Environment(AppRouter.self) private var router
    @Environment(\.sessionContext) private var session
    @Environment(\.scenePhase) private var scenePhase
    @State private var visible = false
    @State private var awaitingAccountTest: Int?

    var body: some View {
        // Back from the background the phase passes .background, so the task restarts once. Restarting it on foregroundRevision or
        // complianceRevision as well would cancel the read just sent, and the new task would skip its first read while that one
        // is still unwinding.
        let polls = visible && scenePhase == .active
        // Each minute the subtitle's “N 分钟前” and the banner's time left are counted again.
        TimelineView(.everyMinute) { _ in
            page.navigationSubtitle(subtitle)
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { moreMenu } }
        .refreshable { await store.refreshHome(noCache: true) }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .task(id: polls) {
            guard polls else { return }
            await store.homePolling()
        }
        .onChange(of: model.securityPrompts.complianceRevision) { _, _ in readAfterCompliance() }
        .refreshesHomeAfterAccountTest($awaitingAccountTest, store: store)
    }

    /// S0-13: a read the compliance sheet held goes on by itself once it passes; otherwise home and its extra reads are read again.
    private func readAfterCompliance() {
        guard visible, scenePhase == .active, !store.isHomeLoading else { return }
        Task { await store.refreshHome(noCache: false) }
    }

    private var requestFailed: Bool { store.homeFailed }
    /// X34: the records of this site's address, an earlier login's among them.
    private var pending: [any PendingMoneyWrite] { session.map { model.pendingMoneyWrites(sameAddressAs: $0.serverID) } ?? [] }
    private var state: HomeScreenState {
        HomeScreenState.resolve(isVendor: session?.site.me.workspace != nil, sections: store.home.phases, requestFailed: requestFailed)
    }

    @ViewBuilder private var page: some View {
        switch state {
        case .vendorPlaceholder:
            ContentUnavailableView("代运营工作区不提供全站概览", systemImage: "building.2")
                .accessibilityIdentifier("home.vendor")
        case .unreachable:
            unreachable
        case .skeleton, .content:
            // X34: this address's records, an earlier login's among them, count once for the queue and for 10 §2.2 condition 4.
            let records = pending
            let calm = HomePresentation.isCalm(availability: store.home.availability, alerts: store.home.alerts, pending: records)
            // 10 §2.1: the whole screen cross-fades whenever a reply changes the layout.
            ZStack {
                if calm {
                    HomeCalmView(store: store) { bannerSection } figures: { figuresSection }
                        .transition(.opacity)
                } else {
                    regularList(pending: records)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut, value: calm)
        }
    }

    private func regularList(pending: [any PendingMoneyWrite]) -> some View {
        List {
            bannerSection
            figuresSection
            HomeAttentionList(store: store, pending: pending, currentServerID: session?.serverID, awaitingAccountTest: $awaitingAccountTest)
            HomeTodaySection(store: store)
            HomeRunSection(store: store)
        }
        .homeListChrome()
        .accessibilityIdentifier("home.regular")
    }

    /// R18: a login without a refresh token signs in again when its access ends; counted on the phone's clock (D03).
    @ViewBuilder private var bannerSection: some View {
        if let site = session?.site, site.refreshTokenUnavailable {
            Section {
                StatusBanner(tone: .caution, systemImage: "clock.badge.exclamationmark",
                             title: HomePresentation.sessionRenewalBanner(expiresAt: site.accessTokenExpiresAt, now: Date()))
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("home.banner.renewal")
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    /// The six cells, then 运维监控未开启 right under them (10 §1.3.1).
    @ViewBuilder private var figuresSection: some View {
        Section {
            HomeTicker(cells: HomePresentation.tickerCells(stats: store.home.stats.value, rates: store.home.rates.value, ratesSource: store.ratesSource),
                       placeholders: HomeTickerLayout.placeholders(stats: store.home.stats.display.homePhase, rates: store.home.rates.display.homePhase))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Palette.surface)
        }
        if store.opsDisabled {
            Section {
                OpsDisabledNotice(style: .inline, tpmExcludesCache: store.tpmExcludesCache)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    /// 10 §1.5: nothing to show; 重试 reads home again past the server cache. The row carries the 429 wait, the compliance step
    /// and the details; the next poll retries by itself (S1D1-20).
    private var unreachable: some View {
        ContentUnavailableView {
            Label("无法连接到站点", systemImage: "wifi.exclamationmark")
        } actions: {
            BlockFailureRow(error: store.homeLastError(for: .stats), refresh: store.homeRefresh(for: .stats), id: "home.unreachable",
                            resendsAfterWait: false) { Task { await store.refreshHome(noCache: true) } }
                .fixedSize()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.unreachable")
    }

    /// 10 §1.3.1 on the server's calendar. The last full success is a local receive time, moved by the current clock offset so
    /// “N 分钟前” compares two server times.
    private var subtitle: String {
        let localNow = Date(), serverNow = store.serverNow()
        let lastFullSuccess = store.lastFullSuccessAt.map { $0.addingTimeInterval(serverNow.timeIntervalSince(localNow)) }
        let status = HomeScreenState.refreshStatus(sections: store.home.phases, lastFullSuccessAt: lastFullSuccess, requestFailed: requestFailed)
        return HomePresentation.subtitle(now: serverNow, status: status, serverTimeZone: session?.site.serverTimeZone ?? .device,
                                         deviceTimeZone: .current)
    }

    /// U11.
    private var moreMenu: some View {
        Menu {
            Button { Task { await store.refreshHome(noCache: true) } } label: { Label("刷新", systemImage: "arrow.clockwise") }
            Button { router.push(.analytics()) } label: { Label("统计分析", systemImage: "chart.xyaxis.line") }
        } label: {
            Label("更多", systemImage: "ellipsis")
        }
        .accessibilityIdentifier("home.more")
    }
}

extension View {
    /// The overview's lists (regular and, from S1-11, calm): grouped cards on the canvas.
    func homeListChrome() -> some View {
        listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Palette.canvas)
    }
}
