import SwiftUI
import Sub2Core

/// 10 §1 the overview's regular layout: the R18 banner, the six cells and the ops notice, then the queue (S1-10) and the today and
/// run sections (S1-09b). The title is the site menu (MainTabs' `siteTitleMenu()`), the subtitle the server's date and freshness.
/// The session's LiveOpsStore polls while this tab shows and the App is active; coming back to the foreground or passing
/// compliance restarts it, which reads at once (D18: no scene-phase handler here). Identifiers home.*.
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

    var body: some View {
        let key = HomePollKey(visible: visible && scenePhase == .active, foreground: model.foregroundRevision,
                              compliance: model.securityPrompts.complianceRevision)
        // Each minute the subtitle's “N 分钟前” and the banner's time left are counted again.
        TimelineView(.everyMinute) { _ in
            page.navigationSubtitle(subtitle)
        }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { moreMenu } }
        .refreshable { await store.refreshHome(noCache: true) }
        .onAppear { visible = true }
        .onDisappear { visible = false }
        .task(id: key) {
            guard key.visible else { return }
            await store.homePolling()
        }
    }

    private var requestFailed: Bool { store.homeFailed }
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
            List {
                bannerSection
                figuresSection
                // 待处理：S1-10 在这里插入 HomeAttentionList
                // 今日区、运行区：S1-09b 在这里插入 HomeTodaySection / HomeRunSection
            }
            .homeListChrome()
            .accessibilityIdentifier("home.regular")
        }
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
                       isPlaceholder: state == .skeleton)
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

/// The task restarts when one of these changes; a hidden tab or a background App ends it.
private struct HomePollKey: Hashable {
    let visible: Bool
    let foreground: Int
    let compliance: Int
}

extension View {
    /// The overview's lists (regular and, from S1-11, calm): grouped cards on the canvas.
    func homeListChrome() -> some View {
        listStyle(.insetGrouped).scrollContentBackground(.hidden).background(Palette.canvas)
    }
}
